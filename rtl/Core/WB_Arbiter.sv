`include "./../SoC_Config.sv"
`timescale 1ns / 1ps
module WB_Arbiter #(
    parameter DATA_WIDTH = `DATA_WIDTH
)(
    // Mem_Access 输出数据（DTCM load 符号扩展 / ALU 结果透传）
    input   logic   [DATA_WIDTH-1:0]    mem_data_i,
    // 总线原始读数据
    input   logic   [DATA_WIDTH-1:0]    bus_rdata_i,
    // 控制
    input   logic                       bus_done_i,

    // 仲裁输出
    output  logic   [DATA_WIDTH-1:0]    wr_reg_data_o
);

// bus_done 时总线数据已就绪，直接走总线
// DTCM load 走 Mem_Access 符号扩展后的数据
// 其余情况（ALU 结果等）走 Mem_Access 透传
always_comb begin
    if(bus_done_i)
        wr_reg_data_o = bus_rdata_i;
    else
        wr_reg_data_o = mem_data_i;    // ALU 结果
end

endmodule
