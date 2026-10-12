// =============================================================================
// pipeline_ctrl_formal_top.sv — Pipeline_Ctrl 形式验证 harness（SymbiYosys）
// =============================================================================
// 目标属性（Pipeline_Ctrl.sv `ifdef FORMAL 区）：
//   ① 中断接受拍冲刷约定（fml_a_accept_*，防双重提交）
//   ② 异常优先级表完整性不变式（fml_a_exc_code_not_all1 / trap_consistent / oitf_flush）
//   ③ 单步 drain 状态机不变式（fml_a_step_legal / drain_bounded）
//
// 断言全部在 Pipeline_Ctrl.sv 内部 `ifdef FORMAL 区（yosys SVA 子集写法：
// 时钟取外层 always、无 disable iff、无 |->），本 harness 只做：
//   - 驱动所有输入自由变量（异常码三组全 1 标记 = 无异常路径）
//   - 复位时序假设（初始 1 拍 rst_n=0，此后恒 1）
//   - 让 sby 的 read -formal -D FORMAL 激活 FORMAL 区
// =============================================================================

module pipeline_ctrl_formal_top #(
    parameter DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    localparam AW = 32;

    // ---- 输入自由变量（默认全 0/全 1 标记）----
    logic                                     f_branch_jump_en;
    logic [AW-1:0]                            f_branch_jump_addr;
    logic                                     f_trap_jump;
    logic [AW-1:0]                            f_trap_jump_addr;
    logic                                     f_trap_jump_exc;
    logic                                     f_int_accept_kill;
    logic [1:0]                               f_priv_mode;
    logic                                     f_waiting_int;
    logic                                     f_dbg_halt_req;
    logic                                     f_dbg_step;
    logic                                     f_dbg_resume_pulse;
    logic                                     f_trigger_match;
    logic                                     f_ebreak_halt;
    logic                                     f_sba_bus_active;
    logic                                     f_mem_split_stall;
    logic                                     f_itcm_data_stall;
    logic                                     f_ex_access_en;
    logic                                     f_zcmp_busy;
    logic                                     f_load_use_flag;
    logic                                     f_bus_ready;
    logic                                     f_oitf_stall;
    logic                                     f_reg_rd_wen_wb;
    logic [AW-1:0]                            f_inst_addr_if;
    logic                                     f_inst_valid_if;
    logic                                     f_fetch_wait_if;
    logic [AW-1:0]                            f_inst_addr_id;
    logic [AW-1:0]                            f_inst_addr_ex;
    logic [AW-1:0]                            f_inst_addr_mem;
    logic [DATA_WIDTH-1:0]                    f_exc_code_if;
    logic [DATA_WIDTH-1:0]                    f_exc_code_id;
    logic [DATA_WIDTH-1:0]                    f_exc_code_ex;
    logic [DATA_WIDTH-1:0]                    f_exc_val_if;
    logic [DATA_WIDTH-1:0]                    f_exc_val_id;
    logic [DATA_WIDTH-1:0]                    f_exc_val_ex;

    // 异常码/指令地址放开为自由输入。原钉全 1 标记使 exception_trap 恒 0，
    // fml_a_exc_code_not_all1/trap_consistent/exc_s2/exc_s1_keep/oitf_flush 全部
    // 断言空转（harness 目标②失去覆盖）。
    // 自由码（含全 1 标记）让优先级表/全 1 标记不变式被真实探索；地址独立自由值
    // 使 exc_s2/exc_s1_keep 的地址 mux 选择可观测。
    assign f_exc_val_if  = '0;
    assign f_exc_val_id  = '0;
    assign f_exc_val_ex  = '0;
    assign f_inst_addr_mem = '0;
    assign f_branch_jump_addr = '0;
    assign f_trap_jump_addr   = '0;
    assign f_priv_mode = 2'b11;

    // ---- DUT 输出 ----
    logic                       o_pc_stall;
    logic                       o_ctrl_jump_en;
    logic [AW-1:0]             o_ctrl_jump_addr;
    logic                       o_if_id_stall;
    logic                       o_if_id_flush;
    logic                       o_id_ex_stall;
    logic                       o_id_ex_flush;
    logic                       o_ex_mem_stall;
    logic                       o_ex_mem_flush;
    logic                       o_mem_wb_stall;
    logic                       o_mem_wb_flush;
    logic                       o_oitf_flush;
    logic [AW-1:0]             o_exc_inst_addr;
    logic                       o_exception_trap;
    logic [DATA_WIDTH-1:0]     o_exception_code;
    logic [DATA_WIDTH-1:0]     o_exception_val;
    logic                       o_dbg_halted;

    // ---- 复位时序假设：初始 1 拍 rst_n=0，此后恒 1 ----
    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;
    always_ff @(posedge clk) begin
        if (!f_past_valid) assume (!rst_n);
        else               assume (rst_n);
    end
    // 复位期间控制动作输入恒 0（L1 断言 disable-iff 的等价形式假设，
    // 防形式引擎在 rst 首拍搜出 int_accept_kill=1 而 FSM/寄存器尚未初始化的伪反例）
    always @(posedge clk) begin
        if (!rst_n) begin
            assume (!f_int_accept_kill);
            assume (!f_trap_jump);
            assume (!f_trap_jump_exc);
            assume (!f_branch_jump_en);
        end
    end

    // ---- 输入约定假设（harness 侧保证，防形式引擎搜出非物理输入组合）----
    // ① 冲刷/跳转脉冲互斥（同一拍只能有最高优先级的一类动作）
    // ② trap_jump_exc=1 时 trap_jump 必为 1（exc 是 trap 的子集）
    // ③ 硬件单拍脉冲信号：每拍至多 1 拍有效（dbg_resume_pulse / trigger_match
    //    是 Debug Module 输出的单拍脉冲，不允许连续 2 拍）
    // ④ 调试信号组合物理约束：trigger_match / dbg_halt_req 与 ebreak_halt 互斥
    //    （ebreak_halt=1 时 CPU 已 halt，后续调试事件被 zcmp 门控抑制）
    // ⑤ waiting_int 与 int_accept_kill 互斥（WFI 睡眠期间中断被接受则退出睡眠）
    // ⑥ zcmp_busy 时 int_accept_kill 不可能（Zcmp 展开中屏蔽中断）
    // ⑦ oitf_stall 与 int_accept_kill 互斥（OITF 忙时不接受中断）
    // ⑧ 多脉冲信号单拍有效：trap_jump / int_accept_kill / trap_jump_exc
    always @(posedge clk) begin
        if (rst_n) begin
            // ① 互斥
            assume (!(f_trap_jump && f_int_accept_kill));
            assume (!(f_int_accept_kill && f_branch_jump_en));
            // ② exc 是 trap 子集
            assume (f_trap_jump_exc ? f_trap_jump : 1'b1);
            // ③ 单拍脉冲
            assume (!(f_dbg_resume_pulse && $past(f_dbg_resume_pulse)));
            assume (!(f_trigger_match && $past(f_trigger_match)));
            assume (!(f_trap_jump && $past(f_trap_jump)));
            // ⑨ 挂起的 trap 重定向（前一拍 trap_jump/trap_jump_exc 锁存
            //    r_trap_redirect）期间不接受中断（该分支优先级高于 accept 分支，
            //    会遮蔽 accept 的 flush，约定在遮蔽场景下不检查）
            assume (!(f_int_accept_kill && $past(f_trap_jump)));
            assume (!(f_int_accept_kill && $past(f_trap_jump_exc)));
            assume (!(f_int_accept_kill && $past(f_int_accept_kill)));
            assume (!(f_trap_jump_exc && $past(f_trap_jump_exc)));
            // ④ 调试信号互斥
            assume (!(f_trigger_match && f_ebreak_halt));
            assume (!(f_dbg_halt_req && f_ebreak_halt));
            // ⑤ WFI 与接受互斥
            assume (!(f_waiting_int && f_int_accept_kill));
            // ⑥ Zcmp 与接受互斥
            assume (!(f_zcmp_busy && f_int_accept_kill));
            // ⑦ OITF 与接受互斥
            assume (!(f_oitf_stall && f_int_accept_kill));
            // ⑧ 高优先级 debug 分支与 accept 互斥（它们抢先设置 if_id_flush，
            //    accept_kill 分支被遮蔽，约定只在 debug 静默时检查）
            assume (!(f_dbg_halt_req && f_int_accept_kill));
            assume (!(f_trigger_match && f_int_accept_kill));
            assume (!(f_ebreak_halt && f_int_accept_kill));
            assume (!(f_dbg_resume_pulse && f_int_accept_kill));
            // —— 分阶段合法异常码约束（生产者约定）——
            // 自由 31 位码会产生“bit30=0 但 get_priority 落默认 15”的非法组合：
            // trap=1 而选中全 1 标记 → fml_a_exc_code_not_all1 假失败（真实流水线不会产出）。
            // 各阶段合法集按 get_priority 查表域（code[3:0]）约束，全 1 标记(bit30=1)恒合法。
            assume (f_exc_code_if[30] || f_exc_code_if[3:0] == 4'd0 || f_exc_code_if[3:0] == 4'd1);
            assume (f_exc_code_id[30] || f_exc_code_id[3:0] == 4'd2 || f_exc_code_id[3:0] == 4'd3
                 || f_exc_code_id[3:0] == 4'd8 || f_exc_code_id[3:0] == 4'd9
                 || f_exc_code_id[3:0] == 4'd11);
            assume (f_exc_code_ex[30] || f_exc_code_ex[3:0] == 4'd2 || f_exc_code_ex[3:0] == 4'd4
                 || f_exc_code_ex[3:0] == 4'd5 || f_exc_code_ex[3:0] == 4'd6
                 || f_exc_code_ex[3:0] == 4'd7);
            // ⑩ step 状态机非 DRAIN（STEP_DRAIN 期间 accept 被 step_drain 分支遮蔽）
            //    简化：f_dbg_step=0 时 step_state 不会进入 RUN/DRAIN
            //    （STEP 序列需要 dbg_resume_pulse && dbg_step 启动）
            //    因此 accept_kill=1 时 step 必然为 IDLE/HALT，不需额外假设
        end
    end

    Pipeline_Ctrl #(
        .ADDR_WIDTH (AW),
        .DATA_WIDTH (DATA_WIDTH)
    ) dut (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .branch_jump_en           (f_branch_jump_en),
        .branch_jump_addr         (f_branch_jump_addr),
        .trap_jump                (f_trap_jump),
        .trap_jump_addr           (f_trap_jump_addr),
        .trap_jump_exc            (f_trap_jump_exc),
        .int_accept_kill          (f_int_accept_kill),
        .priv_mode                (f_priv_mode),
        .waiting_int              (f_waiting_int),
        .dbg_halt_req             (f_dbg_halt_req),
        .dbg_halted               (o_dbg_halted),
        .dbg_step                 (f_dbg_step),
        .dbg_resume_pulse         (f_dbg_resume_pulse),
        .trigger_match            (f_trigger_match),
        .ebreak_halt              (f_ebreak_halt),
        .sba_bus_active           (f_sba_bus_active),
        .mem_split_stall          (f_mem_split_stall),
        .itcm_data_stall          (f_itcm_data_stall),
        .ex_access_en             (f_ex_access_en),
        .zcmp_busy                (f_zcmp_busy),
        .load_use_flag            (f_load_use_flag),
        .bus_ready                (f_bus_ready),
        .oitf_stall               (f_oitf_stall),
        .reg_rd_wen_wb            (f_reg_rd_wen_wb),
        .inst_addr_if             (f_inst_addr_if),
        .inst_valid_if            (f_inst_valid_if),
        .fetch_wait_if            (f_fetch_wait_if),
        .inst_addr_id             (f_inst_addr_id),
        .inst_addr_ex             (f_inst_addr_ex),
        .inst_addr_mem            (f_inst_addr_mem),
        .exception_code_if        (f_exc_code_if),
        .exception_code_id        (f_exc_code_id),
        .exception_code_ex        (f_exc_code_ex),
        .exception_val_if         (f_exc_val_if),
        .exception_val_id         (f_exc_val_id),
        .exception_val_ex         (f_exc_val_ex),
        .pc_stall                 (o_pc_stall),
        .ctrl_jump_en             (o_ctrl_jump_en),
        .ctrl_jump_addr           (o_ctrl_jump_addr),
        .if_id_stall              (o_if_id_stall),
        .if_id_flush              (o_if_id_flush),
        .id_ex_stall             (o_id_ex_stall),
        .id_ex_flush              (o_id_ex_flush),
        .ex_mem_stall             (o_ex_mem_stall),
        .ex_mem_flush             (o_ex_mem_flush),
        .mem_wb_stall             (o_mem_wb_stall),
        .mem_wb_flush             (o_mem_wb_flush),
        .oitf_flush               (o_oitf_flush),
        .exception_inst_addr      (o_exc_inst_addr),
        .exception_trap           (o_exception_trap),
        .exception_code           (o_exception_code),
        .exception_val            (o_exception_val)
    );

endmodule
