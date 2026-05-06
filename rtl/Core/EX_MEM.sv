`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
module EX_MEM #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
 )( 
    input   logic                           clk,
    input   logic                           rst_n,
    input   logic                           stall,
    input   logic                           flush,
    // from execute
    input   logic   [ADDR_WIDTH-1:0]        inst_addr_i,
    input   logic   [DATA_WIDTH-1:0]        inst_i,
    input   logic                           wr_reg_en_i,
    input   logic   [REG_ADDR_WIDTH-1:0]    wr_reg_addr_i,
    input   logic   [DATA_WIDTH-1:0]        wr_reg_data_i,
    input   logic   [ADDR_WIDTH-1:0]        mem_addr_i,
    input   logic                           access_en_i,
    input   logic                           access_wr_i,
    input   logic   [2:0]                   rd_mem_func3_i,

    input   logic   [DATA_WIDTH-1:0]        wr_mem_data_i,
    input   logic   [ALIGN_BYTES-1:0]       wr_mem_mask_i,

`ifdef BRANCH_JUMP_DELAYED
    // ====================================================================
    // BRANCH_JUMP_DELAYED 模式下：
    //   输入：来自 Executer 的 branch_taken/branch_target/predict 等
    //   输出：MEM 阶段计算的 branch_jump_en/addr + 寄存的 branch 信号
    //         给到 Dynamic_Branch_Predictor（已寄存，切断组合路径）
    // ====================================================================
    // 分支预测所需输入（来自 ID_EX / Executer）
    input   logic                           predict_taken_i,
    input   logic   [ADDR_WIDTH-1:0]        predict_target_i,
    input   logic                           branch_taken_i,
    input   logic   [ADDR_WIDTH-1:0]        branch_target_i,
    input   logic                           branch_req_i,
    input   logic   [1:0]                   branch_inst_type_i,
    input   logic                           branch_predict_success_i,
    input   logic                           push_ras_i,
    input   logic                           pop_ras_i,
    input   logic                           is_fence_i,

    // 寄存器输出（给 Dynamic_Branch_Predictor）
    output  logic                           branch_taken_o,
    output  logic   [ADDR_WIDTH-1:0]        branch_target_o,
    output  logic                           branch_req_o,
    output  logic   [1:0]                   branch_inst_type_o,
    output  logic                           branch_predict_success_o,
    output  logic                           push_ras_o,
    output  logic                           pop_ras_o,
    // 到 Pipeline_Ctrl
    output  logic                           branch_jump_en_o,
    output  logic   [ADDR_WIDTH-1:0]        branch_jump_addr_o,
`endif

    // to mem
    output  logic   [ADDR_WIDTH-1:0]        inst_addr_o,
    output  logic   [DATA_WIDTH-1:0]        inst_o,
    output  logic   [ADDR_WIDTH-1:0]        mem_addr_o,
    output  logic                           access_en_o,
    output  logic                           access_wr_o,
    output  logic   [2:0]                   rd_mem_func3_o,
    output  logic   [DATA_WIDTH-1:0]        wr_mem_data_o,
    output  logic   [ALIGN_BYTES-1:0]       wr_mem_mask_o,
    // to wb
    output  logic                           wr_reg_en_o,
    output  logic   [REG_ADDR_WIDTH-1:0]    wr_reg_addr_o,
    output  logic   [DATA_WIDTH-1:0]        wr_reg_data_o
);

`ifdef BRANCH_JUMP_DELAYED
    // =========================================================================
    // 寄存器声明
    // =========================================================================
    logic                      predict_taken_r;
    logic [ADDR_WIDTH-1:0]     predict_target_r;
    logic                      branch_taken_r;
    logic [ADDR_WIDTH-1:0]     branch_target_r;
    logic                      branch_req_r;
    logic [1:0]                branch_inst_type_r;
    logic                      branch_predict_success_r;
    logic                      push_ras_r;
    logic                      pop_ras_r;
    logic                      is_fence_r;

    // MEM 阶段组合逻辑
    logic                      branch_jump_en_comb;
    logic [ADDR_WIDTH-1:0]     branch_jump_addr_comb;
    logic [ADDR_WIDTH-1:0]     inst_addr_plus_4_comb;

    assign inst_addr_plus_4_comb = inst_addr_o + 4;

    assign branch_jump_en_comb = ~branch_predict_success_r || is_fence_r;

    always_comb begin
        if (is_fence_r) begin
            branch_jump_addr_comb = inst_addr_plus_4_comb;
        end else if (branch_predict_success_r) begin
            branch_jump_addr_comb = predict_target_r;
        end else if (branch_taken_r && ~predict_taken_r) begin
            branch_jump_addr_comb = branch_target_r;
        end else if (~branch_taken_r && predict_taken_r) begin
            branch_jump_addr_comb = inst_addr_plus_4_comb;
        end else if (predict_target_r != branch_target_r) begin
            branch_jump_addr_comb = branch_target_r;
        end else begin
            branch_jump_addr_comb = inst_addr_plus_4_comb;
        end
    end
`endif

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_o     <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 `INST_NOP;
        mem_addr_o      <= #1 'h0;
        access_en_o     <= #1 1'b0;
        rd_mem_func3_o  <= #1 'h0;
        access_wr_o     <= #1 1'b0;
        wr_mem_data_o   <= #1 'h0;
        wr_mem_mask_o   <= #1 'h0;
        wr_reg_en_o     <= #1 1'b0;
        wr_reg_addr_o   <= #1 'h0;
        wr_reg_data_o   <= #1 'h0;
`ifdef BRANCH_JUMP_DELAYED
        predict_taken_r        <= #1 1'b0;
        predict_target_r       <= #1 '0;
        branch_taken_r         <= #1 1'b0;
        branch_target_r        <= #1 '0;
        branch_req_r           <= #1 1'b0;
        branch_inst_type_r     <= #1 2'b00;
        branch_predict_success_r <= #1 1'b1;
        push_ras_r             <= #1 1'b0;
        pop_ras_r              <= #1 1'b0;
        is_fence_r             <= #1 1'b0;
`endif
    end else if(flush) begin
        inst_addr_o     <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 `INST_NOP;
        mem_addr_o      <= #1 'h0;
        access_en_o     <= #1 1'b0;
        rd_mem_func3_o  <= #1 'h0;
        access_wr_o     <= #1 1'b0;
        wr_mem_data_o   <= #1 'h0;
        wr_mem_mask_o   <= #1 'h0;
        wr_reg_en_o     <= #1 1'b0;
        wr_reg_addr_o   <= #1 'h0;
        wr_reg_data_o   <= #1 'h0;
`ifdef BRANCH_JUMP_DELAYED
        predict_taken_r        <= #1 1'b0;
        predict_target_r       <= #1 '0;
        branch_taken_r         <= #1 1'b0;
        branch_target_r        <= #1 '0;
        branch_req_r           <= #1 1'b0;
        branch_inst_type_r     <= #1 2'b00;
        branch_predict_success_r <= #1 1'b1;
        push_ras_r             <= #1 1'b0;
        pop_ras_r              <= #1 1'b0;
        is_fence_r             <= #1 1'b0;
`endif
    end else if(!stall) begin
        inst_addr_o     <= #1 inst_addr_i;
        inst_o          <= #1 inst_i;
        mem_addr_o      <= #1 mem_addr_i;
        access_en_o     <= #1 access_en_i;
        rd_mem_func3_o  <= #1 rd_mem_func3_i;
        access_wr_o     <= #1 access_wr_i;
        wr_mem_data_o   <= #1 wr_mem_data_i;
        wr_mem_mask_o   <= #1 wr_mem_mask_i;
        wr_reg_en_o     <= #1 wr_reg_en_i;
        wr_reg_addr_o   <= #1 wr_reg_addr_i;
        wr_reg_data_o   <= #1 wr_reg_data_i;
`ifdef BRANCH_JUMP_DELAYED
        predict_taken_r        <= #1 predict_taken_i;
        predict_target_r       <= #1 predict_target_i;
        branch_taken_r         <= #1 branch_taken_i;
        branch_target_r        <= #1 branch_target_i;
        branch_req_r           <= #1 branch_req_i;
        branch_inst_type_r     <= #1 branch_inst_type_i;
        branch_predict_success_r <= #1 branch_predict_success_i;
        push_ras_r             <= #1 push_ras_i;
        pop_ras_r              <= #1 pop_ras_i;
        is_fence_r             <= #1 is_fence_i;
`endif
    end
end

`ifdef BRANCH_JUMP_DELAYED
// MEM 阶段组合输出
assign branch_jump_en_o  = branch_jump_en_comb;
assign branch_jump_addr_o = branch_jump_addr_comb;
// 寄存器输出给 Dynamic_Branch_Predictor
assign branch_taken_o         = branch_taken_r;
assign branch_target_o        = branch_target_r;
assign branch_req_o           = branch_req_r;
assign branch_inst_type_o     = branch_inst_type_r;
assign branch_predict_success_o = branch_predict_success_r;
assign push_ras_o             = push_ras_r;
assign pop_ras_o              = pop_ras_r;
`endif

endmodule
