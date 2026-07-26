`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
module Decoder #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH
    )(
    input   logic   [ADDR_WIDTH-1:0]        inst_addr,
    input   logic   [DATA_WIDTH-1:0]        inst,
    //from register
    input   logic   [DATA_WIDTH-1:0]        reg_rs1_rdata,
    input   logic   [DATA_WIDTH-1:0]        reg_rs2_rdata,

    //to register
    output  logic   [REG_ADDR_WIDTH-1:0]    reg_rs1_raddr,
    output  logic   [REG_ADDR_WIDTH-1:0]    reg_rs2_raddr,
    //to instr execute
    output  logic   [DATA_WIDTH-1:0]        alu_op1,
    output  logic   [DATA_WIDTH-1:0]        alu_op2,
    output  logic   [DATA_WIDTH-1:0]        imm,
    output  logic                           access_en,
    output  logic                           access_wr,
    output  logic                           csr_en,
    output  logic   [CSR_ADDR_WIDTH-1:0]    csr_addr,
    output  logic                           is_fence_i,
    output  logic                           is_nop,  
    output  logic   [1:0]                   branch_inst_type,// 指令类型 (00:非跳转指令, 01:B, 10:JAL, 11:JALR)
    output  logic                           branch_req,
    output  logic                           push_ras,        // call
    output  logic                           pop_ras,          // ret

    //to Ctrl
    output  logic                           id_illegal_inst, // 非法指令
    output  logic                           id_ecall,        // 环境调用
    output  logic                           id_ebreak,       // 环境断点
    output  logic   [2:0]                   inst_type           // 0:OTHER 1:ALU 2:LOAD 3:STORE 4:BR 5:JMP 6:MULDIV
);



logic [6:0] opcode;
// logic [4:0]     rd;
logic [2:0] func3;
logic [4:0] rs1;
logic [4:0] rs2;
logic [4:0] rd;
logic [6:0] func7;
logic [11:0]func12;
logic [11:0]zimm;


logic       invalid_inst;
logic       ecall_req;
logic       ebreak_req;

/*
link为x1或x5

对于JAL指令, rd = link时push
对于JALR指令:
        rd  |  rs1  | rs1 = rd |   RAS操作
    -------------------------------------------
    !link | !link |    ---   |    none
    !link | link  |    ---   |    pop
    link  | !link |    ---   |    push
    link  | link  |     0    |    pop, then push
    link  | link  |     1    |    push
*/
logic rd_link;
logic rs1_link;
logic rs1_eq_rd;


assign  opcode  = inst[6:0];
assign  rd      = inst[11:7];
assign  func3   = inst[14:12];
assign  rs1     = inst[19:15];
assign  rs2     = inst[24:20];
assign  func7   = inst[31:25];
assign  func12  = inst[31:20];
assign  zimm    = inst[31:20];

assign  rd_link = (rd == 'd1 || rd == 'd5);
assign  rs1_link = (inst[19:15] == 'd1 || inst[19:15] == 'd5);
assign  rs1_eq_rd = (inst[19:15] == rd);

assign  is_nop = (inst == `INST_NOP);
assign  id_illegal_inst = invalid_inst;
assign  id_ecall        = ecall_req;
assign  id_ebreak       = ebreak_req;

always_comb begin
    inst_type = 3'd0;
    case(opcode)
        `INST_TYPE_I:            inst_type = 3'd1;  // ALU
        `INST_TYPE_R_M:          inst_type = func7[0] ? 3'd6 : 3'd1;  // MULDIV or ALU
        `INST_TYPE_B:            inst_type = 3'd4;  // BRANCH
        `INST_TYPE_S:            inst_type = 3'd3;  // STORE
        `INST_TYPE_L:            inst_type = 3'd2;  // LOAD
        `INST_JAL, `INST_JALR:   inst_type = 3'd5;  // JUMP
        `INST_LUI, `INST_AUIPC:  inst_type = 3'd1;  // ALU
        default:                 inst_type = 3'd0;  // OTHER
    endcase
end

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
    reg_rs1_raddr   = 0;
    reg_rs2_raddr   = 0;
    alu_op1     = 'h0;
    alu_op2     = 'h0;
    access_en   = 1'b0;
    access_wr   = 1'b0;
    csr_en      = 1'b0;
    csr_addr    = 'h0;
    invalid_inst = 1'b0;
    ecall_req       = 1'b0;
    ebreak_req      = 1'b0;
    is_fence_i      = 1'b0;
    branch_inst_type= 2'b00;
    branch_req      = 1'b0;
    push_ras        = 1'b0;
    pop_ras         = 1'b0;
    case(opcode)
        `INST_TYPE_I:begin
            case(func3)
                `INST_ADDI,`INST_SLTI, `INST_SLTIU, `INST_XORI, `INST_ORI, `INST_ANDI, `INST_SLLI, `INST_SRI:begin

                    access_en       = 1'b0;
                    access_wr       = 1'b0;
                    csr_en          = 1'b0;
                    reg_rs1_raddr   = rs1;
                    reg_rs2_raddr   = 5'h0;
                    alu_op1         = reg_rs1_rdata;
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

                    access_en       = 1'b0;
                    access_wr       = 1'b0;
                    csr_en          = 1'b0;
                    reg_rs1_raddr   = rs1;
                    reg_rs2_raddr   = rs2;
                    alu_op1         = reg_rs1_rdata;
                    alu_op2         = reg_rs2_rdata;
                end
                default: begin
                    invalid_inst = 1'b1;
                end
            endcase
        end
        `INST_TYPE_B:begin
            case(func3)
                `INST_BEQ,`INST_BNE,`INST_BLT,`INST_BGE,`INST_BLTU,`INST_BGEU:begin
        
                    access_en       = 1'b0;
                    access_wr       = 1'b0;
                    csr_en          = 1'b0;
                    reg_rs1_raddr   = rs1;
                    reg_rs2_raddr   = rs2;
                    alu_op1         = reg_rs1_rdata;
                    alu_op2         = reg_rs2_rdata;
                    branch_inst_type= 2'b01;
                    branch_req      = 1'b1;
                end
                default: begin
                    invalid_inst = 1'b1;
                end
            endcase
        end
        `INST_TYPE_S:begin
            case(func3)
                `INST_SB, `INST_SW, `INST_SH:begin
        
                    access_en       = 1'b1;
                    access_wr       = 1'b1;
                    csr_en          = 1'b0;
                    reg_rs1_raddr   = rs1;
                    reg_rs2_raddr   = rs2;
                    alu_op1         = reg_rs1_rdata;
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

                    access_en       = 1'b1;
                    access_wr       = 1'b0;
                    csr_en          = 1'b0;
                    reg_rs1_raddr   = rs1;
                    reg_rs2_raddr   = 'h0;
                    alu_op1         = reg_rs1_rdata;
                    alu_op2         = imm;
                end
                default: begin
                    invalid_inst = 1'b1;
                end
            endcase
        end
        `INST_SYSTEM:begin
            
            case(func3)
                `INST_CSRRW, `INST_CSRRS, `INST_CSRRC:begin
                    csr_addr        = zimm;

                    access_en       = 1'b0;
                    access_wr       = 1'b0;
                    csr_en          = 1'b1;
                    reg_rs1_raddr   = rs1;
                    reg_rs2_raddr   = 'h0;
                    alu_op1         = reg_rs1_rdata;
                    alu_op2         = 'h0;
                end
                `INST_CSRRWI, `INST_CSRRSI, `INST_CSRRCI:begin
                    csr_addr        = zimm;

                    access_en       = 1'b0;
                    access_wr       = 1'b0;
                    csr_en          = 1'b1;
                    reg_rs1_raddr   = 'h0;
                    reg_rs2_raddr   = 'h0;
                    alu_op1         = reg_rs1_rdata;
                    alu_op2         = 'h0;
                end
                `INST_PRIV: begin
                    case(func12)
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

            access_en       = 1'b0;
            access_wr       = 1'b0;
            csr_en          = 1'b0;
            reg_rs1_raddr   = 5'h0;
            reg_rs2_raddr   = 5'h0;
            alu_op1         = inst_addr;
            alu_op2         = imm;
            branch_inst_type= 2'b10;
            branch_req      = 1'b1;
            push_ras        = rd_link;//push or none
        end
        `INST_JALR:begin

            access_en       = 1'b0;
            access_wr       = 1'b0;
            csr_en          = 1'b0;
            reg_rs1_raddr   = rs1;
            reg_rs2_raddr   = 5'h0;
            alu_op1         = reg_rs1_rdata;
            alu_op2         = imm;
            branch_inst_type= 2'b11;
            branch_req      = 1'b1;
            push_ras        = rd_link;
            pop_ras         = rs1_link && ((rd_link && ~rs1_eq_rd) || ~rd_link);
        end
        `INST_LUI:begin

            access_en       = 1'b0;
            access_wr       = 1'b0;
            csr_en          = 1'b0;
            reg_rs1_raddr   = 5'h0;
            reg_rs2_raddr   = 5'h0;
            alu_op1         = 32'h0;
            alu_op2         = imm;
        end
        `INST_AUIPC:begin

            access_en       = 1'b0;
            access_wr       = 1'b0;
            csr_en          = 1'b0;
            reg_rs1_raddr   = 5'h0;
            reg_rs2_raddr   = 5'h0;
            alu_op1         = inst_addr;
            alu_op2         = imm;
        end
        `INST_FENCE: begin

            access_en       = 1'b0;
            access_wr       = 1'b0;
            csr_en          = 1'b0;
            reg_rs1_raddr   = 5'h0;
            reg_rs2_raddr   = 5'h0;
            alu_op1         = inst_addr;
            alu_op2         = 32'h4;
            is_fence_i      = func3[0];
        end
        default: begin
            invalid_inst = |inst;
        end
    endcase 
end
    
endmodule
