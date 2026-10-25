// =============================================================================
// axi_master_formal_top.sv — AXI_Lite_Master 形式验证 harness（SymbiYosys）
// =============================================================================
// 断言在 AXI_Lite_Master.sv 内部（`ifdef FORMAL 区）：
//   · 6 态 one-hot FSM 合法性 / req_ready / rsp_valid 一致性
//   · 等待态有界逃逸（BUS_TIMEOUT 强制 DONE，无需环境假设）
//   · DONE 拍 req_ready 恒高 / AW-W 同窗
// 稳定性断言（`ifndef SYNTHESIS 区）在形式构建中同样激活，从机侧输入全自由
// ——包括永不握手的最恶劣从机（超时强制撤 valid 的逃逸拍除外，AXI 稳定性由此成立）。
// AXI 侧经 axi_if 接口连接；本 harness 不驱动任何 AXI 成员（全自由输入）。
// 本文件经 sv2v 预处理（接口内联）后进入 yosys，见 sv2v_convert.bat。
// =============================================================================

module axi_master_formal_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = 4,
    parameter ID_WIDTH   = 4,
    parameter LEN_WIDTH  = 8
)(
    input logic clk,
    input logic rst_n
);

    // CPU 侧（全自由输入）
    logic                      req_valid;
    logic                      req_write;
    logic [ADDR_WIDTH-1:0]     req_addr;
    logic [DATA_WIDTH-1:0]     req_wdata;
    logic [STRB_WIDTH-1:0]     req_wstrb;
    logic                      req_ready;
    logic                      rsp_valid;
    logic [1:0]                rsp_error;
    logic [DATA_WIDTH-1:0]     rsp_rdata;

    // AXI 侧（接口实例；成员无驱动 = 形式验证的自由输入）
    axi_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .LEN_WIDTH  (LEN_WIDTH)
    ) m_axi ();

    // 复位时序假设：初始 1 拍 rst_n=0，此后恒 1
    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;
    always_ff @(posedge clk) begin
        if (!f_past_valid) assume (!rst_n);
        else               assume (rst_n);
    end

    AXI_Lite_Master #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .STRB_WIDTH (STRB_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .LEN_WIDTH  (LEN_WIDTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .req_valid  (req_valid),
        .req_write  (req_write),
        .req_addr   (req_addr),
        .req_wdata  (req_wdata),
        .req_wstrb  (req_wstrb),
        .req_ready  (req_ready),
        .rsp_valid  (rsp_valid),
        .rsp_error  (rsp_error),
        .rsp_rdata  (rsp_rdata),
        .m          (m_axi)
    );

endmodule
