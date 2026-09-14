// =============================================================================
// ifu_buffer_formal_top.sv — IFU_Buffer 形式验证 harness（SymbiYosys）
// =============================================================================
// 断言在 IFU_Buffer.sv 内部（`ifdef FORMAL 区）：取指窗口簿记不变式
//   · 取指请求恒字对齐 / cur_w 窗口与 req_addr 配对 / Zcmp 冻结期指针保持
// w_new/fetch_served 全自由穷举（存储器可为任意内容、任意抢占时机）；
// Zcmp 契约假设见模块内 assume（last_retired 只许在展开进行中出现）。
// 范围说明：本环境证控制平面簿记；"指令流==存储器流"的数据等价需要
// 存储器模型 harness，暂由仿真（riscv-tests/custom_asm 全量）覆盖。
// =============================================================================

module ifu_buffer_formal_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    // 控制
    // 三个跳转目标只引出 [31:1]：RTL 取 [31:1] 拼 1'b0（16 位对齐），bit0 被
    // 弃用；若整端口暴露，未用位会被 opt 转成 x 连接，毒化 abc pdr 的 AIGER 后端
    logic [ADDR_WIDTH-2:0]     jump_addr_hi;
    logic                      jump_en;
    logic [ADDR_WIDTH-2:0]     predict_target_hi;
    logic                      predict_taken;
    logic                      stall;
    logic                      dbg_load_en;
    logic [ADDR_WIDTH-2:0]     dbg_load_addr_hi;
    // 取指数据
    logic [DATA_WIDTH-1:0]     w_new;
    logic                      fetch_served;
    // Zcmp 控制
    logic                      zcmp_flush_any_i;
    logic                      zcmp_last_retired_i;

    // DUT 输出（必须显式声明）
    logic [ADDR_WIDTH-1:0]     pc;
    logic [ADDR_WIDTH-1:0]     inst_addr_o;
    logic [ADDR_WIDTH-1:0]     fetch_word_addr_o;
    logic [DATA_WIDTH-1:0]     inst_o;
    logic                      inst_valid_o;
    logic                      fetch_wait_o;
    logic                      is_compressed_o;
    logic                      illegal_inst_o;
    logic                      zcmp_micro_last_o;
    logic                      zcmp_micro_any_o;
    logic                      zcb_tag_o;
    logic                      zcmp_busy_o;
    logic                      predict_taken_o;
    logic                      if_addr_misalign;
    logic                      if_access_fault;

    // 复位时序假设：初始 1 拍 rst_n=0，此后恒 1
    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;
    always_ff @(posedge clk) begin
        if (!f_past_valid) assume (!rst_n);
        else               assume (rst_n);
    end

    IFU_Buffer #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .jump_en              (jump_en),
        .jump_addr            ({jump_addr_hi, 1'b0}),
        .predict_taken        (predict_taken),
        .predict_target       ({predict_target_hi, 1'b0}),
        .stall                (stall),
        .dbg_load_en          (dbg_load_en),
        .dbg_load_addr        ({dbg_load_addr_hi, 1'b0}),
        .w_new                (w_new),
        .fetch_served         (fetch_served),
        .zcmp_flush_any_i     (zcmp_flush_any_i),
        .zcmp_last_retired_i  (zcmp_last_retired_i),
        .pc                   (pc),
        .inst_addr_o          (inst_addr_o),
        .fetch_word_addr_o    (fetch_word_addr_o),
        .inst_o               (inst_o),
        .inst_valid_o         (inst_valid_o),
        .fetch_wait_o         (fetch_wait_o),
        .is_compressed_o      (is_compressed_o),
        .illegal_inst_o       (illegal_inst_o),
        .zcmp_micro_last_o    (zcmp_micro_last_o),
        .zcmp_micro_any_o     (zcmp_micro_any_o),
        .zcb_tag_o            (zcb_tag_o),
        .zcmp_busy_o          (zcmp_busy_o),
        .predict_taken_o      (predict_taken_o),
        .if_addr_misalign     (if_addr_misalign),
        .if_access_fault      (if_access_fault)
    );

endmodule
