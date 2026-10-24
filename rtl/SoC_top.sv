`include "SoC_Config.sv"
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

import bd32_pkg::*;

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
    parameter GPIO_NUM = GPIO_NUM,
    parameter TIMER_NUM = TIMER_NUM,
    parameter TIMER_CHANNEL_NUM = TIMER_CHANNEL_NUM,
    localparam NUM_TARGETS = 1,
    localparam ID_WIDTH    = AXI_ID_WIDTH,
    localparam LEN_WIDTH   = AXI_LEN_WIDTH,
    localparam APB_NUM_SLAVES = APB_NUM_SLAVES
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
    inout  [TIMER_NUM*TIMER_CHANNEL_NUM-1:0] timer_channel_io,
    // Debug Module 接口（透传至 RISC_V_Core）
    input   logic                       dbg_halt_req,
    output  logic                       dbg_halted,
    input   logic                       dbg_resume_req,
    input   logic                       dbg_step,
    input   logic                       dbg_ebreakm,
    input   logic                       dbg_reg_we,
    input   logic   [REG_ADDR_WIDTH-1:0] dbg_reg_addr,
    input   logic   [DATA_WIDTH-1:0]    dbg_reg_wdata,
    output  logic   [DATA_WIDTH-1:0]    dbg_reg_rdata,
    output  logic   [DATA_WIDTH-1:0]    dbg_dpc,
    input   logic   [DATA_WIDTH-1:0]    dbg_pc_wdata,
    // SBA 总线（来自 Debug Module）
    input   logic                       sba_req_valid,
    input   logic   [ADDR_WIDTH-1:0]    sba_addr,
    input   logic   [DATA_WIDTH-1:0]    sba_wdata,
    input   logic                       sba_write,
    input   logic   [2:0]               sba_size,
    input   logic   [ALIGN_BYTES-1:0]   sba_be,
    output  logic                       sba_rsp_valid,
    output  logic   [DATA_WIDTH-1:0]    sba_rdata,
    output  logic                       sba_error,
    // Trigger（硬件断点 + 数据观察点，透传至 RISC_V_Core）
    input   logic   [`TRIGGER_NUM-1:0]  trigger_en,
    input   logic   [`TRIGGER_NUM-1:0]  trigger_exec_en,
    input   logic   [`TRIGGER_NUM-1:0]  trigger_load_en,
    input   logic   [`TRIGGER_NUM-1:0]  trigger_store_en,
    input   logic   [`TRIGGER_NUM*2-1:0] trigger_size,
    input   logic   [`TRIGGER_NUM*DATA_WIDTH-1:0] trigger_addr,
    output  logic                       trigger_hit,
    output  logic                       ebreak_halt,
    // Debug CSR 访问（透传至 RISC_V_Core）
    input   logic                       dbg_csr_we,
    input   logic   [CSR_ADDR_WIDTH-1:0] dbg_csr_addr,
    input   logic   [DATA_WIDTH-1:0]    dbg_csr_wdata,
    output  logic   [DATA_WIDTH-1:0]    dbg_csr_rdata
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

logic                       bus_tran_done;
logic                       bus_ready;
logic   [DATA_WIDTH-1:0]    bus_rdata;
logic   [1:0]               bus_resp;

logic   [2*DATA_WIDTH-1:0]  mtime_shadow;
logic                       software_int;
logic                       timer_int;
logic                       external_int;
logic   [NUM_TARGETS-1:0]   plic_irq;

// AXI 总线接口（Bus_Access ↔ 互联 ↔ 三从机；位宽用 axi_if 默认值）
axi_if                             axi_bus ();   // Bus_Access ↔ AXI_Interconnect
axi_if                             axi_apb ();   // AXI_Interconnect.m0 ↔ AXI_APB_Bridge
axi_if                             axi_mrom();   // AXI_Interconnect.m1 ↔ MROM/Flash err_slave
axi_if                             axi_ddr ();   // AXI_Interconnect.m2 ↔ DDR err_slave
// --- AW ---
// --- W ---
// --- B ---
// --- AR ---
// --- R ---


// APB 总线接口（bridge 主机 ↔ 互联 ↔ 各从机；位宽用 apb_if 默认 32/32）
apb_if                             apb_m ();                 // AXI_APB_Bridge ↔ APB_Interconnect
apb_if                             apb_s [APB_NUM_SLAVES] (); // APB_Interconnect ↔ 各从机（[5:15] 预留槽 tie-off）



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
    .clk                (clk_soc            ),
    .rst_n              (rst_n_sync         ),
    .itcm_download_en   (itcm_download_en   ),
    .itcm_download_addr (itcm_download_addr ),
    .itcm_download_data (itcm_download_data ),
    .dtcm_download_en   (dtcm_download_en   ),
    .dtcm_download_addr (dtcm_download_addr ),
    .dtcm_download_data (dtcm_download_data ),
    .mtime_shadow       (mtime_shadow       ),
    .software_int       (software_int       ),
    .timer_int          (timer_int          ),
    .external_int       (external_int       ),
    .bus_tran_done      (bus_tran_done      ),
    .bus_ready          (bus_ready          ),
    .bus_rdata          (bus_rdata          ),
    .bus_resp           (bus_resp           ),
    .bus_transfer       (bus_transfer       ),
    .bus_access_write   (bus_access_write   ),
    .bus_access_addr    (bus_access_addr    ),
    .bus_access_wstrb   (bus_access_wstrb   ),
    .bus_access_wdata   (bus_access_wdata   ),
    // Debug Module
    .dbg_halt_req       (dbg_halt_req       ),
    .dbg_halted         (dbg_halted         ),
    .dbg_resume_req     (dbg_resume_req     ),
    .dbg_step           (dbg_step           ),
    .dbg_ebreakm        (dbg_ebreakm        ),
    .dbg_reg_we         (dbg_reg_we         ),
    .dbg_reg_addr       (dbg_reg_addr       ),
    .dbg_reg_wdata      (dbg_reg_wdata      ),
    .dbg_reg_rdata      (dbg_reg_rdata      ),
    .dbg_dpc            (dbg_dpc            ),
    .dbg_pc_wdata       (dbg_pc_wdata       ),
    // SBA
    .sba_req_valid      (sba_req_valid      ),
    .sba_addr           (sba_addr           ),
    .sba_wdata          (sba_wdata          ),
    .sba_write          (sba_write          ),
    .sba_size           (sba_size           ),
    .sba_be             (sba_be             ),
    .sba_rsp_valid      (sba_rsp_valid      ),
    .sba_rdata          (sba_rdata          ),
    .sba_error          (sba_error          ),
    // Trigger
    .trigger_en         (trigger_en         ),
    .trigger_exec_en     (trigger_exec_en     ),
    .trigger_load_en     (trigger_load_en     ),
    .trigger_store_en    (trigger_store_en    ),
    .trigger_size        (trigger_size        ),
    .trigger_addr       (trigger_addr       ),
    .trigger_hit        (trigger_hit        ),
    .ebreak_halt        (ebreak_halt        ),
    // Debug CSR
    .dbg_csr_we         (dbg_csr_we         ),
    .dbg_csr_addr       (dbg_csr_addr       ),
    .dbg_csr_wdata      (dbg_csr_wdata      ),
    .dbg_csr_rdata      (dbg_csr_rdata      )
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
    .o_bus_tran_done(bus_tran_done ),
    .o_bus_ready  (bus_ready),
    .o_bus_rdata  (bus_rdata),
    .o_bus_error  (bus_resp),
    // AXI Master → Interconnect
    .m           (axi_bus     )
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
    .s           (axi_bus     ),

    // Slave 0 → APB Bridge
    .m0          (axi_apb     ),

    // Slave 1 → MROM/Flash (err_slave)
    .m1          (axi_mrom    ),

    // Slave 2 → DDR (err_slave)
    .m2          (axi_ddr     )
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
    .s           (axi_apb     ),
    // APB Master → APB_Interconnect（接口）
    .apb          (apb_m         )
);

// =========================================================================
// APB Interconnect（地址解码 + 返回聚合）
// =========================================================================
APB_Interconnect #(
    .PADDR_WIDTH (ADDR_WIDTH    ),
    .PDATA_WIDTH (DATA_WIDTH    ),
    .NUM_SLAVES  (APB_NUM_SLAVES)
) u_APB_Interconnect (
    .m          (apb_m         ),
    .s          (apb_s         )
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
    .s           (axi_mrom    )
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
    .s           (axi_ddr     )
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
    .s          (apb_s[0]),
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
    .s          (apb_s[1]),
    .irq_i        ({12'b0, timer_irq, gpio_irq, uart_irq, 1'b0}),
    .irq_o        (plic_irq      )
);

assign external_int = plic_irq[0];

`ifndef SYNTHESIS
// ===== SVA：SoC 顶层中断映射不变式（L2，+define+ASSERT_MODULE 使能）=====
// PLIC irq_i 固定映射：[3]=timer_irq(CLINT), [2]=gpio_irq, [1]=uart_irq,
// [0]=1'b0(source 0 保留)，其余 12 位未用 = 0。
`ifdef ASSERT_MODULE
    // 时钟/复位：SoC 顶层用 clk_soc / rst_n_sync（已板级同步释放）
    always @(posedge clk_soc) begin
        if (rst_n_sync) begin
            // ① 保留源 0 恒静默
            a_soc_plic_src0_silent: assert property (!u_PLIC.irq_i[0]);
            // ② 未用源 4~15 恒 0（irq_i 16 位，{12'b0, timer_irq, gpio_irq, uart_irq, 1'b0}）
            a_soc_plic_unused_zero: assert property (u_PLIC.irq_i[15:4] == '0);
            // ③ CPU 看到的 external_int 与 PLIC irq_o[0] 一致（irq_o[0] 已打一拍）
            a_soc_extint_eq_eip: assert property
                (external_int == u_PLIC.irq_o[0]);
        end
    end
`endif
`endif

// --- PSEL[2]: GPIO ---
apb_gpio #(
    .ADDR_WIDTH  (ADDR_WIDTH  ),
    .DATA_WIDTH  (DATA_WIDTH  ),
    .ALIGN_BYTES (ALIGN_BYTES )
) u_apb_gpio (
    .PCLK         (clk_soc       ),
    .PRESETn      (rst_n_sync     ),
    .s          (apb_s[2]),
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
    .s          (apb_s[3]),
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
    .s          (apb_s[4]),
    .irq_o        (timer_irq          ),
    .channel_io   (timer_channel_io   )
);

// --- PSEL[5]~[15]: 预留（SPI/I2C/...），PREADY=1, PRDATA=0, PSLVERR=0 ---
genvar i;
generate
    for (i = 5; i < APB_NUM_SLAVES; i = i + 1) begin : gen_unused_apb
        assign apb_s[i].prdata  = {DATA_WIDTH{1'b0}};
        assign apb_s[i].pready  = 1'b1;
        assign apb_s[i].pslverr = 1'b0;
    end
endgenerate

endmodule
