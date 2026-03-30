`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
module Decoder #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH
    )(
    input   logic   [ADDR_WIDTH-1:0]        inst_addr,
    input   logic   [DATA_WIDTH-1:0]        inst,
    //from register
    input   logic   [DATA_WIDTH-1:0]        rd_rs1_data,
    input   logic   [DATA_WIDTH-1:0]        rd_rs2_data,

    input   logic   [1:0]                   priv_mode,
    //to register
    output  logic   [REG_ADDR_WIDTH-1:0]    rd_rs1_addr,
    output  logic   [REG_ADDR_WIDTH-1:0]    rd_rs2_addr,
    output  logic                           wr_reg_en,
    //to instr execute
    output  logic   [DATA_WIDTH-1:0]        alu_op1,
    output  logic   [DATA_WIDTH-1:0]        alu_op2,
    output  logic   [DATA_WIDTH-1:0]        imm,
    output  logic                           access_en,
    output  logic                           access_wr,
    output  logic                           access_csr_en,
    output  logic   [CSR_ADDR_WIDTH-1:0]    csr_addr,

    //to Ctrl
    output  logic   [DATA_WIDTH-2:0]        exception_code,
    output  logic   [DATA_WIDTH-1:0]        exception_val
);

logic [6:0] opcode;
// logic [4:0]     rd;
logic [2:0] func3;
logic [4:0] rs1;
logic [4:0] rs2;
logic [6:0] func7;
logic [11:0]zimm;

logic       invalid_inst;
logic       ecall_req;
logic       ebreak_req;


assign  opcode  = inst[6:0];
// assign  rd      = inst[11:7];
assign  func3   = inst[14:12];
assign  rs1     = inst[19:15];
assign  rs2     = inst[24:20];
assign  func7   = inst[31:25];
assign  zimm    = inst[31:20];

assign  exception_code = invalid_inst ? 'h2 : ecall_req ? ((priv_mode == 2'b00) ? 'h8 : 'h11): ebreak_req ? 'h3 : {(DATA_WIDTH-1){1'b1}};
assign  exception_val  = 'h0;
always_comb begin
    case(opcode)
        `INST_TYPE_I,`INST_TYPE_L,`INST_JALR:
            imm = {{20{inst[31]}},inst[31:20]};
        `INST_TYPE_S:
            imm = {{20{inst[31]}},inst[31:25],inst[11:7]};
        `INST_TYPE_B:
            imm = {{20{inst[31]}},inst[7],inst[30:25],inst[11:8],1'b0};
        `INST_JAL:
            imm = {{12{inst[31]}},inst[19:12],inst[20],inst[30:21],1'b0};
        `INST_LUI,`INST_AUIPC:
            imm = {inst[31:12],12'h0};
        default:
            imm = 32'h0;
    endcase
end

always_comb    begin
    rd_rs1_addr = 0;
    rd_rs2_addr = 0;
    alu_op1     = 'h0;
    alu_op2     = 'h0;
    wr_reg_en   = 1'b0;
    access_en   = 1'b0;
    access_wr   = 1'b0;
    access_csr_en   = 1'b0;
    csr_addr    = 'h0;
    invalid_inst = 1'b0;
    ecall_req       = 1'b0;
    ebreak_req      = 1'b0;

    case(opcode)
        `INST_TYPE_I:begin
            case(func3)
                `INST_ADDI,`INST_SLTI, `INST_SLTIU, `INST_XORI, `INST_ORI, `INST_ANDI, `INST_SLLI, `INST_SRI:begin
                    wr_reg_en       = 1'b1;
                    access_en       = 1'b0;
                    access_wr       = 1'b0;
                    access_csr_en   = 1'b0;
                    rd_rs1_addr     = rs1;
                    rd_rs2_addr     = 5'h0;
                    alu_op1         = rd_rs1_data;
                    alu_op2         = imm;
                end
                default: begin
                    invalid_inst = 1'b1;
                end
            endcase
        end
        `INST_TYPE_R_M:begin
            case(func3)
                `INST_ADD_SUB,`INST_SLL,`INST_SLT,`INST_SLTU,`INST_XOR,`INST_SR,`INST_OR,`INST_AND,
                `INST_MUL,`INST_MULHU,`INST_MULH,`INST_MULHSU,`INST_DIV,`INST_DIVU,`INST_REM,`INST_REMU:begin
                    wr_reg_en       = 1'b1;
                    access_en       = 1'b0;
                    access_wr       = 1'b0;
                    access_csr_en   = 1'b0;
                    rd_rs1_addr     = rs1;
                    rd_rs2_addr     = rs2;
                    alu_op1         = rd_rs1_data;
                    alu_op2         = rd_rs2_data;
                end
                default: begin
                    invalid_inst = 1'b1;
                end
            endcase
        end
        `INST_TYPE_B:begin
            case(func3)
                `INST_BEQ,`INST_BNE,`INST_BLT,`INST_BGE,`INST_BLTU,`INST_BGEU:begin
                    wr_reg_en       = 1'b0;
                    access_en       = 1'b0;
                    access_wr       = 1'b0;
                    access_csr_en   = 1'b0;
                    rd_rs1_addr     = rs1;
                    rd_rs2_addr     = rs2;
                    alu_op1         = rd_rs1_data;
                    alu_op2         = rd_rs2_data;
                end
                default: begin
                    invalid_inst = 1'b1;
                end
            endcase
        end
        `INST_TYPE_S:begin
            case(func3)
                `INST_SB, `INST_SW, `INST_SH:begin
                    wr_reg_en       = 1'b0;
                    access_en       = 1'b1;
                    access_wr       = 1'b1;
                    access_csr_en   = 1'b0;
                    rd_rs1_addr     = rs1;
                    rd_rs2_addr     = rs2;
                    alu_op1         = rd_rs1_data;
                    alu_op2         = imm;
                end
                default: begin
                    invalid_inst = 1'b1;
                end
            endcase
        end
        `INST_TYPE_L:begin
            case(func3)
                `INST_LB, `INST_LH, `INST_LW, `INST_LBU, `INST_LHU:begin
                    wr_reg_en       = 1'b1;
                    access_en       = 1'b1;
                    access_wr       = 1'b0;
                    access_csr_en   = 1'b0;
                    rd_rs1_addr     = rs1;
                    rd_rs2_addr     = 'h0;
                    alu_op1         = rd_rs1_data;
                    alu_op2         = imm;
                end
                default: begin
                    invalid_inst = 1'b1;
                end
            endcase
        end
        `INST_SYSTEM:begin
            csr_addr = imm;
            case(func3)
                `INST_CSRRW, `INST_CSRRS, `INST_CSRRC:begin
                    wr_reg_en       = 1'b1;
                    access_en       = 1'b0;
                    access_wr       = 1'b0;
                    access_csr_en   = 1'b1;
                    rd_rs1_addr     = rs1;
                    rd_rs2_addr     = 'h0;
                    alu_op1         = rd_rs1_data;
                    alu_op2         = 'h0;
                end
                `INST_CSRRWI, `INST_CSRRSI, `INST_CSRRCI:begin
                    wr_reg_en       = 1'b1;
                    access_en       = 1'b0;
                    access_wr       = 1'b0;
                    access_csr_en   = 1'b1;
                    rd_rs1_addr     = 'h0;
                    rd_rs2_addr     = 'h0;
                    alu_op1         = rd_rs1_data;
                    alu_op2         = 'h0;
                end
                `INST_PRIV: begin
                    case(zimm)
                        `INST_EBREAK: ebreak_req = 1'b1;
                        `INST_ECALL :  ecall_req = 1'b1;
                        `INST_WFI,`INST_MRET : ;
                        default: begin
                            invalid_inst = 1'b1;
                        end
                    endcase
                end
                default: begin
                    invalid_inst = 1'b1;
                end
            endcase
        end
        `INST_JAL:begin
            wr_reg_en       = 1'b1;
            access_en       = 1'b0;
            access_wr       = 1'b0;
            access_csr_en   = 1'b0;
            rd_rs1_addr     = 5'h0;
            rd_rs2_addr     = 5'h0;
            alu_op1         = 32'h0;
            alu_op2         = imm;
        end
        `INST_JALR:begin
            wr_reg_en       = 1'b1;
            access_en       = 1'b0;
            access_wr       = 1'b0;
            access_csr_en   = 1'b0;
            rd_rs1_addr     = rs1;
            rd_rs2_addr     = 5'h0;
            alu_op1         = rd_rs1_data;
            alu_op2         = imm;
        end
        `INST_LUI:begin
            wr_reg_en       = 1'b1;
            access_en       = 1'b0;
            access_wr       = 1'b0;
            access_csr_en   = 1'b0;
            rd_rs1_addr     = 5'h0;
            rd_rs2_addr     = 5'h0;
            alu_op1         = 32'h0;
            alu_op2         = imm;
        end
        `INST_AUIPC:begin
            wr_reg_en       = 1'b1;
            access_en       = 1'b0;
            access_wr       = 1'b0;
            access_csr_en   = 1'b0;
            rd_rs1_addr     = 5'h0;
            rd_rs2_addr     = 5'h0;
            alu_op1         = inst_addr;
            alu_op2         = imm;
        end
        `INST_FENCE: begin
            wr_reg_en       = 1'b0;
            access_en       = 1'b0;
            access_wr       = 1'b0;
            access_csr_en   = 1'b0;
            rd_rs1_addr     = 5'h0;
            rd_rs2_addr     = 5'h0;
            alu_op1         = inst_addr;
            alu_op2         = 32'h4;
        end
        `INST_NOP_OP: begin
            wr_reg_en       = 1'b0;
            access_en       = 1'b0;
            access_wr       = 1'b0;
            access_csr_en   = 1'b0;
            rd_rs1_addr     = 5'h0;
            rd_rs2_addr     = 5'h0;
            alu_op1         = 32'h0;
            alu_op2         = 32'h0;
        end
        default: begin
            invalid_inst = |inst;
        end
    endcase 
end
    
endmodule
