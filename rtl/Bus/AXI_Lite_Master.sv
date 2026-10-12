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

module AXI_Lite_Master #(
    parameter ADDR_WIDTH   = `ADDR_WIDTH,
    parameter DATA_WIDTH   = `DATA_WIDTH,
    parameter STRB_WIDTH   = `ALIGN_BYTES,
    parameter ID_WIDTH     = `AXI_ID_WIDTH,
    parameter LEN_WIDTH    = `AXI_LEN_WIDTH
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
    output logic [ID_WIDTH-1:0]       m_awid,
    output logic [ADDR_WIDTH-1:0]     m_awaddr,
    output logic [LEN_WIDTH-1:0]      m_awlen,
    output logic [2:0]                m_awsize,
    output logic [1:0]                m_awburst,
    output logic                      m_awlock,
    output logic [3:0]                m_awcache,
    output logic [2:0]                m_awprot,
    output logic [3:0]                m_awqos,
    output logic [3:0]                m_awregion,
    output logic                      m_awvalid,
    input  logic                      m_awready,

    // --- 写数据通道 (W) ---
    output logic [DATA_WIDTH-1:0]     m_wdata,
    output logic [STRB_WIDTH-1:0]     m_wstrb,
    output logic                      m_wlast,
    output logic                      m_wvalid,
    input  logic                      m_wready,

    // --- 写响应通道 (B) ---
    input  logic [ID_WIDTH-1:0]       m_bid,
    input  logic [1:0]                m_bresp,
    input  logic                      m_bvalid,
    output logic                      m_bready,

    // --- 读地址通道 (AR) ---
    output logic [ID_WIDTH-1:0]       m_arid,
    output logic [ADDR_WIDTH-1:0]     m_araddr,
    output logic [LEN_WIDTH-1:0]      m_arlen,
    output logic [2:0]                m_arsize,
    output logic [1:0]                m_arburst,
    output logic                      m_arlock,
    output logic [3:0]                m_arcache,
    output logic [2:0]                m_arprot,
    output logic [3:0]                m_arqos,
    output logic [3:0]                m_arregion,
    output logic                      m_arvalid,
    input  logic                      m_arready,

    // --- 读数据通道 (R) ---
    input  logic [ID_WIDTH-1:0]       m_rid,
    input  logic [DATA_WIDTH-1:0]     m_rdata,
    input  logic [1:0]                m_rresp,
    input  logic                      m_rlast,
    input  logic                      m_rvalid,
    output logic                      m_rready
);

    // =========================================================================
    // AXI-Lite 固定值（Full 信号输出）
    // =========================================================================
    localparam int unsigned AXI_SIZE_VAL = $clog2(DATA_WIDTH/8);

    assign m_awid     = '0;
    assign m_awlen    = '0;                 // 单拍
    assign m_awsize   = AXI_SIZE_VAL[2:0];
    assign m_awburst  = 2'b01;              // INCR（单拍下与 FIXED 均可）
    assign m_awlock   = 1'b0;
    assign m_awcache  = 4'b0000;
    assign m_awprot   = 3'b000;
    assign m_awqos    = 4'b0000;
    assign m_awregion = 4'b0000;

    assign m_wlast    = 1'b1;

    assign m_arid     = '0;
    assign m_arlen    = '0;
    assign m_arsize   = AXI_SIZE_VAL[2:0];
    assign m_arburst  = 2'b01;
    assign m_arlock   = 1'b0;
    assign m_arcache  = 4'b0000;
    assign m_arprot   = 3'b000;
    assign m_arqos    = 4'b0000;
    assign m_arregion = 4'b0000;

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
    assign aw_hs = m_awvalid && m_awready;
    assign w_hs  = m_wvalid  && m_wready;
    assign ar_hs = m_arvalid && m_arready;
    assign b_hs  = m_bvalid && m_bready;
    assign r_hs  = m_rvalid && m_rready;

    // =========================================================================
    // 总线超时检测
    // =========================================================================
    // 从机挂死（永不拉 ready/valid）时，FSM 会卡在等待态。计数器在等待态累加，
    // 超过 BUS_TIMEOUT 阈值则触发 bus_timeout，强制完成事务并返回 DECERR，
    // 避免 CPU 因 ~bus_ready 永久 stall。
    localparam int unsigned TIMEOUT_VAL   = `BUS_TIMEOUT;
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
    // bus_timeout 优先级最高：从机挂死时强制跳到 DONE 解除卡死
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
    assign m_awaddr = req_addr_i;
    assign m_wdata  = req_wdata_i;
    assign m_wstrb  = req_wstrb_i;
    assign m_araddr = req_addr_i;

    // ── 全寄存器输出 ──
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_awvalid <= 1'b0;
            m_wvalid  <= 1'b0;
            m_arvalid <= 1'b0;
            m_bready  <= 1'b0;
            m_rready  <= 1'b0;
            req_ready <= 1'b0;
            rsp_valid <= 1'b0;
            rsp_error <= 1'b0;
            rsp_rdata <= '0;
        end else begin
            m_awvalid <= (next_state == WAIT_W_AW);
            m_wvalid  <= (next_state == WAIT_W_AW);
            m_arvalid <= (next_state == WAIT_AR);
            m_bready  <= (next_state == WAIT_B);
            m_rready  <= (next_state == WAIT_R);
            req_ready <= (next_state == DONE) || (next_state == IDLE);
            rsp_valid <= (next_state == DONE);
            // 进入 DONE 前锁存响应数据；总线超时则强制 DECERR（从机无响应）
            if (bus_timeout) begin
                rsp_error <= 2'b11;          // DECERR：从机挂死/超时无响应
                rsp_rdata <= '0;
            end else if (state == WAIT_B && b_hs) begin
                rsp_error <= m_bresp;
            end else if (state == WAIT_R && r_hs) begin
                rsp_error <= m_rresp;
                rsp_rdata <= m_rdata;
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
        if ($past(m_awvalid && !m_awready && !bus_timeout)) begin
            a_aw_stable: assert property
                (m_awvalid && (m_awaddr == $past(m_awaddr)));
        end
        if ($past(m_wvalid && !m_wready && !bus_timeout)) begin
            a_w_stable: assert property
                (m_wvalid && (m_wdata == $past(m_wdata)) && (m_wstrb == $past(m_wstrb)));
        end
        if ($past(m_arvalid && !m_arready && !bus_timeout)) begin
            a_ar_stable: assert property
                (m_arvalid && (m_araddr == $past(m_araddr)));
        end
    end
end
`endif

`ifdef FORMAL
// ===== 形式验证属性（SymbiYosys）=====
// 6 态 one-hot FSM 合法性 + 输出一致性 + 等待态有界逃逸（超时计数器保证，
// 无需环境假设——挂死场景由 BUS_TIMEOUT 强制 DONE 并回 DECERR）
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
        fml_a_wait_bounded: assert property (fml_wait_age <= `BUS_TIMEOUT + 2);
        // DONE 拍 req_ready 必为高（响应当拍可被接收/背靠背发射）
        if (state == FML_S_DONE) begin
            fml_a_done_ready: assert property (req_ready);
        end
        // W 通道仅与 AW 同窗口有效（Lite 单事务：AW 与 W 同拍窗口）
        if (m_awvalid) begin
            fml_a_w_with_aw: assert property (m_wvalid);
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
