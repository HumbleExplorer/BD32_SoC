`include "./../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;

module APB_Interconnect #(
    parameter PADDR_WIDTH = `ADDR_WIDTH,
    parameter PDATA_WIDTH = `DATA_WIDTH,
    parameter NUM_SLAVES  = `APB_NUM_SLAVES,
    localparam BLOCK_SIZE_WIDTH = PADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    // APB Master 接口
    input  logic [PADDR_WIDTH-1:0]  PADDR,
    input  logic                    PSEL,
    // 各从机返回信号
    input  wire  [PDATA_WIDTH-1:0]  i_prdata  [NUM_SLAVES],
    input  logic [NUM_SLAVES-1:0]   i_pready,
    input  logic [NUM_SLAVES-1:0]   i_pslverr,
    // 输出给各从机的 PSEL
    output logic [NUM_SLAVES-1:0]   o_psel,
    // 返回给主机的聚合信号
    output logic [PDATA_WIDTH-1:0]  PRDATA,
    output logic                    PREADY,
    output logic                    PSLVERR
);

    logic [NUM_SLAVES-1:0] psel_vec;

    // 地址译码：基于 [31:16] 匹配
    always_comb begin
        psel_vec = '0;
        case (PADDR[PADDR_WIDTH-1:BLOCK_SIZE_WIDTH])
            `CLINT_BASE_TAG: psel_vec[0]  = 1'b1;
            `PLIC_BASE_TAG:  psel_vec[1]  = 1'b1;
            `GPIO_BASE_TAG:  psel_vec[2]  = 1'b1;
            `UART_BASE_TAG:  psel_vec[3]  = 1'b1;
            `TIMER_BASE_TAG: psel_vec[4]  = 1'b1;
            `SPI_BASE_TAG:   psel_vec[5]  = 1'b1;
            `I2C_BASE_TAG:   psel_vec[6]  = 1'b1;
            default:         psel_vec     = '0;
        endcase
    end

    // PSEL 选通：仅当 Master PSEL 有效时输出
    assign o_psel = psel_vec & {NUM_SLAVES{PSEL}};

    // 聚合返回信号
    always_comb begin
        PRDATA  = {PDATA_WIDTH{1'b0}};
        PREADY  = 1'b1;   // 默认就绪，用于未匹配地址
        PSLVERR = 1'b0;   // 默认无错误
        if (|psel_vec) begin
            // 地址命中已知从机，返回对应从机信号
            for (int i = 0; i < NUM_SLAVES; i = i + 1) begin
                if (psel_vec[i]) begin
                    PRDATA  = i_prdata[i];
                    PREADY  = i_pready[i];
                    PSLVERR = i_pslverr[i];
                end
            end
        end
        // 若 psel_vec == 0（未匹配地址），保持默认值：PREADY=1, PRDATA=0, PSLVERR=0
    end

endmodule
