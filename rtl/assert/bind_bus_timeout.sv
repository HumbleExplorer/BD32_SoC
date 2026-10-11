// =============================================================================
// bind_bus_timeout.sv — 双层超时衔接契约（端到端跨层哨兵，bind 挂载，综合不可见）
// =============================================================================
// SVA 分层约定：L3 系统级哨兵（+define+ASSERT_SYS 时编译），与 bind_core.sv 同风格。
//
// 契约（主机 AXI_Lite_Master ↔ 桥内 APB_Master 的跨层超时衔接）：
//   APB_TO_VAL = BUS_TIMEOUT/2（数值约定见 APB_Master.sv 注释），保证桥先于主机恢复。
//   本哨兵在真实 SoC 例化环境里验证端到端窗口：
//   T1 主机 bus_timeout 脉冲（强拆拍）→ 桥内 apb_master 至多再挂 APB_TO_VAL+4 拍
//   回 IDLE（+4 = 桥 tran_done 采样 1 拍 + 状态寄存 1 拍 + CDC/握手裕量 2 拍）。
//   若违约 = 主机先于桥恢复后桥仍占着半事务（新事务会叠加到悬空事务上）。
//
// 挂载：bind 到 SoC_top（端口连接表达式在目标作用域解析，跨层次用 $root 绝对路径
// 直查主机内部信号——仿真合法；综合不可见由 `ifndef SYNTHESIS + ASSERT_SYS 保证）。
// =============================================================================
`ifndef SYNTHESIS
`ifdef ASSERT_SYS

module bus_timeout_link_chk #(
    // 与 APB_Master 的 APB_TO_VAL（= BUS_TIMEOUT/2 = 1024/2）保持一致；
    // 改 SoC_Config 的 BUS_TIMEOUT 时须同步本值（checker 启动时自检不一致即报错）
    parameter int unsigned APB_TO_VAL = 512,
    parameter int unsigned GRACE      = 4      // 桥侧回收的额外裕量拍
)(
    input logic clk,
    input logic rst_n
);
    // 参数一致性自检：与本设计 APB_Master 实际 APB_TO_VAL 对账
`ifdef BTLINK_ENV_SOC
    initial begin
        if (APB_TO_VAL != $root.tb_soc_top.u_SoC_top.u_AXI_APB_Bridge.u_apb_master.APB_TO_VAL)
            $error("[SVA][BTLINK] APB_TO_VAL=%0d != APB_Master's %0d — sync parameter!",
                   APB_TO_VAL, $root.tb_soc_top.u_SoC_top.u_AXI_APB_Bridge.u_apb_master.APB_TO_VAL);
    end
`endif
    // 主机强拆脉冲（AXI_Lite_Master 内部 bus_timeout 为一拍脉冲）
    logic master_abort;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            master_abort <= 1'b0;
        else
            `ifdef BTLINK_ENV_SOC
        master_abort <= $root.tb_soc_top.u_SoC_top.u_Bus_Access.u_AXI_Lite_Master.bus_timeout;
`else
        master_abort <= $root.tb_bus_abort_link.u_bus_access.u_AXI_Lite_Master.bus_timeout;
`endif
    end

    // 桥内 apb_master 的状态/超时（层次引用）
    `ifdef BTLINK_ENV_SOC
    wire       apm_busy  = $root.tb_soc_top.u_SoC_top.u_AXI_APB_Bridge.u_apb_master.current_state != 5'b00001;
    wire       apm_idle  = $root.tb_soc_top.u_SoC_top.u_AXI_APB_Bridge.u_apb_master.current_state == 5'b00001;
`else
    wire       apm_busy  = $root.tb_bus_abort_link.u_AXI_APB_Bridge.u_apb_master.current_state != 5'b00001;
    wire       apm_idle  = $root.tb_bus_abort_link.u_AXI_APB_Bridge.u_apb_master.current_state == 5'b00001;
`endif

    // 等待窗口计数：强拆后桥回 IDLE 的拍数上限 = APB_TO_VAL + GRACE
    int unsigned wait_cnt;
    bit          in_window;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_window <= 1'b0;
            wait_cnt  <= 0;
        end else if (master_abort) begin
            in_window <= 1'b1;
            wait_cnt  <= 0;
        end else if (in_window) begin
            if (apm_idle) begin
                in_window <= 1'b0;
            end else if (wait_cnt > APB_TO_VAL + GRACE) begin
                in_window <= 1'b0;      // 超窗即退出计数（断言已触发）
            end else begin
                wait_cnt <= wait_cnt + 1;
            end
        end
    end

    // 契约：强拆后窗口内桥必须回 IDLE（回收有界）
    a_bt_link_recover: assert property (@(posedge clk) disable iff (!rst_n)
        (master_abort |-> ##[(APB_TO_VAL/2)+1 : APB_TO_VAL+GRACE] apm_idle))
        else $error("[SVA][BTLINK] bridge apb_master not idle within APB_TO_VAL+GRACE after master abort (wait_cnt=%0d)", wait_cnt);

    // 契约：窗口内桥不得接受新 APB 事务（半事务不被叠加）
    a_bt_link_no_overlay: assert property (@(posedge clk) disable iff (!rst_n)
        `ifdef BTLINK_ENV_SOC
        (in_window && !apm_idle |-> !$root.tb_soc_top.u_SoC_top.u_AXI_APB_Bridge.u_apb_master.i_transfer)
`else
        (in_window && !apm_idle |-> !$root.tb_bus_abort_link.u_AXI_APB_Bridge.u_apb_master.i_transfer)
`endif)
        else $error("[SVA][BTLINK] bridge accepted new APB transfer while half-transaction pending");

    // 强拆事件实时打印（证明 checker 活着且观察到了强拆事件；不依赖 final——
    // do 脚本 NoQuitOnFinish/break 流程下 final 不可靠）
    int abort_cnt = 0;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) abort_cnt <= 0;
        else if (master_abort) begin
            abort_cnt <= abort_cnt + 1;
            $display("[BTLINK] master_abort #%0d @%0t — bridge must recover within %0d cycles",
                     abort_cnt + 1, $time, APB_TO_VAL);
        end
    end

endmodule

// 挂载（按环境二选一）：
//   SoC 环境（+define+BTLINK_ENV_SOC）：bind 到 SoC_top，时钟/复位用目标作用域信号
//   独立 TB（tb_bus_abort_link）：不用 bind——TB 内直接实例化 checker，
//     层次引用走 BTLINK_ENV_SOC 未定义分支（$root.tb_bus_abort_link...）
`ifdef BTLINK_ENV_SOC
bind SoC_top bus_timeout_link_chk #(
    .APB_TO_VAL(512),   // = BUS_TIMEOUT/2（bind 文件编译序在 SoC_Config 可见前，宏不可用；
                        //   checker initial 自检对账 APB_Master 实际值，不一致即 $error）
    .GRACE     (4)
) u_chk_btlink (
    .clk   (clk_soc),
    .rst_n (rst_n_sync)
);
`endif

`endif
`endif
