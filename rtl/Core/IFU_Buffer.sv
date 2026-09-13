`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
// =============================================================================
// IFU_Buffer — 取指缓冲 + 16/32 位指令装配 + RVC 展开（替代 PC_counter）
// -----------------------------------------------------------------------------
// 方案（单字 32 位寄存器）：
//   - 取指按"字流"顺序进行（fetch_addr 每周期 +4，请求字对齐地址），
//   - 装配器按 pc_asm[1] 与指令长度编码从 {cur_w, w_new} 中切 16/32 位指令，
//     跨字 32 位指令 = {cur_w[31:16], w_new[15:0]}（w_new 为下一字，稳态下零停顿），
//   - 16 位指令经 RVC_Expander 展开为 32 位等价指令后输出（Decoder 零改动）。
// 取指与装配解耦：pc_asm（架构 PC，16 位对齐）按指令长度推进；
// fetch_addr 始终领先一字。分支/跳转/调试装载重定向时清空窗口重新取。
// 与 LSU/SBA 抢占：fetch_served 指示本拍请求是否被存储器服务（未被抢占）；
// 被抢占时 fetch_addr 保持重发，装配器忽略该拍返回字，保证字流不错位。
// =============================================================================
module IFU_Buffer #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    input  logic                       clk,
    input  logic                       rst_n,
    // ---- 控制（接口同 PC_counter）----
    input  logic                       jump_en,
    input  logic   [ADDR_WIDTH-1:0]    jump_addr,
    input  logic                       predict_taken,
    input  logic   [ADDR_WIDTH-1:0]    predict_target,
    input  logic                       stall,
    input  logic                       dbg_load_en,    // resume 时加载 dpc
    input  logic   [ADDR_WIDTH-1:0]    dbg_load_addr,  // dpc 值
    // ---- 取指数据 ----
    input  logic   [DATA_WIDTH-1:0]    w_new,          // 同步读返回字（已按区域选择）
    input  logic                       fetch_served,   // 本拍请求地址确实被存储器读取
    // ---- Zcmp 展开控制 ----
    input  logic                       zcmp_flush_any_i, // IF/ID/EX/MEM 级 flush（abort 展开）
    input  logic                       zcmp_last_retired_i, // 最后一个微操作已在 WB 退休
    // ---- 输出 ----
    (* MAX_FANOUT = 16 *)output logic  [ADDR_WIDTH-1:0]    pc,          // 取指请求字地址（给 ROM/RAM）
    (* MAX_FANOUT = 16 *)output logic  [ADDR_WIDTH-1:0]    inst_addr_o, // 当前指令地址（16 位对齐，给流水线）
    output  logic   [ADDR_WIDTH-1:0]    fetch_word_addr_o, // req_addr：w_new 所属的请求字地址（取指数据区选用，寄存器）
    output  logic   [DATA_WIDTH-1:0]    inst_o,        // 展开后的指令（未出指令时 NOP）
    output  logic                       inst_valid_o,  // 本拍是否输出了有效指令（供 IF_ID stall）
    output  logic                       fetch_wait_o,  // 取指字未就绪（非 stall/redirect 的等待拍）
    output  logic                       is_compressed_o,// 当前指令是否压缩（供 pc+2 链接）
    output  logic                       illegal_inst_o, // 保留压缩编码
    output  logic                       zcmp_micro_last_o, // 微操作 last 标志（跟 inst 同步）
    output  logic                       zcmp_micro_any_o,  // 本拍输出是否为 Zcmp 微操作
    output  logic                       zcb_tag_o,         // 本拍指令是否为 Zcb（HPM 计数）
    output  logic                       zcmp_busy_o,       // Zcmp 展开进行中（中断/调试屏蔽用）
    output  logic                       predict_taken_o,   // 门控后的预测（Zcmp 微操作不预测）
    output  logic                       if_addr_misalign, // C 下恒 0
    output  logic                       if_access_fault
);

  // ---------------- 状态 ----------------
  logic [ADDR_WIDTH-1:0] pc_asm;      // 待装配指令地址（16 位对齐，bit0 恒 0）
  logic [DATA_WIDTH-1:0] cur_w;       // 包含 pc_asm 的字
  logic [ADDR_WIDTH-1:0] cur_w_addr;  // cur_w 的字地址
  logic                  have_cur;    // cur_w 是否为包含 pc_asm 的字
  logic [ADDR_WIDTH-1:0] fetch_addr;  // 取指请求字地址（当前/下一拍）
  logic [ADDR_WIDTH-1:0] req_addr;    // 上一拍请求的字地址（= 本拍 w_new 的地址）
  logic                  served_d;    // 上一拍请求是否被服务（= 本拍 w_new 是否属于取指）
  logic                  reset_d;

  // ---------------- 重定向 ----------------
  // EX 实际跳转 / 调试装载会丢弃当前未装配指令（redirect）；
  // IF 预测（predict_taken）保留当前指令：JAL/JALR 仍需流经流水线
  // 完成链接寄存器写回与 RAS 更新，仅把下一拍取指目标改为预测目标。
  logic redirect;
  logic predict_redirect;
  logic [ADDR_WIDTH-1:0] redirect_target;
  assign redirect = jump_en | dbg_load_en;
  assign redirect_target = jump_en ? jump_addr : dbg_load_addr;

  // ---------------- 组合装配 ----------------
  logic [15:0] head;
  logic        is32, unaligned32, cur_eff_valid, refill_now, next_ready, can_issue;
  logic [2:0]  inst_len;                       // 2 / 4 字节
  logic        crossing;
  logic [DATA_WIDTH-1:0] cur_eff;              // 有效当前字（have_cur ? cur_w : w_new）
  logic [DATA_WIDTH-1:0] inst_raw;             // 原始 16/32 位指令
  logic [DATA_WIDTH-1:0] inst_exp;             // 展开结果
  logic        exp_illegal, exp_zcmp, exp_zcb;
  logic [31:0] zcmp_micro_inst;
  logic        zcmp_micro_valid, zcmp_micro_last, zcmp_busy;
  logic        zcmp_retire_ok;   // 当前展开自身的最后微操作退休（门控后）
  logic        zcmp_capture, zcmp_active, zcmp_abort;
  // 展开期间 w_new/fetch_served 会被 ITCM 访存覆盖，capture 拍把"消费 cm.push
  // 之后"的窗口状态锁存，consume 拍直接恢复（不能现场重推导）。
  logic [ADDR_WIDTH-1:0] zcmp_restore_pc;
  logic [ADDR_WIDTH-1:0] zcmp_restore_cur_w_addr;
  logic [DATA_WIDTH-1:0] zcmp_restore_cur_w;
  logic [ADDR_WIDTH-1:0] zcmp_restore_fetch_addr;
  logic [ADDR_WIDTH-1:0] zcmp_restore_req_addr;
  logic                  zcmp_restore_have_cur, zcmp_restore_served_d;
  logic                  zcmp_redirected_q;  // 展开期间发生重定向（popret 的 ret）

  assign head = cur_eff[(pc_asm[1] ? 31 : 15) -: 16];
  assign is32 = (head[1:0] == 2'b11);
  assign unaligned32 = is32 & pc_asm[1];
  assign inst_len = is32 ? 3'd4 : 3'd2;        // 4 / 2 字节
  // 本拍 w_new 是 cur_eff 的下一字（跨字 32 位拼接需要）
  assign next_ready = have_cur & served_d & (req_addr == (cur_w_addr + 4));
  // 未装填时本拍 w_new 恰好是 pc_asm 所在字（重定向后首字/补齐字）
  assign refill_now = ~have_cur & served_d &
                      (req_addr == {pc_asm[ADDR_WIDTH-1:2], 2'b00});
  assign cur_eff_valid = have_cur | refill_now;
  assign cur_eff = have_cur ? cur_w : w_new;
  assign can_issue = cur_eff_valid & ~stall & ~redirect & (~unaligned32 | next_ready);
  assign crossing  = can_issue & (is32 | pc_asm[1]);   // 出指令后 pc_asm 进入下一字
  // predict_redirect 仅在可出指令（非 stall 且字就绪）时组合生效：stall 期间 pc 必须
  // 保持 req_addr 重发被抢占/在途字，否则请求地址与状态寄存器错位，
  // OITF 停顿（mul/div 密集段）恢复后取指流会错。
  // Zcmp 微操作共享 cm.popret 的 PC：ret 微操作（jalr）训练 BTB 后，同 PC 的
  // lw/addi 微操作也会被预测为 taken return → 误预测 flush → 展开被 abort。
  // capture/展开期间强制不预测（ret 在 EX 仍会正确重定向，仅少一次预测命中）。
  assign predict_taken_o   = predict_taken & ~(zcmp_capture | zcmp_active);
  assign predict_redirect = predict_taken_o & ~redirect & ~stall & can_issue;

  // 跨字 32 位指令（pc_asm[1]=1）：指令低 16 位在 cur_eff 高半字（内存低地址），
  // 高 16 位在下一字 w_new 低半字（内存高地址）。小端 32 位值必须
  // {高半字, 低半字} = {w_new[15:0], cur_eff[31:16]}，否则高低颠倒。
  assign inst_raw = unaligned32 ? {w_new[15:0], cur_eff[31:16]} :
                    is32        ? cur_eff :
                    pc_asm[1]   ? {16'b0, cur_eff[31:16]} :
                                  {16'b0, cur_eff[15:0]};

  RVC_Expander u_exp (
      .rvc_inst  (inst_raw[15:0]),
      .inst_o    (inst_exp),
      .illegal_o (exp_illegal),
      .zcmp_en_o (exp_zcmp),
      .zcb_en_o  (exp_zcb)
  );

  // Zcmp：本拍输出 cm.push（can_issue 已含 ~stall/~redirect），启动展开 FSM
  assign zcmp_capture = can_issue & exp_zcmp & ~zcmp_active;
  // popret 的 ret（最后一个微操作）自身的分支重定向会触发 if_id_flush + redirect，
  // 这是正常完成路径，不能 abort（否则 busy 提前清、sp 已调而 ret 被冲）；
  // 一旦 ret_pending（最后微操作已发出），只等 WB 退休，flush/redirect 均忽略。
  assign zcmp_abort   = zcmp_flush_any_i | redirect;
  assign zcmp_active  = zcmp_busy;   // 展开冻结（capture 次拍起，直到 last 退休）
  // 不能直接用 zcmp_last_retired_i：背靠背 Zcmp 时上一条指令残留的 last 标签
  // 可能在新展开刚 capture 时退休，把窗口状态提前恢复（consume 早到）。
  // 用展开器内部"尾部已发出"门控后的 retire_ok。
  assign zcmp_consume = zcmp_retire_ok;       // 当前展开最后微操作 WB 退休：补消费

  Zcmp_Expander u_zcmp (
      .clk            (clk),
      .rst_n          (rst_n),
      .zcmp_inst_i    (inst_raw[15:0]),
      .capture_i      (zcmp_capture),
      .stall_i        (stall),
      .abort_i        (zcmp_abort),
      .last_retired_i (zcmp_last_retired_i),
      .micro_inst_o   (zcmp_micro_inst),
      .micro_valid_o  (zcmp_micro_valid),
      .micro_last_o   (zcmp_micro_last),
      .busy_o         (zcmp_busy),
      .retire_ok_o    (zcmp_retire_ok)
  );

  // 展开期间（capture 拍起）用微操作流覆盖正常装配输出。
  // inst_o 数据路径不 做 can_issue NOP 门控：can_issue=0 的拍（redirect/stall/
  // 字未就绪）IF_ID 必被 Pipeline_Ctrl 同拍 flush 或 stall 覆盖（redirect→if_id_flush、
  // stall/fetch_wait→if_id_stall），锁不进流水线；去掉门控后 inst 路径不再依赖
  // ctrl_jump_en（EX 级 trap/branch 长组合链）与 pc_stall 等晚到信号（时序切割）。
  assign inst_o         = (zcmp_capture | zcmp_active) ? zcmp_micro_inst :
                          (is32 ? inst_raw : inst_exp);
  assign inst_valid_o   = (zcmp_capture | zcmp_active) ? (zcmp_micro_valid & ~stall) :
                          can_issue;
  // 取指字未就绪：既无有效指令输出，也非流水线停顿/重定向（这些场景由
  // Pipeline_Ctrl 的 stall/flush 分支处理，不应把 ID_EX 误清）。
  assign fetch_wait_o   = zcmp_active ? 1'b0 : (~can_issue & ~redirect & ~stall);
  assign is_compressed_o = (zcmp_capture | zcmp_active) ? 1'b1 : (can_issue & ~is32);
  assign illegal_inst_o = (zcmp_capture | zcmp_active) ? 1'b0 : (can_issue & ~is32 & exp_illegal);
  assign zcmp_micro_last_o = (zcmp_capture | zcmp_active) ? zcmp_micro_last : 1'b0;
  assign zcmp_micro_any_o  = (zcmp_capture | zcmp_active);
  assign zcb_tag_o         = (zcmp_capture | zcmp_active) ? 1'b0 : (can_issue & ~is32 & exp_zcb);
  assign zcmp_busy_o       = zcmp_busy;

  // 取指请求地址（给 ROM/RAM）：
  //  - 重定向拍组合输出目标字（与 PC_counter 的 jump 覆盖一致）
  //  - stall 期间保持 req_addr（正在返回的那个字），避免存储器超前读到下一个字
  //  - have_cur 时 cur_w 可能含 2 条 16 位指令（2 拍消费），本拍只请求 cur_w 的
  //    下一字（重复请求无害），避免 16 位指令流把下一字提前冲掉；
  //  - 否则输出 fetch_addr（refill 首字 / 预取地址）
  assign pc = redirect ? {redirect_target[ADDR_WIDTH-1:2], 2'b00} :
              predict_redirect ? {predict_target[ADDR_WIDTH-1:2], 2'b00} :
              stall    ? req_addr :
              have_cur ? (cur_w_addr + 4) :
              fetch_addr;
  assign inst_addr_o = pc_asm;   // 当前指令地址（16 位对齐），给流水线/预测器/触发器
  assign fetch_word_addr_o = req_addr;  // w_new = 上一拍请求字（req_addr）的返回数据

  // ---------------- 异常 ----------------
  wire inst_addr_legal = (pc_asm[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH]==`BOOT_BASE_TAG ||
                          pc_asm[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH]==`ITCM_BASE_TAG);
  assign if_addr_misalign = 1'b0;   // C 扩展下取指仅 16 位对齐，无非对齐异常
  assign if_access_fault  = ~inst_addr_legal;

  // ---------------- 状态更新 ----------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
`ifdef DIRECT_LOAD
      pc_asm     <= {`ITCM_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
      fetch_addr <= {`ITCM_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
      req_addr   <= {`ITCM_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
`else
      pc_asm     <= {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
      fetch_addr <= {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
      req_addr   <= {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
`endif
      cur_w      <= '0;
      cur_w_addr <= '0;
      have_cur   <= 1'b0;
      served_d   <= 1'b0;
      reset_d    <= 1'b1;
      zcmp_redirected_q <= 1'b0;
    end else begin
      reset_d <= 1'b0;
      if (redirect && zcmp_active)
        zcmp_redirected_q <= 1'b1;
      else if (!zcmp_active)
        zcmp_redirected_q <= 1'b0;
      if (redirect) begin
        pc_asm     <= {redirect_target[ADDR_WIDTH-1:1], 1'b0};
        // 本拍 pc 已组合输出目标字，fetch_addr 应指向目标+4（下一拍请求），
        // 否则下一拍 pc=fetch_addr=目标会重复请求同一字，字流错位一拍。
        fetch_addr <= {redirect_target[ADDR_WIDTH-1:2], 2'b00} + 4;
        req_addr   <= {redirect_target[ADDR_WIDTH-1:2], 2'b00};
        served_d   <= fetch_served;
        have_cur   <= 1'b0;
      end else if (predict_redirect && can_issue) begin
        // IF 预测命中：当前指令本拍正常输出（can_issue），
        // 下一拍起从预测目标取指/装配（JAL/JALR 由流水线完成写回与 RAS）。
        pc_asm     <= {predict_target[ADDR_WIDTH-1:1], 1'b0};
        fetch_addr <= {predict_target[ADDR_WIDTH-1:2], 2'b00} + 4;
        req_addr   <= {predict_target[ADDR_WIDTH-1:2], 2'b00};
        served_d   <= fetch_served;
        have_cur   <= 1'b0;
      end else begin
        // 取指指针：
        //  - have_cur=1：cur_w 消费中（16 位指令 2 拍/字），请求 cur_w 的下一字
        //    （重复请求无害，w_new 保持该字直到 crossing 装填）；
        //  - have_cur=0：每周期 +4（refill 连续消费 / 复位向量）；
        //  - stall：pc=req_addr 重发在途字（与旧 PC_counter 语义一致）。
        if (zcmp_active | zcmp_capture) begin
          // 展开捕获/冻结：取指指针保持（consume 拍由装配段统一恢复）
          fetch_addr <= fetch_addr;
          req_addr   <= req_addr;
          served_d   <= served_d;
        end else if (stall && ~reset_d) begin
          fetch_addr <= fetch_addr;
          req_addr   <= req_addr;
          served_d   <= fetch_served;
        end else if (have_cur) begin
          req_addr   <= cur_w_addr + 4;
          served_d   <= fetch_served;
        end else begin
          fetch_addr <= fetch_addr + 4;
          req_addr   <= fetch_addr;
          served_d   <= fetch_served;
        end
        // 装配/装填
        if (zcmp_active) begin
          if (zcmp_consume) begin
            if (!zcmp_redirected_q) begin
              // 展开完成：恢复 capture 拍锁存的"消费 cm.push 后"窗口状态
              pc_asm      <= zcmp_restore_pc;
              cur_w       <= zcmp_restore_cur_w;
              cur_w_addr  <= zcmp_restore_cur_w_addr;
              have_cur    <= zcmp_restore_have_cur;
              fetch_addr  <= zcmp_restore_fetch_addr;
              req_addr    <= zcmp_restore_req_addr;
              served_d    <= zcmp_restore_served_d;
            end
          end
          // 否则冻结：不推进 pc_asm/窗口
        end else if (~stall) begin
          if (can_issue) begin
            if (exp_zcmp) begin
              // Zcmp 启动展开：本拍不推进，锁存"出完 cm.push 后"的窗口状态
              zcmp_restore_pc <= pc_asm + 2;
              if (crossing) begin
                if (next_ready) begin
                  zcmp_restore_cur_w      <= w_new;
                  zcmp_restore_cur_w_addr <= req_addr;
                  zcmp_restore_have_cur   <= 1'b1;
                end else if (have_cur) begin
                  zcmp_restore_have_cur   <= 1'b0;
                  zcmp_restore_fetch_addr <= {((pc_asm + 2) >> 2), 2'b00};
                end else begin
                  zcmp_restore_have_cur   <= 1'b0;
                end
              end else if (refill_now) begin
                zcmp_restore_cur_w      <= w_new;
                zcmp_restore_cur_w_addr <= req_addr;
                zcmp_restore_have_cur   <= 1'b1;
              end else begin
                zcmp_restore_have_cur   <= have_cur;
              end
              if (have_cur) begin
                zcmp_restore_req_addr <= cur_w_addr + 4;
              end else begin
                zcmp_restore_fetch_addr <= fetch_addr + 4;
                zcmp_restore_req_addr   <= fetch_addr;
              end
              zcmp_restore_served_d <= fetch_served;
            end else begin
              pc_asm <= pc_asm + inst_len;
              if (crossing) begin
                if (next_ready) begin
                  // 跨字/32 位指令出完后进入下一字：用刚到达的 w_new 装填
                  cur_w      <= w_new;
                  cur_w_addr <= req_addr;
                  have_cur   <= 1'b1;
                end else if (have_cur) begin
                  // 16 位流第二拍（have_cur=1）：下一个字未到（被抢占/首字），
                  // 等待补齐：fetch_addr 指回新 pc_asm 所在字重新请求
                  have_cur   <= 1'b0;
                  fetch_addr <= {((pc_asm + inst_len) >> 2), 2'b00};
                end else begin
                  // 普通 32 位指令出完（have_cur=0）：外层已把 fetch_addr +4
                  // （= 新 pc_asm 的下一字，领先一拍预取），不要再回拨，
                  // 否则下一字被重复请求、每两条指令白等一拍（coremark 22%）。
                  have_cur <= 1'b0;
                end
              end else if (refill_now) begin
                // 16 位偶数半字指令从 w_new 直接出：另一半字仍在 w_new 中，锁存
                cur_w      <= w_new;
                cur_w_addr <= req_addr;
                have_cur   <= 1'b1;
              end
            end
          end else if (refill_now) begin
            cur_w      <= w_new;
            cur_w_addr <= req_addr;
            have_cur   <= 1'b1;
          end
        end
      end
    end
  end

`ifndef SYNTHESIS
// ===== SVA：取指窗口一致性 =====
// 装配地址恒 16 位对齐（C 扩展取指粒度）
a_inst_addr_aligned: assert property (
    @(posedge clk) disable iff (!rst_n)
    (inst_addr_o[0] == 1'b0));
// 重定向清空装配窗口：jump_en/dbg_load_en 次拍 have_cur=0（字流从目标重取）
a_redirect_clear: assert property (
    @(posedge clk) disable iff (!rst_n)
    ((jump_en || dbg_load_en) |=> (!have_cur)));
`endif

endmodule
