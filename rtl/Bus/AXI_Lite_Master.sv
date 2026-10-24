`include "./../SoC_Config.sv"
`ifndef FORMAL
timeunit 1ns;
timeprecision 1ps;
`endif

// =============================================================================
// AXI_Lite_Master - AXI4-Lite 主设备（全寄存器版）
// =============================================================================
// 将 CPU 的 Request-Response 同步阻塞接口转换为 AXI4-Lite 总线事务
// CPU 侧：输入全寄存（req_* → req_*_i），输出全寄存（valid/ready/data）
// AXI 侧：valid/ready 均为寄存器输出，仅 handshake（*_hs）为组合逻辑
// 6 态 FSM：IDLE → WAIT_W_AW/WAIT_AR → WAIT_B/WAIT_R → DONE → IDLE
// =============================================================================

import bd32_pkg::*;

module AXI_Lite_Master #(
    parameter ADDR_WIDTH   = `ADDR_WIDTH,
    parameter DATA_WIDTH   = `DATA_WIDTH,
    parameter STRB_WIDTH   = `ALIGN_BYTES,
    parameter ID_WIDTH     = AXI_ID_WIDTH,
    parameter LEN_WIDTH    = AXI_LEN_WIDTH
)(
    // ========================================================================
    // 系统接口
    // ========================================================================
    input  logic clk,
    input  logic rst_n,

    // ========================================================================
    // CPU 侧：Request-Response 同步阻塞接口
    // ========================================================================
    input  logic                      req_valid,
    input  logic                      req_write,
    input  logic [ADDR_WIDTH-1:0]     req_addr,
    input  logic [DATA_WIDTH-1:0]     req_wdata,
    input  logic [STRB_WIDTH-1:0]     req_wstrb,
    output logic                      req_ready,
    output logic                      rsp_valid,
    output logic [1:0]                rsp_error,
    output logic [DATA_WIDTH-1:0]     rsp_rdata,

    // ========================================================================
    // AXI4 Master 接口（Full 信号，Lite 行为）
    // ========================================================================
    // --- 写地址通道 (AW) ---
    // AXI4 Master 接口（接口）
    axi_if.master m
);

    // =========================================================================
    // AXI-Lite 固定值（Full 信号输出）
    // =========================================================================
    localparam int unsigned AXI_SIZE_VAL = $clog2(DATA_WIDTH/8);

    assign m.awid     = '0;
    assign m.awlen    = '0;                 // 单拍
    assign m.awsize   = AXI_SIZE_VAL[2:0];
    assign m.awburst  = 2'b01;              // INCR（单拍下与 FIXED 均可）
    assign m.awlock   = 1'b0;
    assign m.awcache  = 4'b0000;
    assign m.awprot   = 3'b000;
    assign m.awqos    = 4'b0000;
    assign m.awregion = 4'b0000;

    assign m.wlast    = 1'b1;

    assign m.arid     = '0;
    assign m.arlen    = '0;
    assign m.arsize   = AXI_SIZE_VAL[2:0];
    assign m.arburst  = 2'b01;
    assign m.arlock   = 1'b0;
    assign m.arcache  = 4'b0000;
    assign m.arprot   = 3'b000;
    assign m.arqos    = 4'b0000;
    assign m.arregion = 4'b0000;

    // =========================================================================
    // 状态机
    // =========================================================================
    typedef enum logic [5:0] {
        IDLE      = 6'b000001,
        WAIT_W_AW = 6'b000010,   // 等待 AW/W 都完成
        WAIT_B    = 6'b000100,   // 等待写响应
        WAIT_AR   = 6'b001000,   // 等待读地址完成
        WAIT_R    = 6'b010000,    // 等待读数据
        DONE      = 6'b100000   // 完成
    } state_t;

    state_t state, next_state;

    // ── 组合握手（唯一的组合逻辑）──
    logic aw_hs, w_hs, ar_hs, b_hs, r_hs;
    assign aw_hs = m.awvalid && m.awready;
    assign w_hs  = m.wvalid  && m.wready;
    assign ar_hs = m.arvalid && m.arready;
    assign b_hs  = m.bvalid && m.bready;
    assign r_hs  = m.rvalid && m.rready;

    // =========================================================================
    // 总线超时检测
    // =========================================================================
    // 从机未返回 ready/valid 时，FSM 会停留在等待态。计数器在等待态累加，
    // 超过 BUS_TIMEOUT 阈值则触发 bus_timeout，强制完成事务并返回 DECERR，
    // 避免 CPU 因 ~bus_ready 永久 stall。
    localparam int unsigned TIMEOUT_VAL   = BUS_TIMEOUT;
    // 计数器位宽必须能表示 TIMEOUT_VAL 本身。$clog2(1024)=10 只能存 0~1023，
    // 会使 TIMEOUT_VAL[TIMEOUT_WIDTH-1:0] 把 1024 截成 0，导致 timeout_cnt>=0 恒成立、
    // 每个总线等待态首拍即误触发 DECERR（所有 GPIO/UART 访问都被当成超时）。
    // 用 $clog2(TIMEOUT_VAL+1) 保证位宽容纳阈值（1024 → 11 位）。
    localparam int unsigned TIMEOUT_WIDTH = $clog2(TIMEOUT_VAL + 1);

    logic [TIMEOUT_WIDTH-1:0] timeout_cnt;
    logic                     bus_timeout;

    logic in_wait_state;
    assign in_wait_state = (state == WAIT_W_AW) || (state == WAIT_B)
                        || (state == WAIT_AR)   || (state == WAIT_R);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            timeout_cnt <= '0;
        else if (in_wait_state)
            timeout_cnt <= timeout_cnt + 1'b1;
        else
            timeout_cnt <= '0;
    end

    assign bus_timeout = in_wait_state && (timeout_cnt >= TIMEOUT_VAL[TIMEOUT_WIDTH-1:0]);

    // =========================================================================
    // CPU 侧输入寄存器
    // =========================================================================
    logic                      req_write_i;
    logic [ADDR_WIDTH-1:0]     req_addr_i;
    logic [DATA_WIDTH-1:0]     req_wdata_i;
    logic [STRB_WIDTH-1:0]     req_wstrb_i;

    logic take_req;
    assign take_req = req_valid && req_ready;

        // ── 状态寄存器 ──
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // ── 状态转移（纯组合）──
    // bus_timeout 优先级最高：从机无响应超时后转入 DONE，保证事务有界结束。
    always_comb begin
        next_state = state;
        case (state)
            IDLE:      if (take_req)       next_state = req_write ? WAIT_W_AW : WAIT_AR;
            WAIT_W_AW: if (aw_hs && w_hs)  next_state = WAIT_B;
            WAIT_B:    if (b_hs)           next_state = DONE;
            WAIT_AR:   if (ar_hs)          next_state = WAIT_R;
            WAIT_R:    if (r_hs)           next_state = DONE;
            DONE:      if (take_req)       next_state = req_write_i ? WAIT_W_AW : WAIT_AR;
                       else                next_state = IDLE;
            default:   next_state = IDLE;
        endcase
        if (bus_timeout) next_state = DONE;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_write_i <= 1'b0;
            req_addr_i  <= '0;
            req_wdata_i <= '0;
            req_wstrb_i <= '0;
        end else if (take_req) begin
            req_write_i <= req_write;
            req_addr_i  <= req_addr;
            req_wdata_i <= req_wdata;
            req_wstrb_i <= req_wstrb;
        end else if (state == DONE) begin
            req_write_i <= 1'b0;
            req_addr_i  <= '0;
            req_wdata_i <= '0;
            req_wstrb_i <= '0;
        end
    end

    // AXI 数据通道（来自输入寄存器，稳定）
    assign m.awaddr = req_addr_i;
    assign m.wdata  = req_wdata_i;
    assign m.wstrb  = req_wstrb_i;
    assign m.araddr = req_addr_i;

    // ── 全寄存器输出 ──
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m.awvalid <= 1'b0;
            m.wvalid  <= 1'b0;
            m.arvalid <= 1'b0;
            m.bready  <= 1'b0;
            m.rready  <= 1'b0;
            req_ready <= 1'b0;
            rsp_valid <= 1'b0;
            rsp_error <= 1'b0;
            rsp_rdata <= '0;
        end else begin
            m.awvalid <= (next_state == WAIT_W_AW);
            m.wvalid  <= (next_state == WAIT_W_AW);
            m.arvalid <= (next_state == WAIT_AR);
            m.bready  <= (next_state == WAIT_B);
            m.rready  <= (next_state == WAIT_R);
            req_ready <= (next_state == DONE) || (next_state == IDLE);
            rsp_valid <= (next_state == DONE);
            // 进入 DONE 前锁存响应数据；总线超时则强制 DECERR（从机无响应）
            if (bus_timeout) begin
                rsp_error <= 2'b11;          // DECERR：从机响应超时
                rsp_rdata <= '0;
            end else if (state == WAIT_B && b_hs) begin
                rsp_error <= m.bresp;
            end else if (state == WAIT_R && r_hs) begin
                rsp_error <= m.rresp;
                rsp_rdata <= m.rdata;
            end
        end
    end


`ifndef SYNTHESIS
// ===========================================================================
// SVA: AXI4-Lite 握手稳定性（VALID 拉起后必须保持到握手完成）
// Yosys SVA 子集写法：时钟取自外层 always、$stable 改 $past、|=> 改 $past 判断
// （ModelSim 同样接受）；总线超时逃逸拍例外——超时强制撤 valid 是设计行为
// ===========================================================================
always @(posedge clk) begin
    if (rst_n) begin
        if ($past(m.awvalid && !m.awready && !bus_timeout)) begin
            a_aw_stable: assert property
                (m.awvalid && (m.awaddr == $past(m.awaddr)));
        end
        if ($past(m.wvalid && !m.wready && !bus_timeout)) begin
            a_w_stable: assert property
                (m.wvalid && (m.wdata == $past(m.wdata)) && (m.wstrb == $past(m.wstrb)));
        end
        if ($past(m.arvalid && !m.arready && !bus_timeout)) begin
            a_ar_stable: assert property
                (m.arvalid && (m.araddr == $past(m.araddr)));
        end
    end
end
`endif

`ifdef FORMAL
// ===== 形式验证属性（SymbiYosys）=====
// 6 态 one-hot FSM 合法性 + 输出一致性 + 等待态有界逃逸（超时计数器保证，
// 无需环境假设：BUS_TIMEOUT 保证请求在有限周期内进入 DONE 并返回 DECERR。
localparam logic [5:0] FML_S_IDLE      = 6'b000001;
localparam logic [5:0] FML_S_WAIT_W_AW = 6'b000010;
localparam logic [5:0] FML_S_WAIT_B    = 6'b000100;
localparam logic [5:0] FML_S_WAIT_AR   = 6'b001000;
localparam logic [5:0] FML_S_WAIT_R    = 6'b010000;
localparam logic [5:0] FML_S_DONE      = 6'b100000;
// 等待态年龄计数（有界逃逸检查用）
logic [15:0] fml_wait_age;
always_ff @(posedge clk) begin
    if (!rst_n)            fml_wait_age <= '0;
    else if (in_wait_state) fml_wait_age <= fml_wait_age + 1'b1;
    else                    fml_wait_age <= '0;
end
always @(posedge clk) begin
    if (rst_n) begin
        // FSM 只允许落在 6 个合法 one-hot 编码
        fml_a_state_legal: assert property
            ((state == FML_S_IDLE) || (state == FML_S_WAIT_W_AW) || (state == FML_S_WAIT_B)
          || (state == FML_S_WAIT_AR) || (state == FML_S_WAIT_R) || (state == FML_S_DONE));
        // CPU 侧约定：req_ready/rsp_valid 与状态一致（蕴含式——req_ready 是
        // 寄存器输出，复位后第一拍 state=IDLE 而 req_ready 仍为复位值 0，
        // 精确相等式会在启动拍误报）
        if (req_ready) begin
            fml_a_req_ready_fwd: assert property
                ((state == FML_S_DONE) || (state == FML_S_IDLE));
        end
        fml_a_rsp_valid: assert property (rsp_valid == (state == FML_S_DONE));
        // 等待态有界逃逸：至多 TIMEOUT_VAL+1 拍必被超时强制离开（最终完成 → 有界完成）
        fml_a_wait_bounded: assert property (fml_wait_age <= BUS_TIMEOUT + 2);
        // DONE 拍 req_ready 必为高（响应当拍可被接收/背靠背发射）
        if (state == FML_S_DONE) begin
            fml_a_done_ready: assert property (req_ready);
        end
        // W 通道仅与 AW 同窗口有效（Lite 单事务：AW 与 W 同拍窗口）
        if (m.awvalid) begin
            fml_a_w_with_aw: assert property (m.wvalid);
        end
        // cover：读写事务完成 / 背靠背 / 超时逃逸
        // （FORMAL 下 BUS_TIMEOUT 缩为 8，见 SoC_Config——超时路径深度可达）
        fml_c_write_done: cover property ((state == FML_S_DONE) && req_write_i && !bus_timeout);
        fml_c_read_done:  cover property ((state == FML_S_DONE) && !req_write_i && !bus_timeout);
        fml_c_b2b:        cover property ((state == FML_S_DONE) && req_valid && req_ready);
        fml_c_timeout:    cover property (bus_timeout);
    end
end
`endif

`ifdef ASSERT_MODULE
// ===== SVA L2：AXI_Lite_Master 深化——单笔在途与响应质量 =====
always @(posedge clk) begin
    if (rst_n) begin
        // 总线超时恒不发生（从机有界完成约定端到端）
        a_l2_axi_no_timeout: assert property (!bus_timeout);
        // 响应数据/错误码无 X
        if (rsp_valid) a_l2_axi_rsp_nox: assert property (!$isunknown(rsp_rdata) && !$isunknown(rsp_error));
        // 单笔在途：接受请求后未回响应前不得再接受新请求
        if ($past(req_valid && req_ready) && !rsp_valid)
            a_l2_axi_single_outstanding: assert property (!req_ready);
    end
end
`endif

endmodule
