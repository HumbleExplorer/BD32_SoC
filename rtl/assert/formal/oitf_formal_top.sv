// =============================================================================
// oitf_formal_top.sv — OITF 形式验证 harness（SymbiYosys）
// =============================================================================
// 仅驱动输入 + 最小假设。断言在 OITF.sv 内部（`ifdef FORMAL 区），
// 由 sby 的 read -formal 激活。属性计划见 doc/verification.md 形式验证章节。
// =============================================================================

module oitf_formal_top #(
    parameter OITF_DEPTH     = 4,
    parameter DATA_WIDTH     = 32,
    parameter REG_ADDR_WIDTH = 5,
    parameter NUM_LP_UNITS   = 2
)(
    input logic clk,
    input logic rst_n
);

    logic                                     lp_valid;
    logic [$clog2(NUM_LP_UNITS)-1:0]          lp_unit_id;
    logic [REG_ADDR_WIDTH-1:0]                disp_rd_addr;
    logic                                     disp_rd_wen;
    logic [REG_ADDR_WIDTH-1:0]                reg_rs1_raddr_ex;
    logic                                     ex_rs1_valid;
    logic [REG_ADDR_WIDTH-1:0]                reg_rs2_raddr_ex;
    logic                                     ex_rs2_valid;
    logic [REG_ADDR_WIDTH-1:0]                reg_rd_waddr_ex;
    logic                                     reg_rd_wen_ex;
    logic [NUM_LP_UNITS-1:0]                  unit_ready;
    logic [NUM_LP_UNITS-1:0]                  unit_wbck_valid;
    logic [NUM_LP_UNITS*DATA_WIDTH-1:0]       result_wbck;
    logic                                     flush;

    // DUT 输出（必须显式声明，否则 Yosys 隐式 1-bit wire 会让断言静默失真）
    logic                                     oitf_stall;
    logic                                     retire_valid;
    logic [REG_ADDR_WIDTH-1:0]                retire_rd_addr;
    logic [DATA_WIDTH-1:0]                    retire_rd_data;
    logic                                     retire_rd_wen;

    // 复位时序假设：初始 1 拍 rst_n=0，此后恒 1
    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;
    always_ff @(posedge clk) begin
        if (!f_past_valid) assume (!rst_n);
        else               assume (rst_n);
    end

    OITF #(
        .OITF_DEPTH     (OITF_DEPTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .REG_ADDR_WIDTH (REG_ADDR_WIDTH),
        .NUM_LP_UNITS   (NUM_LP_UNITS)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .lp_valid         (lp_valid),
        .lp_unit_id       (lp_unit_id),
        .disp_rd_addr     (disp_rd_addr),
        .disp_rd_wen      (disp_rd_wen),
        .reg_rs1_raddr_ex (reg_rs1_raddr_ex),
        .ex_rs1_valid     (ex_rs1_valid),
        .reg_rs2_raddr_ex (reg_rs2_raddr_ex),
        .ex_rs2_valid     (ex_rs2_valid),
        .reg_rd_waddr_ex  (reg_rd_waddr_ex),
        .reg_rd_wen_ex    (reg_rd_wen_ex),
        .unit_ready       (unit_ready),
        .unit_wbck_valid  (unit_wbck_valid),
        .result_wbck      (result_wbck),
        .flush            (flush),
        .oitf_stall       (oitf_stall),
        .retire_valid     (retire_valid),
        .retire_rd_addr   (retire_rd_addr),
        .retire_rd_data   (retire_rd_data),
        .retire_rd_wen    (retire_rd_wen)
    );

endmodule
