`include "./../SoC_Config.sv"

timeunit 1ns;
timeprecision 1ps;
import bd32_pkg::*;

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
    input   logic                       is_compressed_i,  // 当前指令是否压缩（PC+2 链接）
    input   logic                       illegal_inst_i,   // 压缩保留编码
    input   logic                       zcmp_micro_last_i,// Zcmp 最后一个微操作
    input   logic                       zcmp_micro_any_i, // Zcmp 微操作（任意）
    input   logic                       zcb_tag_i,        // Zcb 指令标签（HPM）
    input   logic                       predict_taken_i,
    input   logic   [ADDR_WIDTH-1:0]    predict_target_i,

    //to id
    output  logic   [ADDR_WIDTH-1:0]    inst_addr_o,
    output  logic   [DATA_WIDTH-1:0]    inst_o,
    output  logic                       is_compressed_o,
    output  logic                       illegal_inst_o,
    output  logic                       zcmp_micro_last_o,
    output  logic                       zcmp_micro_any_o,
    output  logic                       zcb_tag_o,
    output  logic                       predict_taken_o,
    output  logic   [ADDR_WIDTH-1:0]    predict_target_o,
`ifdef DISPLAY_INST_WAVE
    output  logic   [ADDR_WIDTH-1:0]    inst_addr_display_o,
`endif
    output  logic                       valid_o
);

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_o     <= #1 {BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 INST_NOP;
        is_compressed_o <= #1 1'b0;
        illegal_inst_o  <= #1 1'b0;
        zcmp_micro_last_o <= #1 1'b0;
        zcmp_micro_any_o  <= #1 1'b0;
        zcb_tag_o         <= #1 1'b0;
        predict_taken_o <= #1 1'b0;
        predict_target_o<= #1 'h0;
    end else if(flush) begin
        inst_o          <= #1 INST_NOP;
        is_compressed_o <= #1 1'b0;
        illegal_inst_o  <= #1 1'b0;
        zcmp_micro_last_o <= #1 1'b0;
        zcmp_micro_any_o  <= #1 1'b0;
        zcb_tag_o         <= #1 1'b0;
        predict_taken_o <= #1 1'b0;
        predict_target_o<= #1 'h0;
    end else if (!stall) begin//指令地址无需清零
        inst_addr_o     <= #1 inst_addr_i;
        inst_o          <= #1 inst_i;
        is_compressed_o <= #1 is_compressed_i;
        illegal_inst_o  <= #1 illegal_inst_i;
        zcmp_micro_last_o <= #1 zcmp_micro_last_i;
        zcmp_micro_any_o  <= #1 zcmp_micro_any_i;
        zcb_tag_o         <= #1 zcb_tag_i;
        // inst_o          <= #1 inst_i == {DATA_WIDTH{1'bx}} ? INST_NOP : inst_i;//冗余设计
        predict_taken_o <= #1 predict_taken_i;
        predict_target_o<= #1 predict_target_i;
    end
end

`ifdef DISPLAY_INST_WAVE
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_display_o <= #1 {BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
    end else if(flush) begin
        inst_addr_display_o <= #1 {BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
    end else if (!stall) begin
        inst_addr_display_o <= #1 inst_addr_i;
    end
end
`endif

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)                    valid_o <= #1 1'b0;
    else if(flush)                valid_o <= #1 1'b0;
    else                          valid_o <= #1 1'b1;
end
endmodule
