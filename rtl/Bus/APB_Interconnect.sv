`include "./../SoC_Config.sv"
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
    // 输出给每个从机的 PSEL 信号
    output logic                    o_gpio_psel,
    output logic                    o_uart_psel,

    // 返回给主机的最终信号
    output logic [PDATA_WIDTH-1:0]  PRDATA,
    output logic                    PREADY,
    output logic                    PSLVERR
);

assign o_gpio_psel = (PADDR[PDATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `GPIO_BASE_ADDR) & PSEL;
assign o_uart_psel = (PADDR[PDATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `UART_BASE_ADDR) & PSEL;

assign PREADY = i_gpio_ready & i_uart_ready;
assign PSLVERR = 1'b0;

always_comb begin
    PRDATA = 'h0;
    if (o_gpio_psel)
        PRDATA = i_gpio_rdata;
    else if (o_uart_psel)
        PRDATA = i_uart_rdata;
    else
        PRDATA = 'h0;
end

endmodule