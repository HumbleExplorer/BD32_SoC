`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
module Executer #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    parameter ALIGN_WIDTH = `ALIGN_WIDTH
)(
    input   logic                           clk,
    input   logic                           rst_n,
    // from id_ex
    input   logic   [ADDR_WIDTH-1:0]        inst_addr,
    input   logic   [DATA_WIDTH-1:0]        inst,
    input   logic   [DATA_WIDTH-1:0]        imm,
    input   logic                           predict_taken,
    input   logic   [ADDR_WIDTH-1:0]        predict_target,
    `ifndef BRANCH_JUMP_DELAYED
    input   logic                           is_fence_i,
    `endif
    input   logic                           access_wr,
    // from CSR
    input   logic   [DATA_WIDTH-1:0]        rd_csr_data,
    input   logic                           illegal_inst_csr,
    // from MEM
    input   logic                           access_illegal,
    // from data_hazard (register values + addresses)
    (*MAX_FANOUT=32*)input   logic   [DATA_WIDTH-1:0]        alu_op1,
    (*MAX_FANOUT=32*)input   logic   [DATA_WIDTH-1:0]        alu_op2,
    input   logic   [REG_ADDR_WIDTH-1:0]    rd_rs1_addr,
    input   logic   [REG_ADDR_WIDTH-1:0]    rd_rs2_addr,
    input   logic   [ADDR_WIDTH-1:0]        jump_imm,       // 预计算分支目标
    input   logic   [ADDR_WIDTH-1:0]        inst_addr_plus_4,// 预计算 PC+4
    input   logic   [DATA_WIDTH-1:0]        wr_mem_data_temp,
    // to ctrl
    `ifndef BRANCH_JUMP_DELAYED
    output  logic                           branch_jump_en,//实际上是否跳转
    output  logic   [ADDR_WIDTH-1:0]        branch_jump_addr,//实际跳转地址
    `endif
    output  logic   [DATA_WIDTH-2:0]        exception_code,
    output  logic   [DATA_WIDTH-1:0]        exception_val,
    output  logic                           mul_div_ready,
    // to mem
    output  logic   [ADDR_WIDTH-1:0]        access_addr,
    output  logic   [DATA_WIDTH-1:0]        wr_mem_data,
    output  logic   [ALIGN_BYTES-1:0]       wr_mem_mask,
    output  logic   [2:0]                   rd_mem_func3,
    // to wb
    output  logic   [REG_ADDR_WIDTH-1:0]    wr_reg_addr,
    output  logic   [DATA_WIDTH-1:0]        wr_reg_data,
    // to csr
    output  logic   [DATA_WIDTH-1:0]        wr_csr_data,
    output  logic                           wfi_req,
    output  logic                           mret_req,
    // to IF
    output  logic                           branch_taken,    // 分支跳转方向
    output  logic   [ADDR_WIDTH-1:0]        branch_target   // 分支目标跳转地址
    `ifndef BRANCH_JUMP_DELAYED,
    output  logic                           branch_predict_success
    `endif
);

logic   [6:0]               opcode;
logic   [4:0]               rd;
logic   [2:0]               func3;
logic   [4:0]               zimm;
logic   [6:0]               func7;
logic                       equal;
logic                       less_signed;
logic                       less_unsigned;

logic   [DATA_WIDTH-1:0]    sr_shift;
logic   [DATA_WIDTH-1:0]    sr_shift_mask;

// logic                       access_addr_misalign;
// 支持非对齐访存

assign  opcode          =   inst[6:0];
assign  rd              =   inst[11:7];
assign  func3           =   inst[14:12];
assign  zimm            =   inst[19:15];
assign  func7           =   inst[31:25];
assign  equal           =   (alu_op1 == alu_op2);
assign  less_signed     =   ($signed(alu_op1) < $signed(alu_op2));
assign  less_unsigned   =   (alu_op1 < alu_op2);

assign  sr_shift        =   alu_op1 >> alu_op2[4:0];
assign  sr_shift_mask   =   {DATA_WIDTH{1'b1}} >> alu_op2[4:0];

assign  access_addr = alu_op1 + imm;
// assign  access_addr_misalign = |access_addr[ALIGN_WIDTH-1:0];
assign  rd_mem_func3 = func3;
logic                       mul_div_en;
logic   [2:0]               mul_div_func3;
logic                       mul_div_valid;
logic   [DATA_WIDTH-1:0]    result_mul_div;

assign  mul_div_en = (opcode == `INST_TYPE_R_M) && (func7 == 7'b0000001);
assign  mul_div_func3 = func3;

assign exception_code =(illegal_inst_csr) ? 'h3 : access_illegal ? (access_wr ? 4'd7 : 4'd5) : {DATA_WIDTH-1{1'b1}};
assign exception_val = access_illegal ? access_addr : 'h0;
`ifndef BRANCH_JUMP_DELAYED
assign  branch_predict_success = (predict_taken == branch_taken) && (predict_target == branch_target);
assign  branch_jump_en  = ~branch_predict_success || is_fence_i;//预测失败时跳转
always_comb begin
    if (is_fence_i) begin
        branch_jump_addr = inst_addr_plus_4;
    end else if (branch_predict_success) begin //预测成功
        branch_jump_addr = predict_target;
    end else if (branch_taken && ~predict_taken) begin //跳被预测为不跳
        branch_jump_addr = branch_target;
    end else if (~branch_taken && predict_taken) begin //不跳被预测为跳
        branch_jump_addr = inst_addr_plus_4;
    end else if (predict_target != branch_target) begin //预测地址不正确（默认是跳被预测为跳，因为如果不跳被预测为不跳，那两个地址应都为inst_addr+4）
        branch_jump_addr = branch_target;
    end else begin //其他
        branch_jump_addr = inst_addr_plus_4;
    end
end
`endif

always_comb begin
    wr_reg_addr     = 5'h0;
    wr_reg_data     = 'h0;
    wr_mem_data     = 'h0;
    wr_mem_mask     = 4'b0000;
    wr_csr_data     = 'h0;
    wfi_req         = 1'b0;
    mret_req        = 1'b0;
    branch_taken    = 1'b0;
    branch_target   = 'h0;
    case(opcode)
        `INST_TYPE_I:begin
            wr_reg_addr     = rd;
            case(func3)
                `INST_ADDI  : wr_reg_data   = alu_op1 + alu_op2;
                `INST_SLTI  : wr_reg_data   = less_signed ? 32'h1 : 32'h0;
                `INST_SLTIU : wr_reg_data   = less_unsigned ? 32'h1 : 32'h0;
                `INST_XORI  : wr_reg_data   = alu_op1 ^ alu_op2;
                `INST_ORI   : wr_reg_data   = alu_op1 | alu_op2;
                `INST_ANDI  : wr_reg_data   = alu_op1 & alu_op2;
                `INST_SLLI  : wr_reg_data   = alu_op1 << alu_op2[4:0];
                `INST_SRI:begin
                    if(func7 == 7'b0100000)//SRAI
                        // wr_reg_data = (sr_shift & sr_shift_mask) | ({DATA_WIDTH{alu_op1[DATA_WIDTH-1]}} & (~sr_shift_mask));
                        wr_reg_data = $signed(alu_op1) >>> alu_op2[4:0];
                    else//SRLI
                        wr_reg_data = alu_op1 >> alu_op2[4:0];
                end
            endcase
        end
        `INST_TYPE_R_M:begin
            if ((func7 == 7'b0000000) || (func7 == 7'b0100000)) begin
                wr_reg_addr = rd;
                case(func3)
                    `INST_ADD_SUB:begin
                        if(func7 == 7'b000_0000)//ADD
                            wr_reg_data = alu_op1 + alu_op2;
                        else//SUB
                            wr_reg_data = alu_op1 - alu_op2;
                    end 
                    `INST_SLL: wr_reg_data = alu_op1 << alu_op2[4:0];
                    `INST_SLT: wr_reg_data = less_signed ? 32'h1 : 32'h0;
                    `INST_SLTU:wr_reg_data = less_unsigned ? 32'h1 : 32'h0;
                    `INST_XOR: wr_reg_data = alu_op1 ^ alu_op2;
                    `INST_OR: wr_reg_data  = alu_op1 | alu_op2;
                    `INST_AND:wr_reg_data  = alu_op1 & alu_op2;
                    `INST_SR:begin
                        if(func7 == 7'b0100000)//SRAI
                            // wr_reg_data = (sr_shift & sr_shift_mask) | ({DATA_WIDTH{alu_op1[DATA_WIDTH-1]}} & (~sr_shift_mask));
                            wr_reg_data = $signed(alu_op1) >>> alu_op2[4:0];
                        else//SRLI
                            wr_reg_data = alu_op1 >> alu_op2[4:0];
                    end
                endcase
            end
            else if(func7 == 7'b0000001) begin//RV_M
                if(mul_div_valid) begin
                    wr_reg_data = result_mul_div;
                    wr_reg_addr = rd;
                end
            end
        end
        `INST_TYPE_B: begin
            wr_reg_addr     = 5'h0;
            wr_reg_data     = 'h0;
            wr_mem_data     = 'h0;
            case(func3)
                `INST_BEQ: branch_taken     = equal;
                `INST_BNE: branch_taken     = ~equal;
                `INST_BLT: branch_taken     = less_signed;
                `INST_BGE: branch_taken     = ~less_signed;
                `INST_BLTU:branch_taken     = less_unsigned;
                `INST_BGEU:branch_taken     = ~less_unsigned;
                default: branch_taken     = 1'b0;
            endcase
            branch_target   = branch_taken ? jump_imm : 0;
        end
        `INST_TYPE_S:begin
            case(func3)
                `INST_SB:begin
                    case (access_addr[1:0])
                        2'b00: begin
                            wr_mem_data = {24'h0,wr_mem_data_temp[7:0]};
                            wr_mem_mask = 4'b0001;
                        end
                        2'b01: begin
                            wr_mem_data = {16'h0,wr_mem_data_temp[7:0],8'h0};
                            wr_mem_mask = 4'b0010;
                        end
                        2'b10: begin
                            wr_mem_data = {8'h0,wr_mem_data_temp[7:0],16'h0};
                            wr_mem_mask = 4'b0100;
                        end
                        2'b11: begin
                            wr_mem_data = {wr_mem_data_temp[7:0],24'h0};
                            wr_mem_mask = 4'b1000;
                        end
                        default: begin
                            wr_mem_data = {24'h0,wr_mem_data_temp[7:0]};
                            wr_mem_mask = 4'b0001;
                        end
                    endcase
                end
                `INST_SH: begin
                    case (access_addr[1])
                        1'b0: begin
                            wr_mem_data = {16'h0,wr_mem_data_temp[15:0]};
                            wr_mem_mask = 4'b0011;
                        end
                        1'b1: begin
                            wr_mem_data = {wr_mem_data_temp[15:0],16'h0};
                            wr_mem_mask = 4'b1100;
                        end
                        default: begin
                            wr_mem_data = {16'h0,wr_mem_data_temp[15:0]};
                            wr_mem_mask = 4'b0011;
                        end
                    endcase
                end
                `INST_SW: begin
                    wr_mem_data = wr_mem_data_temp;
                    wr_mem_mask = 4'b1111;
                end
            endcase
        end
        `INST_TYPE_L: begin
            wr_reg_addr = rd;
        end
        `INST_SYSTEM: begin
            wr_reg_addr = rd;
            wr_reg_data = rd_csr_data;
            case (func3)
                `INST_CSRRW: wr_csr_data = alu_op1;
                `INST_CSRRS: wr_csr_data = rd_csr_data | alu_op1;
                `INST_CSRRC: wr_csr_data = rd_csr_data & (~alu_op1);
                `INST_CSRRWI:wr_csr_data = {27'h0,zimm};
                `INST_CSRRSI:wr_csr_data = rd_csr_data | {27'h0,zimm};
                `INST_CSRRCI:wr_csr_data = rd_csr_data & {~{27'h0,zimm}};
                `INST_PRIV:
                    case(zimm)
                        `INST_MRET: mret_req = 1'b1;
                        `INST_WFI:  wfi_req =  1'b1;
                    endcase
            endcase
        end
        /*
        link为x1或x5
        
        对于JAL指令, rd = link时push
        对于JALR指令:
            rd  |  rs1  | rs1 = rd |   RAS操作
        -------------------------------------------
            !link | !link |    ---   |    none
            !link | link  |    ---   |    pop
            link  | !link |    ---   |    push
            link  | link  |     0    |  pop,then push
            link  | link  |     1    |    push
        */
        `INST_JAL:begin
            wr_reg_addr     = rd;
            wr_reg_data     = inst_addr_plus_4;
            branch_taken    = 1'b1;
            branch_target   = jump_imm;
        end
        `INST_JALR:begin
            wr_reg_addr     = rd;
            wr_reg_data     = inst_addr_plus_4;
            branch_taken    = 1'b1;
            branch_target   = alu_op1 + imm;
        end
        `INST_LUI:begin
            wr_reg_addr     = rd;
            wr_reg_data     = alu_op2;
        end
        `INST_AUIPC:begin
            wr_reg_addr     = rd;
            wr_reg_data     = alu_op1 + alu_op2;
        end
        `INST_FENCE:begin
            if(func3) begin//FENCE.I 冲刷
                ;
            end else begin //FENCE 等同于NOP
                ;
            end
        end
        `INST_NOP_OP:;
    endcase
end

    // =========================================================================
    // mul_div 乘法除法单元
    // =========================================================================
    mul_div #(
        .DATA_WIDTH     	(DATA_WIDTH),
        .REG_ADDR_WIDTH 	(REG_ADDR_WIDTH)
    ) u_mul_div (
        .clk         	(clk            ),
        .rst_n       	(rst_n          ),
        .enable      	(mul_div_en     ),
        .rd_rs1_addr 	(rd_rs1_addr    ),
        .rd_rs2_addr 	(rd_rs2_addr    ),
        .wr_rd_addr  	(wr_reg_addr    ),
        .func3_i     	(mul_div_func3  ),
        .a_i         	(alu_op1        ),
        .b_i         	(alu_op2        ),
        .result_o    	(result_mul_div ),
        .data_valid  	(mul_div_valid  ),
        .ready       	(mul_div_ready  )
    );
    
endmodule
