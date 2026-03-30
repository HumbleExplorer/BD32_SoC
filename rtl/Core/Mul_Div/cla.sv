`timescale 1ns / 1ps
module cla #(
    parameter PRODUCT_WIDTH = 64,
    localparam GROUP_NUM = PRODUCT_WIDTH / 4
)(
    input   logic   [PRODUCT_WIDTH-1:0] op1,
    input   logic   [PRODUCT_WIDTH-1:0] op2,
    output  logic   [PRODUCT_WIDTH-1:0] sum,
    output  logic   cout
);

logic [GROUP_NUM:0] c;
assign c[0] = 1'b0;
assign cout = c[GROUP_NUM];

generate
    genvar i;
    for (i = 0; i < GROUP_NUM; i = i + 1) begin
        cla_4bit u_cla_4bit_i (
            .op1(op1[4*i+3:4*i]),
            .op2(op2[4*i+3:4*i]),
            .cin(c[i]),
            .sum(sum[4*i+3:4*i]),
            .cout(c[i+1])
            );
    end
endgenerate

endmodule