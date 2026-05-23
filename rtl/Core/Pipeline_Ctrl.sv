`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
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
    // from EX
    input   logic                       branch_jump_en,
    input   logic   [ADDR_WIDTH-1:0]    branch_jump_addr,
    // from CSR
    input   logic                       trap_jump,
    input   logic   [ADDR_WIDTH-1:0]    trap_jump_addr,
    input   logic   [1:0]               priv_mode,
    // from Forward
    input   logic                       load_use_flag,
    // from EX
    input   logic                       mem_access_ready,
    input   logic                       mul_div_ready,
    // from IF/ID/EX
    (* MAX_FANOUT = 16 *)(* mark_debug = "true" *)input   logic   [ADDR_WIDTH-1:0]    inst_addr_if,
    (* MAX_FANOUT = 16 *)(* mark_debug = "true" *)input   logic   [ADDR_WIDTH-1:0]    inst_addr_id,
    (* MAX_FANOUT = 16 *)(* mark_debug = "true" *)input   logic   [ADDR_WIDTH-1:0]    inst_addr_ex,
    (* MAX_FANOUT = 16 *)(* mark_debug = "true" *)input   logic   [ADDR_WIDTH-1:0]    inst_addr_mem,
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
    // to CSR
    output  logic   [ADDR_WIDTH-1:0]    exception_inst_addr,
    (* MAX_FANOUT = 16 *)output  logic                       exception_trap,
    output  logic   [DATA_WIDTH-2:0]    exception_code,
    output  logic   [DATA_WIDTH-1:0]    exception_val,
    output  logic   [ADDR_WIDTH-1:0]    next_inst_addr
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

assign priority_if = exception_code_if[DATA_WIDTH-2] ? {4{1'b1}} : get_priority(2'd0, exception_code_if);
assign priority_id = exception_code_id[DATA_WIDTH-2] ? {4{1'b1}} : get_priority(2'd1, exception_code_id);
assign priority_ex = exception_code_ex[DATA_WIDTH-2] ? {4{1'b1}} : get_priority(2'd2, exception_code_ex);

always_comb begin
    min_priority = 4'd15;
    sel_stage = 2'd0;
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
            exception_code = exception_code_ex;
            exception_inst_addr = inst_addr_ex;
            exception_val = exception_val_ex;
        end
        2'd1: begin // ID阶段
            exception_code = exception_code_id;
            exception_inst_addr = inst_addr_id;
            exception_val = exception_val_id;
        end
        2'd0: begin // IF阶段
            exception_code = exception_code_if;
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

assign next_inst_addr = trap_jump ? trap_jump_addr :
                        branch_jump_en ? branch_jump_addr :
                        inst_addr_id;
assign exception_trap = ~(exception_code_if[DATA_WIDTH-2] && exception_code_id[DATA_WIDTH-2] && exception_code_ex[DATA_WIDTH-2]);

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
    if(trap_jump) begin
        if_id_flush = 1'b1;
        id_ex_flush = 1'b1;
        ex_mem_flush = 1'b1;
        ctrl_jump_en = 1'b1;
        ctrl_jump_addr = trap_jump_addr;
    end else if (branch_jump_en) begin
        if_id_flush  = 1'b1;
        id_ex_flush  = 1'b1;
    `ifdef BRANCH_JUMP_DELAYED
        ex_mem_flush = 1'b1;
    `endif 
        ctrl_jump_en = 1'b1;
        ctrl_jump_addr = branch_jump_addr;
    end else if (~mem_access_ready) begin
        pc_stall        = 1'b1;
        if_id_stall     = 1'b1;
        id_ex_stall     = 1'b1;
        ex_mem_stall    = 1'b1;
        mem_wb_stall    = 1'b1;
    end else if (load_use_flag) begin
        pc_stall        = 1'b1;
        if_id_stall     = 1'b1;
        id_ex_flush     = 1'b1;
    end else if (~mul_div_ready) begin
        pc_stall        = 1'b1;
        if_id_stall     = 1'b1;
        id_ex_stall     = 1'b1;
    end
end

endmodule
