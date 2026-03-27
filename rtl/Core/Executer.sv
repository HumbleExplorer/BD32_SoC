`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
module Executer #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    parameter ALIGN_WIDTH = `ALIGN_WIDTH
)(
    // from id_ex
    input   logic   [ADDR_WIDTH-1:0]        inst_addr,
    input   logic   [DATA_WIDTH-1:0]        inst,
    input   logic   [DATA_WIDTH-1:0]        imm,
    input   logic   [ADDR_WIDTH-1:0]        predict_target_pc,
    input   logic                           predict_taken,
    // from CSR
    input   logic   [DATA_WIDTH-1:0]        rd_csr_data,
    input   logic                           illegal_inst_csr,
    // from data_hazard
    input   logic   [DATA_WIDTH-1:0]        alu_op1,
    input   logic   [DATA_WIDTH-1:0]        alu_op2,
    input   logic   [DATA_WIDTH-1:0]        wr_mem_data_temp,

    // from mul_div
    input   logic                           mul_div_valid,
    input   logic   [DATA_WIDTH-1:0]        result_mul_div,
    // from mem
    input   logic   [DATA_WIDTH-1:0]        wr_reg_data_mem,//forward_A_B_C
    // from wb
    input   logic   [DATA_WIDTH-1:0]        wr_reg_data_wb,//forward_A_B
    // to ctrl
    output  logic                           branch_jump_en,//实际上是否跳转
    output  logic   [ADDR_WIDTH-1:0]        branch_jump_addr,//实际跳转地址
    output  logic   [DATA_WIDTH-2:0]        exception_code,
    output  logic   [DATA_WIDTH-1:0]        exception_val,
    // to mul_div
    output  logic                           mul_div_en,
    output  logic   [2:0]                   mul_div_func3,
    // to mem
    output  logic   [ADDR_WIDTH-1:0]        mem_addr,
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
    output  logic                           is_fence_i,
    output  logic                           branch_taken,    // 分支跳转方向
    output  logic   [ADDR_WIDTH-1:0]        branch_target,   // 分支目标跳转地址
    output  logic   [1:0]                   branch_inst_type,// 指令类型 (00:非跳转指令, 01:B, 10:JAL, 11:JALR)
    output  logic                           branch_req,
    output  logic                           branch_predict_success,
    output  logic                           push_ras,        // call
    output  logic                           pop_ras          // ret

);

logic   [6:0]               opcode;
logic   [4:0]               rd;
logic   [2:0]               func3;
logic   [4:0]               zimm;
logic   [6:0]               func7;
logic                       equal;
logic                       less_signed;
logic                       less_unsigned;
logic   [ADDR_WIDTH-1:0]    jump_imm;

logic   [DATA_WIDTH-1:0]    sr_shift;
logic   [DATA_WIDTH-1:0]    sr_shift_mask;

// logic                       access_addr_misalign;
// 支持非对齐访存

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



assign  opcode          =   inst[6:0];
assign  rd              =   inst[11:7];
assign  func3           =   inst[14:12];
assign  zimm            =   inst[19:15];
assign  func7           =   inst[31:25];
assign  equal           =   (alu_op1 == alu_op2) ? 1'b1 : 1'b0;
assign  less_signed     =   ($signed(alu_op1) < $signed(alu_op2)) ? 1'b1 : 1'b0;
assign  less_unsigned   =   (alu_op1 < alu_op2) ? 1'b1 : 1'b0;
assign  jump_imm        =   inst_addr + imm;

assign  sr_shift        =   alu_op1 >> alu_op2[4:0];
assign  sr_shift_mask   =   {DATA_WIDTH{1'b1}} >> alu_op2[4:0];

assign  mem_addr = alu_op1 + imm;
// assign  access_addr_misalign = |mem_addr[ALIGN_WIDTH-1:0];
assign  rd_mem_func3 = func3;
assign  mul_div_en = (opcode == `INST_TYPE_R_M) && (func7 == 7'b0000001);
assign  mul_div_func3 = func3;

// assign  exception_code = (illegal_inst_csr) ? 'h3 : (access_addr_misalign) ? 'h11 : {DATA_WIDTH-1{1'b1}};
assign  exception_code = (illegal_inst_csr) ? 'h3 : {DATA_WIDTH-1{1'b1}};
// assign exception_code = {DATA_WIDTH-1{1'b1}};
assign  exception_val = 'h0;

assign  rd_link = (rd == 'd1 || rd == 'd5);
assign  rs1_link = (inst[19:15] == 'd1 || inst[19:15] == 'd5);
assign  rs1_eq_rd = (inst[19:15] == rd);
assign  is_fence_i = (opcode == `INST_FENCE) && (func3[0]);

assign  branch_predict_success = (predict_taken == branch_taken) && (predict_target_pc == branch_target);
assign  branch_jump_en  = ~branch_predict_success || is_fence_i;//预测失败时跳转
assign  branch_jump_addr= (((branch_taken && ~predict_taken) || (predict_target_pc != branch_target)) && ~is_fence_i) ?//跳被预测为不跳，或者跳不准
                         branch_target : inst_addr + 4;//不跳被预测为跳

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
    branch_inst_type= 2'b00;
    branch_req      = 1'b0;
    push_ras        = 1'b0;
    pop_ras         = 1'b0;
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
            branch_inst_type= 2'b01;
            branch_req      = 1'b1;
            case(func3)
                `INST_BEQ: begin
                    branch_taken     = equal;
                    branch_target   = equal ? jump_imm : 'h0;
                end
                `INST_BNE: begin
                    branch_taken     = ~equal;
                    branch_target   = ~equal ? jump_imm : 'h0;
                end
                `INST_BLT: begin
                    branch_taken     = less_signed;
                    branch_target   = less_signed ? jump_imm : 'h0;
                end
                `INST_BGE: begin
                    branch_taken     = ~less_signed;
                    branch_target   = ~less_signed ? jump_imm : 'h0;
                end
                `INST_BLTU: begin
                    branch_taken     = less_unsigned;
                    branch_target   = less_unsigned ? jump_imm : 'h0;
                end
                `INST_BGEU: begin
                    branch_taken     = ~less_unsigned;
                    branch_target   = ~less_unsigned ? jump_imm : 'h0;
                end
            endcase
        end
        `INST_TYPE_S:begin
            case(func3)
                `INST_SB:begin
                    case (mem_addr[1:0])
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
                    case (mem_addr[1])
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
            wr_reg_data     = inst_addr + 32'h4;
            branch_taken    = 1'b1;
            branch_target   = inst_addr + alu_op2;
            branch_inst_type= 2'b10;
            branch_req      = 1'b1;
            push_ras        = rd_link;//push or none
        end
        `INST_JALR:begin
            wr_reg_addr     = rd;
            wr_reg_data     = inst_addr + 32'h4;
            branch_taken    = 1'b1;
            branch_target   = alu_op1 + alu_op2;
            branch_inst_type= 2'b11;
            branch_req      = 1'b1;
            push_ras        = rd_link;
            pop_ras         = rs1_link && ((rd_link && ~rs1_eq_rd) || ~rd_link);
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
    
endmodule
