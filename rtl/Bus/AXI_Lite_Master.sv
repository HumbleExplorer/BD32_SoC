`include "./../SoC_Config.sv"
`timescale 1ns / 1ps

// =============================================================================
// AXI_Lite_Master - AXI4-Lite 主设备
// =============================================================================
// 将 CPU 的 Request-Response 同步阻塞接口转换为 AXI4-Lite 总线事务
//
// 条件编译：
//   `AXI_LITE_RSP_PIPELINED —— 使能响应打拍模式（在 rsp_* 输出处插寄存器）
//   未定义时保持原始组合逻辑（兼容旧设计 / 功能仿真）
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
    output logic                      rsp_error,
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
        WAIT_R    = 6'b010000,   // 等待读数据
        RSP_HOLD  = 6'b100000    // 响应保持（打拍模式）
    } state_t;

    state_t state, next_state;

`ifdef AXI_LITE_RSP_PIPELINED
    // =========================================================================
    // 响应寄存器（打拍模式）
    // b_hs/r_hs 当拍由 AXI 侧锁存到寄存器，下一拍在 RSP_HOLD 状态输出
    // 切断 rsp_* 到后续模块的长组合路径
    // =========================================================================
    logic                      rsp_valid_d;
    logic                      rsp_error_d;
    logic [DATA_WIDTH-1:0]     rsp_rdata_d;
`endif

    // =========================================================================
    // 当前事务锁存
    // =========================================================================
    logic [ADDR_WIDTH-1:0] addr_reg;
    logic [DATA_WIDTH-1:0] wdata_reg;
    logic [STRB_WIDTH-1:0] wstrb_reg;

    // 写事务中记录 AW/W 是否已完成
    logic aw_done, w_done;

    // =========================================================================
    // CPU 请求接受条件
    // 支持：
    //   1) IDLE 直接接请求
    //   2) B/R 完成当拍接下一笔请求（背靠背）
    //   3) RSP_HOLD 态（打拍模式）接下一笔请求
    // =========================================================================
    assign req_ready =
        (state == IDLE) ||
`ifdef AXI_LITE_RSP_PIPELINED
        (state == RSP_HOLD) ||
        ((state == WAIT_B) && m_bvalid) ||   // WAIT_B 的 b_hs 当拍接受新请求
        ((state == WAIT_R) && m_rvalid);     // WAIT_R 的 r_hs 当拍接受新请求
`else
        ((state == WAIT_B) && m_bvalid) ||
        ((state == WAIT_R) && m_rvalid);
`endif

    logic take_req;
    assign take_req = req_valid && req_ready;

    // =========================================================================
    // “本拍新发起请求”标志
    // =========================================================================
    logic launch_wr_now, launch_rd_now;
    assign launch_wr_now = take_req &&  req_write;
    assign launch_rd_now = take_req && !req_write;

    // =========================================================================
    // AXI 通道输出
    // - 新请求接受当拍：直接旁路 req_*
    // - 否则：使用锁存值
    // =========================================================================
    assign m_awaddr  = launch_wr_now ? req_addr  : addr_reg;
    assign m_wdata   = launch_wr_now ? req_wdata : wdata_reg;
    assign m_wstrb   = launch_wr_now ? req_wstrb : wstrb_reg;
    assign m_araddr  = launch_rd_now ? req_addr  : addr_reg;

    assign m_awvalid = launch_wr_now || ((state == WAIT_W_AW) && !aw_done);
    assign m_wvalid  = launch_wr_now || ((state == WAIT_W_AW) && !w_done);
    assign m_arvalid = launch_rd_now || (state == WAIT_AR);

    assign m_bready  = (state == WAIT_B);
    assign m_rready  = (state == WAIT_R);

    // =========================================================================
    // 握手检测
    // =========================================================================
    logic aw_hs, w_hs, ar_hs, b_hs, r_hs;

    assign aw_hs = m_awvalid && m_awready;
    assign w_hs  = m_wvalid  && m_wready;
    assign ar_hs = m_arvalid && m_arready;
    assign b_hs  = (state == WAIT_B) && m_bvalid && m_bready;
    assign r_hs  = (state == WAIT_R) && m_rvalid && m_rready;

    // =========================================================================
    // 锁存请求
    // 只要 take_req，就把这笔“被接受”的请求锁存起来
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_reg  <= '0;
            wdata_reg <= '0;
            wstrb_reg <= '0;
        end else if (take_req) begin
            addr_reg  <= req_addr;
            wdata_reg <= req_wdata;
            wstrb_reg <= req_wstrb;
        end
    end

    // =========================================================================
    // 记录写事务的 AW/W 完成情况
    // 关键：新写事务被接受时，必须重新初始化为“这笔新事务当拍是否已握手”
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_done <= 1'b0;
            w_done  <= 1'b0;
        end else begin
            if (launch_wr_now) begin
                // 新写事务开始：按“这笔新事务”当拍是否已完成来初始化
                aw_done <= aw_hs;
                w_done  <= w_hs;
            end else if (state == WAIT_W_AW) begin
                // 续传阶段：补齐未完成通道
                if (aw_hs) aw_done <= 1'b1;
                if (w_hs)  w_done  <= 1'b1;
            end else begin
                // 非写请求启动时，清零，避免旧状态残留
                if (launch_rd_now || state == IDLE) begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // 状态机
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // =========================================================================
    // 状态机（条件编译：打拍模式）
    // 打拍模式下，b_hs/r_hs 后先跳转到 RSP_HOLD，
    // 在 RSP_HOLD 态输出寄存器锁存的响应，同时接受新请求
    // =========================================================================
    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (take_req) begin
                    if (req_write) begin
                        if (aw_hs && w_hs)
                            next_state = WAIT_B;
                        else
                            next_state = WAIT_W_AW;
                    end else begin
                        if (ar_hs)
                            next_state = WAIT_R;
                        else
                            next_state = WAIT_AR;
                    end
                end else begin
                    next_state = IDLE;
                end
            end

            WAIT_W_AW: begin
                if ((aw_done || aw_hs) && (w_done || w_hs))
                    next_state = WAIT_B;
                else
                    next_state = WAIT_W_AW;
            end

`ifdef AXI_LITE_RSP_PIPELINED
            // =================================================================
            // 响应保持态（打拍模式）
            // 这拍输出锁存的响应，同时可接受新请求（req_ready 拉高）
            // 新请求同拍进入后：
            //   - aw_hs/w_hs 直通完成 → 去 WAIT_B 等写响应
            //   - ar_hs 直通完成 → 去 WAIT_R 等读数据
            //   - 否则 → 去对应的 WAIT_W_AW / WAIT_AR
            // =================================================================
            RSP_HOLD: begin
                if (take_req) begin
                    if (req_write) begin
                        if (aw_hs && w_hs)
                            next_state = WAIT_B;   // AW/W 直通，等 B
                        else
                            next_state = WAIT_W_AW;
                    end else begin
                        if (ar_hs)
                            next_state = WAIT_R;   // AR 直通，等 R
                        else
                            next_state = WAIT_AR;
                    end
                end else begin
                    next_state = IDLE;
                end
            end
`endif

            WAIT_B: begin
                if (b_hs) begin
`ifdef AXI_LITE_RSP_PIPELINED
                    next_state = RSP_HOLD;
`else
                    if (take_req) begin
                        if (req_write) begin
                            if (aw_hs && w_hs)
                                next_state = WAIT_B;
                            else
                                next_state = WAIT_W_AW;
                        end else begin
                            if (ar_hs)
                                next_state = WAIT_R;
                            else
                                next_state = WAIT_AR;
                        end
                    end else begin
                        next_state = IDLE;
                    end
`endif
                end else begin
                    next_state = WAIT_B;
                end
            end

            WAIT_AR: begin
                if (ar_hs)
                    next_state = WAIT_R;
                else
                    next_state = WAIT_AR;
            end

            WAIT_R: begin
                if (r_hs) begin
`ifdef AXI_LITE_RSP_PIPELINED
                    next_state = RSP_HOLD;
`else
                    if (take_req) begin
                        if (req_write) begin
                            if (aw_hs && w_hs)
                                next_state = WAIT_B;
                            else
                                next_state = WAIT_W_AW;
                        end else begin
                            if (ar_hs)
                                next_state = WAIT_R;
                            else
                                next_state = WAIT_AR;
                        end
                    end else begin
                        next_state = IDLE;
                    end
`endif
                end else begin
                    next_state = WAIT_R;
                end
            end

            default: next_state = IDLE;
        endcase
    end

`ifdef AXI_LITE_RSP_PIPELINED
    // =========================================================================
    // 响应寄存器锁存（打拍模式）
    // b_hs 或 r_hs 当拍锁存响应数据，下拍在 RSP_HOLD 状态输出
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid_d <= 1'b0;
            rsp_error_d <= 1'b0;
            rsp_rdata_d <= '0;
        end else begin
            if (b_hs) begin
                // 写响应：锁存 bresp 的 error bit
                rsp_valid_d <= 1'b1;
                rsp_error_d <= m_bresp[1];
            end else if (r_hs) begin
                // 读响应：锁存读数据和 bresp
                rsp_valid_d <= 1'b1;
                rsp_error_d <= m_rresp[1];
                rsp_rdata_d <= m_rdata;
            end else if (state != RSP_HOLD) begin
                // 非 RSP_HOLD 状态时清除，避免遗留
                rsp_valid_d <= 1'b0;
            end
            // RSP_HOLD 状态下保留锁存值不变（直到跳走）
        end
    end

    assign rsp_valid = (state == RSP_HOLD) ? rsp_valid_d : 1'b0;
    assign rsp_error = (state == RSP_HOLD) ? rsp_error_d : 1'b0;
    assign rsp_rdata = (state == RSP_HOLD) ? rsp_rdata_d : '0;

`else /* 原始组合逻辑 */
    // =========================================================================
    // CPU 侧响应（原始组合逻辑）
    // AXI 返回当拍旁路给 CPU，零延迟
    // =========================================================================
    assign rsp_valid =
        ((state == WAIT_B) && m_bvalid) ||
        ((state == WAIT_R) && m_rvalid);

    assign rsp_error =
        ((state == WAIT_B) && m_bvalid) ? m_bresp[1] :
        ((state == WAIT_R) && m_rvalid) ? m_rresp[1] :
        1'b0;

    assign rsp_rdata =
        ((state == WAIT_R) && m_rvalid) ? m_rdata : '0;
`endif

endmodule
