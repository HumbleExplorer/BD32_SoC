`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
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
    input   logic   [DATA_WIDTH-1:0]        reg_rs2_rdata_i,
    // 停顿期间前递回写（Solution A）：当指令因 OITF RAW 停顿停留在 EX 时，
    // 被依赖的长周期指令陆续退休，其 1 拍前递脉冲需锁存进操作数寄存器，
    // 否则先退休指令（如 divu）的前递值会在后退休指令（如 remu）退休前丢失。
    input   logic   [DATA_WIDTH-1:0]        alu_op1_fwd_i,
    input   logic                           fwd_a_hit_i,
    input   logic   [DATA_WIDTH-1:0]        alu_op2_fwd_i,
    input   logic                           fwd_b_hit_i,
    input   logic   [ADDR_WIDTH-1:0]        jump_imm_i,
    input   logic   [ADDR_WIDTH-1:0]        inst_addr_plus_len_i,   // PC+指令长度（压缩+2/普通+4）
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rs1_raddr_i,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rs2_raddr_i,
    input   logic                           access_en_i,
    input   logic                           access_wr_i,
    input   logic                           csr_en_i,
    input   logic   [CSR_ADDR_WIDTH-1:0]    csr_addr_i,
    input   logic                           is_nop_i,
    input   logic                           is_fence_i_i,
    input   logic   [1:0]                   branch_inst_type_i,// 指令类型 (00:非跳转指令, 01:B, 10:JAL, 11:JALR)
    input   logic                           branch_req_i,
    input   logic                           push_ras_i,        // call
    input   logic                           pop_ras_i,          // ret

    //to execute
    output  logic   [ADDR_WIDTH-1:0]        inst_addr_o,
    output  logic   [DATA_WIDTH-1:0]        inst_o,
    output  logic                           predict_taken_o,
    output  logic   [ADDR_WIDTH-1:0]        predict_target_o,
    output  logic   [DATA_WIDTH-1:0]        alu_op1_o,
    output  logic   [DATA_WIDTH-1:0]        alu_op2_o,
    output  logic   [DATA_WIDTH-1:0]        imm_o,
    output  logic   [DATA_WIDTH-1:0]        reg_rs2_rdata_o,
    output  logic   [ADDR_WIDTH-1:0]        jump_imm_o,
    output  logic   [ADDR_WIDTH-1:0]        inst_addr_plus_len_o,
    output  logic                           access_en_o,
    output  logic                           access_wr_o,
    output  logic                           csr_en_o,
    output  logic   [CSR_ADDR_WIDTH-1:0]    csr_addr_o,
    output  logic                           is_nop_o,
    output  logic                           is_fence_i_o,
    output  logic   [1:0]                   branch_inst_type_o,// 指令类型 (00:非跳转指令, 01:B, 10:JAL, 11:JALR)
    output  logic                           branch_req_o,
    output  logic                           push_ras_o,        // call
    output  logic                           pop_ras_o,          // ret
    //to Data_Hazard
    output  logic   [REG_ADDR_WIDTH-1:0]    reg_rs1_raddr_o,
    output  logic   [REG_ADDR_WIDTH-1:0]    reg_rs2_raddr_o,
`ifdef DISPLAY_INST_WAVE
    output  logic   [ADDR_WIDTH-1:0]        inst_addr_display_o,
`endif
    input   logic   [2:0]                   inst_type_i,
    output  logic   [2:0]                   inst_type_o,
    input   logic                           zcmp_micro_last_i,
    output  logic                           zcmp_micro_last_o,
    input   logic                           zcmp_micro_any_i,
    output  logic                           zcmp_micro_any_o,
    input   logic                           zcb_tag_i,
    output  logic                           zcb_tag_o,
    input   logic                           valid_i,
    output  logic                           valid_o
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
        reg_rs2_rdata_o <= #1 'h0;
        jump_imm_o      <= #1 'h0;
    inst_addr_plus_len_o <= #1 'h0;
        access_en_o     <= #1 1'b0;
        access_wr_o     <= #1 1'b0;
        csr_en_o        <= #1 1'b0;
        csr_addr_o      <= #1 'h0;
        is_nop_o        <= #1 1'b1;
        is_fence_i_o    <= #1 1'b0;
        branch_inst_type_o<= #1 'h0;
        branch_req_o    <= #1 1'b0;
        push_ras_o      <= #1 1'b0;
        pop_ras_o       <= #1 1'b0;
        reg_rs1_raddr_o <= #1 'h0;
        reg_rs2_raddr_o <= #1 'h0;
    inst_type_o     <= #1 3'd0;
    zcmp_micro_last_o <= #1 1'b0;
    zcmp_micro_any_o  <= #1 1'b0;
    zcb_tag_o         <= #1 1'b0;
    end else if(flush) begin
        inst_o          <= #1 `INST_NOP;
        predict_taken_o <= #1 1'b0;
        predict_target_o<= #1 'h0;
        access_en_o     <= #1 1'b0;
        csr_en_o        <= #1 1'b0;
        is_nop_o        <= #1 1'b1;
        is_fence_i_o    <= #1 1'b0;
        branch_inst_type_o<= #1 'h0;
        branch_req_o    <= #1 1'b0;
        push_ras_o      <= #1 1'b0;
        pop_ras_o       <= #1 1'b0;
    inst_type_o     <= #1 3'd0;
    zcmp_micro_last_o <= #1 1'b0;
    zcmp_micro_any_o  <= #1 1'b0;
    zcb_tag_o         <= #1 1'b0;
    end else if (!stall) begin
        inst_addr_o     <= #1 inst_addr_i;
        inst_o          <= #1 inst_i;
        predict_taken_o <= #1 predict_taken_i;
        predict_target_o<= #1 predict_target_i;
        alu_op1_o       <= #1 alu_op1_i;
        alu_op2_o       <= #1 alu_op2_i;
        imm_o           <= #1 imm_i;
        reg_rs2_rdata_o <= #1 reg_rs2_rdata_i;
        jump_imm_o      <= #1 jump_imm_i;
    inst_addr_plus_len_o <= #1 inst_addr_plus_len_i;
        access_en_o     <= #1 access_en_i;
        access_wr_o     <= #1 access_wr_i;
        csr_en_o        <= #1 csr_en_i;
        csr_addr_o      <= #1 csr_addr_i;
        is_nop_o        <= #1 is_nop_i;
        is_fence_i_o    <= #1 is_fence_i_i;
        branch_inst_type_o<= #1 branch_inst_type_i;
        branch_req_o    <= #1 branch_req_i;
        push_ras_o      <= #1 push_ras_i;
        pop_ras_o       <= #1 pop_ras_i;
        reg_rs1_raddr_o <= #1 reg_rs1_raddr_i;
        reg_rs2_raddr_o <= #1 reg_rs2_raddr_i;
    inst_type_o     <= #1 inst_type_i;
    zcmp_micro_last_o <= #1 zcmp_micro_last_i;
    zcmp_micro_any_o  <= #1 zcmp_micro_any_i;
    zcb_tag_o         <= #1 zcb_tag_i;
    end else begin
        // stall 期间：控制字段保持不变，但若前递命中，则锁存前递值到操作数
        // 寄存器。用于捕获 OITF 退休的 1 拍前递脉冲（先退休的长指令结果不会
        // 因后续仍停顿而丢失）。
        if (fwd_a_hit_i) alu_op1_o       <= #1 alu_op1_fwd_i;
        if (fwd_b_hit_i) begin
            alu_op2_o       <= #1 alu_op2_fwd_i;
            reg_rs2_rdata_o <= #1 alu_op2_fwd_i;
        end
    end
end
`ifdef DISPLAY_INST_WAVE
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_display_o <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
    end else if(flush) begin
        inst_addr_display_o <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
    end else if (!stall) begin
        inst_addr_display_o <= #1 inst_addr_i;
    end
end
`endif
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)           valid_o <= #1 1'b0;
    else if(flush)       valid_o <= #1 1'b0;
    else                 valid_o <= #1 ~stall & valid_i;
end

`ifndef SYNTHESIS
// ===== SVA：流水线寄存器控制一致性 =====
// flush 次拍指令有效位必须清零（边界指令死亡语义）
a_flush_clear: assert property (
    @(posedge clk) disable iff (!rst_n)
    (flush) |=> (!valid_o));
// stall（非 flush）时指令内容保持——字段由 !stall 门保持，不许漂移
a_stall_hold: assert property (
    @(posedge clk) disable iff (!rst_n)
    (stall && !flush) |=> ($stable(inst_o) && $stable(inst_addr_o)));
`endif

`ifdef ASSERT_MODULE
// ===== SVA L2：ID_EX 深化——stall 保持覆盖全部控制字段（L1 仅查 inst/addr）=====
always @(posedge clk) begin
    // stall 已持续一拍（次拍起）内容必须冻结——注意不能用"当拍 stall 比当前/上一拍"：
    // 进入 stall 的第一拍，寄存器装载的是 stall 前最后一拍的新指令，合法变化
    if (rst_n && $past(rst_n) && $past(stall && !flush && valid_o)
        && stall && !flush && valid_o) begin
        a_l2_idex_ctrl_hold: assert property (
            reg_rs1_raddr_o == $past(reg_rs1_raddr_o) &&
            reg_rs2_raddr_o == $past(reg_rs2_raddr_o) &&
            reg_rs2_rdata_o == $past(reg_rs2_rdata_o) &&
            inst_type_o     == $past(inst_type_o) &&
            branch_req_o    == $past(branch_req_o) &&
            branch_inst_type_o == $past(branch_inst_type_o) &&
            access_en_o     == $past(access_en_o) &&
            access_wr_o     == $past(access_wr_o) &&
            csr_en_o        == $past(csr_en_o) &&
            csr_addr_o      == $past(csr_addr_o) &&
            jump_imm_o      == $past(jump_imm_o) &&
            predict_taken_o == $past(predict_taken_o) &&
            predict_target_o == $past(predict_target_o) &&
            push_ras_o      == $past(push_ras_o) &&
            pop_ras_o       == $past(pop_ras_o));
    end
end
`endif

endmodule
