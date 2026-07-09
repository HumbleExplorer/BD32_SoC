/*
================================================================================
  动态分支预测模块 (Dynamic Branch Predictor)
  
  功能描述:
  --------
  本模块实现了一个完整的动态分支预测系统，包含以下核心组件:
  
  1. 分支目标缓存 (BTB - Branch Target Buffer)
     - 用于缓存分支指令的PC和目标地址
     - 支持快速查询和更新
     - 采用直接映射或组相联方式
  
  2. 全局历史寄存器 (GHR - Global History Register)
     - 记录分支指令的历史跳转方向
     - 支持全局历史
  
  3. 模式历史表 (PHT - Pattern History Table)
     - 存储2bit饱和计数器，用于预测分支方向
     - 基于分支历史进行预测
  
  4. 返回地址堆栈 (RAS - Return Address Stack)
     - 用于预测JALR指令的返回地址
     - 支持压栈和出栈操作
  
  预测流程:
  --------
  1. IF阶段: 根据当前PC查询BTB和PHT
  2. 获得预测的目标地址和跳转方向
  3. 在执行阶段获得实际跳转结果后，更新预测表
  4. 如果预测错误，刷新流水线
  
  2bit饱和计数器状态转移:
  ----------------------
  00 (Strongly Not Taken) -> 01 (Weakly Not Taken) -> 10 (Weakly Taken) -> 11 (Strongly Taken)
  
  参数配置:
  --------
  - BTB_ENTRIES: BTB表项数 (通常为256-512) 直接相连
  - PHT_ENTRIES: PHT表项数 (通常为256-1024)
  - GHR_WIDTH: 全局历史寄存器宽度 (通常为8-16)
  - RAS_DEPTH: 返回地址堆栈深度 (通常为4-16)
  
================================================================================
*/

`include "../SoC_Config.sv"

timeunit 1ns;
timeprecision 1ps;
module Dynamic_Branch_Predictor #(
    parameter ADDR_WIDTH = `ADDR_WIDTH, // 地址宽度
    parameter DATA_WIDTH = `DATA_WIDTH,  // 数据宽度
    parameter ALIGN_WIDTH = `ALIGN_WIDTH, // 字节对齐宽度
    parameter BTB_ENTRIES = 128,        // BTB表项数
    parameter PHT_ENTRIES = 128,        // PHT表项数
    parameter RAS_DEPTH = 8,            // 返回地址堆栈深度
    localparam GHR_WIDTH = $clog2(PHT_ENTRIES),            // 全局历史寄存器宽度
    localparam PC_HASH_WIDTH = GHR_WIDTH, // PC哈希宽度
    localparam BTB_ADDR_WIDTH = $clog2(BTB_ENTRIES),
    localparam PHT_ADDR_WIDTH = $clog2(PHT_ENTRIES),
    localparam RAS_ADDR_WIDTH = $clog2(RAS_DEPTH),
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH,
    // BTB_TAG_WIDTH 减去 BTB_ADDR_WIDTH，避免 Tag 包含 Index
    localparam BTB_TAG_WIDTH = BLOCK_SIZE_WIDTH - ALIGN_WIDTH - BTB_ADDR_WIDTH,
    localparam BTB_BTA_WIDTH = BLOCK_SIZE_WIDTH - ALIGN_WIDTH,
    localparam RAS_DATA_WIDTH = BLOCK_SIZE_WIDTH - ALIGN_WIDTH

)(
    // 时钟和复位
    input   logic                       clk,
    input   logic                       rst_n,

    // 控制信号
    input   logic                       is_fence_i,
    input   logic                       stall,

    // From IF
    input logic [ADDR_WIDTH-1:0] inst_addr,  // IF阶段的PC

    // From EX
    input   logic   [ADDR_WIDTH-1:0]    branch_pc,          // 分支指令PC
    input   logic                       branch_taken,       // 实际分支跳转方向
    input   logic   [ADDR_WIDTH-1:0]    branch_target,      // 实际分支目标跳转地址
    input   logic                       branch_req,         // 是否为分支和跳转指令
    input   logic                       branch_predict_success, // 预测结果正确
    input   logic   [1:0]               branch_inst_type,   // 指令类型 (00:非跳转, 01:B, 10:JAL, 11:JALR)
    input   logic                       push_ras,   // call
    input   logic                       pop_ras,    // ret

    // To IF
    output  logic                       predict_taken,      // 预测的跳转方向
    output  logic   [ADDR_WIDTH-1:0]    predict_target     // 预测的目标地址
);

// 2bit饱和计数器状态定义
typedef enum logic [1:0] {
    STRONGLY_NOT_TAKEN,
    WEAKLY_NOT_TAKEN,
    WEAKLY_TAKEN,
    STRONGLY_TAKEN
} state_2bit_cnt;

typedef enum logic [1:0] {
    BRANCH_INST_TYPE_NON,
    BRANCH_INST_TYPE_B,
    BRANCH_INST_TYPE_JAL,
    BRANCH_INST_TYPE_JALR
} branch_inst_type_t;

// BTB相关信号
(* RAM_STYLE="distributed"*) logic [BTB_TAG_WIDTH-1:0]  btb_tag_array [BTB_ENTRIES-1:0];
(* RAM_STYLE="distributed"*) logic [BTB_BTA_WIDTH-1:0]  btb_target_array [BTB_ENTRIES-1:0];
logic                   btb_valid_array [BTB_ENTRIES-1:0];
logic   [1:0]           btb_inst_type_array [BTB_ENTRIES-1:0];
logic                   btb_push_ras_array [BTB_ENTRIES-1:0];
logic                   btb_pop_ras_array [BTB_ENTRIES-1:0];

// PHT相关信号
(* RAM_STYLE="distributed"*) logic [1:0]             pht_array [PHT_ENTRIES-1:0];
logic [PC_HASH_WIDTH-1:0] pc_hash;

// GHR：推测 GHR + 真实 GHR
logic [GHR_WIDTH-1:0]   spec_global_history;
logic [GHR_WIDTH-1:0]   real_global_history;
logic [GHR_WIDTH-1:0]   spec_global_history_next;
logic [GHR_WIDTH-1:0]   real_global_history_next;

// RAS：推测RAS + 真实RAS
(* RAM_STYLE="distributed"*)logic [RAS_DATA_WIDTH-1:0] ras_stack [RAS_DEPTH-1:0];
logic [RAS_ADDR_WIDTH:0] spec_ras_ptr;
logic [RAS_ADDR_WIDTH:0] real_ras_ptr;
logic [RAS_ADDR_WIDTH:0] spec_ras_ptr_next;
logic [RAS_ADDR_WIDTH:0] real_ras_ptr_next;

// 预测阶段信号
logic [BTB_ADDR_WIDTH-1:0] predict_btb_idx;
logic [PHT_ADDR_WIDTH-1:0] predict_pht_idx;
logic [1:0]                predict_2bit_cnt;
logic                      predict_pht_taken;
logic                      predict_btb_hit;

// 更新阶段信号
logic [BTB_ADDR_WIDTH-1:0] update_btb_idx;
logic [PHT_ADDR_WIDTH-1:0] update_pht_idx;
logic [PC_HASH_WIDTH-1:0]  update_pc_hash;

// ========================================================
// IF 阶段：预测逻辑
// ========================================================

assign predict_btb_idx = inst_addr[BTB_ADDR_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH];

assign pc_hash = inst_addr[PC_HASH_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH] ^
                 inst_addr[2*PC_HASH_WIDTH+ALIGN_WIDTH-1:PC_HASH_WIDTH+ALIGN_WIDTH];
assign predict_pht_idx = pc_hash ^ spec_global_history;

// BTB命中比对 (Tag跨过Index位)
assign predict_btb_hit = btb_valid_array[predict_btb_idx] && 
                        (btb_tag_array[predict_btb_idx] == inst_addr[BTB_TAG_WIDTH + BTB_ADDR_WIDTH + ALIGN_WIDTH - 1 : BTB_ADDR_WIDTH + ALIGN_WIDTH]);

assign predict_2bit_cnt = pht_array[predict_pht_idx];
assign predict_pht_taken = predict_2bit_cnt[1];

assign predict_taken =  predict_btb_hit && 
                        ((predict_pht_taken && btb_inst_type_array[predict_btb_idx] == BRANCH_INST_TYPE_B) || 
                        btb_inst_type_array[predict_btb_idx][1]);

wire [ADDR_WIDTH-1:0] predict_ras_target;
wire [ADDR_WIDTH-1:0] predict_btb_target;

// RAS 返回地址 (注意此处拼接使用了 BTB_BTA_WIDTH)
assign predict_ras_target = (predict_btb_hit && btb_pop_ras_array[predict_btb_idx]) ?
    {inst_addr[ADDR_WIDTH-1:ALIGN_WIDTH+BTB_BTA_WIDTH],ras_stack[spec_ras_ptr_next],{ALIGN_WIDTH{1'b0}}} : inst_addr + 4;

// BTB 目标地址
assign predict_btb_target = (predict_btb_hit &&
    ((predict_pht_taken && btb_inst_type_array[predict_btb_idx] == BRANCH_INST_TYPE_B) || 
    btb_inst_type_array[predict_btb_idx][1])) ?
    {inst_addr[ADDR_WIDTH-1:ALIGN_WIDTH+BTB_BTA_WIDTH],btb_target_array[predict_btb_idx],{ALIGN_WIDTH{1'b0}}} : inst_addr + 4;

assign predict_target = btb_pop_ras_array[predict_btb_idx] ? predict_ras_target : predict_btb_target;


// ========================================================
// EX 阶段：更新索引计算
// ========================================================

assign update_btb_idx = branch_pc[BTB_ADDR_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH];
assign update_pc_hash = branch_pc[PC_HASH_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH] ^
                        branch_pc[2*PC_HASH_WIDTH+ALIGN_WIDTH-1:PC_HASH_WIDTH+ALIGN_WIDTH];
assign update_pht_idx = {update_pc_hash ^ real_global_history};


// ========================================================
// EX 阶段：REAL 结构更新计算 (下一拍状态)
// ========================================================

// 1. Real GHR 更新 (仅 B 类分支)
always_comb begin
    if (!stall && branch_req && branch_inst_type == BRANCH_INST_TYPE_B) begin
        real_global_history_next = {real_global_history[GHR_WIDTH-2:0], branch_taken};
    end else begin
        real_global_history_next = real_global_history;
    end
end

// 2. Real RAS 指针更新
always_comb begin
    case ({push_ras, pop_ras})
        2'b10:   real_ras_ptr_next = (real_ras_ptr == RAS_DEPTH - 1) ? 0 : real_ras_ptr + 1;
        2'b01:   real_ras_ptr_next = (real_ras_ptr == 0) ? RAS_DEPTH - 1 : real_ras_ptr - 1;
        default: real_ras_ptr_next = real_ras_ptr;
    endcase
end


// ========================================================
// IF/EX 交互：SPEC 结构恢复与更新计算 (下一拍状态)
// ========================================================
// 优先级：EX 阶段的预测错误恢复 > IF 阶段的推测更新

// 1. Spec GHR 更新与恢复
always_comb begin
    if (!stall && branch_req && !branch_predict_success && branch_inst_type == BRANCH_INST_TYPE_B) begin
        // EX阶段发现预测错误，用真实结果覆盖推测结果
        spec_global_history_next = real_global_history_next;
    end else if (!stall && predict_btb_hit && btb_inst_type_array[predict_btb_idx] == BRANCH_INST_TYPE_B) begin
        // IF阶段正常推测更新
        spec_global_history_next = {spec_global_history[GHR_WIDTH-2:0], predict_pht_taken};
    end else begin
        spec_global_history_next = spec_global_history;
    end
end

// 2. Spec RAS 指针更新与恢复
always_comb begin
    if (!stall && branch_req && !branch_predict_success) begin
        // EX阶段发现预测错误，用真实结果覆盖推测结果
        spec_ras_ptr_next = real_ras_ptr_next;
    end else if (!stall && predict_btb_hit) begin
        // IF阶段正常推测更新
        case ({btb_push_ras_array[predict_btb_idx], btb_pop_ras_array[predict_btb_idx]})
            2'b10:   spec_ras_ptr_next = (spec_ras_ptr == RAS_DEPTH - 1) ? 0 : spec_ras_ptr + 1;
            2'b01:   spec_ras_ptr_next = (spec_ras_ptr == 0) ? RAS_DEPTH -1 : spec_ras_ptr - 1;
            default: spec_ras_ptr_next = spec_ras_ptr;
        endcase
    end else begin
        spec_ras_ptr_next = spec_ras_ptr;
    end
end


// ========================================================
// 时序逻辑：寄存器更新
// ========================================================

// 1. BTB 更新 (直接由 EX 阶段信号驱动)
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (int i = 0; i < BTB_ENTRIES; i++) begin
            btb_valid_array[i]      <= #1 1'b0;
`ifndef SYNTHESIS
            btb_tag_array[i]        <= #1 'h0;
            btb_target_array[i]     <= #1 'h0;
`endif
            btb_inst_type_array[i]  <= #1 BRANCH_INST_TYPE_NON;
            btb_push_ras_array[i]   <= #1 1'b0;
            btb_pop_ras_array[i]    <= #1 1'b0;
        end
    end else if (is_fence_i) begin
        // Fence.i 清空BTB
        for (int i = 0; i < BTB_ENTRIES; i++) begin
            btb_valid_array[i] <= #1 1'b0;
        end
    end else if (!stall && branch_req && branch_taken) begin
        btb_valid_array[update_btb_idx]     <= #1 1'b1;
        // Tag 提取跨过 Index
        btb_tag_array[update_btb_idx]       <= #1 branch_pc[BTB_TAG_WIDTH + BTB_ADDR_WIDTH + ALIGN_WIDTH - 1 : BTB_ADDR_WIDTH + ALIGN_WIDTH];
        btb_target_array[update_btb_idx]    <= #1 branch_target[BTB_BTA_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH];
        btb_inst_type_array[update_btb_idx] <= #1 branch_inst_type;
        btb_pop_ras_array[update_btb_idx]   <= #1 pop_ras;
        btb_push_ras_array[update_btb_idx]  <= #1 push_ras;
    end
end

// 2. PHT 更新 (直接由 EX 阶段信号驱动)
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (int i = 0; i < PHT_ENTRIES; i++) begin
            pht_array[i] <= #1 WEAKLY_NOT_TAKEN;
        end
    end else if (is_fence_i) begin
        for (int i = 0; i < PHT_ENTRIES; i++) begin
            pht_array[i] <= #1 WEAKLY_NOT_TAKEN;
        end
    end else if (!stall && branch_req && branch_inst_type == BRANCH_INST_TYPE_B) begin
        case (pht_array[update_pht_idx])
            STRONGLY_NOT_TAKEN: pht_array[update_pht_idx] <= #1 branch_taken ? WEAKLY_NOT_TAKEN  : STRONGLY_NOT_TAKEN;
            WEAKLY_NOT_TAKEN:   pht_array[update_pht_idx] <= #1 branch_taken ? WEAKLY_TAKEN      : STRONGLY_NOT_TAKEN;
            WEAKLY_TAKEN:       pht_array[update_pht_idx] <= #1 branch_taken ? STRONGLY_TAKEN    : WEAKLY_NOT_TAKEN;
            STRONGLY_TAKEN:     pht_array[update_pht_idx] <= #1 branch_taken ? STRONGLY_TAKEN    : WEAKLY_TAKEN;
            default: ;
        endcase
    end
end

// 3. GHR 寄存器更新
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        spec_global_history <= #1 '0;
        real_global_history <= #1 '0;
    end else if (is_fence_i) begin
        spec_global_history <= #1 '0;
        real_global_history <= #1 '0;
    end else if (!stall) begin
        spec_global_history <= #1 spec_global_history_next;
        real_global_history <= #1 real_global_history_next;
    end
end

// 4. RAS 指针寄存器更新
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        spec_ras_ptr <= #1 '0;
        real_ras_ptr <= #1 '0;
    end else if (is_fence_i) begin
        spec_ras_ptr <= #1 '0;
        real_ras_ptr <= #1 '0;
    end else if (!stall) begin
        spec_ras_ptr <= #1 spec_ras_ptr_next;
        real_ras_ptr <= #1 real_ras_ptr_next;
    end
end

// 5. RAS 栈内容更新
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (int i=0; i<RAS_DEPTH; i++) ras_stack[i] <= #1 '0;
    end else if (is_fence_i) begin
        for (int i=0; i<RAS_DEPTH; i++) ras_stack[i] <= #1 '0;
    end else begin
        // 优先处理 EX 阶段的真实写 (预测错误冲刷时也会写入)
        if (!stall && push_ras) begin
            ras_stack[real_ras_ptr] <= #1 branch_pc[RAS_DATA_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH] + 1;
        end else if (!stall && predict_btb_hit && btb_push_ras_array[predict_btb_idx]) begin
            // 如果没有 EX 阶段的写，则进行 IF 阶段的推测写
            ras_stack[spec_ras_ptr] <= #1 inst_addr[RAS_ADDR_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH] + 1;
        end
    end
end

endmodule
