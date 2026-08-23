`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
// =============================================================================
// IFU_Buffer — 取指缓冲 + 16/32 位指令装配 + RVC 展开（替代 PC_counter）
// -----------------------------------------------------------------------------
// 方案二（单字 32 位寄存器）：
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
    // ---- 输出 ----
    (* MAX_FANOUT = 16 *)output logic  [ADDR_WIDTH-1:0]    pc,          // 取指请求字地址（给 ROM/RAM）
    (* MAX_FANOUT = 16 *)output logic  [ADDR_WIDTH-1:0]    inst_addr_o, // 当前指令地址（16 位对齐，给流水线）
    output  logic   [DATA_WIDTH-1:0]    inst_o,        // 展开后的指令（未出指令时 NOP）
    output  logic                       inst_valid_o,  // 本拍是否输出了有效指令（供 IF_ID stall）
    output  logic                       fetch_wait_o,  // 取指字未就绪（非 stall/redirect 的等待拍）
    output  logic                       is_compressed_o,// 当前指令是否压缩（供 pc+2 链接）
    output  logic                       illegal_inst_o, // 保留压缩编码
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
  logic        exp_illegal;

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
  assign predict_redirect = predict_taken & ~redirect & ~stall & can_issue;

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
      .illegal_o (exp_illegal)
  );

  assign inst_o         = can_issue ? (is32 ? inst_raw : inst_exp) : `INST_NOP;
  assign inst_valid_o   = can_issue;
  // 取指字未就绪：既无有效指令输出，也非流水线停顿/重定向（这些场景由
  // Pipeline_Ctrl 的 stall/flush 分支处理，不应把 ID_EX 误清）。
  assign fetch_wait_o   = ~can_issue & ~redirect & ~stall;
  assign is_compressed_o = can_issue & ~is32;
  assign illegal_inst_o = can_issue & ~is32 & exp_illegal;

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
    end else begin
      reset_d <= 1'b0;
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
        if (stall && ~reset_d) begin
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
        if (~stall) begin
          if (can_issue) begin
            pc_asm <= pc_asm + inst_len;
            if (crossing) begin
              if (next_ready) begin
                // 跨字/32 位指令出完后进入下一字：用刚到达的 w_new 装填
                cur_w      <= w_new;
                cur_w_addr <= req_addr;
                have_cur   <= 1'b1;
              end else begin
                // 下一字未到（被抢占/首字），等待补齐：fetch_addr 指向新 pc_asm 所在字
                have_cur   <= 1'b0;
                fetch_addr <= {((pc_asm + inst_len) >> 2), 2'b00};
              end
            end else if (refill_now) begin
              // 16 位偶数半字指令从 w_new 直接出：另一半字仍在 w_new 中，锁存
              cur_w      <= w_new;
              cur_w_addr <= req_addr;
              have_cur   <= 1'b1;
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

endmodule
