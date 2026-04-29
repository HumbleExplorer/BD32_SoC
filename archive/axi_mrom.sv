`include "./../SoC_Config.sv"
`timescale 1ns / 1ps
// =============================================================================
// axi_mrom - MROM 的 AXI4 Slave 接口
// =============================================================================
// 功能：
//   - AXI4 Slave 接收读写请求，从 ROM 存储返回数据
//   - MROM 为只读，写操作返回 OKAY 但不写入
//   - 端口保留 AXI-Full 信号，忽略 Full-only 输入
//   - 支持 $readmemh 初始化加载
//
// 地址映射：基址 0x8000_0000（由 AXI_Interconnect 控制）
//           深度 1KB (256 words x 32bit)
// =============================================================================

module axi_mrom #(
    parameter MROM_DEPTH    = `MROM_DEPTH,
    parameter MROM_FILE     = `MROM_FILE,
    parameter ADDR_WIDTH    = `ADDR_WIDTH,
    parameter DATA_WIDTH    = `DATA_WIDTH,
    parameter STRB_WIDTH    = `ALIGN_BYTES,
    parameter ID_WIDTH      = `AXI_ID_WIDTH,
    parameter PATH          = "../../test_data/"
)(
    // ========================================================================
    // 系统接口
    // ========================================================================
    input  logic clk,
    input  logic rst_n,

    // ========================================================================
    // AXI4 Slave 接口（Full 信号，Lite 行为）
    // ========================================================================
    // --- 写地址通道 (AW) ---
    input  logic [ID_WIDTH-1:0]       s_awid,
    input  logic [ADDR_WIDTH-1:0]     s_awaddr,
    input  logic [7:0]                s_awlen,
    input  logic [2:0]                s_awsize,
    input  logic [1:0]                s_awburst,
    input  logic                      s_awlock,
    input  logic [3:0]                s_awcache,
    input  logic [2:0]                s_awprot,
    input  logic [3:0]                s_awqos,
    input  logic [3:0]                s_awregion,
    input  logic                      s_awvalid,
    output logic                      s_awready,

    // --- 写数据通道 (W) ---
    input  logic [DATA_WIDTH-1:0]     s_wdata,
    input  logic [STRB_WIDTH-1:0]     s_wstrb,
    input  logic                      s_wlast,
    input  logic                      s_wvalid,
    output logic                      s_wready,

    // --- 写响应通道 (B) ---
    output logic [ID_WIDTH-1:0]       s_bid,
    output logic [1:0]                s_bresp,
    output logic                      s_bvalid,
    input  logic                      s_bready,

    // --- 读地址通道 (AR) ---
    input  logic [ID_WIDTH-1:0]       s_arid,
    input  logic [ADDR_WIDTH-1:0]     s_araddr,
    input  logic [7:0]                s_arlen,
    input  logic [2:0]                s_arsize,
    input  logic [1:0]                s_arburst,
    input  logic                      s_arlock,
    input  logic [3:0]                s_arcache,
    input  logic [2:0]                s_arprot,
    input  logic [3:0]                s_arqos,
    input  logic [3:0]                s_arregion,
    input  logic                      s_arvalid,
    output logic                      s_arready,

    // --- 读数据通道 (R) ---
    output logic [ID_WIDTH-1:0]       s_rid,
    output logic [DATA_WIDTH-1:0]     s_rdata,
    output logic [1:0]                s_rresp,
    output logic                      s_rlast,
    output logic                      s_rvalid,
    input  logic                      s_rready
);

    // =========================================================================
    // 常量
    // =========================================================================
    localparam MROM_ADDR_WIDTH = $clog2(MROM_DEPTH);  // 10 bits for 1K words
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    // =========================================================================
    // ROM 存储
    // =========================================================================
    logic [DATA_WIDTH-1:0] rom_mem [0:MROM_DEPTH-1];

    initial begin
        $readmemh({PATH, MROM_FILE}, rom_mem);
    end

    // =========================================================================
    // 读通路（无状态机，组合直通 + 一拍寄存）
    // =========================================================================
    logic [MROM_ADDR_WIDTH-1:0] rom_addr;
    logic                       addr_valid;
    logic [DATA_WIDTH-1:0]      rdata_hold;
    logic [ID_WIDTH-1:0]        arid_hold;

    // 字对齐地址：addr[11:2] → rom_addr[9:0]
    assign rom_addr   = s_araddr[MROM_ADDR_WIDTH+1:2];
    assign addr_valid = (s_araddr < (MROM_DEPTH * 4));

    // 锁存读数据（AR 握手拍）
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata_hold <= '0;
            arid_hold  <= '0;
        end else if (s_arvalid && s_arready) begin
            rdata_hold <= addr_valid ? rom_mem[rom_addr] : {DATA_WIDTH{1'b0}};
            arid_hold  <= s_arid;
        end
    end

    // AR 通道：IDLE 时立即接受
    assign s_arready = 1'b1;

    // R 通道：AR 握手后下一拍数据有效
    logic r_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_pending <= 1'b0;
        else if (s_arvalid && s_arready)
            r_pending <= 1'b1;
        else if (r_pending && s_rready)
            r_pending <= 1'b0;
    end

    assign s_rdata  = rdata_hold;
    assign s_rid    = arid_hold;
    assign s_rresp  = RESP_OKAY;  // ROM 始终 OKAY
    assign s_rlast  = 1'b1;       // 单拍
    assign s_rvalid = r_pending;

    // =========================================================================
    // 写通路（ROM 只读，接受写请求但丢弃数据，返回 OKAY）
    // =========================================================================
    // AW 通道：IDLE 时立即接受
    assign s_awready = 1'b1;

    // W 通道：AW 握手后接受写数据
    logic w_pending;
    logic [ID_WIDTH-1:0] awid_hold;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_pending <= 1'b0;
            awid_hold <= '0;
        end else if (s_awvalid && s_awready) begin
            w_pending <= 1'b1;
            awid_hold <= s_awid;
        end else if (w_pending && s_wvalid && s_wready) begin
            w_pending <= 1'b0;
        end
    end

    assign s_wready = w_pending;

    // B 通道：写完成后返回 OKAY
    logic b_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            b_pending <= 1'b0;
        else if (w_pending && s_wvalid && s_wready)
            b_pending <= 1'b1;
        else if (b_pending && s_bready)
            b_pending <= 1'b0;
    end

    assign s_bid    = awid_hold;
    assign s_bresp  = RESP_OKAY;
    assign s_bvalid = b_pending;

endmodule
