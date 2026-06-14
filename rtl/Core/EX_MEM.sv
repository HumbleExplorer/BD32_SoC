`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
module EX_MEM #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
 )(
    input   logic                           clk,
    input   logic                           rst_n,
    input   logic                           stall,
    input   logic                           flush,
    // from execute
    input   logic   [ADDR_WIDTH-1:0]        inst_addr_i,
    input   logic   [DATA_WIDTH-1:0]        inst_i,
    input   logic                           reg_rd_wen_i,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rd_waddr_i,
    input   logic   [DATA_WIDTH-1:0]        reg_rd_wdata_i,
    input   logic                           lp_valid_i,        // 长指令门控：MUL/DIV 不写 ALU 路径
    input   logic                           access_en_i,
    input   logic                           access_wr_i,
    input   logic                           bus_sel,
`ifdef BRANCH_JUMP_DELAYED
    // ====================================================================
    // BRANCH_JUMP_DELAYED 模式下：
    //   输入：来自 Executer 的 branch_taken/branch_target/predict 等
    //   输出：MEM 阶段计算的 branch_jump_en/addr + 寄存的 branch 信号
    //         给到 Dynamic_Branch_Predictor（已寄存，切断组合路径）
    // ====================================================================
    // 分支预测所需输入（来自 ID_EX / Executer）
    input   logic   [ADDR_WIDTH-1:0]        inst_addr_plus_4_i,
    input   logic                           is_fence_i_i,
    input   logic                           predict_taken_i,
    input   logic   [ADDR_WIDTH-1:0]        predict_target_i,
    input   logic                           branch_taken_i,
    input   logic   [ADDR_WIDTH-1:0]        branch_target_i,
    input   logic                           branch_req_i,
    input   logic   [1:0]                   branch_inst_type_i,
    input   logic                           push_ras_i,
    input   logic                           pop_ras_i,

    // 寄存器输出（给 Dynamic_Branch_Predictor）
    output  logic                           is_fence_i_o,
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
    output  logic                           access_en_o,
    output  logic                           access_wr_o,
    // to wb
    output  logic                           reg_rd_wen_o,
    output  logic   [REG_ADDR_WIDTH-1:0]    reg_rd_waddr_o,
    output  logic   [DATA_WIDTH-1:0]        reg_rd_wdata_o

`ifdef ENABLE_HPM
    ,
    input   logic   [2:0]                   inst_type_i,
    output  logic   [2:0]                   inst_type_o,
    input   logic                           valid_i,
    output  logic                           valid_o
`endif
);

`ifdef BRANCH_JUMP_DELAYED

    // MEM 阶段组合逻辑
    logic predict_taken_r;
    logic [ADDR_WIDTH-1:0] predict_target_r;
    logic [ADDR_WIDTH-1:0] inst_addr_plus_4_r;
    assign branch_jump_en_o = ~branch_predict_success_o || is_fence_i_o;
    assign  branch_predict_success_o = (predict_taken_r == branch_taken_o) && (predict_target_r == branch_target_o);

    always_comb begin
        if (is_fence_i_o) begin
            branch_jump_addr_o = inst_addr_plus_4_r;
        end else if (branch_predict_success_o) begin
            branch_jump_addr_o = predict_target_r;
        end else if (branch_taken_o && ~predict_taken_r) begin
            branch_jump_addr_o = branch_target_o;
        end else if (~branch_taken_o && predict_taken_r) begin
            branch_jump_addr_o = inst_addr_plus_4_r;
        end else if (predict_target_r != branch_target_o) begin
            branch_jump_addr_o = branch_target_o;
        end else begin
            branch_jump_addr_o = inst_addr_plus_4_r;
        end
    end
`endif

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_o     <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 `INST_NOP;
        access_en_o     <= #1 1'b0;
        access_wr_o     <= #1 1'b0;
        reg_rd_wen_o    <= #1 1'b0;
        reg_rd_waddr_o  <= #1 'h0;
        reg_rd_wdata_o  <= #1 'h0;
`ifdef ENABLE_HPM
        inst_type_o     <= #1 3'd0;
`endif
`ifdef BRANCH_JUMP_DELAYED
        is_fence_i_o           <= #1 1'b0;
        predict_taken_r        <= #1 1'b0;
        predict_target_r       <= #1 '0;
        inst_addr_plus_4_r     <= #1 '0;
        branch_taken_o         <= #1 1'b0;
        branch_target_o        <= #1 '0;
        branch_req_o           <= #1 1'b0;
        branch_inst_type_o     <= #1 2'b00;
        push_ras_o             <= #1 1'b0;
        pop_ras_o              <= #1 1'b0;
`endif
    end else begin
        if(flush) begin
            inst_addr_o     <= #1 inst_addr_i;
            inst_o          <= #1 `INST_NOP;
            access_en_o     <= #1 1'b0;
            access_wr_o     <= #1 1'b0;
            reg_rd_wen_o    <= #1 1'b0;
            reg_rd_waddr_o  <= #1 'h0;
            reg_rd_wdata_o  <= #1 'h0;
`ifdef ENABLE_HPM
            inst_type_o     <= #1 3'd0;
`endif
        `ifdef BRANCH_JUMP_DELAYED
            is_fence_i_o           <= #1 1'b0;
            predict_taken_r        <= #1 1'b0;
            predict_target_r       <= #1 '0;
            inst_addr_plus_4_r     <= #1 '0;
            branch_taken_o         <= #1 1'b0;
            branch_target_o        <= #1 '0;
            branch_req_o           <= #1 1'b0;
            branch_inst_type_o     <= #1 2'b00;
            push_ras_o             <= #1 1'b0;
            pop_ras_o              <= #1 1'b0;
        `endif
        end else if(!stall) begin
            inst_addr_o     <= #1 inst_addr_i;
            inst_o          <= #1 inst_i;
            access_en_o     <= #1 access_en_i;
            access_wr_o     <= #1 access_wr_i;
            reg_rd_wen_o    <= #1 (bus_sel | lp_valid_i) ? 1'b0 : reg_rd_wen_i;
            reg_rd_waddr_o  <= #1 reg_rd_waddr_i;
            reg_rd_wdata_o  <= #1 reg_rd_wdata_i;
        `ifdef BRANCH_JUMP_DELAYED
            predict_taken_r        <= #1 predict_taken_i;
            predict_target_r       <= #1 predict_target_i;
            inst_addr_plus_4_r     <= #1 inst_addr_plus_4_i;
            branch_taken_o         <= #1 branch_taken_i;
            branch_target_o        <= #1 branch_target_i;
            branch_req_o           <= #1 branch_req_i;
            branch_inst_type_o     <= #1 branch_inst_type_i;
            push_ras_o             <= #1 push_ras_i;
            pop_ras_o              <= #1 pop_ras_i;
            is_fence_i_o           <= #1 is_fence_i_i;
        `endif
`ifdef ENABLE_HPM
            inst_type_o     <= #1 inst_type_i;
`endif
        end
    end
end

`ifdef ENABLE_HPM
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)                    valid_o <= #1 1'b0;
    else if(flush)                valid_o <= #1 1'b0;
    else if(!stall)               valid_o <= #1 valid_i;
end
`endif

endmodule
