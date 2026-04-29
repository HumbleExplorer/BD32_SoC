`include "./../SoC_Config.sv"
`timescale 1ns / 1ps
// =============================================================================
// axi_apb_bridge - AXI4 转 APB 桥（含内部 APB Interconnect）
// =============================================================================
// 功能：
//   - AXI4 Slave 接收 AXI 读写请求，转换为 APB 总线事务
//   - 内部集成 APB Interconnect，根据地址解码 PSEL[0:APB_NUM_SLAVES-1]
//   - APB 外设数量可配置（APB_NUM_SLAVES 参数，默认 16）
//   - 端口保留 AXI-Full 信号，忽略 Full-only 输入
//
// AXI 地址 → PSEL 解码规则：
//   使用 APB 从机基址数组 SLAVE_BASE_ADDR[0:APB_NUM_SLAVES-1]
//   匹配 AXI 地址 [31:16] == SLAVE_BASE_ADDR[i][31:16]
//   PADDR = AXI 地址 [APB_SLAVE_ADDR_WIDTH-1:0]
//
// APB 时序（无等待周期外设）：
//   SETUP(PSEL↑) → ACCESS(PENABLE↑, PREADY=1) → 完成
//   总共 2 个 APB 时钟周期
// =============================================================================

module axi_apb_bridge #(
    parameter ADDR_WIDTH       = `ADDR_WIDTH,
    parameter DATA_WIDTH       = `DATA_WIDTH,
    parameter STRB_WIDTH       = `ALIGN_BYTES,
    parameter ID_WIDTH         = `AXI_ID_WIDTH,
    parameter APB_NUM_SLAVES   = `APB_NUM_SLAVES,  // 16
    parameter APB_ADDR_WIDTH   = `APB_SLAVE_ADDR_WIDTH  // 16
)(
    input  logic clk,
    input  logic rst_n,

    // ========================================================================
    // AXI4 Slave 接口
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
    input  logic                      s_rready,

    // ========================================================================
    // APB Master → 外设（共享总线 + 独立 PSEL）
    // ========================================================================
    output logic [ADDR_WIDTH-1:0]     apb_paddr,
    output logic [APB_NUM_SLAVES-1:0] apb_psel,
    output logic                      apb_penable,
    output logic                      apb_pwrite,
    output logic [STRB_WIDTH-1:0]     apb_pstrb,
    output logic [DATA_WIDTH-1:0]     apb_pwdata,
    input  logic [DATA_WIDTH-1:0]     apb_prdata  [APB_NUM_SLAVES],
    input  logic [APB_NUM_SLAVES-1:0] apb_pready,
    input  logic [APB_NUM_SLAVES-1:0] apb_pslverr
);

    // =========================================================================
    // 常量
    // =========================================================================
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    // =========================================================================
    // APB 从机基址表（由 SoC_Config.sv 定义）
    // =========================================================================
    logic [ADDR_WIDTH-1:0] slave_base_addr [0:APB_NUM_SLAVES-1];

    always_comb begin
        for (int i = 0; i < APB_NUM_SLAVES; i++)
            slave_base_addr[i] = {ADDR_WIDTH{1'b0}};  // 默认无效地址
        slave_base_addr[0] = `APB_CLINT_BASE_ADDR;     // 0xF200_0000
        slave_base_addr[1] = `APB_PLIC_BASE_ADDR;      // 0xFC00_0000
        slave_base_addr[2] = `APB_GPIO_BASE_ADDR;      // 0xE000_0000
        slave_base_addr[3] = `APB_UART_BASE_ADDR;      // 0xE001_0000
        slave_base_addr[4] = `APB_TIMER_BASE_ADDR;     // 0xE002_0000
        slave_base_addr[5] = `APB_SPI_BASE_ADDR;       // 0xE003_0000
        slave_base_addr[6] = `APB_I2C_BASE_ADDR;       // 0xE004_0000
    end

    // =========================================================================
    // 地址解码 → PSEL
    // =========================================================================
    logic [APB_NUM_SLAVES-1:0] psel_decode;
    logic                      apb_hit;      // 至少一个从机命中

    always_comb begin
        psel_decode = '0;
        apb_hit     = 1'b0;
        for (int i = 0; i < APB_NUM_SLAVES; i++) begin
            if (apb_paddr[ADDR_WIDTH-1:APB_ADDR_WIDTH] ==
                slave_base_addr[i][ADDR_WIDTH-1:APB_ADDR_WIDTH]) begin
                psel_decode[i] = 1'b1;
                apb_hit        = 1'b1;
            end
        end
    end

    // =========================================================================
    // AXI → APB 状态机
    // =========================================================================
    typedef enum logic [2:0] {
        AXI_IDLE    = 3'b000,  // 空闲
        AXI_AR_LATCH = 3'b001, // 锁存读地址
        APB_RD_SETUP = 3'b010, // APB 读 SETUP 拍
        APB_RD_ACCESS = 3'b011,// APB 读 ACCESS 拍
        AXI_AW_LATCH = 3'b100, // 锁存写地址
        APB_WR_SETUP = 3'b101, // APB 写 SETUP 拍
        APB_WR_ACCESS = 3'b110 // APB 写 ACCESS 拍
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= AXI_IDLE;
        else
            state <= next_state;
    end

    // =========================================================================
    // 锁存 AXI 请求
    // =========================================================================
    logic [ADDR_WIDTH-1:0]   axi_addr_reg;
    logic [DATA_WIDTH-1:0]   axi_wdata_reg;
    logic [STRB_WIDTH-1:0]   axi_wstrb_reg;
    logic [ID_WIDTH-1:0]     axi_id_reg;
    logic                    axi_write_reg;
    logic [APB_NUM_SLAVES-1:0] psel_reg;

    // 读响应寄存器
    logic [DATA_WIDTH-1:0]   apb_rdata_reg;
    logic                    apb_err_reg;
    logic [ID_WIDTH-1:0]     rid_reg;
    logic [ID_WIDTH-1:0]     bid_reg;

    // AXI 通道握手寄存
    logic ar_handshake;  // AR 已握手，等待 APB 完成
    logic aw_handshake;
    logic w_handshake;

    // =========================================================================
    // APB 总线输出
    // =========================================================================
    // PADDR 使用锁存地址的低 APB_ADDR_WIDTH 位
    assign apb_paddr   = axi_addr_reg;
    assign apb_penable = (state == APB_RD_ACCESS) || (state == APB_WR_ACCESS);
    assign apb_pwrite  = axi_write_reg;
    assign apb_pstrb   = axi_wstrb_reg;
    assign apb_pwdata  = axi_wdata_reg;

    // PSEL：仅在 APB 事务期间有效
    assign apb_psel    = ((state == APB_RD_SETUP) || (state == APB_RD_ACCESS) ||
                          (state == APB_WR_SETUP) || (state == APB_WR_ACCESS)) ? psel_reg : '0;

    // =========================================================================
    // APB 返回数据 MUX
    // =========================================================================
    logic [DATA_WIDTH-1:0] apb_prdata_mux;
    logic                  apb_pready_mux;
    logic                  apb_pslverr_mux;

    always_comb begin
        apb_prdata_mux  = '0;
        apb_pready_mux  = 1'b1;   // 无从机命中时默认 OK
        apb_pslverr_mux = 1'b0;
        for (int i = 0; i < APB_NUM_SLAVES; i++) begin
            if (psel_reg[i]) begin
                apb_prdata_mux  = apb_prdata[i];
                apb_pready_mux  = apb_pready[i];
                apb_pslverr_mux = apb_pslverr[i];
            end
        end
    end

    // =========================================================================
    // 状态转移逻辑
    // =========================================================================
    always_comb begin
        next_state = state;
        case (state)
            AXI_IDLE: begin
                if (s_arvalid)       next_state = AXI_AR_LATCH;
                else if (s_awvalid)  next_state = AXI_AW_LATCH;
            end

            AXI_AR_LATCH: begin
                next_state = APB_RD_SETUP;
            end

            APB_RD_SETUP: begin
                next_state = APB_RD_ACCESS;
            end

            APB_RD_ACCESS: begin
                if (apb_pready_mux)
                    next_state = AXI_IDLE;
            end

            AXI_AW_LATCH: begin
                if (s_wvalid)
                    next_state = APB_WR_SETUP;
            end

            APB_WR_SETUP: begin
                next_state = APB_WR_ACCESS;
            end

            APB_WR_ACCESS: begin
                if (apb_pready_mux)
                    next_state = AXI_IDLE;
            end

            default: next_state = AXI_IDLE;
        endcase
    end

    // =========================================================================
    // AXI 通道握手
    // =========================================================================
    // --- AR 通道 ---
    assign s_arready = (state == AXI_IDLE) || (state == AXI_AR_LATCH);

    // --- R 通道 ---
    logic r_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_pending <= 1'b0;
        else if (state == APB_RD_ACCESS && apb_pready_mux && next_state == AXI_IDLE)
            r_pending <= 1'b1;
        else if (r_pending && s_rready)
            r_pending <= 1'b0;
    end

    assign s_rvalid = r_pending;
    assign s_rid    = rid_reg;
    assign s_rdata  = apb_rdata_reg;
    assign s_rresp  = apb_err_reg ? RESP_SLVERR : RESP_OKAY;
    assign s_rlast  = 1'b1;

    // --- AW 通道 ---
    assign s_awready = (state == AXI_IDLE) || (state == AXI_AW_LATCH);

    // --- W 通道 ---
    assign s_wready = (state == AXI_AW_LATCH);

    // --- B 通道 ---
    logic b_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            b_pending <= 1'b0;
        else if (state == APB_WR_ACCESS && apb_pready_mux && next_state == AXI_IDLE)
            b_pending <= 1'b1;
        else if (b_pending && s_bready)
            b_pending <= 1'b0;
    end

    assign s_bvalid = b_pending;
    assign s_bid    = bid_reg;
    assign s_bresp  = RESP_OKAY;

    // =========================================================================
    // 锁存寄存器
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_addr_reg  <= '0;
            axi_wdata_reg <= '0;
            axi_wstrb_reg <= '0;
            axi_id_reg    <= '0;
            axi_write_reg <= 1'b0;
            psel_reg      <= '0;
            apb_rdata_reg <= '0;
            apb_err_reg   <= 1'b0;
            rid_reg       <= '0;
            bid_reg       <= '0;
        end else begin
            case (state)
                AXI_IDLE: begin
                    if (s_arvalid) begin
                        // 读请求锁存
                        axi_addr_reg  <= s_araddr;
                        axi_id_reg    <= s_arid;
                        axi_write_reg <= 1'b0;
                        rid_reg       <= s_arid;
                        psel_reg      <= psel_decode;
                    end else if (s_awvalid) begin
                        // 写地址锁存
                        axi_addr_reg  <= s_awaddr;
                        axi_id_reg    <= s_awid;
                        axi_write_reg <= 1'b1;
                        bid_reg       <= s_awid;
                        psel_reg      <= psel_decode;
                    end
                end

                AXI_AW_LATCH: begin
                    if (s_wvalid) begin
                        axi_wdata_reg <= s_wdata;
                        axi_wstrb_reg <= s_wstrb;
                    end
                end

                APB_RD_ACCESS: begin
                    if (apb_pready_mux) begin
                        apb_rdata_reg <= apb_prdata_mux;
                        apb_err_reg   <= apb_pslverr_mux;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule
