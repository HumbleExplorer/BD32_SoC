// =============================================================================
// axi_master_formal_top.sv — AXI_Lite_Master 形式验证 harness（SymbiYosys）
// =============================================================================
// 断言在 AXI_Lite_Master.sv 内部（`ifdef FORMAL 区）：
//   · 6 态 one-hot FSM 合法性 / req_ready / rsp_valid 一致性
//   · 等待态有界逃逸（BUS_TIMEOUT 强制 DONE，无需环境假设）
//   · DONE 拍 req_ready 恒高 / AW-W 同窗
// 稳定性断言（`ifndef SYNTHESIS 区）在形式构建中同样激活，从机侧输入全自由
// ——包括永不握手的最恶劣从机（超时逃逸豁免拍除外，AXI 稳定性由此成立）。
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

    // CPU 侧
    logic                      req_valid;
    logic                      req_write;
    logic [ADDR_WIDTH-1:0]     req_addr;
    logic [DATA_WIDTH-1:0]     req_wdata;
    logic [STRB_WIDTH-1:0]     req_wstrb;
    logic                      req_ready;
    logic                      rsp_valid;
    logic [1:0]                rsp_error;
    logic [DATA_WIDTH-1:0]     rsp_rdata;

    // AXI 侧
    logic [ID_WIDTH-1:0]       m_awid;
    logic [ADDR_WIDTH-1:0]     m_awaddr;
    logic [LEN_WIDTH-1:0]      m_awlen;
    logic [2:0]                m_awsize;
    logic [1:0]                m_awburst;
    logic                      m_awlock;
    logic [3:0]                m_awcache;
    logic [2:0]                m_awprot;
    logic [3:0]                m_awqos;
    logic [3:0]                m_awregion;
    logic                      m_awvalid;
    logic                      m_awready;
    logic [DATA_WIDTH-1:0]     m_wdata;
    logic [STRB_WIDTH-1:0]     m_wstrb;
    logic                      m_wlast;
    logic                      m_wvalid;
    logic                      m_wready;
    logic [ID_WIDTH-1:0]       m_bid;
    logic [1:0]                m_bresp;
    logic                      m_bvalid;
    logic                      m_bready;
    logic [ID_WIDTH-1:0]       m_arid;
    logic [ADDR_WIDTH-1:0]     m_araddr;
    logic [LEN_WIDTH-1:0]      m_arlen;
    logic [2:0]                m_arsize;
    logic [1:0]                m_arburst;
    logic                      m_arlock;
    logic [3:0]                m_arcache;
    logic [2:0]                m_arprot;
    logic [3:0]                m_arqos;
    logic [3:0]                m_arregion;
    logic                      m_arvalid;
    logic                      m_arready;
    logic [ID_WIDTH-1:0]       m_rid;
    logic [DATA_WIDTH-1:0]     m_rdata;
    logic [1:0]                m_rresp;
    logic                      m_rlast;
    logic                      m_rvalid;
    logic                      m_rready;

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
        .m_awid     (m_awid),
        .m_awaddr   (m_awaddr),
        .m_awlen    (m_awlen),
        .m_awsize   (m_awsize),
        .m_awburst  (m_awburst),
        .m_awlock   (m_awlock),
        .m_awcache  (m_awcache),
        .m_awprot   (m_awprot),
        .m_awqos    (m_awqos),
        .m_awregion (m_awregion),
        .m_awvalid  (m_awvalid),
        .m_awready  (m_awready),
        .m_wdata    (m_wdata),
        .m_wstrb    (m_wstrb),
        .m_wlast    (m_wlast),
        .m_wvalid   (m_wvalid),
        .m_wready   (m_wready),
        .m_bid      (m_bid),
        .m_bresp    (m_bresp),
        .m_bvalid   (m_bvalid),
        .m_bready   (m_bready),
        .m_arid     (m_arid),
        .m_araddr   (m_araddr),
        .m_arlen    (m_arlen),
        .m_arsize   (m_arsize),
        .m_arburst  (m_arburst),
        .m_arlock   (m_arlock),
        .m_arcache  (m_arcache),
        .m_arprot   (m_arprot),
        .m_arqos    (m_arqos),
        .m_arregion (m_arregion),
        .m_arvalid  (m_arvalid),
        .m_arready  (m_arready),
        .m_rid      (m_rid),
        .m_rdata    (m_rdata),
        .m_rresp    (m_rresp),
        .m_rlast    (m_rlast),
        .m_rvalid   (m_rvalid),
        .m_rready   (m_rready)
    );

endmodule
