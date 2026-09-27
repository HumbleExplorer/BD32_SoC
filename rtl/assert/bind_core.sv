// =============================================================================
// bind_core.sv — RISC_V_Core 系统级断言 checker（bind 挂载，综合不可见）
// =============================================================================
// SVA 分层约定：
//   L1 核心合同：各模块 inline 断言区，常驻（`ifndef SYNTHESIS）
//   L2 完整模块断言：+define+ASSERT_MODULE 时编译
//   L3 系统级 tracker：本文件（+define+ASSERT_SYS 时编译）
// 断言失败统一 $error + "[SVA][模块]" 前缀；回归脚本将 "** Error: [SVA]" 计入 FAIL。
// =============================================================================
`ifndef SYNTHESIS
`ifdef ASSERT_SYS

// -----------------------------------------------------------------------------
// int_boundary_chk —— 中断边界双提交哨兵
// 契约：int_accept 拍锁存 mepc 后，到 mret 前该 PC 的指令不得完成写回。
// 历史 bug：接受拍 ex_mem_flush=0 使边界指令泄漏 EX_MEM 完成写回（第一次提交），
// mret 后又按 mepc 重执行（第二次提交），非幂等指令（addi s0,s0,1768）状态
// 双重累加 → tidle 的 s0=0x22dd0 → defunct 读野指针 → SERR。
// -----------------------------------------------------------------------------
module int_boundary_chk #(
    parameter int W = 32
)(
    input logic               clk,
    input logic               rst_n,
    // 目标模块（RISC_V_Core）内部信号，bind 时连接
    input logic               int_accept_kill,  // 中断接受拍（mepc 当拍锁存边界 PC）
    input logic               mret_req,         // mret 的跳转拍
    input logic [W-1:0]       mepc,             // CSR 内 mepc
    input logic               valid_wb,         // WB 级指令有效
    input logic               reg_rd_wen_wb,    // WB 写回使能
    input logic [4:0]         rd_wb,            // WB 写回地址
    input logic [W-1:0]       pc_wb             // WB 指令 PC
);
    bit         pend;
    bit [W-1:0] pend_pc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pend    <= 1'b0;
            pend_pc <= '0;
        end else if (int_accept_kill) begin
            pend    <= 1'b1;
            pend_pc <= mepc;
        end else if (mret_req) begin
            pend    <= 1'b0;
        end
    end

    property p_no_double_commit;
        @(posedge clk) disable iff (!rst_n)
        (pend && valid_wb && reg_rd_wen_wb && (pc_wb == pend_pc));
    endproperty
    a_no_double_commit: assert property (p_no_double_commit)
        else $error("[SVA][INT] 边界指令 %h 在 mret 前写回（双重提交）", pend_pc);

endmodule

bind RISC_V_Core int_boundary_chk #(.W(32)) u_chk_int_bnd (
    .clk            (clk),
    .rst_n          (rst_n),
    .int_accept_kill(int_accept_kill),
    .mret_req       (mret_req),
    .mepc           (u_CSR_Reg_Access.mepc),
    .valid_wb       (mem_wb_valid),
    .reg_rd_wen_wb  (reg_rd_wen),
    .rd_wb          (reg_rd_waddr_wb),
    .pc_wb          (inst_addr_wb)
);

`endif // ASSERT_SYS
`endif // SYNTHESIS
