`include "./../SoC_Config.sv"
`timescale 1ns / 1ps
module APB_Interconnect #(
    parameter PADDR_WIDTH = `ADDR_WIDTH,
    parameter PDATA_WIDTH = `DATA_WIDTH,
    localparam BLOCK_SIZE_WIDTH = PADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    // APB 主机信号
    input  logic [PADDR_WIDTH-1:0]  PADDR,
    input  logic                    PSEL,
    // 来自所有从机的返回信号
    input  logic [PDATA_WIDTH-1:0]  i_gpio_rdata,
    input  logic                    i_gpio_ready,
    input  logic [PDATA_WIDTH-1:0]  i_uart_rdata,
    input  logic                    i_uart_ready,
    input  logic [PDATA_WIDTH-1:0]  i_timer_rdata,
    input  logic                    i_timer_ready,
    input  logic [PDATA_WIDTH-1:0]  i_clint_rdata,
    input  logic                    i_clint_ready,
    input  logic [PDATA_WIDTH-1:0]  i_plic_rdata,
    input  logic                    i_plic_ready,
    // 输出给每个从机的 PSEL 信号
    output logic                    o_gpio_psel,
    output logic                    o_uart_psel,
    output logic                    o_timer_psel,
    output logic                    o_clint_psel,
    output logic                    o_plic_psel,

    // 返回给主机的最终信号
    output logic [PDATA_WIDTH-1:0]  PRDATA,
    output logic                    PREADY,
    output logic                    PSLVERR
);

assign o_gpio_psel  = (PADDR[PDATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `GPIO_BASE_ADDR)  & PSEL;
assign o_uart_psel   = (PADDR[PDATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `UART_BASE_ADDR)  & PSEL;
assign o_timer_psel  = (PADDR[PDATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `TIMER_BASE_ADDR) & PSEL;
assign o_clint_psel   = (PADDR[PDATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `CLINT_BASE_ADDR)  & PSEL;
assign o_plic_psel    = (PADDR[PDATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `PLIC_BASE_ADDR)   & PSEL;

// Ready 信号：根据选中的从机返回对应的 ready
assign PREADY = (o_gpio_psel  & i_gpio_ready) |
                (o_uart_psel   & i_uart_ready) |
                (o_timer_psel  & i_timer_ready) |
                (o_clint_psel  & i_clint_ready) |
                (o_plic_psel   & i_plic_ready);

assign PSLVERR = 1'b0;

always_comb begin
    PRDATA = 'h0;
    if (o_gpio_psel)
        PRDATA = i_gpio_rdata;
    else if (o_uart_psel)
        PRDATA = i_uart_rdata;
    else if (o_timer_psel)
        PRDATA = i_timer_rdata;
    else if (o_clint_psel)
        PRDATA = i_clint_rdata;
    else if (o_plic_psel)
        PRDATA = i_plic_rdata;
    else
        PRDATA = 'h0;
end

endmodule