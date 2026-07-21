`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
module Executer #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    parameter ALIGN_WIDTH = `ALIGN_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    input   logic                           clk,
    input   logic                           rst_n,
    // from id_ex
    input   logic   [ADDR_WIDTH-1:0]        inst_addr,
    input   logic   [DATA_WIDTH-1:0]        inst,
    input   logic   [DATA_WIDTH-1:0]        imm,
    input   logic                           predict_taken,
    input   logic   [ADDR_WIDTH-1:0]        predict_target,
    input   logic                           is_nop,
    input   logic                           is_fence_i,
    input   logic                           access_en,
    input   logic                           access_wr,
    input   logic                           id_ex_flush,
    input   logic                           id_ex_stall,
    // from CSR
    input   logic   [DATA_WIDTH-1:0]        csr_rdata,
    input   logic                           illegal_inst_csr,
    // from data_hazard (register values + addresses)
    (*MAX_FANOUT=32*)input   logic   [DATA_WIDTH-1:0]        alu_op1,
    (*MAX_FANOUT=32*)input   logic   [DATA_WIDTH-1:0]        alu_op2,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rs1_raddr,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rs2_raddr,
    input   logic   [ADDR_WIDTH-1:0]        jump_imm,       // 预计算分支目标
    input   logic   [ADDR_WIDTH-1:0]        inst_addr_plus_4,// 预计算 PC+4
    input   logic   [DATA_WIDTH-1:0]        access_wdata_temp,
    // to ctrl
    output  logic                           branch_jump_en,//实际上是否跳转
    output  logic   [ADDR_WIDTH-1:0]        branch_jump_addr,//实际跳转地址
    output  logic   [DATA_WIDTH-2:0]        exception_code,
    output  logic   [DATA_WIDTH-1:0]        exception_val,
    // to OITF（长周期指令派发）
    output  logic                           lp_valid,           // EX 阶段确认长周期指令
    output  logic                           lp_is_div,          // 1=DIV  0=MUL
    output  logic                           mul_ready,
    output  logic                           div_ready,
    output  logic                           mul_valid_wbck,
    output  logic                           div_valid_wbck,
    output  logic   [DATA_WIDTH-1:0]        mul_result_wbck,
    output  logic   [DATA_WIDTH-1:0]        div_result_wbck,
    // to mem
    output  logic   [ADDR_WIDTH-1:0]        access_addr,
    output  logic   [DATA_WIDTH-1:0]        access_wdata,
    output  logic   [ALIGN_BYTES-1:0]       access_wmask,
    output  logic   [2:0]                   access_func3,
    // to wb（写寄存器信息）
    output  logic                           reg_rd_wen,
    output  logic   [REG_ADDR_WIDTH-1:0]    reg_rd_waddr,
    output  logic   [DATA_WIDTH-1:0]        reg_rd_wdata,
    // to csr
    output  logic   [DATA_WIDTH-1:0]        csr_wdata,
    output  logic                           wfi_req,
    output  logic                           mret_req,
    // to IF
    output  logic                           branch_taken,    // 分支跳转方向
    output  logic   [ADDR_WIDTH-1:0]        branch_target,   // 分支目标跳转地址
    output  logic                           branch_predict_success
);

logic   [6:0]               opcode;
logic   [4:0]               rd;
logic   [2:0]               func3;
logic   [4:0]               zimm;
logic   [6:0]               func7;
logic   [11:0]              func12;
logic                       equal;
logic                       less_signed;
logic                       less_unsigned;
logic   [DATA_WIDTH-1:0]    sr_shift;
logic   [DATA_WIDTH-1:0]    sr_shift_mask;
logic                       mul_div_en;
logic  access_illegal;
logic  access_addr_misalign;

assign  opcode          =   inst[6:0];
assign  rd              =   inst[11:7];
assign  func3           =   inst[14:12];
assign  zimm            =   inst[19:15];
assign  func7           =   inst[31:25];
assign  func12          =   inst[31:20];
assign  equal           =   (alu_op1 == alu_op2);
assign  less_signed     =   ($signed(alu_op1) < $signed(alu_op2));
assign  less_unsigned   =   (alu_op1 < alu_op2);

assign  sr_shift        =   alu_op1 >> alu_op2[4:0];
assign  sr_shift_mask   =   {DATA_WIDTH{1'b1}} >> alu_op2[4:0];

assign  access_addr = alu_op1 + imm;
assign  access_func3 = func3;
assign  lp_is_div = func3[2];

assign access_illegal = access_en ? (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] < `DTCM_BASE_TAG): 1'b0;
assign exception_code = access_illegal ? (access_wr ? 4'd7 : 4'd5) : access_addr_misalign ? (access_wr ? 4'd6 : 4'd4) : (illegal_inst_csr) ? 4'd2 : {DATA_WIDTH-1{1'b1}};
assign exception_val = (access_illegal || access_addr_misalign) ? access_addr : illegal_inst_csr ? inst : 'h0;
assign branch_predict_success = ((predict_taken && branch_taken) && (predict_target == branch_target)) 
                            || (~predict_taken && ~branch_taken);
assign branch_jump_addr = branch_taken ? branch_target : inst_addr_plus_4;
assign branch_jump_en  = ~branch_predict_success || is_fence_i;//预测失败时跳转

always_comb begin
    reg_rd_wen        = 1'b0;
    reg_rd_waddr      = 5'h0;
    reg_rd_wdata      = 'h0;
    access_wdata      = 'h0;
    access_wmask      = 4'b0000;
    access_addr_misalign = 1'b0;
    csr_wdata         = 'h0;
    wfi_req           = 1'b0;
    mret_req          = 1'b0;
    lp_valid          = 1'b0;
    mul_div_en        = 1'b0;
    branch_taken      = 1'b0;
    branch_target     = inst_addr_plus_4;
    case(opcode)
        `INST_TYPE_I:begin
            reg_rd_wen        = ~is_nop;
            reg_rd_waddr      = rd;
            case(func3)
                `INST_ADDI  : reg_rd_wdata   = alu_op1 + alu_op2;
                `INST_SLTI  : reg_rd_wdata   = less_signed ? 32'h1 : 32'h0;
                `INST_SLTIU : reg_rd_wdata   = less_unsigned ? 32'h1 : 32'h0;
                `INST_XORI  : reg_rd_wdata   = alu_op1 ^ alu_op2;
                `INST_ORI   : reg_rd_wdata   = alu_op1 | alu_op2;
                `INST_ANDI  : reg_rd_wdata   = alu_op1 & alu_op2;
                `INST_SLLI  : reg_rd_wdata   = alu_op1 << alu_op2[4:0];
                `INST_SRI:begin
                    if(func7 == 7'b0100000)//SRAI
                        // reg_rd_wdata = (sr_shift & sr_shift_mask) | ({DATA_WIDTH{alu_op1[DATA_WIDTH-1]}} & (~sr_shift_mask));
                        reg_rd_wdata = $signed(alu_op1) >>> alu_op2[4:0];
                    else//SRLI
                        reg_rd_wdata = alu_op1 >> alu_op2[4:0];
                end
            endcase
        end
        `INST_TYPE_R_M:begin
            reg_rd_waddr      = rd;
            if ((func7 == 7'b0000000) || (func7 == 7'b0100000)) begin
                reg_rd_wen        = 1'b1;
                case(func3)
                    `INST_ADD_SUB:begin
                        if(func7 == 7'b000_0000)//ADD
                            reg_rd_wdata = alu_op1 + alu_op2;
                        else//SUB
                            reg_rd_wdata = alu_op1 - alu_op2;
                    end
                    `INST_SLL: reg_rd_wdata = alu_op1 << alu_op2[4:0];
                    `INST_SLT: reg_rd_wdata = less_signed ? 32'h1 : 32'h0;
                    `INST_SLTU:reg_rd_wdata = less_unsigned ? 32'h1 : 32'h0;
                    `INST_XOR: reg_rd_wdata = alu_op1 ^ alu_op2;
                    `INST_OR: reg_rd_wdata  = alu_op1 | alu_op2;
                    `INST_AND:reg_rd_wdata  = alu_op1 & alu_op2;
                    `INST_SR:begin
                        if(func7 == 7'b0100000)//SRAI
                            // reg_rd_wdata = (sr_shift & sr_shift_mask) | ({DATA_WIDTH{alu_op1[DATA_WIDTH-1]}} & (~sr_shift_mask));
                            reg_rd_wdata = $signed(alu_op1) >>> alu_op2[4:0];
                        else//SRLI
                            reg_rd_wdata = alu_op1 >> alu_op2[4:0];
                    end
                endcase
            end
            else if(func7 == 7'b0000001) begin//RV_M → 结果走 OITF，但 reg_rd_wen/waddr 仍输出
                // reg_rd_wen        = 1'b1;
                mul_div_en = ~id_ex_stall;//在停顿的最后一周期启动
                lp_valid = 1'b1;
            end
        end
        `INST_TYPE_B: begin
            reg_rd_wdata      = 'h0;
            access_wdata      = 'h0;
            case(func3)
                `INST_BEQ: branch_taken     = equal;
                `INST_BNE: branch_taken     = ~equal;
                `INST_BLT: branch_taken     = less_signed;
                `INST_BGE: branch_taken     = ~less_signed;
                `INST_BLTU:branch_taken     = less_unsigned;
                `INST_BGEU:branch_taken     = ~less_unsigned;
                default: branch_taken     = 1'b0;
            endcase
            // branch_target   = branch_taken ? jump_imm : inst_addr_plus_4;
            branch_target   = jump_imm;
        end
        `INST_TYPE_S:begin
            case(func3)
                `INST_SB:begin
                    case (access_addr[1:0])
                        2'b00: begin
                            access_wdata = {24'h0,access_wdata_temp[7:0]};
                            access_wmask = 4'b0001;
                        end
                        2'b01: begin
                            access_wdata = {16'h0,access_wdata_temp[7:0],8'h0};
                            access_wmask = 4'b0010;
                        end
                        2'b10: begin
                            access_wdata = {8'h0,access_wdata_temp[7:0],16'h0};
                            access_wmask = 4'b0100;
                        end
                        2'b11: begin
                            access_wdata = {access_wdata_temp[7:0],24'h0};
                            access_wmask = 4'b1000;
                        end
                        default: begin
                            access_wdata = {24'h0,access_wdata_temp[7:0]};
                            access_wmask = 4'b0001;
                        end
                    endcase
                end
                `INST_SH: begin
                    access_addr_misalign = access_addr[0];
                    case (access_addr[1])
                        1'b0: begin
                            access_wdata = {16'h0,access_wdata_temp[15:0]};
                            access_wmask = 4'b0011;
                        end
                        1'b1: begin
                            access_wdata = {access_wdata_temp[15:0],16'h0};
                            access_wmask = 4'b1100;
                        end
                        default: begin
                            access_wdata = {16'h0,access_wdata_temp[15:0]};
                            access_wmask = 4'b0011;
                        end
                    endcase
                end
                `INST_SW: begin
                    access_addr_misalign = |access_addr[ALIGN_WIDTH-1:0];
                    access_wdata = access_wdata_temp;
                    access_wmask = 4'b1111;
                end
            endcase
        end
        `INST_TYPE_L: begin
            // reg_rd_wen        = 1'b1;
            reg_rd_waddr      = rd;
            case(func3)
                `INST_LH, `INST_LHU: 
                    access_addr_misalign = access_addr[0];
                `INST_LW: 
                    access_addr_misalign = |access_addr[ALIGN_WIDTH-1:0];
            endcase
        end
        `INST_SYSTEM: begin
            reg_rd_wen        = 1'b1;
            reg_rd_waddr      = rd;
            reg_rd_wdata = csr_rdata;
            case (func3)
                `INST_CSRRW: csr_wdata = alu_op1;
                `INST_CSRRS: csr_wdata = csr_rdata | alu_op1;
                `INST_CSRRC: csr_wdata = csr_rdata & (~alu_op1);
                `INST_CSRRWI:csr_wdata = {27'h0,zimm};
                `INST_CSRRSI:csr_wdata = csr_rdata | {27'h0,zimm};
                `INST_CSRRCI:csr_wdata = csr_rdata & {~{27'h0,zimm}};
                `INST_PRIV: begin
                    reg_rd_wen    = 1'b0;   // MRET/WFI 不写寄存器
                    reg_rd_waddr  = 5'h0;
                    case(func12)
                        // `INST_EBREAK: ebreak_req = 1'b1;
                        // `INST_ECALL :  ecall_req = 1'b1;
                        `INST_MRET: mret_req = 1'b1;
                        `INST_WFI:  wfi_req =  1'b1;
                    endcase
                end
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
            reg_rd_wen        = 1'b1;
            reg_rd_waddr      = rd;
            reg_rd_wdata      = inst_addr_plus_4;
            branch_taken      = 1'b1;
            branch_target     = jump_imm;
        end
        `INST_JALR:begin
            reg_rd_wen        = 1'b1;
            reg_rd_waddr      = rd;
            reg_rd_wdata      = inst_addr_plus_4;
            branch_taken      = 1'b1;
            branch_target     = alu_op1 + imm;
        end
        `INST_LUI:begin
            reg_rd_wen        = 1'b1;
            reg_rd_waddr      = rd;
            reg_rd_wdata      = alu_op2;
        end
        `INST_AUIPC:begin
            reg_rd_wen        = 1'b1;
            reg_rd_waddr      = rd;
            reg_rd_wdata      = alu_op1 + alu_op2;
        end
        `INST_FENCE:begin
            if(func3) begin//FENCE.I 冲刷
                ;
            end else begin //FENCE 等同于NOP
                ;
            end
        end
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
    .start      	(mul_div_en     ),
    .reg_rs1_raddr 	(reg_rs1_raddr  ),
    .reg_rs2_raddr 	(reg_rs2_raddr  ),
    .reg_rd_waddr   (rd             ),
    .func3_i     	(func3          ),
    .a_i         	(alu_op1        ),
    .b_i         	(alu_op2        ),
    .mul_result_o   (mul_result_wbck),
    .div_result_o   (div_result_wbck),
    .mul_ready_o    (mul_ready      ),
    .div_ready_o    (div_ready      ),
    .mul_valid_o    (mul_valid_wbck ),
    .div_valid_o    (div_valid_wbck)

);

endmodule
