`include "./../SoC_Config.sv"
`timescale 1ns / 1ps
// =============================================================================
// AXI_Lite_Master - AXI4-Lite 主设备接口（优化版）
// =============================================================================
// 功能：
//   将 CPU 的 Request-Response 同步阻塞接口转换为 AXI4 协议
//   - 端口保留 AXI-Full 信号（ID/LEN/SIZE/BURST/LOCK/CACHE/PROT/QOS/REGION/LAST）
//   - 内部按 AXI-Lite 运行：单拍传输，Full 信号输出固定值
//   - 同步阻塞：CPU 等待当前传输完成后才能发下一个请求
//
// 时序优化（相对旧版省 1 周期）：
//   IDLE 状态直接输出地址/数据/valid，不经过 addr_reg 锁存后再发
//   - 读：IDLE 直接发 AR，若 ARREADY=1 则直接跳到 WAIT_R（跳过 WAIT_AR）
//   - 写：IDLE 直接发 AW+W，若都握手则直接跳到 WAIT_B
//
// 优化后时序（Bridge 也优化后）：
//   读：IDLE → WAIT_AR(可选) → WAIT_R → IDLE  = 3 周期（含 AR 握手）
//   写：IDLE → WAIT_AW(可选) → WAIT_W(可选) → WAIT_B → IDLE = 3 周期
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
    input  logic                      req_valid,   // 请求有效（CPU 发起）
    input  logic                      req_write,   // 1=写, 0=读
    input  logic [ADDR_WIDTH-1:0]     req_addr,
    input  logic [DATA_WIDTH-1:0]     req_wdata,
    input  logic [STRB_WIDTH-1:0]     req_wstrb,
    output logic                      req_ready,   // 可以接受新请求
    output logic                      rsp_valid,   // 响应有效
    output logic                      rsp_error,   // 响应错误（SLVERR/DECERR）
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
    assign m_awid     = {ID_WIDTH{1'b0}};               // ID = 0
    assign m_awlen    = {LEN_WIDTH{1'b0}};              // 单拍传输
    assign m_awsize   = 3'b010;                          // 4 bytes (2^2)
    assign m_awburst  = 2'b00;                           // FIXED
    assign m_awlock   = 1'b0;                            // Normal
    assign m_awcache  = 4'b0000;                         // Device Non-bufferable
    assign m_awprot   = 3'b000;                          // Data, Secure, Unprivileged
    assign m_awqos    = 4'b0000;
    assign m_awregion = 4'b0000;

    assign m_wlast    = 1'b1;                            // 单拍，始终 LAST

    assign m_arid     = {ID_WIDTH{1'b0}};
    assign m_arlen    = {LEN_WIDTH{1'b0}};
    assign m_arsize   = 3'b010;
    assign m_arburst  = 2'b00;
    assign m_arlock   = 1'b0;
    assign m_arcache  = 4'b0000;
    assign m_arprot   = 3'b000;
    assign m_arqos    = 4'b0000;
    assign m_arregion = 4'b0000;

    // =========================================================================
    // 状态机
    // =========================================================================
    typedef enum logic [2:0] {
        IDLE    = 3'b000,
        WAIT_AW = 3'b001,  // 等待写地址握手
        WAIT_W  = 3'b010,  // 等待写数据握手
        WAIT_B  = 3'b011,  // 等待写响应
        WAIT_AR = 3'b100,  // 等待读地址握手
        WAIT_R  = 3'b101   // 等待读数据
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // =========================================================================
    // 请求锁存（IDLE 拍锁存 CPU 请求，供后续状态使用）
    // =========================================================================
    logic [ADDR_WIDTH-1:0]   addr_reg;
    logic [DATA_WIDTH-1:0]   wdata_reg;
    logic [STRB_WIDTH-1:0]   wstrb_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_reg  <= '0;
            wdata_reg <= '0;
            wstrb_reg <= '0;
        end else if (state == IDLE && req_valid) begin
            addr_reg  <= req_addr;
            wdata_reg <= req_wdata;
            wstrb_reg <= req_wstrb;
        end
    end

    // =========================================================================
    // 响应数据寄存器
    // =========================================================================
    logic [DATA_WIDTH-1:0] rdata_reg;
    logic                  rerr_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata_reg <= '0;
            rerr_reg  <= 1'b0;
        end else if (state == WAIT_R && m_rvalid) begin
            rdata_reg <= m_rdata;
            rerr_reg  <= m_rresp[1];  // bit1=1 → SLVERR/DECERR
        end
    end

    // =========================================================================
    // 状态转移
    // =========================================================================
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (req_valid) begin
                    if (!req_write) begin  // 读请求
                        if (m_arready)
                            next_state = WAIT_R;   // AR 握手成功，直接等 R
                        else
                            next_state = WAIT_AR;  // AR 没握手，留在 WAIT_AR
                    end else begin          // 写请求
                        if (m_awready && m_wready)
                            next_state = WAIT_B;   // AW+W 同时握手，直接等 B
                        else
                            next_state = WAIT_AW;  // 至少有一个没握手，先等 AW
                    end
                end
            end

            WAIT_AW: begin
                if (m_awvalid && m_awready)
                    next_state = WAIT_W;
            end

            WAIT_W: begin
                if (m_wvalid && m_wready)
                    next_state = WAIT_B;
            end

            WAIT_B: begin
                if (m_bvalid && m_bready)
                    next_state = IDLE;
            end

            WAIT_AR: begin
                if (m_arvalid && m_arready)
                    next_state = WAIT_R;
            end

            WAIT_R: begin
                if (m_rvalid && m_rready)
                    next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // =========================================================================
    // AXI 通道输出（优化：IDLE 状态直接输出 req 信号，不经过锁存）
    // =========================================================================
    // 写地址：IDLE 时直接输出 req_addr，否则用 addr_reg
    assign m_awaddr  = (state == IDLE) ? req_addr : addr_reg;
    assign m_awvalid = (state == IDLE && req_valid && req_write) || (state == WAIT_AW);

    // 写数据：IDLE 时直接输出 req_wdata，否则用 wdata_reg
    assign m_wdata   = (state == IDLE) ? req_wdata : wdata_reg;
    assign m_wstrb   = (state == IDLE) ? req_wstrb : wstrb_reg;
    assign m_wvalid  = (state == IDLE && req_valid && req_write) || (state == WAIT_W);

    // 写响应
    assign m_bready  = (state == WAIT_B);

    // 读地址：IDLE 时直接输出 req_addr，否则用 addr_reg
    assign m_araddr  = (state == IDLE) ? req_addr : addr_reg;
    assign m_arvalid = (state == IDLE && req_valid && !req_write) || (state == WAIT_AR);

    // 读数据
    assign m_rready  = (state == WAIT_R);

    // =========================================================================
    // CPU 侧响应
    // =========================================================================
    assign req_ready = (state == IDLE);

    assign rsp_valid = ((state == WAIT_B) && m_bvalid && m_bready) ||
                       ((state == WAIT_R) && m_rvalid && m_rready);

    assign rsp_error = (state == WAIT_B) ? m_bresp[1] :
                       (state == WAIT_R) ? rerr_reg : 1'b0;

    assign rsp_rdata = rdata_reg;

endmodule
