`include "./../SoC_Config.sv"
`timescale 1ns / 1ps
module Bus_Access #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES
)(
    //clk and rst
    input   logic                       i_sys_clk,// 时钟信号
    input   logic                       i_rst_n,// 复位信号，低电平有效
    // connect User
    // 外部输入的User信号和i_sys_clk同源，不必做异步处理
    input   logic                       i_transfer,
    input   logic                       i_write,
    input   logic   [ADDR_WIDTH-1:0]    i_addr,
    input   logic   [DATA_WIDTH-1:0]    i_wdata,
    input   logic   [ALIGN_BYTES-1:0]   i_wmask,
    output  logic   [DATA_WIDTH-1:0]    o_rdata,
    output  logic                       o_tran_done,
    // connect APB Slave
    output  logic   [ADDR_WIDTH-1:0]    o_periph_addr,// 地址总线
    output  logic                       o_gpio_psel,// 选择信号
    output  logic                       o_uart_psel,// 选择信号
    output  logic                       o_timer_psel,// 选择信号
    output  logic                       o_clint_psel,// 选择信号
    output  logic                       o_periph_enable,// 使能信号
    output  logic                       o_periph_write,// 写信号
    output  logic   [ALIGN_BYTES-1:0]   o_periph_wmask, // 写使能信号
    output  logic   [DATA_WIDTH-1:0]    o_periph_wdata,// 写数据总线
    input   logic   [DATA_WIDTH-1:0]    i_gpio_rdata,// 读数据总线
    input   logic                       i_gpio_ready,// 准备就绪信号
    input   logic   [DATA_WIDTH-1:0]    i_uart_rdata,// 读数据总线
    input   logic                       i_uart_ready,// 准备就绪信号
    input   logic   [DATA_WIDTH-1:0]    i_timer_rdata,// 读数据总线
    input   logic                       i_timer_ready,// 准备就绪信号
    input   logic   [DATA_WIDTH-1:0]    i_clint_rdata,// 读数据总线
    input   logic                       i_clint_ready// 准备就绪信号
);
logic PSEL;
logic [DATA_WIDTH-1:0] PRDATA;
logic PREADY;
logic PSLVERR;

APB_Master #(
    .ADDR_WIDTH     (ADDR_WIDTH ),
    .DATA_WIDTH     (DATA_WIDTH ),
    .ALIGN_BYTES    (ALIGN_BYTES)
) u_APB_Master(
    .*,
    .o_PADDR        (o_periph_addr  ),
    .o_PSEL         (PSEL           ),
    .o_PENABLE      (o_periph_enable),
    .o_PWRITE       (o_periph_write ),
    .o_PSTRB        (o_periph_wmask ),
    .o_PWDATA       (o_periph_wdata ),
    .i_PRDATA       (PRDATA         ),
    .i_PREADY       (PREADY         ),
    .i_PSLVERR      (PSLVERR        )
);

APB_Interconnect #(
    .PADDR_WIDTH 	(ADDR_WIDTH  ),
    .PDATA_WIDTH 	(DATA_WIDTH  ))
u_APB_Interconnect(
    .PADDR          (o_periph_addr),
    .*
);


endmodule