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
    input  logic                                     sys_rst_n,         // 板载复位按键
    input  logic                                     uart_rx,
    output logic                                     uart_tx,
    inout  [GPIO_NUM-1:0]                            gpio_io,
    inout  [TIMER_NUM*TIMER_CHANNEL_NUM-1:0]         timer_channel_io
);

// =========================================================================
// MMCM 时钟生成：50MHz → 90MHz / 16MHz / 8.388MHz
// =========================================================================
logic clk_wiz_locked;
logic clk_90mhz, clk_16mhz, clk_8m388;

clk_wiz_0 u_clk_wiz_0 (
    .clk_in     (sys_clk),
    .clk_90mhz  (clk_90mhz),
    .clk_16mhz  (clk_16mhz),
    .clk_8m388  (clk_8m388),
    .reset      (~sys_rst_n),
    .locked     (clk_wiz_locked)
);

// =========================================================================
// 复位：按键有效 && MMCM 锁定 → BUFG → 异步复位同步释放
// =========================================================================
logic rst_async_n;
logic rst_n_bufg;

assign rst_async_n = sys_rst_n && clk_wiz_locked;
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
    .dst_clk    (clk_90mhz),
    .dst_rst_n  (rst_n_bufg),
    .async_sig  (1'b1),
    .sync_sig   (rst_n_sync)
);

// =========================================================================
// 16MHz → 1MHz CLINT timer 时钟（独立域，供 mtime 计数）
// =========================================================================
logic clk_1mhz;

clk_div_static #(
    .DIV_NUM (16)
) u_clint_timer_div (
    .clk_in  (clk_16mhz),
    .rst_n   (rst_n_bufg),
    .clk_out (clk_1mhz)
);

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
    .sys_clk          (clk_90mhz  ),
    .sys_rst_n        (rst_n_sync ),   // 经 Cdc_Sync 3-stage 同步释放
    .timer_clk_i      (clk_1mhz   ),
    .uart_rx          (uart_rx    ),
    .uart_tx          (uart_tx    ),
    .gpio_io          (gpio_io    ),
    .timer_channel_io (timer_channel_io)
);

endmodule
