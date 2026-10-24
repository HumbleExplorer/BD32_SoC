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
//   其余（0x0~0x7、0xD）→ 无从机选中，无握手发生（由主机侧总线超时以 DECERR 处理）
//
// 特性：
//   - 组合逻辑地址译码，无状态机延迟
//   - 端口保留 AXI-Full 信号，直接透传
//   - 单次传输（OUTSTANDING=1，无 Burst）
// =============================================================================

import bd32_pkg::*;

module AXI_Interconnect #(
    parameter ADDR_WIDTH   = `ADDR_WIDTH,
    parameter DATA_WIDTH   = `DATA_WIDTH,
    parameter STRB_WIDTH   = `ALIGN_BYTES,
    parameter ID_WIDTH     = AXI_ID_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    // ========================================================================
    // AXI Master 侧（连接 Bus_Access / AXI_Lite_Master）
    // ========================================================================
    // --- 写地址通道 (AW) ---
    // AXI4 Slave/Master 接口（接口）
    axi_if.slave  s,
    axi_if.master m0,
    axi_if.master m1,
    axi_if.master m2
);

    // =========================================================================
    // 写地址通道地址译码
    // =========================================================================
    logic [3:0] aw_msb;
    logic       aw_sel_apb;       // Slave 0
    logic       aw_sel_mrom_flash;// Slave 1
    logic       aw_sel_ddr;       // Slave 2

    assign aw_msb          = s.awaddr[31:28];
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

    assign ar_msb          = s.araddr[31:28];
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
        end else if (s.arvalid && s.arready) begin
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
        end else if (s.awvalid && s.awready) begin
            aw_sel_apb_r        <= aw_sel_apb;
            aw_sel_mrom_flash_r <= aw_sel_mrom_flash;
            aw_sel_ddr_r        <= aw_sel_ddr;
        end
    end

    // =========================================================================
    // 写地址通道路由 (AW)
    // =========================================================================
    assign {m0.awid, m1.awid, m2.awid}       = {3{s.awid}};
    assign {m0.awaddr, m1.awaddr, m2.awaddr} = {3{s.awaddr}};
    assign {m0.awlen, m1.awlen, m2.awlen}    = {3{s.awlen}};
    assign {m0.awsize, m1.awsize, m2.awsize} = {3{s.awsize}};
    assign {m0.awburst, m1.awburst, m2.awburst} = {3{s.awburst}};
    assign {m0.awlock, m1.awlock, m2.awlock} = {3{s.awlock}};
    assign {m0.awcache, m1.awcache, m2.awcache} = {3{s.awcache}};
    assign {m0.awprot, m1.awprot, m2.awprot} = {3{s.awprot}};
    assign {m0.awqos, m1.awqos, m2.awqos}   = {3{s.awqos}};
    assign {m0.awregion, m1.awregion, m2.awregion} = {3{s.awregion}};

    assign m0.awvalid = s.awvalid & aw_sel_apb;
    assign m1.awvalid = s.awvalid & aw_sel_mrom_flash;
    assign m2.awvalid = s.awvalid & aw_sel_ddr;

    assign s.awready = (m0.awready & aw_sel_apb) |
                       (m1.awready & aw_sel_mrom_flash) |
                       (m2.awready & aw_sel_ddr);

    // =========================================================================
    // 写数据通道路由 (W) — 使用组合译码 aw_sel_*（与 AW 同周期）
    // 原因：W 和 AW 是同一笔写事务，地址相同，必须同周期路由到同一 Slave
    // =========================================================================
    assign {m0.wdata, m1.wdata, m2.wdata}    = {3{s.wdata}};
    assign {m0.wstrb, m1.wstrb, m2.wstrb}    = {3{s.wstrb}};
    assign {m0.wlast, m1.wlast, m2.wlast}     = {3{s.wlast}};

    assign m0.wvalid = s.wvalid & aw_sel_apb;
    assign m1.wvalid = s.wvalid & aw_sel_mrom_flash;
    assign m2.wvalid = s.wvalid & aw_sel_ddr;

    assign s.wready = (m0.wready & aw_sel_apb) |
                      (m1.wready & aw_sel_mrom_flash) |
                      (m2.wready & aw_sel_ddr);

    // =========================================================================
    // 写响应通道路由 (B) — 使用锁存版 aw_sel_*_r
    // =========================================================================
    assign m0.bready = s.bready & aw_sel_apb_r;
    assign m1.bready = s.bready & aw_sel_mrom_flash_r;
    assign m2.bready = s.bready & aw_sel_ddr_r;

    assign s.bid    = aw_sel_apb_r       ? m0.bid  :
                      aw_sel_mrom_flash_r ? m1.bid  : m2.bid;

    assign s.bresp  = aw_sel_apb_r       ? m0.bresp  :
                      aw_sel_mrom_flash_r ? m1.bresp  : m2.bresp;

    assign s.bvalid = (m0.bvalid & aw_sel_apb_r) |
                      (m1.bvalid & aw_sel_mrom_flash_r) |
                      (m2.bvalid & aw_sel_ddr_r);

    // =========================================================================
    // 读地址通道路由 (AR)
    // =========================================================================
    assign {m0.arid, m1.arid, m2.arid}       = {3{s.arid}};
    assign {m0.araddr, m1.araddr, m2.araddr} = {3{s.araddr}};
    assign {m0.arlen, m1.arlen, m2.arlen}    = {3{s.arlen}};
    assign {m0.arsize, m1.arsize, m2.arsize} = {3{s.arsize}};
    assign {m0.arburst, m1.arburst, m2.arburst} = {3{s.arburst}};
    assign {m0.arlock, m1.arlock, m2.arlock} = {3{s.arlock}};
    assign {m0.arcache, m1.arcache, m2.arcache} = {3{s.arcache}};
    assign {m0.arprot, m1.arprot, m2.arprot} = {3{s.arprot}};
    assign {m0.arqos, m1.arqos, m2.arqos}   = {3{s.arqos}};
    assign {m0.arregion, m1.arregion, m2.arregion} = {3{s.arregion}};

    assign m0.arvalid = s.arvalid & ar_sel_apb;
    assign m1.arvalid = s.arvalid & ar_sel_mrom_flash;
    assign m2.arvalid = s.arvalid & ar_sel_ddr;

    assign s.arready = (m0.arready & ar_sel_apb) |
                       (m1.arready & ar_sel_mrom_flash) |
                       (m2.arready & ar_sel_ddr);

    // =========================================================================
    // 读数据通道路由 (R) — 使用锁存版 ar_sel_*_r
    // =========================================================================
    assign m0.rready = s.rready & ar_sel_apb_r;
    assign m1.rready = s.rready & ar_sel_mrom_flash_r;
    assign m2.rready = s.rready & ar_sel_ddr_r;

    assign s.rid    = ar_sel_apb_r       ? m0.rid  :
                      ar_sel_mrom_flash_r ? m1.rid  : m2.rid;

    assign s.rdata  = ar_sel_apb_r       ? m0.rdata  :
                      ar_sel_mrom_flash_r ? m1.rdata  : m2.rdata;

    assign s.rresp  = ar_sel_apb_r       ? m0.rresp  :
                      ar_sel_mrom_flash_r ? m1.rresp  : m2.rresp;

    assign s.rlast  = ar_sel_apb_r       ? m0.rlast  :
                      ar_sel_mrom_flash_r ? m1.rlast  : m2.rlast;

    assign s.rvalid = (m0.rvalid & ar_sel_apb_r) |
                      (m1.rvalid & ar_sel_mrom_flash_r) |
                      (m2.rvalid & ar_sel_ddr_r);

endmodule
