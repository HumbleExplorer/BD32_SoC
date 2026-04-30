`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
module EX_MEM #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
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
    input   logic   [ADDR_WIDTH-1:0]        mem_addr_i,
    input   logic                           access_en_i,
    input   logic                           access_wr_i,
    input   logic   [2:0]                   rd_mem_func3_i,

    input   logic   [DATA_WIDTH-1:0]        wr_mem_data_i,
    input   logic   [ALIGN_BYTES-1:0]       wr_mem_mask_i,
    // from execute (branch control, for BRANCH_JUMP_DELAYED)
    input   logic                           branch_jump_en_i,
    input   logic   [ADDR_WIDTH-1:0]        branch_jump_addr_i,
    //to ctrl
    // output  logic                           jump_en,
    // output  logic   [ADDR_WIDTH-1:0]        jump_addr,
    // to mem
    output  logic   [ADDR_WIDTH-1:0]        inst_addr_o,
    output  logic   [DATA_WIDTH-1:0]        inst_o,
    output  logic   [ADDR_WIDTH-1:0]        mem_addr_o,
    output  logic                           access_en_o,
    output  logic                           access_wr_o,
    output  logic   [2:0]                   rd_mem_func3_o,
    output  logic   [DATA_WIDTH-1:0]        wr_mem_data_o,
    output  logic   [ALIGN_BYTES-1:0]       wr_mem_mask_o,
    // to ctrl (branch control, for BRANCH_JUMP_DELAYED)
    output  logic                           branch_jump_en_o,
    output  logic   [ADDR_WIDTH-1:0]        branch_jump_addr_o,
    // to wb
    output  logic                           wr_reg_en_o,
    output  logic   [REG_ADDR_WIDTH-1:0]    wr_reg_addr_o,
    output  logic   [DATA_WIDTH-1:0]        wr_reg_data_o
);


always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_o     <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 `INST_NOP;
        mem_addr_o      <= #1 'h0;
        access_en_o     <= #1 1'b0;
        rd_mem_func3_o  <= #1 'h0;
        access_wr_o     <= #1 1'b0;
        wr_mem_data_o   <= #1 'h0;
        wr_mem_mask_o   <= #1 'h0;
        wr_reg_en_o     <= #1 1'b0;
        wr_reg_addr_o   <= #1 'h0;
        wr_reg_data_o   <= #1 'h0;
        branch_jump_en_o  <= #1 1'b0;
        branch_jump_addr_o<= #1 'h0;
    end else if(flush) begin
        inst_addr_o     <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 `INST_NOP;
        mem_addr_o      <= #1 'h0;
        access_en_o     <= #1 1'b0;
        rd_mem_func3_o  <= #1 'h0;
        access_wr_o     <= #1 1'b0;
        wr_mem_data_o   <= #1 'h0;
        wr_mem_mask_o   <= #1 'h0;
        wr_reg_en_o     <= #1 1'b0;
        wr_reg_addr_o   <= #1 'h0;
        wr_reg_data_o   <= #1 'h0;
        branch_jump_en_o  <= #1 1'b0;
        branch_jump_addr_o<= #1 'h0;
    end else if(!stall) begin//指令地址无需清零
        inst_addr_o     <= #1 inst_addr_i;
        inst_o          <= #1 inst_i;
        mem_addr_o      <= #1 mem_addr_i;
        access_en_o     <= #1 access_en_i;
        rd_mem_func3_o  <= #1 rd_mem_func3_i;
        access_wr_o     <= #1 access_wr_i;
        wr_mem_data_o   <= #1 wr_mem_data_i;
        wr_mem_mask_o   <= #1 wr_mem_mask_i;
        wr_reg_en_o     <= #1 wr_reg_en_i;
        wr_reg_addr_o   <= #1 wr_reg_addr_i;
        wr_reg_data_o   <= #1 wr_reg_data_i;
        branch_jump_en_o  <= #1 branch_jump_en_i;
        branch_jump_addr_o<= #1 branch_jump_addr_i;
    end
end

endmodule
