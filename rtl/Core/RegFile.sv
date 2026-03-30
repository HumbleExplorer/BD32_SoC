`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
module RegFile #(
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter REGFILE_NUM =`REGFILE_NUM
    )( 
    input   logic                           clk,
    input   logic                           rst_n,
    //from inst_decode
    input   logic   [REG_ADDR_WIDTH-1:0]    rd_rs1_addr,
    input   logic   [REG_ADDR_WIDTH-1:0]    rd_rs2_addr,
    //to inst_decode
    output  logic   [DATA_WIDTH-1:0]        rd_rs1_data,
    output  logic   [DATA_WIDTH-1:0]        rd_rs2_data,
    //from execute 
    input   logic                           wr_reg_en,
    input   logic   [REG_ADDR_WIDTH-1:0]    wr_reg_addr,
    input   logic   [DATA_WIDTH-1:0]        wr_reg_data
);  

logic [DATA_WIDTH-1:0] regs [0:REGFILE_NUM-1] ;

always_comb begin
    if(!rst_n)
        rd_rs1_data = 'h0;
    else if(rd_rs1_addr == 5'h0)
        rd_rs1_data = 'h0;
    else if(wr_reg_en && (rd_rs1_addr == wr_reg_addr))//旁路
        rd_rs1_data = wr_reg_data;
    else
        rd_rs1_data = regs[rd_rs1_addr];
end

always_comb begin
    if(!rst_n)
        rd_rs2_data = 'h0;
    else if(rd_rs2_addr == 5'h0)
        rd_rs2_data = 'h0;
    else if(wr_reg_en && (rd_rs2_addr == wr_reg_addr))
        rd_rs2_data = wr_reg_data;
    else
        rd_rs2_data = regs[rd_rs2_addr];
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(int i=0;i<REGFILE_NUM;i++) begin
            regs[i] <= #1 'h0;
        end
    end
    else if(wr_reg_en && (wr_reg_addr != 5'h0)) begin
        regs[wr_reg_addr] <= #1 wr_reg_data;
    end
end
endmodule