`include "SoC_Config.sv"
`include "RV32_Inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
// =============================================================================
// SoC_top - AXI 总线架构顶层
// =============================================================================
// 架构：
//   CPU → Bus_Access(AXI_Lite_Master) → AXI_Interconnect → 3 Slaves:
//     Slave 0: axi_apb_bridge  (0xE000_0000 ~ 0xFFFF_FFFF) → APB外设
//     Slave 1: axi_err_slave   (0x9000_0000 ~ 0xAFFF_FFFF, MROM/Flash留空)
//     Slave 2: axi_err_slave   (0xB000_0000 ~ 0xCFFF_FFFF, DDR留空)
// MROM 已移至 CPU 本地直读（Core/BootROM.sv），不再挂总线
// =============================================================================

module SoC_top #(
    parameter ITCM_FILE = `ITCM_FILE,
    parameter DTCM_FILE = `DTCM_FILE,
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REGFILE_NUM = `REGFILE_NUM,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    parameter ALIGN_WIDTH = `ALIGN_WIDTH,
    parameter GPIO_NUM = `GPIO_NUM,
    parameter TIMER_NUM = `TIMER_NUM,
    parameter TIMER_CHANNEL_NUM = `TIMER_CHANNEL_NUM,
    localparam NUM_TARGETS = 1,
    localparam ID_WIDTH    = `AXI_ID_WIDTH,
    localparam LEN_WIDTH   = `AXI_LEN_WIDTH,
    localparam APB_NUM_SLAVES = `APB_NUM_SLAVES
)(
    // System
    input   logic   sys_clk,
    input   logic   sys_rst_n,
    input   logic   timer_clk_i,   // CLINT 1MHz 独立时钟域
    // UART
    input   logic   uart_rx,
    output  logic   uart_tx,
    // GPIO
    inout  [GPIO_NUM-1:0]  gpio_io,
    // Timer
    inout  [TIMER_NUM*TIMER_CHANNEL_NUM-1:0] timer_channel_io
);

// clk_wiz / clk_div / BUFG / Cdc_Sync 已全部移至 bd32_board_top（FPGA 板级顶层）
// SoC_top 作为纯数字 IP，sys_rst_n 已是板级同步释放（3-stage）后的干净复位
assign clk_soc     = sys_clk;
wire   rst_n_sync   = sys_rst_n;

// =========================================================================
// CPU 核心信号
// =========================================================================
logic                       itcm_download_en;
logic   [ADDR_WIDTH-1:0]    itcm_download_addr;
logic   [DATA_WIDTH-1:0]    itcm_download_data;
logic                       dtcm_download_en;
logic   [ADDR_WIDTH-1:0]    dtcm_download_addr;
logic   [DATA_WIDTH-1:0]    dtcm_download_data;

logic                       bus_transfer;
logic   [ADDR_WIDTH-1:0]    bus_access_addr;
logic                       bus_access_write;
logic   [DATA_WIDTH-1:0]    bus_access_wdata;
logic   [ALIGN_BYTES-1:0]   bus_access_wstrb;
logic   [DATA_WIDTH-1:0]    bus_rdata;
logic                       bus_tran_done;

logic   [2*DATA_WIDTH-1:0]  mtime_shadow;
logic                       software_int;
logic                       timer_int;
logic                       external_int;
logic   [NUM_TARGETS-1:0]   plic_irq;

// =========================================================================
// AXI 总线信号：Bus_Access ↔ AXI_Interconnect
// =========================================================================
// --- AW ---
logic [ID_WIDTH-1:0]       axi_awid;
logic [ADDR_WIDTH-1:0]     axi_awaddr;
logic [LEN_WIDTH-1:0]      axi_awlen;
logic [2:0]                axi_awsize;
logic [1:0]                axi_awburst;
logic                      axi_awlock;
logic [3:0]                axi_awcache;
logic [2:0]                axi_awprot;
logic [3:0]                axi_awqos;
logic [3:0]                axi_awregion;
logic                      axi_awvalid, axi_awready;
// --- W ---
logic [DATA_WIDTH-1:0]     axi_wdata;
logic [ALIGN_BYTES-1:0]    axi_wstrb;
logic                      axi_wlast;
logic                      axi_wvalid, axi_wready;
// --- B ---
logic [ID_WIDTH-1:0]       axi_bid;
logic [1:0]                axi_bresp;
logic                      axi_bvalid, axi_bready;
// --- AR ---
logic [ID_WIDTH-1:0]       axi_arid;
logic [ADDR_WIDTH-1:0]     axi_araddr;
logic [LEN_WIDTH-1:0]      axi_arlen;
logic [2:0]                axi_arsize;
logic [1:0]                axi_arburst;
logic                      axi_arlock;
logic [3:0]                axi_arcache;
logic [2:0]                axi_arprot;
logic [3:0]                axi_arqos;
logic [3:0]                axi_arregion;
logic                      axi_arvalid, axi_arready;
// --- R ---
logic [ID_WIDTH-1:0]       axi_rid;
logic [DATA_WIDTH-1:0]     axi_rdata;
logic [1:0]                axi_rresp;
logic                      axi_rlast;
logic                      axi_rvalid, axi_rready;

// =========================================================================
// AXI Slave 0 (APB Bridge) 信号
// =========================================================================
logic [ID_WIDTH-1:0]       apb_awid, apb_arid, apb_bid, apb_rid;
logic [ADDR_WIDTH-1:0]     apb_awaddr, apb_araddr;
logic [7:0]                apb_awlen, apb_arlen;
logic [2:0]                apb_awsize, apb_arsize;
logic [1:0]                apb_awburst, apb_arburst;
logic                      apb_awlock, apb_arlock;
logic [3:0]                apb_awcache, apb_arcache;
logic [2:0]                apb_awprot, apb_arprot;
logic [3:0]                apb_awqos, apb_arqos;
logic [3:0]                apb_awregion, apb_arregion;
logic                      apb_awvalid, apb_awready;
logic [DATA_WIDTH-1:0]     apb_wdata;
logic [ALIGN_BYTES-1:0]    apb_wstrb;
logic                      apb_wlast, apb_wvalid, apb_wready;
logic [1:0]                apb_bresp;
logic                      apb_bvalid, apb_bready;
logic                      apb_arvalid, apb_arready;
logic [DATA_WIDTH-1:0]     apb_rdata;
logic [1:0]                apb_rresp;
logic                      apb_rlast, apb_rvalid, apb_rready;

// APB Bridge → APB 外设总线
logic [ADDR_WIDTH-1:0]             apb_paddr;
logic [APB_NUM_SLAVES-1:0]         apb_psel;
logic                              apb_penable;
logic                              apb_pwrite;
logic [ALIGN_BYTES-1:0]            apb_pstrb;
logic [DATA_WIDTH-1:0]             apb_pwdata;
logic [DATA_WIDTH-1:0]             apb_prdata [APB_NUM_SLAVES];
logic [APB_NUM_SLAVES-1:0]         apb_pready;
logic [APB_NUM_SLAVES-1:0]         apb_pslverr;

// AXI_APB_Bridge ↔ APB_Interconnect 中间信号
logic                              bridge_psel;
logic [DATA_WIDTH-1:0]             bridge_prdata;
logic                              bridge_pready;
logic                              bridge_pslverr;

// =========================================================================
// AXI Slave 1 (MROM/Flash err_slave) 信号
// =========================================================================
logic [ID_WIDTH-1:0]       mrom_flash_awid, mrom_flash_arid, mrom_flash_bid, mrom_flash_rid;
logic [ADDR_WIDTH-1:0]     mrom_flash_awaddr, mrom_flash_araddr;
logic [7:0]                mrom_flash_awlen, mrom_flash_arlen;
logic [2:0]                mrom_flash_awsize, mrom_flash_arsize;
logic [1:0]                mrom_flash_awburst, mrom_flash_arburst;
logic                      mrom_flash_awlock, mrom_flash_arlock;
logic [3:0]                mrom_flash_awcache, mrom_flash_arcache;
logic [2:0]                mrom_flash_awprot, mrom_flash_arprot;
logic [3:0]                mrom_flash_awqos, mrom_flash_arqos;
logic [3:0]                mrom_flash_awregion, mrom_flash_arregion;
logic                      mrom_flash_awvalid, mrom_flash_awready;
logic [DATA_WIDTH-1:0]     mrom_flash_wdata;
logic [ALIGN_BYTES-1:0]    mrom_flash_wstrb;
logic                      mrom_flash_wlast, mrom_flash_wvalid, mrom_flash_wready;
logic [1:0]                mrom_flash_bresp;
logic                      mrom_flash_bvalid, mrom_flash_bready;
logic                      mrom_flash_arvalid, mrom_flash_arready;
logic [DATA_WIDTH-1:0]     mrom_flash_rdata;
logic [1:0]                mrom_flash_rresp;
logic                      mrom_flash_rlast, mrom_flash_rvalid, mrom_flash_rready;

// =========================================================================
// AXI Slave 2 (DDR err_slave) 信号
// =========================================================================
logic [ID_WIDTH-1:0]       ddr_awid, ddr_arid, ddr_bid, ddr_rid;
logic [ADDR_WIDTH-1:0]     ddr_awaddr, ddr_araddr;
logic [7:0]                ddr_awlen, ddr_arlen;
logic [2:0]                ddr_awsize, ddr_arsize;
logic [1:0]                ddr_awburst, ddr_arburst;
logic                      ddr_awlock, ddr_arlock;
logic [3:0]                ddr_awcache, ddr_arcache;
logic [2:0]                ddr_awprot, ddr_arprot;
logic [3:0]                ddr_awqos, ddr_arqos;
logic [3:0]                ddr_awregion, ddr_arregion;
logic                      ddr_awvalid, ddr_awready;
logic [DATA_WIDTH-1:0]     ddr_wdata;
logic [ALIGN_BYTES-1:0]    ddr_wstrb;
logic                      ddr_wlast, ddr_wvalid, ddr_wready;
logic [1:0]                ddr_bresp;
logic                      ddr_bvalid, ddr_bready;
logic                      ddr_arvalid, ddr_arready;
logic [DATA_WIDTH-1:0]     ddr_rdata;
logic [1:0]                ddr_rresp;
logic                      ddr_rlast, ddr_rvalid, ddr_rready;

// APB 外设 irq
logic uart_irq, gpio_irq, timer_irq;

// =========================================================================
// CPU 核心例化
// =========================================================================
RISC_V_Core #(
    .ITCM_FILE      (ITCM_FILE      ),
    .DTCM_FILE      (DTCM_FILE      ),
    .ADDR_WIDTH     (ADDR_WIDTH     ),
    .DATA_WIDTH     (DATA_WIDTH     ),
    .REGFILE_NUM    (REGFILE_NUM    ),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH ),
    .CSR_ADDR_WIDTH (CSR_ADDR_WIDTH ),
    .ALIGN_BYTES    (ALIGN_BYTES    ),
    .ALIGN_WIDTH    (ALIGN_WIDTH    )
) u_RISC_V_Core (
    .clk                (clk_soc  ),
    .rst_n              (rst_n_sync      ),
    .itcm_download_en         (itcm_download_en      ),
    .itcm_download_addr       (itcm_download_addr    ),
    .itcm_download_data       (itcm_download_data    ),
    .dtcm_download_en         (dtcm_download_en      ),
    .dtcm_download_addr       (dtcm_download_addr    ),
    .dtcm_download_data       (dtcm_download_data    ),
    .mtime_shadow       (mtime_shadow    ),
    .software_int       (software_int    ),
    .timer_int          (timer_int       ),
    .external_int       (external_int    ),
    .bus_rdata          (bus_rdata       ),
    .bus_tran_done      (bus_tran_done   ),
    .bus_transfer       (bus_transfer    ),
    .bus_access_write   (bus_access_write       ),
    .bus_access_addr    (bus_access_addr        ),
    .bus_access_wstrb   (bus_access_wstrb       ),
    .bus_access_wdata   (bus_access_wdata       )

);

// =========================================================================
// Bus_Access（AXI_Lite_Master 封装）
// =========================================================================
Bus_Access #(
    .ADDR_WIDTH  (ADDR_WIDTH  ),
    .DATA_WIDTH  (DATA_WIDTH  ),
    .STRB_WIDTH  (ALIGN_BYTES ),
    .ID_WIDTH    (ID_WIDTH    ),
    .LEN_WIDTH   (LEN_WIDTH   )
) u_Bus_Access (
    .clk          (clk_soc      ),
    .rst_n        (rst_n_sync    ),
    // CPU 侧
    .i_transfer   (bus_transfer  ),
    .i_write      (bus_access_write),
    .i_addr       (bus_access_addr ),
    .i_wdata      (bus_access_wdata),
    .i_wmask      (bus_access_wstrb),
    .o_rdata      (bus_rdata     ),
    .o_tran_done  (bus_tran_done ),
    // AXI Master → Interconnect
    .o_awid       (axi_awid      ),
    .o_awaddr     (axi_awaddr    ),
    .o_awlen      (axi_awlen     ),
    .o_awsize     (axi_awsize    ),
    .o_awburst    (axi_awburst   ),
    .o_awlock     (axi_awlock    ),
    .o_awcache    (axi_awcache   ),
    .o_awprot     (axi_awprot    ),
    .o_awqos      (axi_awqos     ),
    .o_awregion   (axi_awregion  ),
    .o_awvalid    (axi_awvalid   ),
    .i_awready    (axi_awready   ),
    .o_wdata      (axi_wdata     ),
    .o_wstrb      (axi_wstrb     ),
    .o_wlast      (axi_wlast     ),
    .o_wvalid     (axi_wvalid    ),
    .i_wready     (axi_wready    ),
    .i_bid        (axi_bid       ),
    .i_bresp      (axi_bresp     ),
    .i_bvalid     (axi_bvalid    ),
    .o_bready     (axi_bready    ),
    .o_arid       (axi_arid      ),
    .o_araddr     (axi_araddr    ),
    .o_arlen      (axi_arlen     ),
    .o_arsize     (axi_arsize    ),
    .o_arburst    (axi_arburst   ),
    .o_arlock     (axi_arlock    ),
    .o_arcache    (axi_arcache   ),
    .o_arprot     (axi_arprot    ),
    .o_arqos      (axi_arqos     ),
    .o_arregion   (axi_arregion  ),
    .o_arvalid    (axi_arvalid   ),
    .i_arready    (axi_arready   ),
    .i_rid        (axi_rid       ),
    .i_rdata      (axi_rdata     ),
    .i_rresp      (axi_rresp     ),
    .i_rlast      (axi_rlast     ),
    .i_rvalid     (axi_rvalid    ),
    .o_rready     (axi_rready    )
);

// =========================================================================
// AXI Interconnect（1 Master → 3 Slaves）
// =========================================================================
AXI_Interconnect #(
    .ADDR_WIDTH  (ADDR_WIDTH  ),
    .DATA_WIDTH  (DATA_WIDTH  ),
    .STRB_WIDTH  (ALIGN_BYTES ),
    .ID_WIDTH    (ID_WIDTH    )
) u_AXI_Interconnect (
    .clk          (clk_soc      ),
    .rst_n        (rst_n_sync    ),
    // Master 侧
    .s_awid       (axi_awid      ), .s_awaddr    (axi_awaddr   ),
    .s_awlen      (axi_awlen     ), .s_awsize    (axi_awsize   ),
    .s_awburst    (axi_awburst   ), .s_awlock    (axi_awlock   ),
    .s_awcache    (axi_awcache   ), .s_awprot    (axi_awprot   ),
    .s_awqos      (axi_awqos     ), .s_awregion  (axi_awregion ),
    .s_awvalid    (axi_awvalid   ), .s_awready   (axi_awready  ),
    .s_wdata      (axi_wdata     ), .s_wstrb     (axi_wstrb    ),
    .s_wlast      (axi_wlast     ), .s_wvalid    (axi_wvalid   ),
    .s_wready     (axi_wready    ),
    .s_bid        (axi_bid       ), .s_bresp     (axi_bresp    ),
    .s_bvalid     (axi_bvalid    ), .s_bready    (axi_bready   ),
    .s_arid       (axi_arid      ), .s_araddr    (axi_araddr   ),
    .s_arlen      (axi_arlen     ), .s_arsize    (axi_arsize   ),
    .s_arburst    (axi_arburst   ), .s_arlock    (axi_arlock   ),
    .s_arcache    (axi_arcache   ), .s_arprot    (axi_arprot   ),
    .s_arqos      (axi_arqos     ), .s_arregion  (axi_arregion ),
    .s_arvalid    (axi_arvalid   ), .s_arready   (axi_arready  ),
    .s_rid        (axi_rid       ), .s_rdata     (axi_rdata    ),
    .s_rresp      (axi_rresp     ), .s_rlast     (axi_rlast    ),
    .s_rvalid     (axi_rvalid    ), .s_rready    (axi_rready   ),

    // Slave 0 → APB Bridge
    .m0_awid       (apb_awid      ), .m0_awaddr   (apb_awaddr   ),
    .m0_awlen      (apb_awlen     ), .m0_awsize   (apb_awsize   ),
    .m0_awburst    (apb_awburst   ), .m0_awlock   (apb_awlock   ),
    .m0_awcache    (apb_awcache   ), .m0_awprot   (apb_awprot   ),
    .m0_awqos      (apb_awqos     ), .m0_awregion (apb_awregion ),
    .m0_awvalid    (apb_awvalid   ), .m0_awready  (apb_awready  ),
    .m0_wdata      (apb_wdata     ), .m0_wstrb    (apb_wstrb    ),
    .m0_wlast      (apb_wlast     ), .m0_wvalid   (apb_wvalid   ),
    .m0_wready     (apb_wready    ),
    .m0_bid        (apb_bid       ), .m0_bresp    (apb_bresp    ),
    .m0_bvalid     (apb_bvalid    ), .m0_bready   (apb_bready   ),
    .m0_arid       (apb_arid      ), .m0_araddr   (apb_araddr   ),
    .m0_arlen      (apb_arlen     ), .m0_arsize   (apb_arsize   ),
    .m0_arburst    (apb_arburst   ), .m0_arlock   (apb_arlock   ),
    .m0_arcache    (apb_arcache   ), .m0_arprot   (apb_arprot   ),
    .m0_arqos      (apb_arqos     ), .m0_arregion (apb_arregion ),
    .m0_arvalid    (apb_arvalid   ), .m0_arready  (apb_arready  ),
    .m0_rid        (apb_rid       ), .m0_rdata    (apb_rdata    ),
    .m0_rresp      (apb_rresp     ), .m0_rlast    (apb_rlast    ),
    .m0_rvalid     (apb_rvalid    ), .m0_rready   (apb_rready   ),

    // Slave 1 → MROM/Flash (err_slave)
    .m1_awid       (mrom_flash_awid      ), .m1_awaddr   (mrom_flash_awaddr  ),
    .m1_awlen      (mrom_flash_awlen     ), .m1_awsize   (mrom_flash_awsize  ),
    .m1_awburst    (mrom_flash_awburst   ), .m1_awlock   (mrom_flash_awlock  ),
    .m1_awcache    (mrom_flash_awcache   ), .m1_awprot   (mrom_flash_awprot  ),
    .m1_awqos      (mrom_flash_awqos     ), .m1_awregion (mrom_flash_awregion),
    .m1_awvalid    (mrom_flash_awvalid   ), .m1_awready  (mrom_flash_awready ),
    .m1_wdata      (mrom_flash_wdata     ), .m1_wstrb    (mrom_flash_wstrb   ),
    .m1_wlast      (mrom_flash_wlast     ), .m1_wvalid   (mrom_flash_wvalid  ),
    .m1_wready     (mrom_flash_wready    ),
    .m1_bid        (mrom_flash_bid       ), .m1_bresp    (mrom_flash_bresp   ),
    .m1_bvalid     (mrom_flash_bvalid    ), .m1_bready   (mrom_flash_bready  ),
    .m1_arid       (mrom_flash_arid      ), .m1_araddr   (mrom_flash_araddr  ),
    .m1_arlen      (mrom_flash_arlen     ), .m1_arsize   (mrom_flash_arsize  ),
    .m1_arburst    (mrom_flash_arburst   ), .m1_arlock   (mrom_flash_arlock  ),
    .m1_arcache    (mrom_flash_arcache   ), .m1_arprot   (mrom_flash_arprot  ),
    .m1_arqos      (mrom_flash_arqos     ), .m1_arregion (mrom_flash_arregion),
    .m1_arvalid    (mrom_flash_arvalid   ), .m1_arready  (mrom_flash_arready ),
    .m1_rid        (mrom_flash_rid       ), .m1_rdata    (mrom_flash_rdata   ),
    .m1_rresp      (mrom_flash_rresp     ), .m1_rlast    (mrom_flash_rlast   ),
    .m1_rvalid     (mrom_flash_rvalid    ), .m1_rready   (mrom_flash_rready  ),

    // Slave 2 → DDR (err_slave)
    .m2_awid       (ddr_awid      ), .m2_awaddr   (ddr_awaddr   ),
    .m2_awlen      (ddr_awlen     ), .m2_awsize   (ddr_awsize   ),
    .m2_awburst    (ddr_awburst   ), .m2_awlock   (ddr_awlock   ),
    .m2_awcache    (ddr_awcache   ), .m2_awprot   (ddr_awprot   ),
    .m2_awqos      (ddr_awqos     ), .m2_awregion (ddr_awregion ),
    .m2_awvalid    (ddr_awvalid   ), .m2_awready  (ddr_awready  ),
    .m2_wdata      (ddr_wdata     ), .m2_wstrb    (ddr_wstrb    ),
    .m2_wlast      (ddr_wlast     ), .m2_wvalid   (ddr_wvalid   ),
    .m2_wready     (ddr_wready    ),
    .m2_bid        (ddr_bid       ), .m2_bresp    (ddr_bresp    ),
    .m2_bvalid     (ddr_bvalid    ), .m2_bready   (ddr_bready   ),
    .m2_arid       (ddr_arid      ), .m2_araddr   (ddr_araddr   ),
    .m2_arlen      (ddr_arlen     ), .m2_arsize   (ddr_arsize   ),
    .m2_arburst    (ddr_arburst   ), .m2_arlock   (ddr_arlock   ),
    .m2_arcache    (ddr_arcache   ), .m2_arprot   (ddr_arprot   ),
    .m2_arqos      (ddr_arqos     ), .m2_arregion (ddr_arregion ),
    .m2_arvalid    (ddr_arvalid   ), .m2_arready  (ddr_arready  ),
    .m2_rid        (ddr_rid       ), .m2_rdata    (ddr_rdata    ),
    .m2_rresp      (ddr_rresp     ), .m2_rlast    (ddr_rlast    ),
    .m2_rvalid     (ddr_rvalid    ), .m2_rready   (ddr_rready   )
);

// =========================================================================
// AXI Slave 0: APB Bridge
// =========================================================================
AXI_APB_Bridge #(
    .ADDR_WIDTH      (ADDR_WIDTH      ),
    .DATA_WIDTH      (DATA_WIDTH      ),
    .STRB_WIDTH      (ALIGN_BYTES     ),
    .ID_WIDTH        (ID_WIDTH        )
) u_AXI_APB_Bridge (
    .clk          (clk_soc       ),
    .rst_n        (rst_n_sync     ),
    // AW
    .s_awid       (apb_awid      ), .s_awaddr   (apb_awaddr   ),
    .s_awlen      (apb_awlen     ), .s_awsize   (apb_awsize   ),
    .s_awburst    (apb_awburst   ), .s_awlock   (apb_awlock   ),
    .s_awcache    (apb_awcache   ), .s_awprot   (apb_awprot   ),
    .s_awqos      (apb_awqos     ), .s_awregion (apb_awregion ),
    .s_awvalid    (apb_awvalid   ), .s_awready  (apb_awready  ),
    // W
    .s_wdata      (apb_wdata     ), .s_wstrb    (apb_wstrb    ),
    .s_wlast      (apb_wlast     ), .s_wvalid   (apb_wvalid   ),
    .s_wready     (apb_wready    ),
    // B
    .s_bid        (apb_bid       ), .s_bresp    (apb_bresp    ),
    .s_bvalid     (apb_bvalid    ), .s_bready   (apb_bready   ),
    // AR
    .s_arid       (apb_arid      ), .s_araddr   (apb_araddr   ),
    .s_arlen      (apb_arlen     ), .s_arsize   (apb_arsize   ),
    .s_arburst    (apb_arburst   ), .s_arlock   (apb_arlock   ),
    .s_arcache    (apb_arcache   ), .s_arprot   (apb_arprot   ),
    .s_arqos      (apb_arqos     ), .s_arregion (apb_arregion ),
    .s_arvalid    (apb_arvalid   ), .s_arready  (apb_arready  ),
    // R
    .s_rid        (apb_rid       ), .s_rdata    (apb_rdata    ),
    .s_rresp      (apb_rresp     ), .s_rlast    (apb_rlast    ),
    .s_rvalid     (apb_rvalid    ), .s_rready   (apb_rready   ),
    // APB Master → APB_Interconnect
    .PADDR        (apb_paddr     ),
    .PSEL         (bridge_psel   ),
    .PENABLE      (apb_penable   ),
    .PWRITE       (apb_pwrite    ),
    .PSTRB        (apb_pstrb     ),
    .PWDATA       (apb_pwdata    ),
    .PRDATA       (bridge_prdata ),
    .PREADY       (bridge_pready ),
    .PSLVERR      (bridge_pslverr)
);

// =========================================================================
// APB Interconnect（地址解码 + 返回聚合）
// =========================================================================
APB_Interconnect #(
    .PADDR_WIDTH (ADDR_WIDTH    ),
    .PDATA_WIDTH (DATA_WIDTH    ),
    .NUM_SLAVES  (APB_NUM_SLAVES)
) u_APB_Interconnect (
    .PADDR     (apb_paddr     ),
    .PSEL      (bridge_psel   ),
    .i_prdata  (apb_prdata    ),
    .i_pready  (apb_pready    ),
    .i_pslverr (apb_pslverr   ),
    .o_psel    (apb_psel      ),
    .PRDATA    (bridge_prdata ),
    .PREADY    (bridge_pready ),
    .PSLVERR   (bridge_pslverr)
);

// =========================================================================
// AXI Slave 1: MROM/Flash (err_slave, 读返回 0)
// =========================================================================
axi_err_slave #(
    .ADDR_WIDTH  (ADDR_WIDTH  ),
    .DATA_WIDTH  (DATA_WIDTH  ),
    .STRB_WIDTH  (ALIGN_BYTES ),
    .ID_WIDTH    (ID_WIDTH    )
) u_mrom_flash_err (
    .clk          (clk_soc       ),
    .rst_n        (rst_n_sync     ),
    .s_awid       (mrom_flash_awid      ), .s_awaddr   (mrom_flash_awaddr  ),
    .s_awlen      (mrom_flash_awlen     ), .s_awsize   (mrom_flash_awsize  ),
    .s_awburst    (mrom_flash_awburst   ), .s_awlock   (mrom_flash_awlock  ),
    .s_awcache    (mrom_flash_awcache   ), .s_awprot   (mrom_flash_awprot  ),
    .s_awqos      (mrom_flash_awqos     ), .s_awregion (mrom_flash_awregion),
    .s_awvalid    (mrom_flash_awvalid   ), .s_awready  (mrom_flash_awready ),
    .s_wdata      (mrom_flash_wdata     ), .s_wstrb    (mrom_flash_wstrb   ),
    .s_wlast      (mrom_flash_wlast     ), .s_wvalid   (mrom_flash_wvalid  ),
    .s_wready     (mrom_flash_wready    ),
    .s_bid        (mrom_flash_bid       ), .s_bresp    (mrom_flash_bresp   ),
    .s_bvalid     (mrom_flash_bvalid    ), .s_bready   (mrom_flash_bready  ),
    .s_arid       (mrom_flash_arid      ), .s_araddr   (mrom_flash_araddr  ),
    .s_arlen      (mrom_flash_arlen     ), .s_arsize   (mrom_flash_arsize  ),
    .s_arburst    (mrom_flash_arburst   ), .s_arlock   (mrom_flash_arlock  ),
    .s_arcache    (mrom_flash_arcache   ), .s_arprot   (mrom_flash_arprot  ),
    .s_arqos      (mrom_flash_arqos     ), .s_arregion (mrom_flash_arregion),
    .s_arvalid    (mrom_flash_arvalid   ), .s_arready  (mrom_flash_arready ),
    .s_rid        (mrom_flash_rid       ), .s_rdata    (mrom_flash_rdata   ),
    .s_rresp      (mrom_flash_rresp     ), .s_rlast    (mrom_flash_rlast   ),
    .s_rvalid     (mrom_flash_rvalid    ), .s_rready   (mrom_flash_rready  )
);

// =========================================================================
// AXI Slave 2: DDR (err_slave, 读返回 0)
// =========================================================================
axi_err_slave #(
    .ADDR_WIDTH  (ADDR_WIDTH  ),
    .DATA_WIDTH  (DATA_WIDTH  ),
    .STRB_WIDTH  (ALIGN_BYTES ),
    .ID_WIDTH    (ID_WIDTH    )
) u_ddr_err (
    .clk          (clk_soc       ),
    .rst_n        (rst_n_sync     ),
    .s_awid       (ddr_awid      ), .s_awaddr   (ddr_awaddr   ),
    .s_awlen      (ddr_awlen     ), .s_awsize   (ddr_awsize   ),
    .s_awburst    (ddr_awburst   ), .s_awlock   (ddr_awlock   ),
    .s_awcache    (ddr_awcache   ), .s_awprot   (ddr_awprot   ),
    .s_awqos      (ddr_awqos     ), .s_awregion (ddr_awregion ),
    .s_awvalid    (ddr_awvalid   ), .s_awready  (ddr_awready  ),
    .s_wdata      (ddr_wdata     ), .s_wstrb    (ddr_wstrb    ),
    .s_wlast      (ddr_wlast     ), .s_wvalid   (ddr_wvalid   ),
    .s_wready     (ddr_wready    ),
    .s_bid        (ddr_bid       ), .s_bresp    (ddr_bresp    ),
    .s_bvalid     (ddr_bvalid    ), .s_bready   (ddr_bready   ),
    .s_arid       (ddr_arid      ), .s_araddr   (ddr_araddr   ),
    .s_arlen      (ddr_arlen     ), .s_arsize   (ddr_arsize   ),
    .s_arburst    (ddr_arburst   ), .s_arlock   (ddr_arlock   ),
    .s_arcache    (ddr_arcache   ), .s_arprot   (ddr_arprot   ),
    .s_arqos      (ddr_arqos     ), .s_arregion (ddr_arregion ),
    .s_arvalid    (ddr_arvalid   ), .s_arready  (ddr_arready  ),
    .s_rid        (ddr_rid       ), .s_rdata    (ddr_rdata    ),
    .s_rresp      (ddr_rresp     ), .s_rlast    (ddr_rlast    ),
    .s_rvalid     (ddr_rvalid    ), .s_rready   (ddr_rready   )
);

// =========================================================================
// APB 外设例化（均连接到 APB Bridge 输出的共享 APB 总线）
// =========================================================================

// --- PSEL[0]: CLINT ---
CLINT #(
    .ADDR_WIDTH  (ADDR_WIDTH  ),
    .DATA_WIDTH  (DATA_WIDTH  ),
    .ALIGN_BYTES (ALIGN_BYTES )
) u_CLINT (
    .PCLK         (clk_soc       ),
    .PRESETn      (rst_n_sync     ),
    .PADDR        (apb_paddr     ),
    .PSEL         (apb_psel[0]   ),
    .PENABLE      (apb_penable   ),
    .PWRITE       (apb_pwrite    ),
    .PSTRB        (apb_pstrb     ),
    .PWDATA       (apb_pwdata    ),
    .PRDATA       (apb_prdata[0] ),
    .PREADY       (apb_pready[0] ),
    .PSLVERR      (apb_pslverr[0]),
    .timer_clk_i   (timer_clk_i  ),
    .mtime_shadow  (mtime_shadow  ),
    .software_int  (software_int  ),
    .timer_int     (timer_int     )
);

// --- PSEL[1]: PLIC ---
PLIC #(
    .NUM_SOURCES    (16           ),
    .MAX_PRIORITY   (7            ),
    .NUM_TARGETS    (1            )
) u_PLIC (
    .PCLK         (clk_soc       ),
    .PRESETn      (rst_n_sync     ),
    .PADDR        (apb_paddr     ),
    .PSEL         (apb_psel[1]   ),
    .PENABLE      (apb_penable   ),
    .PWRITE       (apb_pwrite    ),
    .PSTRB        (apb_pstrb     ),
    .PWDATA       (apb_pwdata    ),
    .PRDATA       (apb_prdata[1] ),
    .PREADY       (apb_pready[1] ),
    .PSLVERR      (apb_pslverr[1]),
    .irq_i        ({12'b0, timer_irq, gpio_irq, uart_irq, 1'b0}),
    .irq_o        (plic_irq      )
);

assign external_int = plic_irq[0];

// --- PSEL[2]: GPIO ---
apb_gpio #(
    .ADDR_WIDTH  (ADDR_WIDTH  ),
    .DATA_WIDTH  (DATA_WIDTH  ),
    .ALIGN_BYTES (ALIGN_BYTES )
) u_apb_gpio (
    .PCLK         (clk_soc       ),
    .PRESETn      (rst_n_sync     ),
    .PADDR        (apb_paddr     ),
    .PSEL         (apb_psel[2]   ),
    .PENABLE      (apb_penable   ),
    .PWRITE       (apb_pwrite    ),
    .PSTRB        (apb_pstrb     ),
    .PWDATA       (apb_pwdata    ),
    .PRDATA       (apb_prdata[2] ),
    .PREADY       (apb_pready[2] ),
    .PSLVERR      (apb_pslverr[2]),
    .irq_o        (gpio_irq      ),
    .gpio_io      (gpio_io       )
);

// --- PSEL[3]: UART ---
apb_uart #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
) u_apb_uart (
    .PCLK         (clk_soc        ),
    .PRESETn      (rst_n_sync      ),
    .PADDR        (apb_paddr      ),
    .PSEL         (apb_psel[3]    ),
    .PENABLE      (apb_penable    ),
    .PWRITE       (apb_pwrite     ),
    .PWDATA       (apb_pwdata     ),
    .PRDATA       (apb_prdata[3]  ),
    .PREADY       (apb_pready[3]  ),
    .PSLVERR      (apb_pslverr[3] ),
    .irq_o        (uart_irq       ),
    .uart_rx_i    (uart_rx        ),
    .uart_tx_o    (uart_tx        ),
    .itcm_download_en_o (itcm_download_en     ),
    .itcm_download_addr_o(itcm_download_addr  ),
    .itcm_download_data_o(itcm_download_data  ),
    .dtcm_download_en_o (dtcm_download_en     ),
    .dtcm_download_addr_o(dtcm_download_addr  ),
    .dtcm_download_data_o(dtcm_download_data  )
);

// --- PSEL[4]: Timer ---
apb_timer #(
    .ADDR_WIDTH     (ADDR_WIDTH        ),
    .DATA_WIDTH     (DATA_WIDTH        ),
    .ALIGN_BYTES    (ALIGN_BYTES       ),
    .TIMER_WIDTH    (16                ),
    .CHANNEL_NUM    (TIMER_CHANNEL_NUM )
) u_apb_timer (
    .PCLK         (clk_soc            ),
    .PRESETn      (rst_n_sync          ),
    .PADDR        (apb_paddr          ),
    .PSEL         (apb_psel[4]        ),
    .PENABLE      (apb_penable        ),
    .PWRITE       (apb_pwrite         ),
    .PSTRB        (apb_pstrb          ),
    .PWDATA       (apb_pwdata         ),
    .PRDATA       (apb_prdata[4]      ),
    .PREADY       (apb_pready[4]      ),
    .PSLVERR      (apb_pslverr[4]     ),
    .irq_o        (timer_irq          ),
    .channel_io   (timer_channel_io   )
);

// --- PSEL[5]~[15]: 预留（SPI/I2C/...），PREADY=1, PRDATA=0, PSLVERR=0 ---
genvar i;
generate
    for (i = 5; i < APB_NUM_SLAVES; i = i + 1) begin : gen_unused_apb
        assign apb_prdata[i]  = {DATA_WIDTH{1'b0}};
        assign apb_pready[i]  = 1'b1;
        assign apb_pslverr[i] = 1'b0;
    end
endgenerate

endmodule
