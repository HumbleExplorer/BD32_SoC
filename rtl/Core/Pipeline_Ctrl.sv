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
    // from Forward
    input   logic                       load_use_flag,
    // from EX
    input   logic                       bus_ready,
    input   logic                       oitf_stall,
    input   logic                       reg_rd_wen_wb,      // WB 阶段写寄存器
    // from IF/ID/EX
    (* MAX_FANOUT = 16 *)input   logic   [ADDR_WIDTH-1:0]    inst_addr_if,
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
begin
    get_priority = {4{1'b1}};
    case(stage)
        2'd0: begin // IF阶段
            case(code)
                4'd0: get_priority = 4'd4;//指令地址未对齐
                4'd1: get_priority = 4'd2;//指令访问错误
            endcase
        end
        2'd1: begin // ID阶段
            case(code)
                4'd2: get_priority = 4'd3; // 非法指令
                4'd3: get_priority = 4'd6; // 环境断点
                4'd8,4'd9,4'd11: get_priority = 4'd5; // 环境调用
            endcase
        end
        2'd2: begin // EX阶段（含访存异常）
            case(code)
                4'd2: get_priority = 4'd3; // 非法指令CSR
                4'd5,4'd7: get_priority = 4'd10; // 访存错误
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
                if (bus_ready && !oitf_stall)
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

// 高优先级 stall（仅依赖寄存器信号，路径极短）
wire hp_stall = (dbg_halt_req | step_halt | trigger_match | ebreak_halt)
              | (dbg_resume_pulse & dbg_step)
              | resume_hold
              | step_run_active
              | (step_drain_active & step_drain_d)
              | waiting_int;

// 低优先级 stall（来自数据通路，但不再被 trap/branch 屏蔽）
wire lp_stall = oitf_stall | ~bus_ready | load_use_flag;

// step_drain_release 期间强制释放 PC（覆盖 lp_stall）
assign pc_stall = (hp_stall | lp_stall) & ~step_drain_release;

// =========================================================================
// 流水线 flush/stall + 跳转：保持优先级结构（无长时序路径问题）
// =========================================================================
always_comb begin
    ctrl_jump_en    = 1'b0;
    if_id_stall     = 1'b0;
    if_id_flush     = 1'b0;
    id_ex_stall     = 1'b0;
    id_ex_flush     = 1'b0;
    ex_mem_stall    = 1'b0;
    ex_mem_flush    = 1'b0;
    mem_wb_stall    = 1'b0;
    mem_wb_flush    = 1'b0;
    ctrl_jump_addr  = `BOOT_BASE_TAG;
    if (dbg_halt_req || step_halt || trigger_match) begin
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
        if_id_flush     = step_drain_d;
    end else if (waiting_int) begin
        if_id_stall     = 1'b1;
        id_ex_stall     = 1'b1;
        ex_mem_stall    = 1'b1;
        mem_wb_stall    = 1'b1;
    end else if(trap_jump) begin
        if_id_flush = 1'b1;
        id_ex_flush = (sel_stage >= 2'd1);
        ex_mem_flush = (sel_stage >= 2'd2);
        ctrl_jump_en = 1'b1;
        ctrl_jump_addr = trap_jump_addr;
    end else if (oitf_stall) begin
        if_id_stall     = 1'b1;
        id_ex_stall     = 1'b1;
        ex_mem_stall    = 1'b1;
        mem_wb_stall    = 1'b1;
    end else if (branch_jump_en) begin
        if_id_flush  = 1'b1;
        id_ex_flush  = 1'b1;
        ctrl_jump_en = 1'b1;
        ctrl_jump_addr = branch_jump_addr;
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
assign dbg_halted = (dbg_halt_req || step_halt || trigger_match || ebreak_halt) && !oitf_stall && (bus_ready || sba_bus_active);

endmodule
