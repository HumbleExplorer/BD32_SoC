// =============================================================================
// bd32_board_top — FPGA 板级顶层
// =============================================================================
// 职责：
//   1. MMCM 时钟生成（50MHz 板载晶振 → 90MHz / 16MHz / 8MHz）
//   2. 16MHz → 1MHz CLINT timer 时钟分频
//   3. BUFG 全局缓冲 + Cdc_Sync 异步复位同步释放
//   4. SoC_top 纯数字 IP 例化
//
// SoC_top 本身不含任何 Xilinx 原语，可作为独立 IP 复用到任意工艺/平台。
// 仿真时直接例化 SoC_top，无需此模块。
// =============================================================================

`include "SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;

module bd32_board_top #(
    parameter GPIO_NUM           = `GPIO_NUM,
    parameter TIMER_NUM          = `TIMER_NUM,
    parameter TIMER_CHANNEL_NUM  = `TIMER_CHANNEL_NUM
)(
    input  logic                                     sys_clk,           // 板载晶振 50MHz
    input  logic                                     sys_rst_n,         // 板载复位按键（低有效）

    // --- Sipeed RV-Debugger 接口 ---
    input  logic                                     dbg_rst,           // 调试器复位（高有效，FTDI ADBUS5）
    input  logic                                     dbg_tck,           // JTAG TCK（预留，接 Debug Module）
    input  logic                                     dbg_tdi,           // JTAG TDI
    input  logic                                     dbg_tms,           // JTAG TMS
    output logic                                     dbg_tdo,           // JTAG TDO

    // --- 板载 UART ---
    input  logic                                     uart_rx,
    output logic                                     uart_tx,

    inout  [GPIO_NUM-1:0]                            gpio_io,
    inout  [TIMER_NUM*TIMER_CHANNEL_NUM-1:0]         timer_channel_io
);

// =========================================================================
// MMCM 时钟生成：50MHz → 90MHz / 16MHz / 8.388MHz
// =========================================================================
logic clk_wiz_locked;
logic clk_cpu, clk_16mhz, clk_8m388;

clk_wiz_0 u_clk_wiz_0 (
    .clk_in     (sys_clk),
    .clk_cpu  (clk_cpu),
    .clk_8m388  (clk_8m388),
    .reset      (~sys_rst_n),
    .locked     (clk_wiz_locked)
);

// =========================================================================
// 复位：按键有效 && MMCM 锁定 → BUFG → 异步复位同步释放
// DM/JTAG 域复位不受 ndmreset 影响（调试器复位 SoC 时 DM 必须存活）
// =========================================================================
// ndmreset：调试器复位整个 SoC（DM/JTAG 自身保持）
logic ndmreset;
logic rst_dbg_async_n;
logic rst_n_dbg_bufg;
logic rst_n_dbg_sync;

logic rst_async_n;
logic rst_n_bufg;

// DM 域复位：按键(低有效) && ~调试器(高有效) && MMCM锁定
assign rst_dbg_async_n = sys_rst_n && (~dbg_rst) && clk_wiz_locked;
BUFG u_rst_dbg_bufg (
    .I  (rst_dbg_async_n),
    .O  (rst_n_dbg_bufg)
);

Cdc_Sync #(
    .WIDTH       (1),
    .RESET_VAL   (0),
    .DELAY_STAGES(3)
) u_cdc_rst_dbg_sync (
    .dst_clk    (clk_cpu),
    .dst_rst_n  (rst_n_dbg_bufg),
    .async_sig  (1'b1),
    .sync_sig   (rst_n_dbg_sync)
);

// SoC 域复位：DM 域复位 && ~ndmreset（调试器可复位整个 SoC）
`ifdef BD32_DEBUG_EN
assign rst_async_n = rst_dbg_async_n && (~ndmreset);
`else
assign rst_async_n = rst_dbg_async_n;
`endif
BUFG u_rst_bufg (
    .I  (rst_async_n),
    .O  (rst_n_bufg)
);

logic rst_n_sync;
Cdc_Sync #(
    .WIDTH       (1),
    .RESET_VAL   (0),
    .DELAY_STAGES(3)
) u_cdc_rst_sync (
    .dst_clk    (clk_cpu),
    .dst_rst_n  (rst_n_bufg),
    .async_sig  (1'b1),
    .sync_sig   (rst_n_sync)
);

// =========================================================================
// 16MHz → 1MHz CLINT timer 时钟（独立域，供 mtime 计数）
// 复位：异步置位、同步释放（对齐 sys_clk）。
// 原来直接接 rst_n_bufg（原始异步复位），释放未对 sys_clk 同步，
// 产生 ndmreset(clk_cpu) → CLINT 分频器 CLR 的跨域 recovery 违例。
// =========================================================================
logic clk_1mhz;
logic rst_n_clint_sync;

Cdc_Sync #(
    .WIDTH       (1),
    .RESET_VAL   (0),
    .DELAY_STAGES(3)
) u_cdc_rst_clint_sync (
    .dst_clk    (sys_clk),
    .dst_rst_n  (rst_n_bufg),
    .async_sig  (1'b1),
    .sync_sig   (rst_n_clint_sync)
);

clk_div_static #(
    .DIV_NUM (50)
) u_clint_timer_div (
    .clk_in  (sys_clk),
    .rst_n   (rst_n_clint_sync),
    .clk_out (clk_1mhz)
);

// =========================================================================
// Debug Module 信号
// =========================================================================
`ifdef BD32_DEBUG_EN
logic                       dbg_halt_req;
logic                       dbg_halted;
logic                       dbg_resume_req;
logic                       dbg_step;
logic                       dbg_ebreakm;
logic                       dbg_reg_we;
logic [4:0]                 dbg_reg_addr;
logic [31:0]                dbg_reg_wdata;
logic [31:0]                dbg_reg_rdata;
logic [31:0]                dbg_dpc;
logic [31:0]                dbg_pc_wdata;
// SBA 总线
logic                       sba_req_valid;
logic [31:0]                sba_addr;
logic [31:0]                sba_wdata;
logic                       sba_write;
logic [2:0]                 sba_size;
logic [3:0]                 sba_be;
logic                       sba_rsp_valid;
logic [31:0]                sba_rdata;
logic                       sba_error;
// Trigger（硬件断点，多路打包）
logic [`TRIGGER_NUM-1:0]    trigger_en;
logic [`TRIGGER_NUM*32-1:0] trigger_addr;
logic                       trigger_hit;
logic                       ebreak_halt;      // CPU ebreak 进 debug 请求
// Debug CSR（Abstract 通用 CSR 读写）
logic                       dbg_csr_we;
logic [11:0]                dbg_csr_addr;
logic [31:0]                dbg_csr_wdata;
logic [31:0]                dbg_csr_rdata;

`endif

// =========================================================================
// SoC_top — 纯数字 SoC IP（接收已同步释放的干净复位）
// =========================================================================
SoC_top #(
    .ITCM_FILE       (`ITCM_FILE       ),
    .DTCM_FILE       (`DTCM_FILE       ),
    .ADDR_WIDTH      (`ADDR_WIDTH      ),
    .DATA_WIDTH      (`DATA_WIDTH      ),
    .REGFILE_NUM     (`REGFILE_NUM     ),
    .REG_ADDR_WIDTH  (`REG_ADDR_WIDTH  ),
    .CSR_ADDR_WIDTH  (`CSR_ADDR_WIDTH  ),
    .ALIGN_BYTES     (`ALIGN_BYTES     ),
    .ALIGN_WIDTH     (`ALIGN_WIDTH     ),
    .GPIO_NUM        (GPIO_NUM         ),
    .TIMER_NUM       (TIMER_NUM        ),
    .TIMER_CHANNEL_NUM (TIMER_CHANNEL_NUM)
) u_SoC_top (
    .sys_clk          (clk_cpu  ),
    .sys_rst_n        (rst_n_sync ),   // 经 Cdc_Sync 3-stage 同步释放
    .timer_clk_i      (clk_1mhz   ),
    .uart_rx          (uart_rx    ),
    .uart_tx          (uart_tx    ),
    .gpio_io          (gpio_io    ),
    .timer_channel_io (timer_channel_io),
    // Debug Module 接口
`ifdef BD32_DEBUG_EN
    .dbg_halt_req     (dbg_halt_req   ),
    .dbg_halted       (dbg_halted     ),
    .dbg_resume_req   (dbg_resume_req ),
    .dbg_step         (dbg_step       ),
    .dbg_ebreakm      (dbg_ebreakm    ),
    .dbg_reg_we       (dbg_reg_we     ),
    .dbg_reg_addr     (dbg_reg_addr   ),
    .dbg_reg_wdata    (dbg_reg_wdata  ),
    .dbg_reg_rdata    (dbg_reg_rdata  ),
    .dbg_dpc          (dbg_dpc        ),
    .dbg_pc_wdata     (dbg_pc_wdata   ),
    // SBA
    .sba_req_valid    (sba_req_valid  ),
    .sba_addr         (sba_addr       ),
    .sba_wdata        (sba_wdata      ),
    .sba_write        (sba_write      ),
    .sba_size         (sba_size       ),
    .sba_be           (sba_be         ),
    .sba_rsp_valid    (sba_rsp_valid  ),
    .sba_rdata        (sba_rdata      ),
    .sba_error        (sba_error      ),
    // Trigger
    .trigger_en       (trigger_en     ),
    .trigger_addr     (trigger_addr   ),
    .trigger_hit      (trigger_hit    ),
    .ebreak_halt      (ebreak_halt    ),
    // Debug CSR
    .dbg_csr_we       (dbg_csr_we     ),
    .dbg_csr_addr     (dbg_csr_addr   ),
    .dbg_csr_wdata    (dbg_csr_wdata  ),
    .dbg_csr_rdata    (dbg_csr_rdata  )
`else
    .dbg_halt_req     (1'b0           ),
    .dbg_halted       (               ),
    .dbg_resume_req   (1'b0           ),
    .dbg_step         (1'b0           ),
    .dbg_ebreakm      (1'b0           ),
    .dbg_reg_we       (1'b0           ),
    .dbg_reg_addr     (5'b0           ),
    .dbg_reg_wdata    (32'b0          ),
    .dbg_reg_rdata    (               ),
    .dbg_dpc          (               ),
    .dbg_pc_wdata     (32'b0          ),
    .sba_req_valid    (1'b0           ),
    .sba_addr         (32'b0          ),
    .sba_wdata        (32'b0          ),
    .sba_write        (1'b0           ),
    .sba_size         (3'b0           ),
    .sba_be           (4'b0           ),
    .sba_rsp_valid    (               ),
    .sba_rdata        (               ),
    .sba_error        (               ),
    .trigger_en       (1'b0           ),
    .trigger_addr     (32'b0          ),
    .trigger_hit      (               ),
    .ebreak_halt      (               ),
    .dbg_csr_we       (1'b0           ),
    .dbg_csr_addr     (12'b0          ),
    .dbg_csr_wdata    (32'b0          ),
    .dbg_csr_rdata    (               )
`endif
);

// =========================================================================
// Debug Module（JTAG TAP + DM）
// =========================================================================
`ifdef BD32_DEBUG_EN
debug_top u_debug_top (
    .clk              (clk_cpu        ),
    .rst_n            (rst_n_dbg_sync ),   // DM/JTAG 域复位，不受 ndmreset 影响
    // JTAG 引脚
    .tck              (dbg_tck        ),
    .tms              (dbg_tms        ),
    .tdi              (dbg_tdi        ),
    .tdo              (dbg_tdo        ),
    // CPU 寄存器堆
    .dbg_reg_we       (dbg_reg_we     ),
    .dbg_reg_addr     (dbg_reg_addr   ),
    .dbg_reg_wdata    (dbg_reg_wdata  ),
    .dbg_reg_rdata    (dbg_reg_rdata  ),
    // CPU 流水线控制
    .dbg_halt_req     (dbg_halt_req   ),
    .dbg_halted       (dbg_halted     ),
    .dbg_resume_req   (dbg_resume_req ),
    .dbg_step         (dbg_step       ),
    .dbg_ebreakm      (dbg_ebreakm    ),
    // Debug CSR
    .dbg_dpc          (dbg_dpc        ),
    .dbg_pc_wdata     (dbg_pc_wdata   ),
    // SBA 总线
    .sba_req_valid    (sba_req_valid  ),
    .sba_addr         (sba_addr       ),
    .sba_wdata        (sba_wdata      ),
    .sba_write        (sba_write      ),
    .sba_size         (sba_size       ),
    .sba_be           (sba_be         ),
    .sba_rsp_valid    (sba_rsp_valid  ),
    .sba_rdata        (sba_rdata      ),
    .sba_error        (sba_error      ),
    // Trigger（硬件断点）
    .trigger_en       (trigger_en     ),
    .trigger_addr     (trigger_addr   ),
    .trigger_hit      (trigger_hit    ),
    .ebreak_halt      (ebreak_halt    ),
    // Debug CSR
    .dbg_csr_we       (dbg_csr_we     ),
    .dbg_csr_addr     (dbg_csr_addr   ),
    .dbg_csr_wdata    (dbg_csr_wdata  ),
    .dbg_csr_rdata    (dbg_csr_rdata  ),
    // 复位控制
    .ndmreset         (ndmreset       )
);
`else
assign dbg_tdo = 1'b0;
`endif

endmodule
