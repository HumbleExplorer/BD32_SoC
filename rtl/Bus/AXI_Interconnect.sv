`include "./../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;
// =============================================================================
// AXI_Interconnect - 地址路由型 AXI 互联矩阵（1 Master → 3 Slaves）
// =============================================================================
// 地址译码规则（地址高 4 位 [31:28]）：
//   4'hE / 4'hF  → APB Bridge    (0xE000_0000 ~ 0xFFFF_FFFF)
//   4'h8 / 4'h9 / 4'hA → MROM/Flash (err) (0x8000_0000 ~ 0xAFFF_FFFF)
//   4'hB / 4'hC  → DDR   (err)   (0xB000_0000 ~ 0xCFFF_FFFF)
//   其他         → 默认 err_slave
//
// 特性：
//   - 组合逻辑地址译码，无状态机延迟
//   - 端口保留 AXI-Full 信号，直接透传
//   - 单次传输（OUTSTANDING=1，无 Burst）
// =============================================================================

module AXI_Interconnect #(
    parameter ADDR_WIDTH   = `ADDR_WIDTH,
    parameter DATA_WIDTH   = `DATA_WIDTH,
    parameter STRB_WIDTH   = `ALIGN_BYTES,
    parameter ID_WIDTH     = `AXI_ID_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    // ========================================================================
    // AXI Master 侧（连接 Bus_Access / AXI_Lite_Master）
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
    input  logic                      s_rready,

    // ========================================================================
    // AXI Slave 0 侧 → APB Bridge
    // ========================================================================
    output logic [ID_WIDTH-1:0]       m0_awid,
    output logic [ADDR_WIDTH-1:0]     m0_awaddr,
    output logic [7:0]                m0_awlen,
    output logic [2:0]                m0_awsize,
    output logic [1:0]                m0_awburst,
    output logic                      m0_awlock,
    output logic [3:0]                m0_awcache,
    output logic [2:0]                m0_awprot,
    output logic [3:0]                m0_awqos,
    output logic [3:0]                m0_awregion,
    output logic                      m0_awvalid,
    input  logic                      m0_awready,
    output logic [DATA_WIDTH-1:0]     m0_wdata,
    output logic [STRB_WIDTH-1:0]     m0_wstrb,
    output logic                      m0_wlast,
    output logic                      m0_wvalid,
    input  logic                      m0_wready,
    input  logic [ID_WIDTH-1:0]       m0_bid,
    input  logic [1:0]                m0_bresp,
    input  logic                      m0_bvalid,
    output logic                      m0_bready,
    output logic [ID_WIDTH-1:0]       m0_arid,
    output logic [ADDR_WIDTH-1:0]     m0_araddr,
    output logic [7:0]                m0_arlen,
    output logic [2:0]                m0_arsize,
    output logic [1:0]                m0_arburst,
    output logic                      m0_arlock,
    output logic [3:0]                m0_arcache,
    output logic [2:0]                m0_arprot,
    output logic [3:0]                m0_arqos,
    output logic [3:0]                m0_arregion,
    output logic                      m0_arvalid,
    input  logic                      m0_arready,
    input  logic [ID_WIDTH-1:0]       m0_rid,
    input  logic [DATA_WIDTH-1:0]     m0_rdata,
    input  logic [1:0]                m0_rresp,
    input  logic                      m0_rlast,
    input  logic                      m0_rvalid,
    output logic                      m0_rready,

    // ========================================================================
    // AXI Slave 1 侧 → MROM/Flash (err_slave)
    // ========================================================================
    output logic [ID_WIDTH-1:0]       m1_awid,
    output logic [ADDR_WIDTH-1:0]     m1_awaddr,
    output logic [7:0]                m1_awlen,
    output logic [2:0]                m1_awsize,
    output logic [1:0]                m1_awburst,
    output logic                      m1_awlock,
    output logic [3:0]                m1_awcache,
    output logic [2:0]                m1_awprot,
    output logic [3:0]                m1_awqos,
    output logic [3:0]                m1_awregion,
    output logic                      m1_awvalid,
    input  logic                      m1_awready,
    output logic [DATA_WIDTH-1:0]     m1_wdata,
    output logic [STRB_WIDTH-1:0]     m1_wstrb,
    output logic                      m1_wlast,
    output logic                      m1_wvalid,
    input  logic                      m1_wready,
    input  logic [ID_WIDTH-1:0]       m1_bid,
    input  logic [1:0]                m1_bresp,
    input  logic                      m1_bvalid,
    output logic                      m1_bready,
    output logic [ID_WIDTH-1:0]       m1_arid,
    output logic [ADDR_WIDTH-1:0]     m1_araddr,
    output logic [7:0]                m1_arlen,
    output logic [2:0]                m1_arsize,
    output logic [1:0]                m1_arburst,
    output logic                      m1_arlock,
    output logic [3:0]                m1_arcache,
    output logic [2:0]                m1_arprot,
    output logic [3:0]                m1_arqos,
    output logic [3:0]                m1_arregion,
    output logic                      m1_arvalid,
    input  logic                      m1_arready,
    input  logic [ID_WIDTH-1:0]       m1_rid,
    input  logic [DATA_WIDTH-1:0]     m1_rdata,
    input  logic [1:0]                m1_rresp,
    input  logic                      m1_rlast,
    input  logic                      m1_rvalid,
    output logic                      m1_rready,

    // ========================================================================
    // AXI Slave 2 侧 → DDR (err_slave)
    // ========================================================================
    output logic [ID_WIDTH-1:0]       m2_awid,
    output logic [ADDR_WIDTH-1:0]     m2_awaddr,
    output logic [7:0]                m2_awlen,
    output logic [2:0]                m2_awsize,
    output logic [1:0]                m2_awburst,
    output logic                      m2_awlock,
    output logic [3:0]                m2_awcache,
    output logic [2:0]                m2_awprot,
    output logic [3:0]                m2_awqos,
    output logic [3:0]                m2_awregion,
    output logic                      m2_awvalid,
    input  logic                      m2_awready,
    output logic [DATA_WIDTH-1:0]     m2_wdata,
    output logic [STRB_WIDTH-1:0]     m2_wstrb,
    output logic                      m2_wlast,
    output logic                      m2_wvalid,
    input  logic                      m2_wready,
    input  logic [ID_WIDTH-1:0]       m2_bid,
    input  logic [1:0]                m2_bresp,
    input  logic                      m2_bvalid,
    output logic                      m2_bready,
    output logic [ID_WIDTH-1:0]       m2_arid,
    output logic [ADDR_WIDTH-1:0]     m2_araddr,
    output logic [7:0]                m2_arlen,
    output logic [2:0]                m2_arsize,
    output logic [1:0]                m2_arburst,
    output logic                      m2_arlock,
    output logic [3:0]                m2_arcache,
    output logic [2:0]                m2_arprot,
    output logic [3:0]                m2_arqos,
    output logic [3:0]                m2_arregion,
    output logic                      m2_arvalid,
    input  logic                      m2_arready,
    input  logic [ID_WIDTH-1:0]       m2_rid,
    input  logic [DATA_WIDTH-1:0]     m2_rdata,
    input  logic [1:0]                m2_rresp,
    input  logic                      m2_rlast,
    input  logic                      m2_rvalid,
    output logic                      m2_rready
);

    // =========================================================================
    // 写地址通道地址译码
    // =========================================================================
    logic [3:0] aw_msb;
    logic       aw_sel_apb;       // Slave 0
    logic       aw_sel_mrom_flash;// Slave 1
    logic       aw_sel_ddr;       // Slave 2

    assign aw_msb          = s_awaddr[31:28];
    assign aw_sel_apb      = (aw_msb == 4'hE) || (aw_msb == 4'hF);
    assign aw_sel_mrom_flash = (aw_msb == 4'h8) || (aw_msb == 4'h9) || (aw_msb == 4'hA);
    assign aw_sel_ddr      = (aw_msb == 4'hB) || (aw_msb == 4'hC);

    // =========================================================================
    // 读地址通道地址译码
    // =========================================================================
    logic [3:0] ar_msb;
    logic       ar_sel_apb;
    logic       ar_sel_mrom_flash;
    logic       ar_sel_ddr;

    assign ar_msb          = s_araddr[31:28];
    assign ar_sel_apb      = (ar_msb == 4'hE) || (ar_msb == 4'hF);
    assign ar_sel_mrom_flash = (ar_msb == 4'h8) || (ar_msb == 4'h9) || (ar_msb == 4'hA);
    assign ar_sel_ddr      = (ar_msb == 4'hB) || (ar_msb == 4'hC);

    // =========================================================================
    // 锁存 sel 信号（AR/AW 握手时刻锁存，打破组合环路）
    // =========================================================================
    // R 通道依赖 ar_sel_*：从机 R 响应至少在 AR 握手 1 拍后返回，
    // 因此锁存版 ar_sel_*_r 在 R 数据到来时已稳定，零延迟开销。
    logic ar_sel_apb_r, ar_sel_mrom_flash_r, ar_sel_ddr_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_sel_apb_r        <= 1'b0;
            ar_sel_mrom_flash_r <= 1'b0;
            ar_sel_ddr_r        <= 1'b0;
        end else if (s_arvalid && s_arready) begin
            ar_sel_apb_r        <= ar_sel_apb;
            ar_sel_mrom_flash_r <= ar_sel_mrom_flash;
            ar_sel_ddr_r        <= ar_sel_ddr;
        end
    end

    // B 通道依赖 aw_sel_*：从机 B 响应至少在 AW 握手 1 拍后返回，
    // 同理锁存版 aw_sel_*_r 在 B 响应到来时已稳定。
    logic aw_sel_apb_r, aw_sel_mrom_flash_r, aw_sel_ddr_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_sel_apb_r        <= 1'b0;
            aw_sel_mrom_flash_r <= 1'b0;
            aw_sel_ddr_r        <= 1'b0;
        end else if (s_awvalid && s_awready) begin
            aw_sel_apb_r        <= aw_sel_apb;
            aw_sel_mrom_flash_r <= aw_sel_mrom_flash;
            aw_sel_ddr_r        <= aw_sel_ddr;
        end
    end

    // =========================================================================
    // 写地址通道路由 (AW)
    // =========================================================================
    assign {m0_awid, m1_awid, m2_awid}       = {3{s_awid}};
    assign {m0_awaddr, m1_awaddr, m2_awaddr} = {3{s_awaddr}};
    assign {m0_awlen, m1_awlen, m2_awlen}    = {3{s_awlen}};
    assign {m0_awsize, m1_awsize, m2_awsize} = {3{s_awsize}};
    assign {m0_awburst, m1_awburst, m2_awburst} = {3{s_awburst}};
    assign {m0_awlock, m1_awlock, m2_awlock} = {3{s_awlock}};
    assign {m0_awcache, m1_awcache, m2_awcache} = {3{s_awcache}};
    assign {m0_awprot, m1_awprot, m2_awprot} = {3{s_awprot}};
    assign {m0_awqos, m1_awqos, m2_awqos}   = {3{s_awqos}};
    assign {m0_awregion, m1_awregion, m2_awregion} = {3{s_awregion}};

    assign m0_awvalid = s_awvalid & aw_sel_apb;
    assign m1_awvalid = s_awvalid & aw_sel_mrom_flash;
    assign m2_awvalid = s_awvalid & aw_sel_ddr;

    assign s_awready = (m0_awready & aw_sel_apb) |
                       (m1_awready & aw_sel_mrom_flash) |
                       (m2_awready & aw_sel_ddr);

    // =========================================================================
    // 写数据通道路由 (W) — 使用组合译码 aw_sel_*（与 AW 同周期）
    // 原因：W 和 AW 是同一笔写事务，地址相同，必须同周期路由到同一 Slave
    // =========================================================================
    assign {m0_wdata, m1_wdata, m2_wdata}    = {3{s_wdata}};
    assign {m0_wstrb, m1_wstrb, m2_wstrb}    = {3{s_wstrb}};
    assign {m0_wlast, m1_wlast, m2_wlast}     = {3{s_wlast}};

    assign m0_wvalid = s_wvalid & aw_sel_apb;
    assign m1_wvalid = s_wvalid & aw_sel_mrom_flash;
    assign m2_wvalid = s_wvalid & aw_sel_ddr;

    assign s_wready = (m0_wready & aw_sel_apb) |
                      (m1_wready & aw_sel_mrom_flash) |
                      (m2_wready & aw_sel_ddr);

    // =========================================================================
    // 写响应通道路由 (B) — 使用锁存版 aw_sel_*_r
    // =========================================================================
    assign m0_bready = s_bready & aw_sel_apb_r;
    assign m1_bready = s_bready & aw_sel_mrom_flash_r;
    assign m2_bready = s_bready & aw_sel_ddr_r;

    assign s_bid    = aw_sel_apb_r       ? m0_bid  :
                      aw_sel_mrom_flash_r ? m1_bid  : m2_bid;

    assign s_bresp  = aw_sel_apb_r       ? m0_bresp  :
                      aw_sel_mrom_flash_r ? m1_bresp  : m2_bresp;

    assign s_bvalid = (m0_bvalid & aw_sel_apb_r) |
                      (m1_bvalid & aw_sel_mrom_flash_r) |
                      (m2_bvalid & aw_sel_ddr_r);

    // =========================================================================
    // 读地址通道路由 (AR)
    // =========================================================================
    assign {m0_arid, m1_arid, m2_arid}       = {3{s_arid}};
    assign {m0_araddr, m1_araddr, m2_araddr} = {3{s_araddr}};
    assign {m0_arlen, m1_arlen, m2_arlen}    = {3{s_arlen}};
    assign {m0_arsize, m1_arsize, m2_arsize} = {3{s_arsize}};
    assign {m0_arburst, m1_arburst, m2_arburst} = {3{s_arburst}};
    assign {m0_arlock, m1_arlock, m2_arlock} = {3{s_arlock}};
    assign {m0_arcache, m1_arcache, m2_arcache} = {3{s_arcache}};
    assign {m0_arprot, m1_arprot, m2_arprot} = {3{s_arprot}};
    assign {m0_arqos, m1_arqos, m2_arqos}   = {3{s_arqos}};
    assign {m0_arregion, m1_arregion, m2_arregion} = {3{s_arregion}};

    assign m0_arvalid = s_arvalid & ar_sel_apb;
    assign m1_arvalid = s_arvalid & ar_sel_mrom_flash;
    assign m2_arvalid = s_arvalid & ar_sel_ddr;

    assign s_arready = (m0_arready & ar_sel_apb) |
                       (m1_arready & ar_sel_mrom_flash) |
                       (m2_arready & ar_sel_ddr);

    // =========================================================================
    // 读数据通道路由 (R) — 使用锁存版 ar_sel_*_r
    // =========================================================================
    assign m0_rready = s_rready & ar_sel_apb_r;
    assign m1_rready = s_rready & ar_sel_mrom_flash_r;
    assign m2_rready = s_rready & ar_sel_ddr_r;

    assign s_rid    = ar_sel_apb_r       ? m0_rid  :
                      ar_sel_mrom_flash_r ? m1_rid  : m2_rid;

    assign s_rdata  = ar_sel_apb_r       ? m0_rdata  :
                      ar_sel_mrom_flash_r ? m1_rdata  : m2_rdata;

    assign s_rresp  = ar_sel_apb_r       ? m0_rresp  :
                      ar_sel_mrom_flash_r ? m1_rresp  : m2_rresp;

    assign s_rlast  = ar_sel_apb_r       ? m0_rlast  :
                      ar_sel_mrom_flash_r ? m1_rlast  : m2_rlast;

    assign s_rvalid = (m0_rvalid & ar_sel_apb_r) |
                      (m1_rvalid & ar_sel_mrom_flash_r) |
                      (m2_rvalid & ar_sel_ddr_r);

endmodule
