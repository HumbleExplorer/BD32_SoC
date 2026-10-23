// ============================================================================
// tb_axi_interconnect.sv — AXI 互联链验证（verification_plan §SoC PLANNED 项完成）
//
// BD32 — RV32IM Pipelined RISC-V SoC
// Copyright (c) 2026 BD32 Project
// SPDX-License-Identifier: Apache-2.0
//
// 被测链（与 SoC_top 同构，全真实 DUT）：
//   axi_lite_master_bfm → AXI_Interconnect ┬─ m0 → AXI_APB_Bridge → APB_Interconnect
//                                          │        └─ GPIO 槽位挂 apb_slave_stub
//                                          ├─ m1 → axi_err_slave（0x8/9/A 段）
//                                          └─ m2 → axi_err_slave（0xB/C 段）
//
// 用例：
//   T1 APB 区写读回环（OKAY + 数据一致）
//   T2 从机随机等待态压力（数据完整性，反压经桥回传 AXI）
//   T3 桩从机 PSLVERR → AXI SLVERR 传播
//   T4 MROM/Flash 段 err_slave：读 0 + OKAY、写接受
//   T5 DDR 段 err_slave：同 T4
//   T6 桩从机不响应（PREADY 保持低）→ 桥超时 → SLVERR（有界完成）
//   T7 未路由段（0xD 段）：无从机握手 → BFM 有界超时（验证不挂死）
// ============================================================================
timeunit 1ns;
timeprecision 1ps;

module tb_axi_interconnect;

localparam logic [31:0] STUB_BASE  = 32'hE000_0000;  // APB GPIO 槽位（桩从机）
localparam logic [31:0] STUB_ERR   = 32'hE000_0800;  // addr[11]=1 → 桩从机 PSLVERR
localparam logic [31:0] MROM_ADDR  = 32'h9000_0000;  // m1 err_slave 段
localparam logic [31:0] DDR_ADDR   = 32'hB000_0000;  // m2 err_slave 段
localparam logic [31:0] DEAD_ADDR  = 32'hD000_0000;  // 未路由段

int error_count = 0;
int test_no     = 0;

logic clk;
logic rst_n;

// =================== 时钟与复位 ===================
initial begin
    clk = 1'b0;
    forever #10 clk = ~clk;     // 50MHz
end

initial begin
    rst_n = 1'b0;
    #200;
    rst_n = 1'b1;
end

// =================== AXI 互联信号 ===================
logic [3:0]  awid, arid, bid, rid;
logic [31:0] awaddr, araddr, wdata, rdata;
logic [7:0]  awlen, arlen;
logic [2:0]  awsize, arsize;
logic [1:0]  awburst, arburst, bresp, rresp;
logic        awlock, arlock, wlast, rlast;
logic [3:0]  awcache, arcache, awqos, arqos, awregion, arregion;
logic [2:0]  awprot, arprot;
logic        awvalid, awready, wvalid, wready, bvalid, bready;
logic        arvalid, arready, rvalid, rready;
logic [3:0]  wstrb;

// =================== AXI-Lite Master BFM ===================
axi_lite_master_bfm #(
    .ADDR_WIDTH    (32),
    .DATA_WIDTH    (32),
    .STRB_WIDTH    (4),
    .ID_WIDTH      (4),
    .TIMEOUT_CYCLES(4096)
) bfm (
    .clk        (clk),
    .rst_n      (rst_n),
    .m_awid     (awid),
    .m_awaddr   (awaddr),
    .m_awlen    (awlen),
    .m_awsize   (awsize),
    .m_awburst  (awburst),
    .m_awlock   (awlock),
    .m_awcache  (awcache),
    .m_awprot   (awprot),
    .m_awqos    (awqos),
    .m_awregion (awregion),
    .m_awvalid  (awvalid),
    .m_awready  (awready),
    .m_wdata    (wdata),
    .m_wstrb    (wstrb),
    .m_wlast    (wlast),
    .m_wvalid   (wvalid),
    .m_wready   (wready),
    .m_bid      (bid),
    .m_bresp    (bresp),
    .m_bvalid   (bvalid),
    .m_bready   (bready),
    .m_arid     (arid),
    .m_araddr   (araddr),
    .m_arlen    (arlen),
    .m_arsize   (arsize),
    .m_arburst  (arburst),
    .m_arlock   (arlock),
    .m_arcache  (arcache),
    .m_arprot   (arprot),
    .m_arqos    (arqos),
    .m_arregion (arregion),
    .m_arvalid  (arvalid),
    .m_arready  (arready),
    .m_rid      (rid),
    .m_rdata    (rdata),
    .m_rresp    (rresp),
    .m_rlast    (rlast),
    .m_rvalid   (rvalid),
    .m_rready   (rready)
);

// =================== 互联三个从机口的全部信号 ===================
// m0：APB 桥
logic [3:0]  m0_awid, m0_arid, m0_bid, m0_rid;
logic [31:0] m0_awaddr, m0_araddr, m0_wdata, m0_rdata;
logic [7:0]  m0_awlen, m0_arlen;
logic [2:0]  m0_awsize, m0_arsize;
logic [1:0]  m0_awburst, m0_arburst, m0_bresp, m0_rresp;
logic        m0_awlock, m0_arlock, m0_wlast, m0_rlast;
logic [3:0]  m0_awcache, m0_arcache, m0_awqos, m0_arqos, m0_awregion, m0_arregion;
logic [2:0]  m0_awprot, m0_arprot;
logic [3:0]  m0_wstrb;
logic        m0_awvalid, m0_awready, m0_wvalid, m0_wready, m0_bvalid, m0_bready;
logic        m0_arvalid, m0_arready, m0_rvalid, m0_rready;

// m1/m2：err_slave（同一 shapes）
logic [3:0]  m1_awid, m1_arid, m1_bid, m1_rid;
logic [31:0] m1_awaddr, m1_araddr, m1_wdata, m1_rdata;
logic [7:0]  m1_awlen, m1_arlen;
logic [2:0]  m1_awsize, m1_arsize;
logic [1:0]  m1_awburst, m1_arburst, m1_bresp, m1_rresp;
logic        m1_awlock, m1_arlock, m1_wlast, m1_rlast;
logic [3:0]  m1_awcache, m1_arcache, m1_awqos, m1_arqos, m1_awregion, m1_arregion;
logic [2:0]  m1_awprot, m1_arprot;
logic [3:0]  m1_wstrb;
logic        m1_awvalid, m1_awready, m1_wvalid, m1_wready, m1_bvalid, m1_bready;
logic        m1_arvalid, m1_arready, m1_rvalid, m1_rready;

logic [3:0]  m2_awid, m2_arid, m2_bid, m2_rid;
logic [31:0] m2_awaddr, m2_araddr, m2_wdata, m2_rdata;
logic [7:0]  m2_awlen, m2_arlen;
logic [2:0]  m2_awsize, m2_arsize;
logic [1:0]  m2_awburst, m2_arburst, m2_bresp, m2_rresp;
logic        m2_awlock, m2_arlock, m2_wlast, m2_rlast;
logic [3:0]  m2_awcache, m2_arcache, m2_awqos, m2_arqos, m2_awregion, m2_arregion;
logic [2:0]  m2_awprot, m2_arprot;
logic [3:0]  m2_wstrb;
logic        m2_awvalid, m2_awready, m2_wvalid, m2_wready, m2_bvalid, m2_bready;
logic        m2_arvalid, m2_arready, m2_rvalid, m2_rready;

// =================== DUT：AXI_Interconnect ===================
AXI_Interconnect #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .STRB_WIDTH (4),
    .ID_WIDTH   (4)
) u_interconnect (
    .clk        (clk),
    .rst_n      (rst_n),
    .s_awid     (awid),
    .s_awaddr   (awaddr),
    .s_awlen    (awlen),
    .s_awsize   (awsize),
    .s_awburst  (awburst),
    .s_awlock   (awlock),
    .s_awcache  (awcache),
    .s_awprot   (awprot),
    .s_awqos    (awqos),
    .s_awregion (awregion),
    .s_awvalid  (awvalid),
    .s_awready  (awready),
    .s_wdata    (wdata),
    .s_wstrb    (wstrb),
    .s_wlast    (wlast),
    .s_wvalid   (wvalid),
    .s_wready   (wready),
    .s_bid      (bid),
    .s_bresp    (bresp),
    .s_bvalid   (bvalid),
    .s_bready   (bready),
    .s_arid     (arid),
    .s_araddr   (araddr),
    .s_arlen    (arlen),
    .s_arsize   (arsize),
    .s_arburst  (arburst),
    .s_arlock   (arlock),
    .s_arcache  (arcache),
    .s_arprot   (arprot),
    .s_arqos    (arqos),
    .s_arregion (arregion),
    .s_arvalid  (arvalid),
    .s_arready  (arready),
    .s_rid      (rid),
    .s_rdata    (rdata),
    .s_rresp    (rresp),
    .s_rlast    (rlast),
    .s_rvalid   (rvalid),
    .s_rready   (rready),
    .m0_awid    (m0_awid),
    .m0_awaddr  (m0_awaddr),
    .m0_awlen   (m0_awlen),
    .m0_awsize  (m0_awsize),
    .m0_awburst (m0_awburst),
    .m0_awlock  (m0_awlock),
    .m0_awcache (m0_awcache),
    .m0_awprot  (m0_awprot),
    .m0_awqos   (m0_awqos),
    .m0_awregion(m0_awregion),
    .m0_awvalid (m0_awvalid),
    .m0_awready (m0_awready),
    .m0_wdata   (m0_wdata),
    .m0_wstrb   (m0_wstrb),
    .m0_wlast   (m0_wlast),
    .m0_wvalid  (m0_wvalid),
    .m0_wready  (m0_wready),
    .m0_bid     (m0_bid),
    .m0_bresp   (m0_bresp),
    .m0_bvalid  (m0_bvalid),
    .m0_bready  (m0_bready),
    .m0_arid    (m0_arid),
    .m0_araddr  (m0_araddr),
    .m0_arlen   (m0_arlen),
    .m0_arsize  (m0_arsize),
    .m0_arburst (m0_arburst),
    .m0_arlock  (m0_arlock),
    .m0_arcache (m0_arcache),
    .m0_arprot  (m0_arprot),
    .m0_arqos   (m0_arqos),
    .m0_arregion(m0_arregion),
    .m0_arvalid (m0_arvalid),
    .m0_arready (m0_arready),
    .m0_rid     (m0_rid),
    .m0_rdata   (m0_rdata),
    .m0_rresp   (m0_rresp),
    .m0_rlast   (m0_rlast),
    .m0_rvalid  (m0_rvalid),
    .m0_rready  (m0_rready),
    .m1_awid    (m1_awid),
    .m1_awaddr  (m1_awaddr),
    .m1_awlen   (m1_awlen),
    .m1_awsize  (m1_awsize),
    .m1_awburst (m1_awburst),
    .m1_awlock  (m1_awlock),
    .m1_awcache (m1_awcache),
    .m1_awprot  (m1_awprot),
    .m1_awqos   (m1_awqos),
    .m1_awregion(m1_awregion),
    .m1_awvalid (m1_awvalid),
    .m1_awready (m1_awready),
    .m1_wdata   (m1_wdata),
    .m1_wstrb   (m1_wstrb),
    .m1_wlast   (m1_wlast),
    .m1_wvalid  (m1_wvalid),
    .m1_wready  (m1_wready),
    .m1_bid     (m1_bid),
    .m1_bresp   (m1_bresp),
    .m1_bvalid  (m1_bvalid),
    .m1_bready  (m1_bready),
    .m1_arid    (m1_arid),
    .m1_araddr  (m1_araddr),
    .m1_arlen   (m1_arlen),
    .m1_arsize  (m1_arsize),
    .m1_arburst (m1_arburst),
    .m1_arlock  (m1_arlock),
    .m1_arcache (m1_arcache),
    .m1_arprot  (m1_arprot),
    .m1_arqos   (m1_arqos),
    .m1_arregion(m1_arregion),
    .m1_arvalid (m1_arvalid),
    .m1_arready (m1_arready),
    .m1_rid     (m1_rid),
    .m1_rdata   (m1_rdata),
    .m1_rresp   (m1_rresp),
    .m1_rlast   (m1_rlast),
    .m1_rvalid  (m1_rvalid),
    .m1_rready  (m1_rready),
    .m2_awid    (m2_awid),
    .m2_awaddr  (m2_awaddr),
    .m2_awlen   (m2_awlen),
    .m2_awsize  (m2_awsize),
    .m2_awburst (m2_awburst),
    .m2_awlock  (m2_awlock),
    .m2_awcache (m2_awcache),
    .m2_awprot  (m2_awprot),
    .m2_awqos   (m2_awqos),
    .m2_awregion(m2_awregion),
    .m2_awvalid (m2_awvalid),
    .m2_awready (m2_awready),
    .m2_wdata   (m2_wdata),
    .m2_wstrb   (m2_wstrb),
    .m2_wlast   (m2_wlast),
    .m2_wvalid  (m2_wvalid),
    .m2_wready  (m2_wready),
    .m2_bid     (m2_bid),
    .m2_bresp   (m2_bresp),
    .m2_bvalid  (m2_bvalid),
    .m2_bready  (m2_bready),
    .m2_arid    (m2_arid),
    .m2_araddr  (m2_araddr),
    .m2_arlen   (m2_arlen),
    .m2_arsize  (m2_arsize),
    .m2_arburst (m2_arburst),
    .m2_arlock  (m2_arlock),
    .m2_arcache (m2_arcache),
    .m2_arprot  (m2_arprot),
    .m2_arqos   (m2_arqos),
    .m2_arregion(m2_arregion),
    .m2_arvalid (m2_arvalid),
    .m2_arready (m2_arready),
    .m2_rid     (m2_rid),
    .m2_rdata   (m2_rdata),
    .m2_rresp   (m2_rresp),
    .m2_rlast   (m2_rlast),
    .m2_rvalid  (m2_rvalid),
    .m2_rready  (m2_rready)
);

// =================== DUT：axi_err_slave ×2 ===================
axi_err_slave #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .STRB_WIDTH (4),
    .ID_WIDTH   (4)
) u_err_mrom (
    .clk        (clk),
    .rst_n      (rst_n),
    .s_awid     (m1_awid),
    .s_awaddr   (m1_awaddr),
    .s_awlen    (m1_awlen),
    .s_awsize   (m1_awsize),
    .s_awburst  (m1_awburst),
    .s_awlock   (m1_awlock),
    .s_awcache  (m1_awcache),
    .s_awprot   (m1_awprot),
    .s_awqos    (m1_awqos),
    .s_awregion (m1_awregion),
    .s_awvalid  (m1_awvalid),
    .s_awready  (m1_awready),
    .s_wdata    (m1_wdata),
    .s_wstrb    (m1_wstrb),
    .s_wlast    (m1_wlast),
    .s_wvalid   (m1_wvalid),
    .s_wready   (m1_wready),
    .s_bid      (m1_bid),
    .s_bresp    (m1_bresp),
    .s_bvalid   (m1_bvalid),
    .s_bready   (m1_bready),
    .s_arid     (m1_arid),
    .s_araddr   (m1_araddr),
    .s_arlen    (m1_arlen),
    .s_arsize   (m1_arsize),
    .s_arburst  (m1_arburst),
    .s_arlock   (m1_arlock),
    .s_arcache  (m1_arcache),
    .s_arprot   (m1_arprot),
    .s_arqos    (m1_arqos),
    .s_arregion (m1_arregion),
    .s_arvalid  (m1_arvalid),
    .s_arready  (m1_arready),
    .s_rid      (m1_rid),
    .s_rdata    (m1_rdata),
    .s_rresp    (m1_rresp),
    .s_rlast    (m1_rlast),
    .s_rvalid   (m1_rvalid),
    .s_rready   (m1_rready)
);

axi_err_slave #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .STRB_WIDTH (4),
    .ID_WIDTH   (4)
) u_err_ddr (
    .clk        (clk),
    .rst_n      (rst_n),
    .s_awid     (m2_awid),
    .s_awaddr   (m2_awaddr),
    .s_awlen    (m2_awlen),
    .s_awsize   (m2_awsize),
    .s_awburst  (m2_awburst),
    .s_awlock   (m2_awlock),
    .s_awcache  (m2_awcache),
    .s_awprot   (m2_awprot),
    .s_awqos    (m2_awqos),
    .s_awregion (m2_awregion),
    .s_awvalid  (m2_awvalid),
    .s_awready  (m2_awready),
    .s_wdata    (m2_wdata),
    .s_wstrb    (m2_wstrb),
    .s_wlast    (m2_wlast),
    .s_wvalid   (m2_wvalid),
    .s_wready   (m2_wready),
    .s_bid      (m2_bid),
    .s_bresp    (m2_bresp),
    .s_bvalid   (m2_bvalid),
    .s_bready   (m2_bready),
    .s_arid     (m2_arid),
    .s_araddr   (m2_araddr),
    .s_arlen    (m2_arlen),
    .s_arsize   (m2_arsize),
    .s_arburst  (m2_arburst),
    .s_arlock   (m2_arlock),
    .s_arcache  (m2_arcache),
    .s_arprot   (m2_arprot),
    .s_arqos    (m2_arqos),
    .s_arregion (m2_arregion),
    .s_arvalid  (m2_arvalid),
    .s_arready  (m2_arready),
    .s_rid      (m2_rid),
    .s_rdata    (m2_rdata),
    .s_rresp    (m2_rresp),
    .s_rlast    (m2_rlast),
    .s_rvalid   (m2_rvalid),
    .s_rready   (m2_rready)
);

// =================== DUT：AXI_APB_Bridge ===================
logic [31:0] bridge_paddr, bridge_pwdata, bridge_prdata;
logic [3:0]  bridge_pstrb;
logic        bridge_psel, bridge_penable, bridge_pwrite, bridge_pready, bridge_pslverr;

AXI_APB_Bridge #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .STRB_WIDTH (4),
    .ID_WIDTH   (4),
    .LEN_WIDTH  (8)
) u_bridge (
    .clk       (clk),
    .rst_n     (rst_n),
    .s_awid    (m0_awid),
    .s_awaddr  (m0_awaddr),
    .s_awlen   (m0_awlen),
    .s_awsize  (m0_awsize),
    .s_awburst (m0_awburst),
    .s_awlock  (m0_awlock),
    .s_awcache (m0_awcache),
    .s_awprot  (m0_awprot),
    .s_awqos   (m0_awqos),
    .s_awregion(m0_awregion),
    .s_awvalid (m0_awvalid),
    .s_awready (m0_awready),
    .s_wdata   (m0_wdata),
    .s_wstrb   (m0_wstrb),
    .s_wlast   (m0_wlast),
    .s_wvalid  (m0_wvalid),
    .s_wready  (m0_wready),
    .s_bid     (m0_bid),
    .s_bresp   (m0_bresp),
    .s_bvalid  (m0_bvalid),
    .s_bready  (m0_bready),
    .s_arid    (m0_arid),
    .s_araddr  (m0_araddr),
    .s_arlen   (m0_arlen),
    .s_arsize  (m0_arsize),
    .s_arburst (m0_arburst),
    .s_arlock  (m0_arlock),
    .s_arcache (m0_arcache),
    .s_arprot  (m0_arprot),
    .s_arqos   (m0_arqos),
    .s_arregion(m0_arregion),
    .s_arvalid (m0_arvalid),
    .s_arready (m0_arready),
    .s_rid     (m0_rid),
    .s_rdata   (m0_rdata),
    .s_rresp   (m0_rresp),
    .s_rlast   (m0_rlast),
    .s_rvalid  (m0_rvalid),
    .s_rready  (m0_rready),
    .PADDR     (bridge_paddr),
    .PSEL      (bridge_psel),
    .PENABLE   (bridge_penable),
    .PWRITE    (bridge_pwrite),
    .PSTRB     (bridge_pstrb),
    .PWDATA    (bridge_pwdata),
    .PRDATA    (bridge_prdata),
    .PREADY    (bridge_pready),
    .PSLVERR   (bridge_pslverr)
);

// =================== DUT：APB_Interconnect（16 槽，仅 GPIO 槽挂桩从机）====================
logic [15:0] apb_psel;
logic [31:0] apb_prdata [16];
logic [15:0] apb_pready;
logic [15:0] apb_pslverr;
logic [31:0] stub_prdata;
logic        stub_pready, stub_pslverr;
logic        stub_hang;
logic        stub_rand_wait;

APB_Interconnect #(
    .PADDR_WIDTH (32),
    .PDATA_WIDTH (32),
    .NUM_SLAVES  (16)
) u_apb_interconnect (
    .PADDR    (bridge_paddr),
    .PSEL     (bridge_psel),
    .i_prdata (apb_prdata),
    .i_pready (apb_pready),
    .i_pslverr(apb_pslverr),
    .o_psel   (apb_psel),
    .PRDATA   (bridge_prdata),
    .PREADY   (bridge_pready),
    .PSLVERR  (bridge_pslverr)
);

// 非桩槽位与 SoC_top 同构：PREADY=1, PRDATA=0, PSLVERR=0
generate
    for (genvar g = 0; g < 16; g = g + 1) begin : gen_slot
        if (g != 2) begin : gen_idle
            assign apb_prdata[g]   = 32'd0;
            assign apb_pready[g]   = 1'b1;
            assign apb_pslverr[g]  = 1'b0;
        end
    end
endgenerate
assign apb_prdata[2]   = stub_prdata;
assign apb_pready[2]   = stub_pready;
assign apb_pslverr[2]  = stub_pslverr;

// =================== TB 本地桩从机：APB 寄存器块（GPIO 槽位）====================
// 特性：16 字寄存器；SETUP 拍按使能载入 0~3 拍随机等待；PADDR[11]=1 时
// ACCESS 完成拍报 PSLVERR；force_hang 拉低 PREADY（测桥超时路径）。
apb_slave_stub u_stub (
    .PCLK        (clk),
    .PRESETn     (rst_n),
    .PSEL        (apb_psel[2]),
    .PENABLE     (bridge_penable),
    .PADDR       (bridge_paddr),
    .PWRITE      (bridge_pwrite),
    .PSTRB       (bridge_pstrb),
    .PWDATA      (bridge_pwdata),
    .PRDATA      (stub_prdata),
    .PREADY      (stub_pready),
    .PSLVERR     (stub_pslverr),
    .force_hang  (stub_hang),
    .rand_wait_en(stub_rand_wait)
);

// =================== 主测试流程 ===================
task automatic check(input bit cond, input string msg);
    if (!cond) begin
        error_count++;
        $display("[T%0d] FAIL: %s", test_no, msg);
    end
endtask

task automatic test_apb_region();
    logic [31:0] rdata_q;
    logic [1:0]  resp;
    bit          ok;
    logic [31:0] pat;

    // T1：写读回环
    test_no = 1;
    bfm.write(STUB_BASE + 0, 32'hA5A5_5A5A, 4'hF, resp, ok);
    check(ok && resp == 2'b00, "T1 write resp not OKAY");
    bfm.read(STUB_BASE + 0, rdata_q, resp, ok);
    check(ok && resp == 2'b00 && rdata_q == 32'hA5A5_5A5A,
          $sformatf("T1 readback mismatch: %h", rdata_q));

    // T2：随机等待态压力，走位数据
    test_no = 2;
    stub_rand_wait = 1'b1;
    for (int i = 0; i < 16; i++) begin
        pat = (32'h0000_0001 << i) | (32'hDEAD_0000 + i * 32'h0101);
        bfm.write(STUB_BASE + i * 4, pat, 4'hF, resp, ok);
        check(ok && resp == 2'b00, $sformatf("T2 write[%0d] resp=%b", i, resp));
    end
    for (int i = 0; i < 16; i++) begin
        pat = (32'h0000_0001 << i) | (32'hDEAD_0000 + i * 32'h0101);
        bfm.read(STUB_BASE + i * 4, rdata_q, resp, ok);
        check(ok && resp == 2'b00 && rdata_q == pat,
              $sformatf("T2 read[%0d] mismatch: got %h want %h", i, rdata_q, pat));
    end
    stub_rand_wait = 1'b0;

    // T3：PSLVERR → SLVERR
    test_no = 3;
    bfm.write(STUB_ERR, 32'h0, 4'hF, resp, ok);
    check(ok && resp == 2'b10, $sformatf("T3 write PSLVERR resp=%b", resp));
    bfm.read(STUB_ERR, rdata_q, resp, ok);
    check(ok && resp == 2'b10, $sformatf("T3 read PSLVERR resp=%b", resp));
endtask

task automatic test_err_slave();
    logic [31:0] rdata_q;
    logic [1:0]  resp;
    bit          ok;

    // T4：MROM/Flash 段
    test_no = 4;
    bfm.read(MROM_ADDR, rdata_q, resp, ok);
    check(ok && resp == 2'b00 && rdata_q == 32'd0,
          $sformatf("T4 err read: data=%h resp=%b", rdata_q, resp));
    bfm.write(MROM_ADDR, 32'h1234_5678, 4'hF, resp, ok);
    check(ok && resp == 2'b00, $sformatf("T4 err write resp=%b", resp));

    // T5：DDR 段
    test_no = 5;
    bfm.read(DDR_ADDR, rdata_q, resp, ok);
    check(ok && resp == 2'b00 && rdata_q == 32'd0,
          $sformatf("T5 err read: data=%h resp=%b", rdata_q, resp));
    bfm.write(DDR_ADDR, 32'h8765_4321, 4'hF, resp, ok);
    check(ok && resp == 2'b00, $sformatf("T5 err write resp=%b", resp));
endtask

task automatic test_timeout_paths();
    logic [31:0] rdata_q;
    logic [1:0]  resp;
    bit          ok;
    realtime     t0;

    // T6：桩从机不响应（PREADY 保持低）→ 桥超时（BUS_TIMEOUT=1024 拍）→ SLVERR
    test_no = 6;
    stub_hang = 1'b1;
    t0 = $realtime;
    bfm.read(STUB_BASE, rdata_q, resp, ok);
    check(ok && resp == 2'b10,
          $sformatf("T6 hung-slave read resp=%b ok=%b", resp, ok));
    check(($realtime - t0) < 40.0us,
          "T6 completion not bounded (bridge timeout too long?)");
    bfm.write(STUB_BASE, 32'h0, 4'hF, resp, ok);
    check(ok && resp == 2'b10, $sformatf("T6 hung-slave write resp=%b", resp));
    stub_hang = 1'b0;

    // T7：未路由段 → 无从机握手 → BFM 有界超时（不挂死 TB）
    test_no = 7;
    t0 = $realtime;
    bfm.read(DEAD_ADDR, rdata_q, resp, ok);
    check(!ok, "T7 unrouted read should hit BFM timeout (ok=0)");
    check(($realtime - t0) < 200.0us, "T7 read not bounded");
    t0 = $realtime;
    bfm.write(DEAD_ADDR, 32'h0, 4'hF, resp, ok);
    check(!ok, "T7 unrouted write should hit BFM timeout (ok=0)");
    check(($realtime - t0) < 200.0us, "T7 write not bounded");
endtask

// BFM 复位线程（等 rst_n 释放）
initial begin
    bfm.reset();
end

initial begin
    stub_hang      = 1'b0;
    stub_rand_wait = 1'b0;
    wait (rst_n === 1'b1);
    repeat (4) @(posedge clk);

    $display("============================================================");
    $display("  AXI Interconnect Chain Test Start");
    $display("============================================================");

    test_apb_region();
    test_err_slave();
    test_timeout_paths();

    repeat (10) @(posedge clk);
    $display("============================================================");
    if (error_count == 0)
        $display("  AXI Interconnect Chain Test: ALL PASSED");
    else
        $display("  AXI Interconnect Chain Test: FAILED (%0d errors)", error_count);
    $display("============================================================");
    $finish;
end

// 超时看门狗：整跑 8ms 上限（正常流程远短于此）
initial begin
    #8_000_000;
    $display("[WATCHDOG] global timeout — test hung");
    $finish;
end

endmodule

// ============================================================================
// APB 从机桩（寄存器块 + 等待态/错误/无响应控制）
// ============================================================================
module apb_slave_stub #(
    parameter NUM_REGS = 16
)(
    input  logic        PCLK,
    input  logic        PRESETn,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic [31:0] PADDR,
    input  logic        PWRITE,
    input  logic [3:0]  PSTRB,
    input  logic [31:0] PWDATA,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR,
    input  logic        force_hang,
    input  logic        rand_wait_en
);
    logic [31:0] regs [NUM_REGS];
    logic [3:0]  wait_cnt;
    logic [3:0]  rd_idx;

    // SETUP 拍载入等待拍数（0~3 随机），ACCESS 期递减
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            wait_cnt <= 4'd0;
        else if (PSEL && !PENABLE)
            wait_cnt <= rand_wait_en ? 4'($urandom_range(3)) : 4'd0;
        else if (PSEL && PENABLE && wait_cnt != 0)
            wait_cnt <= wait_cnt - 4'd1;
    end

    assign PREADY  = force_hang ? 1'b0 : (wait_cnt == 4'd0);
    // PADDR[11]=1 → 注入 PSLVERR（ACCESS 完成拍有效语义）
    assign PSLVERR = PSEL && PENABLE && PREADY && PADDR[11];

    assign rd_idx = PADDR[5:2];
    always_comb begin
        if (rd_idx < NUM_REGS)
            PRDATA = regs[rd_idx];
        else
            PRDATA = 32'd0;
    end

    // 写：ACCESS 完成拍按字节使能写入
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            for (int i = 0; i < NUM_REGS; i++) regs[i] <= 32'd0;
        end else if (PSEL && PENABLE && PWRITE && PREADY) begin
            for (int b = 0; b < 4; b++) begin
                if (PSTRB[b])
                    regs[rd_idx][b*8 +: 8] <= PWDATA[b*8 +: 8];
            end
        end
    end
endmodule
