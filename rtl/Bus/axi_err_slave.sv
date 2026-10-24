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

import bd32_pkg::*;

module axi_err_slave #(
    parameter ADDR_WIDTH   = `ADDR_WIDTH,
    parameter DATA_WIDTH   = `DATA_WIDTH,
    parameter STRB_WIDTH   = `ALIGN_BYTES,
    parameter ID_WIDTH     = AXI_ID_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    // ========================================================================
    // AXI4 Slave 接口（Full 信号，Lite 行为）
    // ========================================================================
    // --- 写地址通道 (AW) ---
    // AXI4 Slave 接口（接口）
    axi_if.slave  s
);

    localparam RESP_OKAY = 2'b00;

    // =========================================================================
    // 读通路：AR 握手 → 下一拍返回 0 + OKAY
    // =========================================================================
    logic [ID_WIDTH-1:0] arid_hold;
    logic                r_pending;

    assign s.arready = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arid_hold  <= '0;
            r_pending  <= 1'b0;
        end else begin
            if (s.arvalid && s.arready)
                arid_hold <= s.arid;
            if (s.arvalid && s.arready)
                r_pending <= 1'b1;
            else if (r_pending && s.rready)
                r_pending <= 1'b0;
        end
    end

    assign s.rid    = arid_hold;
    assign s.rdata  = {DATA_WIDTH{1'b0}};
    assign s.rresp  = RESP_OKAY;
    assign s.rlast  = 1'b1;
    assign s.rvalid = r_pending;

    // =========================================================================
    // 写通路：AW 握手 → 接受 WDATA → 返回 BRESP OKAY
    // =========================================================================
    logic [ID_WIDTH-1:0] awid_hold;
    logic                w_pending;
    logic                b_pending;

    assign s.awready = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awid_hold  <= '0;
            w_pending  <= 1'b0;
            b_pending  <= 1'b0;
        end else begin
            if (s.awvalid && s.awready)
                awid_hold <= s.awid;
            if (s.awvalid && s.awready)
                w_pending <= 1'b1;
            else if (w_pending && s.wvalid && s.wready)
                w_pending <= 1'b0;

            if (w_pending && s.wvalid && s.wready)
                b_pending <= 1'b1;
            else if (b_pending && s.bready)
                b_pending <= 1'b0;
        end
    end

    assign s.wready = w_pending;

    assign s.bid    = awid_hold;
    assign s.bresp  = RESP_OKAY;
    assign s.bvalid = b_pending;

endmodule
