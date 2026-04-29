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

`timescale 1ns / 1ps
module Dynamic_Branch_Predictor #(
    parameter ADDR_WIDTH = `ADDR_WIDTH, // 地址宽度
    parameter DATA_WIDTH = `DATA_WIDTH,  // 数据宽度
    parameter ALIGN_WIDTH = `ALIGN_WIDTH, // 字节对齐宽度
    parameter BTB_ENTRIES = 256,        // BTB表项数 (必须为2的幂)
    parameter PHT_ENTRIES = 128,        // PHT表项数 (必须为2的幂)
    parameter RAS_DEPTH = 8,            // 返回地址堆栈深度
    localparam GHR_WIDTH = $clog2(PHT_ENTRIES),            // 全局历史寄存器宽度
    localparam PC_HASH_WIDTH = GHR_WIDTH, // PC哈希宽度
    localparam BTB_ADDR_WIDTH = $clog2(BTB_ENTRIES),
    localparam PHT_ADDR_WIDTH = $clog2(PHT_ENTRIES),
    localparam RAS_ADDR_WIDTH = $clog2(RAS_DEPTH),
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH,
    localparam BTB_TAG_WIDTH = BLOCK_SIZE_WIDTH - ALIGN_WIDTH,// Tag宽度 16-2
    localparam BTB_BTA_WIDTH = BLOCK_SIZE_WIDTH - ALIGN_WIDTH,// branch target address宽度 16-2
    localparam RAS_DATA_WIDTH = BLOCK_SIZE_WIDTH - ALIGN_WIDTH// 堆栈数据宽度 16-2

)(
    // 时钟和复位
    input   logic                       clk,
    input   logic                       rst_n,

    // 控制信号
    input   logic                       is_fence_i,
    input   logic                       stall,

    // From IF
    input   logic   [ADDR_WIDTH-1:0]    pc,                 // IF阶段的PC

    // From EX
    input   logic   [ADDR_WIDTH-1:0]    branch_pc,          // 分支指令PC
    input   logic                       branch_taken,       // 实际分支跳转方向
    input   logic   [ADDR_WIDTH-1:0]    branch_target,      // 实际分支目标跳转地址
    input   logic                       branch_req,         // 是否为分支和跳转指令
    input   logic                       branch_predict_success, // 预测结果正确
    input   logic   [1:0]               branch_inst_type,   // 指令类型 (00:非跳转指令, 01:B, 10:JAL, 11:JALR)
    input   logic                       push_ras,   // call
    input   logic                       pop_ras,     // ret

    // To IF
    output  logic                       predict_taken,      // 预测的跳转方向
    output  logic   [ADDR_WIDTH-1:0]    predict_target     // 预测的目标地址


);

// 2bit饱和计数器状态定义
typedef enum logic [1:0] {
    STRONGLY_NOT_TAKEN,// 强烈不跳转
    WEAKLY_NOT_TAKEN  ,// 弱不跳转
    WEAKLY_TAKEN      ,// 弱跳转
    STRONGLY_TAKEN     // 强烈跳转
} state_2bit_cnt;

typedef enum logic [1:0] {
    BRANCH_INST_TYPE_NON,
    BRANCH_INST_TYPE_B,
    BRANCH_INST_TYPE_JAL,
    BRANCH_INST_TYPE_JALR
} branch_inst_type_t;

// typedef enum logic [1:0] {
//     BRANCH_JUMP_TYPE_NON,
//     BRANCH_JUMP_TYPE_JMP,
//     BRANCH_JUMP_TYPE_CALL,
//     BRANCH_JUMP_TYPE_RET
// } branch_jump_type_t;

// BTB相关信号
(* RAM_STYLE="distributed"*) logic [BTB_TAG_WIDTH-1:0]  btb_tag_array [BTB_ENTRIES-1:0];      // BTB中存储的PC
(* RAM_STYLE="distributed"*) logic [BTB_BTA_WIDTH-1:0]  btb_target_array [BTB_ENTRIES-1:0];  // BTB中存储的目标地址
logic                   btb_valid_array [BTB_ENTRIES-1:0];                           // BTB有效标志
logic [1:0]             btb_inst_type_array [BTB_ENTRIES-1:0];     // BTB中存储的指令类
logic                   btb_push_ras_array [BTB_ENTRIES-1:0];      // BTB中存储的push_ras
logic                   btb_pop_ras_array [BTB_ENTRIES-1:0];       // BTB中存储的pop_ras

// PHT相关信号
logic [1:0]             pht_array [PHT_ENTRIES-1:0];         // PHT中的2bit饱和计数器
logic [PC_HASH_WIDTH-1:0] pc_hash;    // PC哈希值

// 全局历史寄存器 (GHR)：推测 GHR + 真实 GHR
logic [GHR_WIDTH-1:0]   spec_global_history;         // 推测全局历史 (IF 预测用)
logic [GHR_WIDTH-1:0]   real_global_history;          // 真实全局历史 (EX 更新用)
logic [GHR_WIDTH-1:0]   spec_global_history_next;

// RAS：推测RAS + 真实RAS
(* RAM_STYLE="distributed"*)logic [RAS_DATA_WIDTH-1:0] ras_stack [RAS_DEPTH-1:0];           // 返回地址堆栈
logic [RAS_ADDR_WIDTH:0] spec_ras_ptr;                 // 推测 RAS 指针
logic [RAS_ADDR_WIDTH:0] real_ras_ptr;                 // 真实 RAS 指针
logic [RAS_ADDR_WIDTH:0] spec_ras_ptr_next;
logic [RAS_ADDR_WIDTH:0] real_ras_ptr_next;
logic                    ras_full;                           // RAS满标志
logic                    ras_empty;                          // RAS空标志

// 预测阶段信号 Read
logic [BTB_ADDR_WIDTH-1:0] predict_btb_idx;                  // 预测时的BTB索引
logic [PHT_ADDR_WIDTH-1:0] predict_pht_idx;                  // 预测时的PHT索引
logic [1:0]                predict_2bit_cnt;                 // 预测时的2bit计数器
logic                      predict_pht_taken;
logic                      predict_btb_hit;             // 组合逻辑BTB命中

// 更新阶段信号 Write
logic [BTB_ADDR_WIDTH-1:0] update_btb_idx;                   // 更新时的BTB索引
logic [PHT_ADDR_WIDTH-1:0] update_pht_idx;                   // 更新时的PHT索引
logic [PC_HASH_WIDTH-1:0]  update_pc_hash;                   // 更新时的PC哈希值

// 预测时的索引计算
// BTB索引: 使用PC的低位
assign predict_btb_idx = pc[BTB_ADDR_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH];

// PHT索引: 使用Gshare算法 (PC哈希 XOR 全局历史)
// 步骤1: PC哈希 - 将PC的多个位段进行XOR折叠
// 这样可以充分利用PC的高位信息，避免不同内存区域的分支冲突
// assign pc_hash = pc[PC_HASH_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH] ^
//                  pc[2*PC_HASH_WIDTH+ALIGN_WIDTH-1:PC_HASH_WIDTH+ALIGN_WIDTH] ^
//                  pc[3*PC_HASH_WIDTH+ALIGN_WIDTH-1:2*PC_HASH_WIDTH+ALIGN_WIDTH];
assign pc_hash = pc[PC_HASH_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH] ^
                 pc[2*PC_HASH_WIDTH+ALIGN_WIDTH-1:PC_HASH_WIDTH+ALIGN_WIDTH];
// 步骤2: PHT索引 = PC哈希 XOR GHR
// 这实现了标准的Gshare算法
assign predict_pht_idx = pc_hash ^ spec_global_history;

// 更新时的索引计算
assign update_btb_idx = branch_pc[BTB_ADDR_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH];
assign update_pc_hash = branch_pc[PC_HASH_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH] ^
                        branch_pc[2*PC_HASH_WIDTH+ALIGN_WIDTH-1:PC_HASH_WIDTH+ALIGN_WIDTH];
assign update_pht_idx = {update_pc_hash ^ real_global_history};

// BTB查询: 检查PC是否在BTB中
assign predict_btb_hit = btb_valid_array[predict_btb_idx] && 
                        (btb_tag_array[predict_btb_idx] == pc[BTB_TAG_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH]);

// PHT查询: 获取2bit饱和计数器
assign predict_2bit_cnt = pht_array[predict_pht_idx];
assign predict_pht_taken = predict_2bit_cnt[1];

// 预测跳转方向
// 对于B指令: 根据2bit计数器预测
// 对于JAL/JALR指令: 总是预测跳转
assign predict_taken =  predict_btb_hit && 
                        ((predict_pht_taken && btb_inst_type_array[predict_btb_idx] == BRANCH_INST_TYPE_B) || 
                        btb_inst_type_array[predict_btb_idx][1]);

// 预测目标地址
// 对于RET指令: 从RAS获取返回地址
// 对于其他指令: 从BTB获取目标地址
assign predict_target = predict_btb_hit ? // 命中BTB?
                        (btb_pop_ras_array[predict_btb_idx] ? // RET指令？
                        {pc[ADDR_WIDTH-1:ALIGN_WIDTH+BTB_TAG_WIDTH],ras_stack[spec_ras_ptr-1],{ALIGN_WIDTH{1'b0}}} :  // RET: 从RAS取
                        ((predict_pht_taken && btb_inst_type_array[predict_btb_idx] == BRANCH_INST_TYPE_B) || 
                        btb_inst_type_array[predict_btb_idx][1]) ? // 非RET指令，且跳转
                        {pc[ADDR_WIDTH-1:ALIGN_WIDTH+BTB_BTA_WIDTH],btb_target_array[predict_btb_idx],{ALIGN_WIDTH{1'b0}}} : 0): // 从BTB取(预测为不跳时直接取0，因为EX阶段不跳时也取0，原因是暂停时或者刚开始时EX阶段的PC为0)
                        0;// 其他

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位: 初始化所有PHT表项为"弱不跳转"
        for (int i = 0; i < PHT_ENTRIES; i++) begin
            pht_array[i] <= #1 WEAKLY_NOT_TAKEN;
        end
    end else if (ghr_pht_update_en_latched) begin
        case (pht_array[pht_update_idx_latched])
            STRONGLY_NOT_TAKEN: begin
                // 00 -> 01 (如果跳转) 或 00 (如果不跳转)
                pht_array[pht_update_idx_latched] <= #1 pht_update_taken_latched ? WEAKLY_NOT_TAKEN : STRONGLY_NOT_TAKEN;
            end
            WEAKLY_NOT_TAKEN: begin
                // 01 -> 10 (如果跳转) 或 00 (如果不跳转)
                pht_array[pht_update_idx_latched] <= #1 pht_update_taken_latched ? WEAKLY_TAKEN : STRONGLY_NOT_TAKEN;
            end
            WEAKLY_TAKEN: begin
                // 10 -> 11 (如果跳转) 或 01 (如果不跳转)
                pht_array[pht_update_idx_latched] <= #1 pht_update_taken_latched ? STRONGLY_TAKEN : WEAKLY_NOT_TAKEN;
            end
            STRONGLY_TAKEN: begin
                // 11 -> 11 (如果跳转) 或 10 (如果不跳转)
                pht_array[pht_update_idx_latched] <= #1 pht_update_taken_latched ? STRONGLY_TAKEN : WEAKLY_TAKEN;
            end
            default: begin
                ;
            end
        endcase
    end
end

// ========================================================================
// BTB 更新请求与数据锁存
// 目的：将 37 级 LUT 的长组合逻辑从 FDCE 的 CE 引脚移除。
// 机制：在 !stall 时捕获 branch_req && branch_taken 及全部更新数据，
//       下一拍无条件执行更新。更新后使能自动清零。
// 注意：必须同时锁存数据和使能，否则 update_btb_idx 等信号在下一拍
//       变化会导致写入错误的 BTB 条目，造成预测永远失败。
// ========================================================================

logic btb_update_en_latched;
logic [BTB_ADDR_WIDTH-1:0] btb_update_idx_latched;
logic [BTB_TAG_WIDTH-1:0]  btb_update_tag_latched;
logic [BTB_BTA_WIDTH-1:0]  btb_update_target_latched;
logic [1:0]                btb_update_type_latched;
logic                      btb_update_pop_ras_latched;
logic                      btb_update_push_ras_latched;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || is_fence_i) begin
        btb_update_en_latched <= 1'b0;
    end else if (btb_update_en_latched) begin
        // 上一拍捕获的更新请求在本拍执行，执行后清零
        btb_update_en_latched <= 1'b0;
    end else if (!stall) begin
        // 无待处理请求且当前不 stall，捕获新的更新请求和数据
        btb_update_en_latched <= branch_req && branch_taken;
        btb_update_idx_latched     <= update_btb_idx;
        btb_update_tag_latched     <= branch_pc[BTB_TAG_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH];
        btb_update_target_latched  <= branch_target[BTB_BTA_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH];
        btb_update_type_latched    <= branch_inst_type;
        btb_update_pop_ras_latched <= pop_ras;
        btb_update_push_ras_latched<= push_ras;
    end
end

// ========================================================================
// 时序逻辑: BTB更新（使用锁存的使能和数据）
// ========================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || is_fence_i) begin//fence.i后不再使用旧的跳转属性
        // 复位: 清空所有BTB表项
        for (int i = 0; i < BTB_ENTRIES; i++) begin
            btb_valid_array[i]      <= #1 1'b0;
            btb_tag_array[i]        <= #1 'h0;
            btb_target_array[i]     <= #1 'h0;
            btb_inst_type_array[i]  <= #1 2'b00;
            btb_push_ras_array[i]   <= #1 1'b0;
            btb_pop_ras_array[i]    <= #1 1'b0;
        end
    end else if (btb_update_en_latched) begin//使用锁存的使能信号更新BTB
        // 更新BTB表项（使用锁存的数据，避免信号变化导致写入错误位置）
        btb_valid_array[btb_update_idx_latched]     <= #1 1'b1;
        btb_tag_array[btb_update_idx_latched]       <= #1 btb_update_tag_latched;
        btb_target_array[btb_update_idx_latched]    <= #1 btb_update_target_latched;
        btb_inst_type_array[btb_update_idx_latched] <= #1 btb_update_type_latched;
        btb_pop_ras_array[btb_update_idx_latched]   <= #1 btb_update_pop_ras_latched;
        btb_push_ras_array[btb_update_idx_latched]  <= #1 btb_update_push_ras_latched;
    end
end



// ========================================================================
// GHR + PHT 更新请求与数据锁存
// 目的：将 real_global_history_next 的组合逻辑路径从关键时序路径中移除，
//       与 BTB 更新锁存采用相同模式：捕获1拍、下一拍执行。
// 机制：在 !stall 时捕获 B 类分支的 GHR/PHT 更新请求及全部数据，
//       下一拍无条件执行更新。更新后使能自动清零。
// 注意：必须同时锁存数据和使能，否则 update_pht_idx 等信号在下一拍
//       变化会导致写入错误的 PHT 条目。
// ========================================================================

logic                      ghr_pht_update_en_latched;
logic [GHR_WIDTH-1:0]      ghr_update_value_latched;
logic [PHT_ADDR_WIDTH-1:0] pht_update_idx_latched;
logic                      pht_update_taken_latched;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || is_fence_i) begin
        ghr_pht_update_en_latched <= 1'b0;
    end else if (ghr_pht_update_en_latched) begin
        // 上一拍捕获的更新请求在本拍执行，执行后清零
        ghr_pht_update_en_latched <= 1'b0;
    end else if (!stall && branch_req && branch_inst_type == BRANCH_INST_TYPE_B) begin
        // 无待处理请求且当前不 stall，捕获新的 GHR/PHT 更新请求和数据
        ghr_pht_update_en_latched <= 1'b1;
        ghr_update_value_latched  <= {real_global_history[GHR_WIDTH-2:0], branch_taken};
        pht_update_idx_latched    <= update_pht_idx;
        pht_update_taken_latched  <= branch_taken;
    end
end

//========================================================================
// REAL RAS 指针 next 计算 (EX 阶段)
//========================================================================
assign ras_full  = (real_ras_ptr == RAS_DEPTH);
assign ras_empty = (real_ras_ptr == 0);

always_comb begin
    real_ras_ptr_next = real_ras_ptr;
    case ({push_ras, pop_ras})
        2'b10: real_ras_ptr_next = ras_full ? 0 : real_ras_ptr + 1;
        2'b01: real_ras_ptr_next = ras_empty ? RAS_DEPTH : real_ras_ptr - 1;
        default: real_ras_ptr_next = real_ras_ptr;
    endcase
end

//========================================================================
// SPEC RAS 指针 next 计算 (IF阶段，预测错误直接用 real 计算)
//========================================================================
always_comb begin
    if (!branch_predict_success && branch_req) begin // 预测错误
        spec_ras_ptr_next = real_ras_ptr_next;
    end else if (predict_btb_hit) begin // 预测成功
        // 正常预测更新
        case ({btb_push_ras_array[predict_btb_idx], btb_pop_ras_array[predict_btb_idx]})
            2'b10: spec_ras_ptr_next = (spec_ras_ptr == RAS_DEPTH) ? 0 : spec_ras_ptr + 1;
            2'b01: spec_ras_ptr_next = (spec_ras_ptr == 0) ? RAS_DEPTH : spec_ras_ptr - 1;
            default: spec_ras_ptr_next = spec_ras_ptr;
        endcase
    end else begin
        spec_ras_ptr_next = spec_ras_ptr;
    end
end

//========================================================================
// SPEC GHR next
// 注意：预测错误时使用 real_global_history（寄存器输出）而非组合逻辑
// 的 real_global_history_next，以切断关键时序路径。
// 这意味着预测错误恢复后 spec GHR 少移入1位当前分支结果，
// 下一拍 real_global_history 通过锁存更新后自然纠正。
//========================================================================
always_comb begin
    if (!branch_predict_success && branch_req) begin// 预测错误
        spec_global_history_next = real_global_history;
    end else if (predict_btb_hit && btb_inst_type_array[predict_btb_idx] == BRANCH_INST_TYPE_B) begin // 预测成功
        spec_global_history_next = {spec_global_history[GHR_WIDTH-2:0], predict_taken};
    end else begin
        spec_global_history_next = spec_global_history;
    end
end

//========================================================================
// 时序：更新 SPEC GHR + SPEC RAS 指针 + 栈
//========================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        spec_global_history <= #1 '0;
        spec_ras_ptr        <= #1 '0;
    end else if (!stall) begin
        spec_global_history <= #1 spec_global_history_next;
        spec_ras_ptr        <= #1 spec_ras_ptr_next;
    end
end

//========================================================================
// 时序：更新 REAL GHR（使用锁存的使能和数据，延迟1拍更新）
//========================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        real_global_history <= #1 '0;
    end else if (ghr_pht_update_en_latched) begin
        real_global_history <= #1 ghr_update_value_latched;
    end
end

//========================================================================
// 时序：更新 REAL RAS
//========================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        real_ras_ptr <= #1 '0;
    end else if (!stall) begin
        real_ras_ptr <= #1 real_ras_ptr_next;
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (int i=0; i<RAS_DEPTH; i++) ras_stack[i] <= #1 '0;
    end else if (!stall) begin
        if (push_ras) begin
            ras_stack[real_ras_ptr_next] <= #1 branch_pc[RAS_ADDR_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH] + 1;
        end else if (predict_btb_hit && btb_push_ras_array[predict_btb_idx]) begin// 推测压栈
            ras_stack[spec_ras_ptr_next] <= #1 pc[RAS_ADDR_WIDTH+ALIGN_WIDTH-1:ALIGN_WIDTH] + 1;
        end
    end
end

endmodule
