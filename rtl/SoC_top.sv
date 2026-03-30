`include "SoC_Config.sv"
`include "RV32_Inst_Define.sv"
`timescale 1ns / 1ps
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
    parameter GPIO_NUM = `GPIO_NUM
)(
    // System
    input   logic   sys_clk,
    input   logic   rst_n,
    // input   logic   clk_timer,//1MHz
    // UART
    (* mark_debug = "true" *)input   logic   uart_rx,
    (* mark_debug = "true" *)output  logic   uart_tx,

    inout  [GPIO_NUM-1:0]  gpio_io
    // I2C
    // SPI
);

logic   sys_rst_n;
// PLL Output
// logic                       clk_timer;
// Update Output
(* mark_debug = "true" *)logic                       itcm_wr_en;
(* mark_debug = "true" *)logic   [ADDR_WIDTH-1:0]    itcm_wr_addr;
(* mark_debug = "true" *)logic   [DATA_WIDTH-1:0]    itcm_wr_data;

// RISC_V_Core Output
logic                       clint_sel;
logic                       plic_sel;
logic                       bus_sel;
logic   [ADDR_WIDTH-1:0]    access_addr;
logic                       access_wr;
logic   [DATA_WIDTH-1:0]    access_wr_data;
logic   [ALIGN_BYTES-1:0]   access_wr_mask;

// CLINT Output
logic   [DATA_WIDTH-1:0]    clint_rdata;
logic   [2*DATA_WIDTH-1:0]  mtime_shadow;
logic                       software_int;
logic                       timer_int;
// PLIC Output
logic                       external_int;
// Bus_Access Output
logic   [DATA_WIDTH-1:0]    bus_rdata;
logic                       bus_tran_done;
logic   [ADDR_WIDTH-1:0]    periph_addr;
logic                       periph_enable;
logic                       periph_write;
logic   [ALIGN_BYTES-1:0]   periph_wmask;
logic   [DATA_WIDTH-1:0]    periph_wdata;
// logic                       periph_ready;
// apb_uart Output
logic                       uart_psel;
logic   [DATA_WIDTH-1:0]    uart_rdata;
logic                       uart_ready;
logic                       uart_irq;
// apb_gpio Output
logic                       gpio_psel;
logic   [DATA_WIDTH-1:0]    gpio_rdata;
logic                       gpio_ready;
logic                       gpio_irq;

// ------------------------ 用Cdc_Sync实现同步释放 ------------------------
// 关键：Cdc_Sync的dst_rst_n直接接消抖后的异步复位信号（rst_n）
// 这样既保证"异步复位生效"，又通过两拍同步实现"同步释放"
Cdc_Sync #(
    .WIDTH      (1),
    .RESET_VAL  (0),  // 复位后默认值为0（低电平复位）
    .DELAY_STAGES(2)  // 延迟两拍同步
) u_cdc_rst_sync (
    .dst_clk    (sys_clk),  // 目标时钟：系统主时钟
    .dst_rst_n  (rst_n),    // 异步复位：消抖后的按键信号
    .async_sig  (1'b1),     // 固定输入1（同步释放的核心技巧）
    .sync_sig   (sys_rst_n) // 输出：全局复位信号（同步释放后）
);

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
)u_RISC_V_Core(
    .clk            (sys_clk         ),
    .rst_n          (sys_rst_n       ),
    .itcm_wr_en     (itcm_wr_en      ),
    .itcm_wr_addr   (itcm_wr_addr    ),
    .itcm_wr_data   (itcm_wr_data    ),
    .clint_rdata    (clint_rdata     ),
    .mtime_shadow   (mtime_shadow    ),
    .software_int   (software_int    ),
    .timer_int      (timer_int       ),
    .clint_sel      (clint_sel       ),
    .external_int   (external_int    ),
    .plic_sel       (plic_sel        ),
    .bus_rdata      (bus_rdata       ),
    .bus_tran_done  (bus_tran_done   ),
    .bus_sel        (bus_sel         ),
    .access_addr    (access_addr     ),
    .access_wr      (access_wr       ),
    .access_wr_data (access_wr_data  ),
    .access_wr_mask (access_wr_mask  )
);

CLINT #(
    .ADDR_WIDTH     (ADDR_WIDTH    ),
    .DATA_WIDTH     (DATA_WIDTH    ),
    .ALIGN_BYTES    (ALIGN_BYTES   )
)u_CLINT(
    .clk            (sys_clk       ),
    .rst_n          (sys_rst_n     ),
    // .clk_timer      (clk_timer     ),
    .clint_sel      (clint_sel     ),
    .mmio_addr      (access_addr   ),
    .wr_en          (access_wr     ),
    .wr_data        (access_wr_data),
    .wr_mask        (access_wr_mask),
    .rd_data        (clint_rdata   ),
    .mtime_shadow   (mtime_shadow  ),
    .software_int   (software_int  ),
    .timer_int      (timer_int     )
);

Bus_Access #(
    .ADDR_WIDTH  	(ADDR_WIDTH   ),
    .DATA_WIDTH  	(DATA_WIDTH   ),
    .ALIGN_BYTES 	(ALIGN_BYTES  ))
u_Bus_Access(
    .i_sys_clk     	(sys_clk        ),
    .i_rst_n       	(sys_rst_n      ),
    .i_en          	(bus_sel        ),
    .i_write       	(access_wr      ),
    .i_addr        	(access_addr    ),
    .i_wdata       	(access_wr_data ),
    .i_wmask        (access_wr_mask),
    .o_rdata       	(bus_rdata      ),
    .o_tran_done   	(bus_tran_done  ),
    .o_periph_addr  (periph_addr    ),
    .o_gpio_psel   	(gpio_psel      ),
    .o_uart_psel   	(uart_psel      ),
    .o_periph_enable(periph_enable  ),
    .o_periph_write (periph_write   ),
    .o_periph_wmask (periph_wmask   ),
    .o_periph_wdata (periph_wdata   ),
    .i_gpio_rdata 	(gpio_rdata     ),
    .i_gpio_ready 	(gpio_ready     ),
    .i_uart_rdata 	(uart_rdata     ),
    .i_uart_ready 	(uart_ready     )
);

apb_uart #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
)u_apb_uart(
    .PCLK           (sys_clk        ),
    .PSESETn        (sys_rst_n      ),
    .PADDR          (periph_addr    ),
    .PSEL           (uart_psel      ),
    .PENABLE        (periph_enable  ),
    .PWRITE         (periph_write   ),
    .PWDATA         (periph_wdata   ),
    .PRDATA         (uart_rdata     ),
    .PREADY         (uart_ready     ),
    // .pslverr    (pslverr  ),
    .irq_o          (uart_irq       ),
    .uart_rx_i      (uart_rx        ),
    .uart_tx_o      (uart_tx        ),
    .itcm_wr_en_o   (itcm_wr_en     ),
    .itcm_wr_addr_o (itcm_wr_addr   ),
    .itcm_wr_data_o (itcm_wr_data   )
);

apb_gpio #(
    .ADDR_WIDTH  	(ADDR_WIDTH   ),
    .DATA_WIDTH  	(DATA_WIDTH   ),
    .ALIGN_BYTES 	(ALIGN_BYTES  )
)u_apb_gpio(
    .PCLK    	(sys_clk        ),
    .PRESETn 	(sys_rst_n      ),
    .PADDR   	(periph_addr    ),
    .PSEL    	(gpio_psel      ),
    .PENABLE 	(periph_enable  ),
    .PWRITE  	(periph_write   ),
    .PSTRB   	(periph_wmask   ),
    .PWDATA  	(periph_wdata   ),
    .PRDATA  	(gpio_rdata     ),
    .PREADY  	(gpio_ready     ),
    .irq_o   	(gpio_irq       ),
    .gpio_io  	(gpio_io        )
);

// 暂时的
assign external_int = uart_irq || gpio_irq;

endmodule