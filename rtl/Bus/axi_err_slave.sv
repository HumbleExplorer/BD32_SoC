`include "./../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;
// =============================================================================
// axi_err_slave - AXI4 Error/Default Slave
// =============================================================================
// 功能：
//   - 处理未映射地址空间的访问（Flash/DDR 留空区域）
//   - 读返回 0 + OKAY
//   - 写接受但丢弃数据 + OKAY
//   - 端口保留 AXI-Full 信号
// =============================================================================

module axi_err_slave #(
    parameter ADDR_WIDTH   = `ADDR_WIDTH,
    parameter DATA_WIDTH   = `DATA_WIDTH,
    parameter STRB_WIDTH   = `ALIGN_BYTES,
    parameter ID_WIDTH     = `AXI_ID_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    // ========================================================================
    // AXI4 Slave 接口（Full 信号，Lite 行为）
    // ========================================================================
    // --- 写地址通道 (AW) ---
    input  logic [ID_WIDTH-1:0]       s_awid,
    input  logic [ADDR_WIDTH-1:0]     s_awaddr,
    input  logic [7:0]                s_awlen,
    input  logic [2:0]                s_awsize,
    input  logic [1:0]                s_awburst,
    input  logic                      s_awlock,
    input  logic [3:0]                s_awcache,
    input  logic [2:0]                s_awprot,
    input  logic [3:0]                s_awqos,
    input  logic [3:0]                s_awregion,
    input  logic                      s_awvalid,
    output logic                      s_awready,

    // --- 写数据通道 (W) ---
    input  logic [DATA_WIDTH-1:0]     s_wdata,
    input  logic [STRB_WIDTH-1:0]     s_wstrb,
    input  logic                      s_wlast,
    input  logic                      s_wvalid,
    output logic                      s_wready,

    // --- 写响应通道 (B) ---
    output logic [ID_WIDTH-1:0]       s_bid,
    output logic [1:0]                s_bresp,
    output logic                      s_bvalid,
    input  logic                      s_bready,

    // --- 读地址通道 (AR) ---
    input  logic [ID_WIDTH-1:0]       s_arid,
    input  logic [ADDR_WIDTH-1:0]     s_araddr,
    input  logic [7:0]                s_arlen,
    input  logic [2:0]                s_arsize,
    input  logic [1:0]                s_arburst,
    input  logic                      s_arlock,
    input  logic [3:0]                s_arcache,
    input  logic [2:0]                s_arprot,
    input  logic [3:0]                s_arqos,
    input  logic [3:0]                s_arregion,
    input  logic                      s_arvalid,
    output logic                      s_arready,

    // --- 读数据通道 (R) ---
    output logic [ID_WIDTH-1:0]       s_rid,
    output logic [DATA_WIDTH-1:0]     s_rdata,
    output logic [1:0]                s_rresp,
    output logic                      s_rlast,
    output logic                      s_rvalid,
    input  logic                      s_rready
);

    localparam RESP_OKAY = 2'b00;

    // =========================================================================
    // 读通路：AR 握手 → 下一拍返回 0 + OKAY
    // =========================================================================
    logic [ID_WIDTH-1:0] arid_hold;
    logic                r_pending;

    assign s_arready = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arid_hold  <= '0;
            r_pending  <= 1'b0;
        end else begin
            if (s_arvalid && s_arready)
                arid_hold <= s_arid;
            if (s_arvalid && s_arready)
                r_pending <= 1'b1;
            else if (r_pending && s_rready)
                r_pending <= 1'b0;
        end
    end

    assign s_rid    = arid_hold;
    assign s_rdata  = {DATA_WIDTH{1'b0}};
    assign s_rresp  = RESP_OKAY;
    assign s_rlast  = 1'b1;
    assign s_rvalid = r_pending;

    // =========================================================================
    // 写通路：AW 握手 → 接受 WDATA → 返回 BRESP OKAY
    // =========================================================================
    logic [ID_WIDTH-1:0] awid_hold;
    logic                w_pending;
    logic                b_pending;

    assign s_awready = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awid_hold  <= '0;
            w_pending  <= 1'b0;
            b_pending  <= 1'b0;
        end else begin
            if (s_awvalid && s_awready)
                awid_hold <= s_awid;
            if (s_awvalid && s_awready)
                w_pending <= 1'b1;
            else if (w_pending && s_wvalid && s_wready)
                w_pending <= 1'b0;

            if (w_pending && s_wvalid && s_wready)
                b_pending <= 1'b1;
            else if (b_pending && s_bready)
                b_pending <= 1'b0;
        end
    end

    assign s_wready = w_pending;

    assign s_bid    = awid_hold;
    assign s_bresp  = RESP_OKAY;
    assign s_bvalid = b_pending;

endmodule
