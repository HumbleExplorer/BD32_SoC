// 注意：此处divisor = SYS_CLK_FREQ/BAUD/16
// 经计算，当主频为50MHz，波特率为115200时，波特率偏差为0.47%
`timescale 1ns / 1ps
module uart_clk_div (
    input   logic           clk,        // 任意频率系统时钟
    input   logic           rst_n,      // 异步复位，低有效
    input   logic   [15:0]  divisor,    // 16位整数除数（兼容16550，≥2）
    output  logic           clk_sample, // 16x 采样时钟（50%占空比）
    output  logic           clk_uart    // 1x 发送时钟（50%占空比）
);
localparam SAMPLE_DIV = 16;        // 16x采样时钟再分频为1x发送时钟的系数

// 第一级分频：任意频率系统时钟分频为16x采样时钟
clk_div_dynamic #(
    .DIV_WIDTH(16)
) u_clk_div_gen_sample (
    .clk_in(clk),
    .rst_n(rst_n),
    .divisor(divisor),
    .clk_out(clk_sample)
);

// 第二级分频：16x采样时钟分频为1x发送时钟（固定16分频）
clk_div_static #(
    .DIV_NUM(SAMPLE_DIV)
) u_clk_div_gen_uart (
    .clk_in(clk_sample),
    .rst_n(rst_n),
    .clk_out(clk_uart)
);

endmodule