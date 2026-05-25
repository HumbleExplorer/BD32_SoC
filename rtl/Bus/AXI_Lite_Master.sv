`include "./../SoC_Config.sv"
`timescale 1ns / 1ps

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
            // 进入 DONE 前锁存响应数据
            if (state == WAIT_B && b_hs) begin
                rsp_error <= m_bresp[1];
            end else if (state == WAIT_R && r_hs) begin
                rsp_error <= m_rresp[1];
                rsp_rdata <= m_rdata;
            end
        end
    end



endmodule
