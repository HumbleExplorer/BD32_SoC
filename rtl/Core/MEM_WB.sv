`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
module MEM_WB #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
 )( 
    input   logic                           clk,
    input   logic                           rst_n,
    input   logic                           stall,
    input   logic                           flush,
    // from execute
    input   logic   [ADDR_WIDTH-1:0]        inst_addr_i,
    input   logic   [DATA_WIDTH-1:0]        inst_i,
    input   logic                           wr_reg_en_i,
    input   logic   [REG_ADDR_WIDTH-1:0]    wr_reg_addr_i,
    input   logic   [DATA_WIDTH-1:0]        wr_reg_data_i,
    // to ctrl
    // output  logic                           jump_en,
    // output  logic   [ADDR_WIDTH-1:0]        jump_addr,
    // to wb
    output  logic   [DATA_WIDTH-1:0]        inst_o,
    output  logic   [ADDR_WIDTH-1:0]        inst_addr_o,
    output  logic                           wr_reg_en_o,
    output  logic   [REG_ADDR_WIDTH-1:0]    wr_reg_addr_o,
    output  logic   [DATA_WIDTH-1:0]        wr_reg_data_o
);


always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_o     <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 `INST_NOP;
        wr_reg_en_o     <= #1 1'b0;
        wr_reg_addr_o   <= #1 'h0;
        wr_reg_data_o   <= #1 'h0;
    end else if(flush) begin
        inst_addr_o     <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 `INST_NOP;
        wr_reg_en_o     <= #1 1'b0;
        wr_reg_addr_o   <= #1 'h0;
        wr_reg_data_o   <= #1 'h0;
    end else if(!stall) begin//指令地址无需清零
        inst_addr_o     <= #1 inst_addr_i;
        inst_o          <= #1 inst_i;
        wr_reg_en_o     <= #1 wr_reg_en_i;
        wr_reg_addr_o   <= #1 wr_reg_addr_i;
        wr_reg_data_o   <= #1 wr_reg_data_i;
    end
end

endmodule