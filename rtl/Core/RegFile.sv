`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
module RegFile #(
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter REGFILE_NUM =`REGFILE_NUM
    )(
    input   logic                           clk,
    input   logic                           rst_n,
    //读端口
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rs1_raddr,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rs2_raddr,
    output  logic   [DATA_WIDTH-1:0]        reg_rs1_rdata,
    output  logic   [DATA_WIDTH-1:0]        reg_rs2_rdata,
    //写端口1：正常 WB 路径（短指令写回）
    input   logic                           reg_rd_wen,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rd_waddr,
    input   logic   [DATA_WIDTH-1:0]        reg_rd_wdata,
    //写端口2：OITF 退休路径（长指令写回）
    input   logic                           reg_rd_wen2,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rd_waddr2,
    input   logic   [DATA_WIDTH-1:0]        reg_rd_wdata2
);

logic [DATA_WIDTH-1:0] regs [0:REGFILE_NUM-1] ;

always_comb begin
    if(!rst_n)
        reg_rs1_rdata = 'h0;
    else if(reg_rs1_raddr == 5'h0)
        reg_rs1_rdata = 'h0;
    else if(reg_rd_wen && (reg_rs1_raddr == reg_rd_waddr))//旁路 Port1
        reg_rs1_rdata = reg_rd_wdata;
    else if(reg_rd_wen2 && (reg_rs1_raddr == reg_rd_waddr2))//旁路 Port2
        reg_rs1_rdata = reg_rd_wdata2;
    else
        reg_rs1_rdata = regs[reg_rs1_raddr];
end

always_comb begin
    if(!rst_n)
        reg_rs2_rdata = 'h0;
    else if(reg_rs2_raddr == 5'h0)
        reg_rs2_rdata = 'h0;
    else if(reg_rd_wen && (reg_rs2_raddr == reg_rd_waddr))//旁路 Port1
        reg_rs2_rdata = reg_rd_wdata;
    else if(reg_rd_wen2 && (reg_rs2_raddr == reg_rd_waddr2))//旁路 Port2
        reg_rs2_rdata = reg_rd_wdata2;
    else
        reg_rs2_rdata = regs[reg_rs2_raddr];
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(int i=0;i<REGFILE_NUM;i++) begin
            regs[i] <= #1 'h0;
        end
    end
    else begin
        // Port2 先写（OITF 退休），Port1 后写（WB），同地址时 Port1 覆盖
        if(reg_rd_wen2 && (reg_rd_waddr2 != 5'h0))
            regs[reg_rd_waddr2] <= #1 reg_rd_wdata2;
        if(reg_rd_wen && (reg_rd_waddr != 5'h0))
            regs[reg_rd_waddr] <= #1 reg_rd_wdata;
    end
end
endmodule
