`include "./../SoC_Config.sv"
`timescale 1ns / 1ps
// =============================================================================
// Bus_Access - BIU 顶层
// =============================================================================
// 将 CPU 的 Request-Response 同步阻塞接口转换为 AXI4 总线事务
// 对外连接 AXI_Interconnect，由其路由到 MROM/APB Bridge/Flash/DDR
//
// CPU 侧接口：
//   i_transfer + i_write + i_addr + i_wdata + i_wmask → req_valid + req_write + ...
//   o_rdata + o_tran_done ← rsp_rdata + rsp_valid
// =============================================================================

module Bus_Access #(
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
    // CPU 侧：Request-Response 接口
    // ========================================================================
    input  logic                      i_transfer,  // 请求有效
    input  logic                      i_write,     // 1=写, 0=读
    input  logic [ADDR_WIDTH-1:0]     i_addr,
    input  logic [DATA_WIDTH-1:0]     i_wdata,
    input  logic [STRB_WIDTH-1:0]     i_wmask,
    output logic [DATA_WIDTH-1:0]     o_rdata,
    output logic                      o_tran_done,

    // ========================================================================
    // AXI4 Master 接口 → AXI_Interconnect
    // ========================================================================
    // --- 写地址通道 (AW) ---
    output logic [ID_WIDTH-1:0]       o_awid,
    output logic [ADDR_WIDTH-1:0]     o_awaddr,
    output logic [LEN_WIDTH-1:0]      o_awlen,
    output logic [2:0]                o_awsize,
    output logic [1:0]                o_awburst,
    output logic                      o_awlock,
    output logic [3:0]                o_awcache,
    output logic [2:0]                o_awprot,
    output logic [3:0]                o_awqos,
    output logic [3:0]                o_awregion,
    output logic                      o_awvalid,
    input  logic                      i_awready,

    // --- 写数据通道 (W) ---
    output logic [DATA_WIDTH-1:0]     o_wdata,
    output logic [STRB_WIDTH-1:0]     o_wstrb,
    output logic                      o_wlast,
    output logic                      o_wvalid,
    input  logic                      i_wready,

    // --- 写响应通道 (B) ---
    input  logic [ID_WIDTH-1:0]       i_bid,
    input  logic [1:0]                i_bresp,
    input  logic                      i_bvalid,
    output logic                      o_bready,

    // --- 读地址通道 (AR) ---
    output logic [ID_WIDTH-1:0]       o_arid,
    output logic [ADDR_WIDTH-1:0]     o_araddr,
    output logic [LEN_WIDTH-1:0]      o_arlen,
    output logic [2:0]                o_arsize,
    output logic [1:0]                o_arburst,
    output logic                      o_arlock,
    output logic [3:0]                o_arcache,
    output logic [2:0]                o_arprot,
    output logic [3:0]                o_arqos,
    output logic [3:0]                o_arregion,
    output logic                      o_arvalid,
    input  logic                      i_arready,

    // --- 读数据通道 (R) ---
    input  logic [ID_WIDTH-1:0]       i_rid,
    input  logic [DATA_WIDTH-1:0]     i_rdata,
    input  logic [1:0]                i_rresp,
    input  logic                      i_rlast,
    input  logic                      i_rvalid,
    output logic                      o_rready
);

    // =========================================================================
    // 实例化 AXI_Lite_Master
    // =========================================================================
    AXI_Lite_Master #(
        .ADDR_WIDTH  (ADDR_WIDTH  ),
        .DATA_WIDTH  (DATA_WIDTH  ),
        .STRB_WIDTH  (STRB_WIDTH  ),
        .ID_WIDTH    (ID_WIDTH    ),
        .LEN_WIDTH   (LEN_WIDTH   )
    ) u_AXI_Lite_Master (
        .clk          (clk         ),
        .rst_n        (rst_n       ),

        // CPU 侧
        .req_valid    (i_transfer  ),
        .req_write    (i_write     ),
        .req_addr     (i_addr      ),
        .req_wdata    (i_wdata     ),
        .req_wstrb    (i_wmask     ),
        .req_ready    (),                       // CPU 不需要背压（同步阻塞）
        .rsp_valid    (o_tran_done ),
        .rsp_error    (),
        .rsp_rdata    (o_rdata     ),

        // AXI Master → Interconnect
        .m_awid       (o_awid      ),
        .m_awaddr     (o_awaddr    ),
        .m_awlen      (o_awlen     ),
        .m_awsize     (o_awsize    ),
        .m_awburst    (o_awburst   ),
        .m_awlock     (o_awlock    ),
        .m_awcache    (o_awcache   ),
        .m_awprot     (o_awprot    ),
        .m_awqos      (o_awqos     ),
        .m_awregion   (o_awregion  ),
        .m_awvalid    (o_awvalid   ),
        .m_awready    (i_awready   ),

        .m_wdata      (o_wdata     ),
        .m_wstrb      (o_wstrb     ),
        .m_wlast      (o_wlast     ),
        .m_wvalid     (o_wvalid    ),
        .m_wready     (i_wready    ),

        .m_bid        (i_bid       ),
        .m_bresp      (i_bresp     ),
        .m_bvalid     (i_bvalid    ),
        .m_bready     (o_bready    ),

        .m_arid       (o_arid      ),
        .m_araddr     (o_araddr    ),
        .m_arlen      (o_arlen     ),
        .m_arsize     (o_arsize    ),
        .m_arburst    (o_arburst   ),
        .m_arlock     (o_arlock    ),
        .m_arcache    (o_arcache   ),
        .m_arprot     (o_arprot    ),
        .m_arqos      (o_arqos     ),
        .m_arregion   (o_arregion  ),
        .m_arvalid    (o_arvalid   ),
        .m_arready    (i_arready   ),

        .m_rid        (i_rid       ),
        .m_rdata      (i_rdata     ),
        .m_rresp      (i_rresp     ),
        .m_rlast      (i_rlast     ),
        .m_rvalid     (i_rvalid    ),
        .m_rready     (o_rready    )
    );

endmodule
