`include "./../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;

import bd32_pkg::*;

module APB_Interconnect #(
    parameter PADDR_WIDTH = `ADDR_WIDTH,
    parameter PDATA_WIDTH = `DATA_WIDTH,
    parameter NUM_SLAVES  = APB_NUM_SLAVES,
    localparam BLOCK_SIZE_WIDTH = PADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    // 上游 APB 主机（AXI_APB_Bridge 内 APB_Master 输出）
    apb_if.slave  m,
    // 下游各从机（SoC_top 例化的接口数组）
    apb_if.master s [NUM_SLAVES]
);

    logic [NUM_SLAVES-1:0] psel_vec;

    // 从机返回信号采集到线网数组（接口实例数组只允许常量下标访问）
    logic [PDATA_WIDTH-1:0]  slv_prdata  [NUM_SLAVES];
    logic [NUM_SLAVES-1:0]   slv_pready;
    logic [NUM_SLAVES-1:0]   slv_pslverr;

    genvar g;
    generate
        for (g = 0; g < NUM_SLAVES; g = g + 1) begin : gen_bus
            // 共享信号广播，PSEL 按槽位门控（与原 o_psel 同语义）
            assign s[g].paddr   = m.paddr;
            assign s[g].psel    = psel_vec[g] & m.psel;
            assign s[g].penable = m.penable;
            assign s[g].pwrite  = m.pwrite;
            assign s[g].pstrb   = m.pstrb;
            assign s[g].pwdata  = m.pwdata;
            // 返回信号采集
            assign slv_prdata[g]  = s[g].prdata;
            assign slv_pready[g]  = s[g].pready;
            assign slv_pslverr[g] = s[g].pslverr;
        end
    endgenerate

    // 地址译码：基于 [31:16] 匹配
    always_comb begin
        psel_vec = '0;
        case (m.paddr[PADDR_WIDTH-1:BLOCK_SIZE_WIDTH])
            CLINT_BASE_TAG: psel_vec[0]  = 1'b1;
            PLIC_BASE_TAG:  psel_vec[1]  = 1'b1;
            GPIO_BASE_TAG:  psel_vec[2]  = 1'b1;
            UART_BASE_TAG:  psel_vec[3]  = 1'b1;
            TIMER_BASE_TAG: psel_vec[4]  = 1'b1;
            SPI_BASE_TAG:   psel_vec[5]  = 1'b1;
            I2C_BASE_TAG:   psel_vec[6]  = 1'b1;
            default:         psel_vec     = '0;
        endcase
    end

    // 聚合返回信号：按未门控 psel_vec 选择，未命中默认 PREADY=1/PRDATA=0/PSLVERR=0
    always_comb begin
        m.prdata  = {PDATA_WIDTH{1'b0}};
        m.pready  = 1'b1;
        m.pslverr = 1'b0;
        if (|psel_vec) begin
            for (int i = 0; i < NUM_SLAVES; i = i + 1) begin
                if (psel_vec[i]) begin
                    m.prdata  = slv_prdata[i];
                    m.pready  = slv_pready[i];
                    m.pslverr = slv_pslverr[i];
                end
            end
        end
    end

endmodule
