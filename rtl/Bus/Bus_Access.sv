`include "./../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;
// =============================================================================
// Bus_Access - BIU 顶层（薄封装）
// =============================================================================
// CPU 侧直通 → AXI_Lite_Master（请求/响应寄存器均在 AXI_Lite_Master 内部）
// 对外连接 AXI_Interconnect，由其路由到 MROM/APB Bridge/Flash/DDR
// =============================================================================

import bd32_pkg::*;

module Bus_Access #(
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
    // CPU 侧：Request-Response 接口
    // ========================================================================
    input  logic                      i_transfer,  // 请求有效
    input  logic                      i_write,     // 1=写, 0=读
    input  logic [ADDR_WIDTH-1:0]     i_addr,
    input  logic [DATA_WIDTH-1:0]     i_wdata,
    input  logic [STRB_WIDTH-1:0]     i_wmask,
    
    output logic                      o_bus_tran_done,
    output logic                      o_bus_ready,
    output logic [DATA_WIDTH-1:0]     o_bus_rdata,
    output logic [1:0]                o_bus_error,

    // ========================================================================
    // AXI4 Master 接口 → AXI_Interconnect
    // ========================================================================
    // --- 写地址通道 (AW) ---
    // AXI4 Master 接口（接口）
    axi_if.master m
);

    // =========================================================================
    // CPU 侧直通 → AXI_Lite_Master（输入寄存器已移入 AXI_Lite_Master）
    // =========================================================================
    logic                      axi_rsp_valid;
    logic                      axi_rsp_ready;
    logic [DATA_WIDTH-1:0]     axi_rsp_rdata;
    logic [1:0]                axi_rsp_error;
    
    assign o_bus_tran_done = axi_rsp_valid;
    assign o_bus_ready = axi_rsp_ready && ~i_transfer;
    assign o_bus_rdata = axi_rsp_rdata;
    assign o_bus_error = axi_rsp_error;

    // =========================================================================
    // AXI_Lite_Master
    // =========================================================================
    AXI_Lite_Master #(
        .ADDR_WIDTH  (ADDR_WIDTH  ),
        .DATA_WIDTH  (DATA_WIDTH  ),
        .STRB_WIDTH  (STRB_WIDTH  ),
        .ID_WIDTH    (ID_WIDTH    ),
        .LEN_WIDTH   (LEN_WIDTH   )
    ) u_AXI_Lite_Master (
        .clk          (clk           ),
        .rst_n        (rst_n         ),

        // CPU 侧（直通，寄存器在 AXI_Lite_Master 内部）
        .req_valid    (i_transfer    ),
        .req_write    (i_write       ),
        .req_addr     (i_addr        ),
        .req_wdata    (i_wdata       ),
        .req_wstrb    (i_wmask       ),
        .req_ready    (axi_rsp_ready ),
        .rsp_valid    (axi_rsp_valid ),
        .rsp_error    (axi_rsp_error ),
        .rsp_rdata    (axi_rsp_rdata ),

        // AXI Master → Interconnect
        // AXI Master 接口（直通端口 m）
        .m           (m             )
    );

endmodule
