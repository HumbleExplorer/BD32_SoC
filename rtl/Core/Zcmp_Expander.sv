`include "./../SoC_Config.sv"
`ifndef FORMAL
timeunit 1ns;
timeprecision 1ps;
`endif
// =============================================================================
// Zcmp_Expander — Zcmp 压缩堆栈指令 -> 微操作流（时钟 FSM，Ibex 路线）
// -----------------------------------------------------------------------------
// cm.push/cm.pop/cm.popret/cm.popretz 展开为 1:N 条标准 lw/sw/addi/jalr 微操作，
// cm.mvsa01/cm.mva01s 展开为 2 条 addi。微操作逐拍输出，靠 stall 反压；
// 整条指令的 busy 保持到最后一个微操作在 WB 退休（last_retired_i），
// 期间流水线冻结/中断屏蔽由上层（IFU_Buffer/Pipeline_Ctrl/CSR）负责。
// abort_i（flush/redirect）时回到 CmIdle：若 pc_asm 未被重定向改走，IFU 会
// 重新装配同一条 cm.push 实现幂等重放；若被改走（分支重定向/陷阱），则放弃。
//
// 编码与展开依据（GCC 15.2 / unpriv spec 28.13 / Ibex 对照一致）：
//   C2 象限 [15:13]=101；[12:8]=11000 push / 11010 pop / 11100 popretz / 11110 popret
//   rlist=[7:4]（4..15），spimm=[3:2]；mv 指令 [12:8]=011??，[6:5]=01 mvsa01/11 mva01s，
//   rs1'=[9:7]，rs2'=[4:2]（sreg 编码 s0-s7 -> x8/x9/x18-23）。
//   栈调整 = base(rlist) + spimm*16；base：rlist 4-7->16，8-11->32，12-14->48，15->64。
//   寄存器列表：rlist 4={ra}，5={ra,s0}，...，15={ra,s0-s11}（13 个）。
//   push 依次 sw 高->低寄存器到 sp-4/sp-8/...；pop 依次 lw 自 sp+(adj-4) 递减；
//   SP 调整最后；popretz 尾部 = addi sp + li a0,0 + ret，popret 尾部 = addi sp + ret。
// =============================================================================
import bd32_pkg::*;

module Zcmp_Expander (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] zcmp_inst_i,   // 有效 Zcmp 16 位指令（capture 拍）
    input  logic        capture_i,     // 启动展开（can_issue & zcmp_en，本拍输出第一个微操作）
    input  logic        stall_i,       // 流水线停顿：微操作不被接受（FSM 不前进）
    input  logic        abort_i,       // flush/redirect：回 CmIdle
    input  logic        last_retired_i,// 最后一个微操作已在 WB 退休（清 busy）
    output logic [31:0] micro_inst_o,  // 本拍展开的微操作
    output logic        micro_valid_o, // 本拍有有效微操作输出
    output logic        micro_last_o,  // 本拍输出的是最后一个微操作
    output logic        micro_ret_o,   // 本拍输出的是 ret(jalr x0,x1) 微操作（供 IF 恢复预测）
    output logic        busy_o,        // 展开进行中（capture 起到 last 退休止）
    output logic        retire_ok_o    // 本拍退休的是"当前展开自身的最后微操作"
);

  // ---------------- 状态 ----------------
  typedef enum logic [2:0] {
    S_IDLE,
    S_PUSH_STORE, S_PUSH_ADDI,
    S_POP_LOAD,   S_POP_ADDI, S_POP_ZERO, S_POP_RET,
    S_MV_SECOND
  } state_e;

  // 指令类型（[12:8] + [6:5]）
  localparam logic [2:0] T_PUSH = 3'd0, T_POP = 3'd1, T_POPRETZ = 3'd2,
                         T_POPRET = 3'd3, T_MVSA01 = 3'd4, T_MVA01S = 3'd5;

  state_e          state_q, state_d;
  logic [4:0]      rlist_q,  rlist_d;    // 内部 rlist（15 -> 16）
  logic [4:0]      offset_q, offset_d;   // push 存储序号 / pop 载入偏移（字）
  logic [2:0]      type_q,   type_d;
  logic [2:0]      rs1_q, rs1_d, rs2_q, rs2_d;   // mv 指令的 sreg 编码
  logic [3:0]      inst_rlist_q, inst_rlist_d;   // 原始 rlist（addi sp 用）
  logic [1:0]      spimm_q, spimm_d;
  logic            busy_q;
  logic [6:0]      stack_adj_w;   // Vivado 不允许 func(...)[6:2] 直接位选择，先存临时量
  // 尾部门控：busy/consume 只能由"当前展开自身的最后微操作退休"清除。
  // 背靠背 Zcmp（如 rt_tick_increase 尾部 cm.pop {ra},16 紧接 cm.push）时，
  // 上一条指令最后一个微操作的 zcmp_micro_last 标签可能晚 2~3 拍到 WB，
  // 与下一条 cm.push 的 capture 重叠；若不门控，残留的 last_retired 会把
  // 新展开的 busy 提前清掉 → 新 push 只发出 1~2 个微操作就被截断
  // （addi sp,-64 丢失，函数体在错误 sp 上运行，popret 恢复错位）。
  logic            tail_armed_q;

  // ---------------- 组合函数 ----------------
  // 注意：Yosys 不支持函数内 return 语句，一律用「函数名赋值」风格（三端通用）
  function automatic logic [6:0] zcmp_stack_adj_base(input logic [3:0] rlist);
    unique case (rlist)
      4'd4, 4'd5, 4'd6, 4'd7:   zcmp_stack_adj_base = 7'd16;
      4'd8, 4'd9, 4'd10, 4'd11: zcmp_stack_adj_base = 7'd32;
      4'd12, 4'd13, 4'd14:      zcmp_stack_adj_base = 7'd48;
      4'd15:                    zcmp_stack_adj_base = 7'd64;
      default:                  zcmp_stack_adj_base = 7'd0;
    endcase
  endfunction

  function automatic logic [6:0] zcmp_stack_adj(input logic [3:0] rlist,
                                                input logic [1:0] spimm);
    zcmp_stack_adj = zcmp_stack_adj_base(rlist) + (spimm * 16);
  endfunction

  // rlist -> 当前要存取的最高寄存器（内部 rlist 4..16，16 表示 rlist=15 的 s11）
  function automatic logic [4:0] zcmp_top_reg(input logic [4:0] rlist);
    unique case (rlist)
      5'd16, 5'd15, 5'd14, 5'd13, 5'd12, 5'd11, 5'd10, 5'd9, 5'd8, 5'd7:
        zcmp_top_reg = 5'd11 + rlist;
      5'd6, 5'd5: zcmp_top_reg = 5'd3 + rlist;
      5'd4:       zcmp_top_reg = 5'd1;   // ra
      default:    zcmp_top_reg = 5'd0;
    endcase
  endfunction

  // sreg 编码（mvsa01/mva01s）：000=s0(x8),001=s1(x9),010=s2(x18)...111=s7(x23)
  function automatic logic [4:0] zcmp_sreg(input logic [2:0] s);
    unique case (s)
      3'd0: zcmp_sreg = 5'd8;
      3'd1: zcmp_sreg = 5'd9;
      default: zcmp_sreg = {2'b10, s};
    endcase
  endfunction

  // cm.push 第 offset 拍：sw reg, -4*offset(sp)
  function automatic logic [31:0] zcmp_push_store(input logic [4:0] rlist,
                                                  input logic [4:0] offset);
    logic [11:0] neg_off;
    neg_off = -{5'd0, offset, 2'b00};
    zcmp_push_store = {neg_off[11:5], zcmp_top_reg(rlist), 5'd2, 3'b010, neg_off[4:0], 7'b0100011};
  endfunction

  // cm.pop 第 offset 拍：lw reg, 4*offset(sp)
  function automatic logic [31:0] zcmp_pop_load(input logic [4:0] rlist,
                                                input logic [4:0] offset);
    zcmp_pop_load = {5'b0, offset, 2'b00, 5'd2, 3'b010, zcmp_top_reg(rlist), 7'b0000011};
  endfunction

  // addi sp, sp, ±adj
  function automatic logic [31:0] zcmp_sp_addi(input logic [3:0] rlist,
                                               input logic [1:0] spimm,
                                               input logic       decr);
    logic [11:0] adj, imm;
    adj  = zcmp_stack_adj(rlist, spimm);
    imm  = decr ? -adj : adj;
    zcmp_sp_addi = {imm, 5'd2, 3'b000, 5'd2, 7'b0010011};
  endfunction

  // addi rd, rs, 0
  function automatic logic [31:0] zcmp_addi(input logic [4:0] rd, input logic [4:0] rs);
    zcmp_addi = {12'b0, rs, 3'b000, rd, 7'b0010011};
  endfunction

  // jalr x0, x1, 0（ret）
  function automatic logic [31:0] zcmp_ret();
    zcmp_ret = {12'b0, 5'd1, 3'b000, 5'd0, 7'b1100111};
  endfunction

  // [12:8]+[6:5] -> 指令类型
  function automatic logic [2:0] zcmp_type(input logic [15:0] inst);
    unique case (inst[12:8])
      5'b11000: zcmp_type = T_PUSH;
      5'b11010: zcmp_type = T_POP;
      5'b11100: zcmp_type = T_POPRETZ;
      5'b11110: zcmp_type = T_POPRET;
      default:  zcmp_type = (inst[6:5] == 2'b01) ? T_MVSA01 : T_MVA01S;
    endcase
  endfunction

  // rlist 初始化：指令 rlist 15 -> 内部 16（{ra,s0-s11} 先存 s11）
  function automatic logic [4:0] zcmp_rlist_init(input logic [3:0] rlist);
    zcmp_rlist_init = (rlist == 4'd15) ? 5'd16 : {1'b0, rlist};
  endfunction

  logic accept;   // 本拍微操作被流水线接受（不停顿）
  assign accept = micro_valid_o & ~stall_i;

  // ---------------- 组合输出与状态转移 ----------------
  always_comb begin
    micro_inst_o  = INST_NOP;
    micro_valid_o = 1'b0;
    micro_last_o  = 1'b0;
    state_d  = state_q;
    rlist_d  = rlist_q;
    offset_d = offset_q;
    type_d   = type_q;
    rs1_d    = rs1_q;
    rs2_d    = rs2_q;
    inst_rlist_d = inst_rlist_q;
    spimm_d  = spimm_q;
    stack_adj_w = '0;   // 默认值：仅在 pop 家族分支赋值（路径不全会被 Yosys 判锁存）

    if (abort_i) begin
      state_d = S_IDLE;
    end else begin
      unique case (state_q)
        S_IDLE: begin
          if (capture_i) begin
            type_d = zcmp_type(zcmp_inst_i);
            case (type_d)
              T_PUSH: begin
                rlist_d  = zcmp_rlist_init(zcmp_inst_i[7:4]);
                inst_rlist_d = zcmp_inst_i[7:4];
                spimm_d  = zcmp_inst_i[3:2];
                offset_d = 5'd1;
                micro_inst_o  = zcmp_push_store(rlist_d, 5'd1);
                micro_valid_o = 1'b1;
                if (rlist_d == 5'd4) begin
                  state_d = S_PUSH_ADDI;
                end else begin
                  rlist_d  = rlist_d - 5'd1;
                  offset_d = 5'd2;
                  state_d  = S_PUSH_STORE;
                end
              end
              T_POP, T_POPRETZ, T_POPRET: begin
                rlist_d  = zcmp_rlist_init(zcmp_inst_i[7:4]);
                inst_rlist_d = zcmp_inst_i[7:4];
                spimm_d  = zcmp_inst_i[3:2];
                stack_adj_w = zcmp_stack_adj(zcmp_inst_i[7:4], zcmp_inst_i[3:2]);
                offset_d = stack_adj_w[6:2] - 5'd1;
                micro_inst_o  = zcmp_pop_load(rlist_d, offset_d);
                micro_valid_o = 1'b1;
                if (rlist_d == 5'd4) begin
                  state_d = S_POP_ADDI;
                end else begin
                  rlist_d  = rlist_d - 5'd1;
                  offset_d = offset_d - 5'd1;
                  state_d  = S_POP_LOAD;
                end
              end
              default: begin  // T_MVSA01 / T_MVA01S
                rs1_d = zcmp_inst_i[9:7];
                rs2_d = zcmp_inst_i[4:2];
                if (type_d == T_MVSA01)
                  micro_inst_o = zcmp_addi(zcmp_sreg(rs1_d), 5'd10);  // addi s1', a0, 0
                else
                  micro_inst_o = zcmp_addi(5'd10, zcmp_sreg(rs1_d));  // addi a0, s1', 0
                micro_valid_o = 1'b1;
                state_d = S_MV_SECOND;
              end
            endcase
          end
        end

        S_PUSH_STORE: begin
          micro_inst_o  = zcmp_push_store(rlist_q, offset_q);
          micro_valid_o = 1'b1;
          if (accept) begin
            rlist_d = rlist_q - 5'd1;
            offset_d = offset_q + 5'd1;
            if (rlist_q == 5'd4) state_d = S_PUSH_ADDI;
          end
        end

        S_PUSH_ADDI: begin
          micro_inst_o  = zcmp_sp_addi(inst_rlist_q, spimm_q, 1'b1);
          micro_valid_o = 1'b1;
          micro_last_o  = 1'b1;
          if (accept) state_d = S_IDLE;
        end

        S_POP_LOAD: begin
          micro_inst_o  = zcmp_pop_load(rlist_q, offset_q);
          micro_valid_o = 1'b1;
          if (accept) begin
            rlist_d = rlist_q - 5'd1;
            offset_d = offset_q - 5'd1;
            if (rlist_q == 5'd4) state_d = S_POP_ADDI;
          end
        end

        S_POP_ADDI: begin
          micro_inst_o  = zcmp_sp_addi(inst_rlist_q, spimm_q, 1'b0);
          micro_valid_o = 1'b1;
          if (accept) begin
            if (type_q == T_POP) begin
              micro_last_o = 1'b1;
              state_d = S_IDLE;
            end else if (type_q == T_POPRETZ) begin
              state_d = S_POP_ZERO;
            end else begin
              state_d = S_POP_RET;
            end
          end
        end

        S_POP_ZERO: begin
          micro_inst_o  = zcmp_addi(5'd10, 5'd0);   // addi a0, x0, 0
          micro_valid_o = 1'b1;
          if (accept) state_d = S_POP_RET;
        end

        S_POP_RET: begin
          micro_inst_o  = zcmp_ret();
          micro_valid_o = 1'b1;
          micro_last_o  = 1'b1;
          if (accept) state_d = S_IDLE;
        end

        S_MV_SECOND: begin
          if (type_q == T_MVSA01)
            micro_inst_o = zcmp_addi(zcmp_sreg(rs2_q), 5'd11);  // addi s2', a1, 0
          else
            micro_inst_o = zcmp_addi(5'd11, zcmp_sreg(rs2_q));  // addi a1, s2', 0
          micro_valid_o = 1'b1;
          micro_last_o  = 1'b1;
          if (accept) state_d = S_IDLE;
        end

        default: state_d = S_IDLE;
      endcase
    end
  end

  // ---------------- 时序 ----------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q  <= S_IDLE;
      rlist_q  <= '0;
      offset_q <= '0;
      type_q   <= T_PUSH;
      rs1_q    <= '0;
      rs2_q    <= '0;
      inst_rlist_q <= '0;
      spimm_q  <= '0;
      busy_q   <= 1'b0;
      tail_armed_q <= 1'b0;
    end else begin
      state_q  <= state_d;
      rlist_q  <= rlist_d;
      offset_q <= offset_d;
      type_q   <= type_d;
      rs1_q    <= rs1_d;
      rs2_q    <= rs2_d;
      inst_rlist_q <= inst_rlist_d;
      spimm_q  <= spimm_d;
      if (abort_i) begin
        busy_q       <= 1'b0;
        tail_armed_q <= 1'b0;
      end else if (capture_i) begin
        busy_q       <= 1'b1;
        tail_armed_q <= 1'b0;
      end else if (last_retired_i && tail_armed_q) begin
        busy_q <= 1'b0;
      end
      if (micro_last_o && accept)
        tail_armed_q <= 1'b1;   // 本拍最后微操作已被流水线接受，等待其 WB 退休
    end
  end

    assign busy_o = busy_q;
    assign retire_ok_o = last_retired_i && tail_armed_q;
    // ret 微操作唯一发自 S_POP_RET 态（cm.popret/popretz 尾部 jalr x0,x1）
    assign micro_ret_o = micro_valid_o & (state_q == S_POP_RET);

`ifndef SYNTHESIS
// ===========================================================================
// SVA: Zcmp busy 语义守护（背靠背展开竞态场景）
// busy 期间若无 abort 且尾部退休条件未满足，busy 必须保持——
// 防止上一条残留标签提前清 busy 截断新展开（tail_armed 门控语义）
// Yosys SVA 子集写法：时钟取自外层 always、|=> 改 $past 判断（ModelSim 同样接受）
// ===========================================================================
always @(posedge clk) begin
    if (rst_n && $past(busy_q && !abort_i && !retire_ok_o)) begin
        a_zcmp_busy_hold: assert property (busy_q);
    end
end

// ===========================================================================
// SVA: L2 原子性不变式（+define+ASSERT_MODULE 使能，仅在 ModelSim 仿真中启用）
// 依据微码展开表：一条指令的微操作总数固定（push=寄存器数+1、pop/popretz/
// popret=寄存器数+2、mv=2），"微操作计数与编码一致"即下面这些不变式：
`ifdef ASSERT_MODULE
// ① 微操作仅在展开进行中有效；IDLE 态无输出
always @(posedge clk) begin
    if (rst_n) begin
        a_zcmp_idle_no_micro_valid: assert property
            ((state_q == S_IDLE && !capture_i && !abort_i) ? !micro_valid_o : 1'b1);
    end
end
// ② last 标记唯一：只有各家族末态拍可置位（编码与状态机一致）
always @(posedge clk) begin
    if (rst_n) begin
        a_zcmp_last_state: assert property
            (micro_last_o ? ((state_q == S_PUSH_ADDI) || (state_q == S_POP_ADDI)
                              || (state_q == S_POP_RET) || (state_q == S_MV_SECOND)) : 1'b1);
    end
end
// ③ accept 门控：busy 期间 abort/capture/retire 互斥（capture 只在 IDLE）
always @(posedge clk) begin
    if (rst_n) begin
        a_zcmp_cap_idle: assert property (capture_i ? (state_q == S_IDLE) : 1'b1);
        a_zcmp_mutual:   assert property (!(abort_i && capture_i));
        a_zcmp_mutual2:  assert property (!(abort_i && last_retired_i));
    end
end
// ④ tail_armed 仅在 last 微操作被接受后 1 拍置位，retire 消费
always @(posedge clk) begin
    if (rst_n && $past(micro_last_o && accept)) begin
        a_zcmp_tail_armed: assert property (tail_armed_q);
    end
    if (rst_n && $past(retire_ok_o)) begin
        a_zcmp_busy_release: assert property (!busy_q);
    end
end
`endif
`endif

endmodule
