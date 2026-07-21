`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
// =============================================================================
// Pipeline_Ctrl - 流水线控制（4级流水线精简版）
// =============================================================================
// 已合并 EX/MEM 阶段，不再有 ex_mem_stall/flush
// 异常优先级：IF → ID → EX（访存异常在 EX 级检测）
// =============================================================================
module Pipeline_Ctrl #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH
)(
    input   logic                       clk,
    // from EX/MEM
    input   logic                       branch_jump_en,
    input   logic   [ADDR_WIDTH-1:0]    branch_jump_addr,
    // from CSR
    input   logic                       trap_jump,
    input   logic   [ADDR_WIDTH-1:0]    trap_jump_addr,
    input   logic   [1:0]               priv_mode,
    input   logic                       waiting_int,
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

always_comb begin
    pc_stall        = 1'b0;
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
    if (waiting_int) begin
        pc_stall        = 1'b1;
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
        pc_stall        = 1'b1;
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
        pc_stall        = 1'b1;
        if_id_stall     = 1'b1;
        id_ex_flush     = 1'b1;
        ex_mem_flush    = 1'b1;
    end else if (load_use_flag) begin
        pc_stall        = 1'b1;
        if_id_stall     = 1'b1;
        id_ex_flush     = 1'b1;
    end
end



endmodule
