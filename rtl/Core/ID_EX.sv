`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
module ID_EX #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
 )( 
    input   logic                           clk,
    input   logic                           rst_n,
    input   logic                           stall,
    input   logic                           flush,
    //from id
    input   logic   [ADDR_WIDTH-1:0]        inst_addr_i,
    input   logic   [DATA_WIDTH-1:0]        inst_i,
    input   logic                           predict_taken_i,
    input   logic   [ADDR_WIDTH-1:0]        predict_target_i,
    input   logic   [DATA_WIDTH-1:0]        alu_op1_i,
    input   logic   [DATA_WIDTH-1:0]        alu_op2_i,
    input   logic   [DATA_WIDTH-1:0]        imm_i,
    input   logic   [DATA_WIDTH-1:0]        rs2_data_i,
    input   logic                           wr_reg_en_i,
    input   logic                           access_en_i,
    input   logic                           access_wr_i,
    input   logic                           access_csr_en_i,
    input   logic   [CSR_ADDR_WIDTH-1:0]    csr_addr_i,

    input   logic   [REG_ADDR_WIDTH-1:0]    rd_rs1_addr_i,
    input   logic   [REG_ADDR_WIDTH-1:0]    rd_rs2_addr_i,
    //to execute
    output  logic   [ADDR_WIDTH-1:0]        inst_addr_o,
    output  logic   [DATA_WIDTH-1:0]        inst_o,
    output  logic                           predict_taken_o,
    output  logic   [ADDR_WIDTH-1:0]        predict_target_o,
    output  logic   [DATA_WIDTH-1:0]        alu_op1_o,
    output  logic   [DATA_WIDTH-1:0]        alu_op2_o,
    output  logic   [DATA_WIDTH-1:0]        imm_o,
    output  logic   [DATA_WIDTH-1:0]        rs2_data_o,
    output  logic                           wr_reg_en_o,
    output  logic                           access_en_o,
    output  logic                           access_wr_o,
    output  logic                           access_csr_en_o,
    output  logic   [CSR_ADDR_WIDTH-1:0]    csr_addr_o,
    //to Data_Hazard
    output  logic   [REG_ADDR_WIDTH-1:0]    rd_rs1_addr_o,
    output  logic   [REG_ADDR_WIDTH-1:0]    rd_rs2_addr_o
);

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_o     <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 `INST_NOP;
        predict_taken_o <= #1 1'b0;
        predict_target_o<= #1 'h0;
        alu_op1_o       <= #1 'h0;
        alu_op2_o       <= #1 'h0;
        imm_o           <= #1 'h0;
        rs2_data_o      <= #1 'h0;
        wr_reg_en_o     <= #1 1'b0;
        access_en_o     <= #1 1'b0;
        access_wr_o     <= #1 1'b0;
        access_csr_en_o <= #1 1'b0;
        csr_addr_o      <= #1 'h0;
        rd_rs1_addr_o   <= #1 'h0;
        rd_rs2_addr_o   <= #1 'h0;
    end else if(flush) begin
        inst_addr_o     <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 `INST_NOP;
        predict_taken_o <= #1 1'b0;
        predict_target_o<= #1 'h0;
        alu_op1_o       <= #1 'h0;
        alu_op2_o       <= #1 'h0;
        imm_o           <= #1 'h0;
        rs2_data_o      <= #1 'h0;
        wr_reg_en_o     <= #1 1'b0;
        access_en_o     <= #1 1'b0;
        access_wr_o     <= #1 1'b0;
        access_csr_en_o <= #1 1'b0;
        csr_addr_o      <= #1 'h0;
        rd_rs1_addr_o   <= #1 'h0;
        rd_rs2_addr_o   <= #1 'h0;
    end else if (!stall) begin
        inst_addr_o     <= #1 inst_addr_i;
        inst_o          <= #1 inst_i;
        predict_taken_o <= #1 predict_taken_i;
        predict_target_o<= #1 predict_target_i;
        alu_op1_o       <= #1 alu_op1_i;
        alu_op2_o       <= #1 alu_op2_i;
        imm_o           <= #1 imm_i;
        rs2_data_o      <= #1 rs2_data_i;
        wr_reg_en_o     <= #1 wr_reg_en_i;
        access_en_o     <= #1 access_en_i;
        access_wr_o     <= #1 access_wr_i;
        access_csr_en_o <= #1 access_csr_en_i;
        csr_addr_o      <= #1 csr_addr_i;
        rd_rs1_addr_o   <= #1 rd_rs1_addr_i;
        rd_rs2_addr_o   <= #1 rd_rs2_addr_i;
    end
    // else begin
    //     wr_reg_en_o     <= #1 1'b0;
    //     access_en_o     <= #1 1'b0;
    //     access_csr_en_o <= #1 1'b0;
    // end
end

endmodule
