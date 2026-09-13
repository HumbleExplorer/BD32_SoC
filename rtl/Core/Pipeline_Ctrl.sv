`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
// =============================================================================
// Pipeline_Ctrl - 流水线控制
// =============================================================================
// 负责 stall/flush/跳转/异常仲裁/单步调试状态机
// 异常优先级：IF → ID → EX（访存异常在 EX 级检测）
// =============================================================================
module Pipeline_Ctrl #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH
)(
    input   logic                       clk,
    input   logic                       rst_n,
    // from EX/MEM
    input   logic                       branch_jump_en,
    input   logic   [ADDR_WIDTH-1:0]    branch_jump_addr,
    // from CSR
    input   logic                       trap_jump,
    input   logic   [ADDR_WIDTH-1:0]    trap_jump_addr,
    input   logic                       trap_jump_exc, // exception/mret only (no interrupt), for single-step drain
    input   logic                       int_accept_kill, // 中断接受拍脉冲（与 mepc 锁存同拍冲刷）
    input   logic   [1:0]               priv_mode,
    input   logic                       waiting_int,
    // from Debug Module
    input   logic                       dbg_halt_req,
    output  logic                       dbg_halted,
    input   logic                       dbg_step,          // dcsr.step：单步模式
    input   logic                       dbg_resume_pulse,  // resume 单拍脉冲
    input   logic                       trigger_match,     // trigger 地址匹配（硬件断点）
    input   logic                       ebreak_halt,       // ebreak 进入 debug 模式（ID 级）
    input   logic                       sba_bus_active,    // SBA 外设总线访问中（halt 保持）
    input   logic                       mem_split_stall,   // MEM 级非对齐拆分访问进行中
    input   logic                       itcm_data_stall,   // EX 级访问 ITCM（单端口让路）
    input   logic                       ex_access_en,      // EX 级有在途访存（load/store 未提交）：
                                                           // waiting_int 冻结必须让位，否则该访问的
                                                           // rvalid 提交被 stall 门拦掉，唤醒后 load 带
                                                           // 端口陈旧数据写回（tidle wfi+load SERR 根因）
    input   logic                       zcmp_busy,         // Zcmp 展开中（延迟调试事件到整条完成）
    // from Forward
    input   logic                       load_use_flag,
    // from EX
    input   logic                       bus_ready,
    input   logic                       oitf_stall,
    input   logic                       reg_rd_wen_wb,      // WB 阶段写寄存器
    // from IF/ID/EX
    (* MAX_FANOUT = 16 *)input   logic   [ADDR_WIDTH-1:0]    inst_addr_if,
    input   logic                       inst_valid_if,  // IFU 本拍是否输出有效指令
    input   logic                       fetch_wait_if,  // IFU 取指字未就绪（非 stall/redirect）
    (* MAX_FANOUT = 16 *)input   logic   [ADDR_WIDTH-1:0]    inst_addr_id,
    (* MAX_FANOUT = 16 *)input   logic   [ADDR_WIDTH-1:0]    inst_addr_ex,
    (* MAX_FANOUT = 16 *)input   logic   [ADDR_WIDTH-1:0]    inst_addr_mem,
    input   logic   [DATA_WIDTH-2:0]    exception_code_if,
    input   logic   [DATA_WIDTH-2:0]    exception_code_id,
    input   logic   [DATA_WIDTH-2:0]    exception_code_ex,
    input   logic   [DATA_WIDTH-1:0]    exception_val_if,
    input   logic   [DATA_WIDTH-1:0]    exception_val_id,
    input   logic   [DATA_WIDTH-1:0]    exception_val_ex,

    // to pc
    (* MAX_FANOUT = 16 *)output  logic                       pc_stall,
    (* MAX_FANOUT = 16 *)output  logic                       ctrl_jump_en,
    output  logic   [ADDR_WIDTH-1:0]    ctrl_jump_addr,
    // to pipeline reg
    (* MAX_FANOUT = 16 *)output  logic                       if_id_stall,
    (* MAX_FANOUT = 16 *)output  logic                       if_id_flush,
    (* MAX_FANOUT = 16 *)output  logic                       id_ex_stall,
    (* MAX_FANOUT = 16 *)output  logic                       id_ex_flush,
    (* MAX_FANOUT = 16 *)output  logic                       ex_mem_stall,
    (* MAX_FANOUT = 16 *)output  logic                       ex_mem_flush,
    (* MAX_FANOUT = 16 *)output  logic                       mem_wb_stall,
    (* MAX_FANOUT = 16 *)output  logic                       mem_wb_flush,
    // to OITF
    output  logic                       oitf_flush,
    // to CSR
    output  logic   [ADDR_WIDTH-1:0]    exception_inst_addr,
    (* MAX_FANOUT = 16 *)output  logic                       exception_trap,
    output  logic   [DATA_WIDTH-2:0]    exception_code,
    output  logic   [DATA_WIDTH-1:0]    exception_val
);


function automatic [3:0] get_priority;
    input [1:0] stage; // 0:IF, 1:ID, 2:EX
    input [DATA_WIDTH-2:0] code;
    // 只比较 [3:0]：所有合法异常码都是 {{(DATA_WIDTH-5){1'b0}},4'dX} 零扩展，
    // 全 1 哨兵的 [3:0]=4'hF 不命中任何表项仍返回 15，语义与全宽 case 等价；
    // 砍掉 27 位比较是该函数进入 EX→trap 关键路径后的时序补偿（2026-09-11）
begin
    get_priority = {4{1'b1}};
    case(stage)
        2'd0: begin // IF阶段
            case(code[3:0])
                4'd0: get_priority = 4'd4;//指令地址未对齐
                4'd1: get_priority = 4'd2;//指令访问错误
            endcase
        end
        2'd1: begin // ID阶段
            case(code[3:0])
                4'd2: get_priority = 4'd3; // 非法指令
                4'd3: get_priority = 4'd6; // 环境断点
                4'd8,4'd9,4'd11: get_priority = 4'd5; // 环境调用
            endcase
        end
        2'd2: begin // EX阶段（含访存异常）
            case(code[3:0])
                4'd2: get_priority = 4'd3; // 非法指令CSR
                4'd5,4'd7: get_priority = 4'd10; // 访存错误
                4'd4,4'd6: get_priority = 4'd10; // 访存未对齐（ITCM store/BootROM/APB 拆分不可覆盖时）。
                                                 // 缺失本项时 code 携带合法 bit30=0 却查表落默认 15，
                                                 // sel_stage 保持 default → 异常码 mux 输出全 1 哨兵 + mepc=0，
                                                 // 陷阱以 mcause=0x7FFFFFFF 发出（2026-09-11 RT-Thread SERR 根因）
            endcase
        end
    endcase
end
endfunction

// 计算各阶段优先级
logic [3:0] priority_if;
logic [3:0] priority_id;
logic [3:0] priority_ex;
logic [3:0] min_priority;
logic [1:0] sel_stage;
logic [DATA_WIDTH-2:0] exception_code_if_m;
logic [DATA_WIDTH-2:0] exception_code_id_m;
logic [DATA_WIDTH-2:0] exception_code_ex_m;

// 分支/跳转重定向有效（branch_jump_en）时，IF/ID 级是被冲刷的更年轻误取指令，
// 其异常作废（否则误取到的非法字异常会抢在重定向之前触发陷阱，跳飞 PC）。
// 做法：把 IF/ID 的异常码替换为全 1 的“无异常”哨兵值；EX 级（分支指令自身，
// 如 jalr 地址未对齐 / 非法 CSR）保持不变，仍可正常触发陷阱。
// 注意：exception_trap 必须沿用原有的 NAND（~(a&&b&&c)）结构，它在复位初期
// inst_addr 尚为不定态 X 时是“复位安全”的（X&&.. 解析为不触发陷阱）；
// 若改写成 OR 形式会改变 X 解析行为，导致复位瞬间误触发陷阱跳飞 PC。
assign exception_code_if_m = branch_jump_en ? {DATA_WIDTH-1{1'b1}} : exception_code_if;
assign exception_code_id_m = branch_jump_en ? {DATA_WIDTH-1{1'b1}} : exception_code_id;
assign exception_code_ex_m = exception_code_ex;

assign priority_if = exception_code_if_m[DATA_WIDTH-2] ? {4{1'b1}} : get_priority(2'd0, exception_code_if_m);
assign priority_id = exception_code_id_m[DATA_WIDTH-2] ? {4{1'b1}} : get_priority(2'd1, exception_code_id_m);
assign priority_ex = exception_code_ex_m[DATA_WIDTH-2] ? {4{1'b1}} : get_priority(2'd2, exception_code_ex_m);

always_comb begin
    min_priority = 4'd15;
    sel_stage = 2'd3;
    if (priority_ex < min_priority) begin
        min_priority = priority_ex;
        sel_stage = 2'd2;
    end
    if (priority_id < min_priority) begin
        min_priority = priority_id;
        sel_stage = 2'd1;
    end
    if (priority_if < min_priority) begin
        min_priority = priority_if;
        sel_stage = 2'd0;
    end
end

always_comb begin
    case(sel_stage)
        2'd2: begin // EX阶段
            exception_code = exception_code_ex_m;
            exception_inst_addr = inst_addr_ex;
            exception_val = exception_val_ex;
        end
        2'd1: begin // ID阶段
            exception_code = exception_code_id_m;
            exception_inst_addr = inst_addr_id;
            exception_val = exception_val_id;
        end
        2'd0: begin // IF阶段
            exception_code = exception_code_if_m;
            exception_inst_addr = inst_addr_if;
            exception_val = exception_val_if;
        end
        default: begin
            exception_code = {DATA_WIDTH-1{1'b1}};
            exception_inst_addr = '0;
            exception_val = '0;
        end
    endcase
end
assign exception_trap = ~(exception_code_if_m[DATA_WIDTH-2] && exception_code_id_m[DATA_WIDTH-2] && exception_code_ex_m[DATA_WIDTH-2]);
assign oitf_flush     = exception_trap;

// =========================================================================
// Single-step 状态机
// resume with dcsr.step=1 → 执行一条指令 → 重新进入 debug mode
// =========================================================================
localparam STEP_IDLE  = 2'b00;
localparam STEP_RUN   = 2'b01;  // 等待一次 PC 推进（取指）
localparam STEP_DRAIN = 2'b10;  // PC 已锁定，等指令退休
localparam STEP_HALT  = 2'b11;  // 重新 halt

logic [1:0] step_state;
logic [2:0] step_drain_cnt;

// ITCM 单端口让路：访问拍（N）停 PC，数据返回拍（N+1）停 IF_ID，防止捕获 LSU 数据
logic itcm_data_stall_d;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) itcm_data_stall_d <= 1'b0;
    else        itcm_data_stall_d <= itcm_data_stall;
end

wire step_halt         = (step_state == STEP_HALT);
wire step_run_active   = (step_state == STEP_RUN);
wire step_drain_active = (step_state == STEP_DRAIN);

// 延迟一拍：BRAM 有 1 拍读延迟，drain 第一拍不能 flush IF/ID
logic step_drain_d;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) step_drain_d <= 1'b0;
    else        step_drain_d <= step_drain_active;
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        step_state     <= STEP_IDLE;
        step_drain_cnt <= 3'd0;
    end else begin
        case (step_state)
            STEP_IDLE: begin
                if (dbg_resume_pulse && dbg_step) begin
                    step_state     <= STEP_RUN;
                    step_drain_cnt <= 3'd0;
                end
            end
            STEP_RUN: begin
                // 等 1 拍让 ITCM 地址生效（BRAM 下拍出数据）
                step_state <= STEP_DRAIN;
                // 如果外部重新 halt，回到 IDLE
                if (dbg_halt_req)
                    step_state <= STEP_IDLE;
            end
            STEP_DRAIN: begin
                // 只在总线就绪且 OITF 无阻塞时计数
                // Zcmp 展开期间不计数（等整条指令完成）
                if (bus_ready && !oitf_stall && !zcmp_busy)
                    step_drain_cnt <= step_drain_cnt + 3'd1;
                // 6 拍：充足余量确保指令退休
                if (step_drain_cnt >= 3'd6)
                    step_state <= STEP_HALT;
                if (dbg_halt_req)
                    step_state <= STEP_IDLE;
            end
            STEP_HALT: begin
                // step 完成，CPU 已 halt。等待 DM 下一次操作：
                if (dbg_resume_pulse && dbg_step) begin
                    step_state     <= STEP_RUN;   // 再次单步
                    step_drain_cnt <= 3'd0;
                end else if (dbg_resume_pulse || dbg_halt_req)
                    step_state <= STEP_IDLE;  // 正常 resume 或外部 halt 接管
            end
        endcase
    end
end

// =========================================================================
// pc_stall：平坦 OR 结构（与 trap_jump / branch_jump_en 解耦）
// =========================================================================
// PC_counter 内部 jump_en 优先级高于 stall，因此 trap/branch 跳转期间
// 即使 pc_stall=1 也不会影响 PC 跳转。这样 pc_stall 不再依赖
// OITF→ALU→branch→exception→trap 的超长组合路径，打断关键时序路径。
// 唯一例外：step_drain 第一拍（drain_d=0）必须释放 PC 让 inst_addr 推进。
// =========================================================================
wire step_drain_release = step_drain_active & ~step_drain_d;  // drain 第一拍

// 普通 resume（非 step）后一拍保持：pc = inst_addr = dpc，BRAM 取到 dpc 指令。
// step 通过 STEP_RUN 的 pc_stall 实现同样效果；普通 resume 之前缺少该保持，
// pc 直接为 dpc+4，跳过 dpc 处指令（reset halt 后 resume 执行错位）。
logic resume_hold;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)            resume_hold <= 1'b0;
    else if (dbg_resume_pulse && !dbg_step) resume_hold <= 1'b1;
    else                   resume_hold <= 1'b0;
end

// Zcmp 展开期间延迟 halt/硬件断点：cm.push 是"整条"语义，序列中途 halt 会破坏
// SP 调整/ret 尾部原子性，且 dbg_halted 应在整条完成后再确认
wire dbg_halt_eff = dbg_halt_req & ~zcmp_busy;
wire trigger_eff  = trigger_match & ~zcmp_busy;

// 高优先级 stall（仅依赖寄存器信号，路径极短）
wire hp_stall = (dbg_halt_eff | step_halt | trigger_eff | ebreak_halt)
              | (dbg_resume_pulse & dbg_step)
              | resume_hold
              | step_run_active
              | (step_drain_active & step_drain_d & ~zcmp_busy)
              | waiting_int;

// 低优先级 stall（来自数据通路，但不再被 trap/branch 屏蔽）
// 注意 ITCM 让路只停返回拍（itcm_data_stall_d）而非访问拍（itcm_data_stall）：
// 访问拍 PC 照常前进，使 inst_addr 停在"被抢占的那条指令"上，返回拍再取回；
// 若访问拍就停 PC，会把已被 IF_ID 取走的指令地址冻住，load-use 停顿顺路重读 → 重复执行
// Zcmp 展开期间 IFU 冻结、不取指，ITCM 让路无保护对象，跳过以避免插入 NOP 气泡
wire lp_stall = oitf_stall | ~bus_ready | load_use_flag | mem_split_stall | (itcm_data_stall_d & ~zcmp_busy);

// step_drain_release 期间强制释放 PC（覆盖 lp_stall）
assign pc_stall = (hp_stall | lp_stall) & ~step_drain_release;

// ==========================================================================
// trap 重定向寄存器：异常/中断/mret 的 PC 跳转打一拍发出（分支仍为当拍组合重定向）
// -----------------------------------------------------------------------------
// 动机：trap_jump_addr 的组合锥（EX 访存译码→异常优先级→CSR trap 地址 mux）与
// branch/前递链串联后直达 IFU pc→TCM BRAM 引脚，是全设计最长路径（逻辑 3.5ns+
// 布线 10.6ns，物理共置也无法消除）。寄存一拍后：trap 当拍仍完成各级 flush 与
// mepc/mcause 采样（语义不变），仅目标地址的取指重定向晚一拍——当拍多取的顺延
// 指令由重定向拍的 if_id_flush 丢弃。trap 罕见，性能无感；分支路径不受影响。
// 保持语义：r_trap_redirect 置位后保持到 ctrl_jump 实际发出（防止被 oitf_stall
// 等低优先级分支吃掉导致跳转丢失）；resume/重新 halt 时清除（dpc 重装会取代它）。
// ==========================================================================
logic r_trap_redirect;
logic [ADDR_WIDTH-1:0] r_trap_addr;
logic r_trap_flush_mem;     // trap 源自 EX 级时，重定向拍需追加 EX_MEM 冲刷
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_trap_redirect <= 1'b0;
        r_trap_addr     <= 'h0;
        r_trap_flush_mem <= 1'b0;
    end else if (trap_jump) begin
        r_trap_redirect <= 1'b1;
        r_trap_addr     <= trap_jump_addr;
        r_trap_flush_mem <= (sel_stage >= 2'd2);
    end else if (dbg_resume_pulse) begin
        r_trap_redirect <= 1'b0;    // resume 重装 dpc，未发出的 trap 跳转作废
        r_trap_flush_mem <= 1'b0;
    end else if (r_trap_redirect) begin
        r_trap_redirect <= ~ctrl_jump_en;   // 保持到实际发出跳转
        r_trap_flush_mem <= r_trap_flush_mem & ~ctrl_jump_en;
    end
end

`ifndef SYNTHESIS
// ===========================================================================
// SVA: trap 重定向寄存器不变式
// ===========================================================================
// 1) 未发出的 pending 重定向保持置位（仅 resume 清除/新 trap 重锁存例外）
a_trap_pending_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
    (r_trap_redirect && !ctrl_jump_en && !dbg_resume_pulse) |=> r_trap_redirect);
// 2) 挂起的重定向必须发出（同拍或 8 拍内 ctrl_jump——重定向与寄存器置位
//    同周期组合发出，窗口含第 0 拍）；调试停止/恢复为合法等待/清除出口
a_trap_fires: assert property (
    @(posedge clk) disable iff (!rst_n)
    (r_trap_redirect && !dbg_halt_eff && !ebreak_halt) |-> ##[0:8]
    (ctrl_jump_en || dbg_halt_eff || ebreak_halt || dbg_resume_pulse));
// 3) 重定向地址在挂起期间保持稳定（未被重新锁存时）
a_trap_addr_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
    (r_trap_redirect && !trap_jump) |=> (r_trap_addr == $past(r_trap_addr)));
`endif

// =========================================================================
// 流水线 flush/stall + 跳转：保持优先级结构（无长时序路径问题）
// =========================================================================
always_comb begin
    ctrl_jump_en    = 1'b0;
    // 取指字未就绪时保持 IF_ID（避免把 "NOP + 当前地址" 的错误配对锁存进
    // 流水线），同时 flush ID_EX（IF_ID 保持的指令稍后重进 ID/EX，避免重复）。
    // 仅限"非 stall/redirect"的字未就绪拍；OITF/load-use/bus 停顿由各自分支
    // 处理（只停 IF_ID、不清 ID_EX，否则长周期指令会被误清）。
    if_id_stall     = fetch_wait_if;
    if_id_flush     = 1'b0;
    id_ex_stall     = 1'b0;
    id_ex_flush     = fetch_wait_if;
    ex_mem_stall    = 1'b0;
    ex_mem_flush    = 1'b0;
    mem_wb_stall    = 1'b0;
    mem_wb_flush    = 1'b0;
    ctrl_jump_addr  = `BOOT_BASE_TAG;
    if (dbg_halt_eff || step_halt || trigger_eff) begin
        if_id_stall     = 1'b1;
        id_ex_stall     = 1'b1;
        ex_mem_stall    = 1'b1;
        mem_wb_stall    = 1'b1;
        if_id_flush     = 1'b1;
        id_ex_flush     = 1'b1;
    end else if (ebreak_halt) begin
        // ebreak 停在 ID 级：只停不刷，等 OITF 排空/bus 空闲后 dbg_halted 确认，
        // 由 DM 在 halted 上升沿锁存 haltreq（否则 ebreak 只维持 1 拍会丢失 halt）。
        if_id_stall     = 1'b1;
        id_ex_stall     = 1'b1;
        ex_mem_stall    = 1'b1;
        mem_wb_stall    = 1'b1;
    end else if (dbg_resume_pulse || resume_hold) begin
        // 所有 resume（含普通 resume）都冲刷 IF-ID/ID-EX 并保持一拍：
        // reset halt 后 IF-ID 里是复位残留，普通 resume 若不冲刷会执行残留指令；
        // resume_hold 期间 if_id_stall 让 IF-ID 保持，等 BRAM 返回 dpc 的指令，
        // 避免把旧拍指令错误配对到新 dpc。
        if_id_stall     = 1'b1;
        if_id_flush     = 1'b1;
        id_ex_flush     = 1'b1;
    end else if (step_run_active) begin
        if_id_flush     = 1'b1;
        id_ex_flush     = 1'b1;
    end else if (step_drain_active) begin
        // Zcmp 展开期间抑制排水冲刷（微操作由 IF_ID 保持/重派发）
        if_id_flush     = step_drain_d & ~zcmp_busy;
        // During single-step drain, let the stepped instruction's own
        // effects redirect the PC:
        //  - trap (exception / mret): jump to mtvec/mepc and flush like
        //    the normal trap path (interrupts excluded - they must wait
        //    until after resume, matching dcsr.stepie=0);
        //  - taken branch/jump: redirect to the branch target.
        // Otherwise stepping such an instruction leaves dpc at X+4 and
        // the resume after OpenOCD's watchpoint dance executes the wrong
        // address (e.g. a gap of zeros after `j _start`).
        if (trap_jump_exc) begin
            if_id_flush    = 1'b1;
            id_ex_flush    = (sel_stage >= 2'd1);
            ex_mem_flush   = (sel_stage >= 2'd2);
            // ctrl_jump 由下一拍的 r_trap_redirect 分支发出（trap 重定向统一打一拍）
        end else if (r_trap_redirect) begin
            if_id_flush    = 1'b1;
            id_ex_flush    = 1'b1;
            ex_mem_flush   = 1'b1;
            ctrl_jump_en   = 1'b1;
            ctrl_jump_addr = r_trap_addr;
        end else if (branch_jump_en) begin
            ctrl_jump_en   = 1'b1;
            ctrl_jump_addr = branch_jump_addr;
        end
    end else if (r_trap_redirect) begin
        // 寄存后的 trap 重定向拍：当拍多取的顺延指令全部冲刷。
        // 优先级高于 waiting_int/oitf_stall/branch 等分支，保证跳转不被吃掉。
        if_id_flush     = 1'b1;
        id_ex_flush     = 1'b1;
        ex_mem_flush    = r_trap_flush_mem;
        ctrl_jump_en    = 1'b1;
        ctrl_jump_addr  = r_trap_addr;
    end else if (waiting_int && ~ex_access_en) begin
        // WFI 睡眠冻结：但 EX 级若有在途访存（access_en_ex=1），必须先放行一拍让
        // 该访问正常提交（rvalid），否则唤醒后该 load 用端口残留数据写回（bug 2026-09-11）。
        // 次拍 access_en_ex=0 后重新冻结，wfi 语义不变。
        if_id_stall     = 1'b1;
        id_ex_stall     = 1'b1;
        ex_mem_stall    = 1'b1;
        mem_wb_stall    = 1'b1;
    end else if (trap_jump || int_accept_kill) begin
        // trap 当拍完成冲刷与 CSR 采样，PC 跳转延迟一拍。
        // 中断（接受拍 int_accept_kill 与 int_trap_jump 拍动作相同）：冲 IF_ID+ID_EX+EX_MEM，
        // 边界指令（EX 级）连同其 EX 结果一并冲掉，PC 已由 CSR 锁存进 mepc，mret 后重执行；
        // EX_MEM 的更老指令同拍已进 MEM_WB 照常提交（ex_mem_flush 不损失任何提交）。
        // 【2026-09-12 SERR 根因修复】原实现 ex_mem_flush=0（只冲 IF_ID+ID_EX）：边界指令
        // 的 EX 结果仍泄漏进 EX_MEM 完成写回（第一次提交），mret 后又按 mepc 重执行
        // （第二次提交）——非幂等指令（如 addi s0,s0,1768）状态被双重累加：
        // tidle 的 s0=0x226e8+1768=0x22dd0 → defunct 读野指针 → SERR。
        // 异常（trap_jump_exc=1）有故障指令级，按 sel_stage 部分冲刷。
        if_id_flush = 1'b1;
        if (trap_jump_exc) begin
            id_ex_flush  = (sel_stage >= 2'd1);
            ex_mem_flush = (sel_stage >= 2'd2);
        end else begin
            id_ex_flush  = 1'b1;
            ex_mem_flush = 1'b1;
        end
    end else if (mem_split_stall) begin
        // 非对齐拆分访问：停 IF/ID/EX_MEM，保持 EX 级访存参数与 EX_MEM 中的 rd；
        // 不停 MEM_WB，保证 P3 合并拍能正常写回
        if_id_stall     = 1'b1;
        id_ex_stall     = 1'b1;
        ex_mem_stall    = 1'b1;
    end else if (oitf_stall) begin
        if_id_stall     = 1'b1;
        id_ex_stall     = 1'b1;
        ex_mem_stall    = 1'b1;
        mem_wb_stall    = 1'b1;
    end else if (branch_jump_en) begin
        if_id_flush  = 1'b1;
        id_ex_flush  = (sel_stage >= 2'd1);
        ctrl_jump_en = 1'b1;
        ctrl_jump_addr = branch_jump_addr;
    end else if (itcm_data_stall_d & ~zcmp_busy) begin
        // ITCM 单端口：数据返回拍禁止 IF_ID 捕获（取指在访问拍已停 PC），并冲刷 ID_EX：
        // IF_ID 保持时 ID 内容若继续被派发会重复执行；冲刷后下拍再正常派发（仅一次）。
        // 不能用 id_ex_stall：会把刚派发还未离开 EX 的长指令冻在 EX，
        // 触发 OITF RAW/WAW 对自身条目的自匹配死锁。
        // 注意必须位于 oitf_stall / branch_jump_en 之后：OITF 停顿需要 EX_MEM/MEM_WB 全停，
        // 分支冲刷需优先于让路，否则会被本分支抢先而丢失
        if_id_stall     = 1'b1;
        id_ex_flush     = 1'b1;
    end else if (~bus_ready) begin
        if_id_stall     = 1'b1;
        id_ex_flush     = 1'b1;
        ex_mem_flush    = 1'b1;
    end else if (load_use_flag) begin
        if_id_stall     = 1'b1;
        id_ex_flush     = 1'b1;
    end
end

// Debug halted 确认：halt 请求有效（含 step 完成 / trigger 命中）+ OITF 排空 + 总线空闲
// SBA 外设总线访问期间 bus_ready 为 0（总线忙），此时仍视为 halt 保持
assign dbg_halted = (dbg_halt_eff || step_halt || trigger_eff || ebreak_halt) && !oitf_stall && (bus_ready || sba_bus_active);

`ifndef SYNTHESIS
// ===========================================================================
// SVA: 中断接受拍冲刷契约（2026-09 中断边界语义修复的防线）
// 契约：接受拍冲 IF_ID+ID_EX（边界指令死在 ID_EX，mepc 已锁存其 PC），
//       EX_MEM 不冲（更老指令照常提交）。动作若与契约背离立即触发。
// ===========================================================================
// 1) 接受拍必须冲 IF_ID（无论是否与异常同拍重叠）
a_accept_kill_ifid: assert property (
    @(posedge clk) disable iff (!rst_n)
    (int_accept_kill |-> if_id_flush));
// 2) 纯中断接受拍（无异常重叠）：冲 ID_EX+EX_MEM（边界指令连 EX 结果一并冲，
//    防止其写回泄漏 + mret 重执行的双重提交【2026-09-12 SERR 根因】）
a_accept_kill_flush: assert property (
    @(posedge clk) disable iff (!rst_n)
    ((int_accept_kill && !trap_jump_exc) |->
     (id_ex_flush && ex_mem_flush)));
`endif

endmodule
