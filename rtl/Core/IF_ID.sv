`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"

`timescale 1ns / 1ps
module IF_ID #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    input   logic                       clk,
    input   logic                       rst_n,
    //from ctrl
    input   logic                       stall,
    input   logic                       flush,
    //from if
    input   logic   [ADDR_WIDTH-1:0]    inst_addr_i,
    input   logic   [DATA_WIDTH-1:0]    inst_i,
    input   logic                       predict_taken_i,
    input   logic   [ADDR_WIDTH-1:0]    predict_target_i,

    //to id
    output  logic   [ADDR_WIDTH-1:0]    inst_addr_o,
    output  logic   [DATA_WIDTH-1:0]    inst_o,
    output  logic                       predict_taken_o,
    output  logic   [ADDR_WIDTH-1:0]    predict_target_o

`ifdef ENABLE_HPM
    ,
    output  logic                       valid_o
`endif
);

`ifdef ENABLE_HPM
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)                 valid_o <= #1 1'b0;
    else if(flush)             valid_o <= #1 1'b0;
    else if (!stall)           valid_o <= #1 1'b1;
end
`endif

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_o     <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 `INST_NOP;
        predict_taken_o <= #1 1'b0;
        predict_target_o<= #1 'h0;
    end else if(flush) begin
        inst_addr_o     <= #1 inst_addr_i;
        inst_o          <= #1 `INST_NOP;
        predict_taken_o <= #1 1'b0;
        predict_target_o<= #1 'h0;
    end else if (!stall) begin//指令地址无需清零
        inst_addr_o     <= #1 inst_addr_i;
        inst_o          <= #1 inst_i;
        // inst_o          <= #1 inst_i == {DATA_WIDTH{1'bx}} ? `INST_NOP : inst_i;//冗余设计
        predict_taken_o <= #1 predict_taken_i;
        predict_target_o<= #1 predict_target_i;
    end
end
endmodule


