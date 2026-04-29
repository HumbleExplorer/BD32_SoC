`include "./../SoC_Config.sv"
`timescale 1ns / 1ps

module AXI_APB_Bridge #(
    parameter ADDR_WIDTH  = `ADDR_WIDTH,
    parameter DATA_WIDTH  = `DATA_WIDTH,
    parameter STRB_WIDTH  = `ALIGN_BYTES,
    parameter ID_WIDTH    = `AXI_ID_WIDTH,
    parameter LEN_WIDTH   = `AXI_LEN_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    // AXI4-Lite Slave 接口
    input  logic [ID_WIDTH-1:0]       s_awid,
    input  logic [ADDR_WIDTH-1:0]     s_awaddr,
    input  logic [LEN_WIDTH-1:0]      s_awlen,
    input  logic [2:0]                s_awsize,
    input  logic [1:0]                s_awburst,
    input  logic                      s_awlock,
    input  logic [3:0]                s_awcache,
    input  logic [2:0]                s_awprot,
    input  logic [3:0]                s_awqos,
    input  logic [3:0]                s_awregion,
    input  logic                      s_awvalid,
    output logic                      s_awready,

    input  logic [DATA_WIDTH-1:0]     s_wdata,
    input  logic [STRB_WIDTH-1:0]     s_wstrb,
    input  logic                      s_wlast,
    input  logic                      s_wvalid,
    output logic                      s_wready,

    output logic [ID_WIDTH-1:0]       s_bid,
    output logic [1:0]                s_bresp,
    output logic                      s_bvalid,
    input  logic                      s_bready,

    input  logic [ID_WIDTH-1:0]       s_arid,
    input  logic [ADDR_WIDTH-1:0]     s_araddr,
    input  logic [LEN_WIDTH-1:0]      s_arlen,
    input  logic [2:0]                s_arsize,
    input  logic [1:0]                s_arburst,
    input  logic                      s_arlock,
    input  logic [3:0]                s_arcache,
    input  logic [2:0]                s_arprot,
    input  logic [3:0]                s_arqos,
    input  logic [3:0]                s_arregion,
    input  logic                      s_arvalid,
    output logic                      s_arready,

    output logic [ID_WIDTH-1:0]       s_rid,
    output logic [DATA_WIDTH-1:0]     s_rdata,
    output logic [1:0]                s_rresp,
    output logic                      s_rlast,
    output logic                      s_rvalid,
    input  logic                      s_rready,

    // APB Master 接口
    output logic [ADDR_WIDTH-1:0]     PADDR,
    output logic                      PSEL,
    output logic                      PENABLE,
    output logic                      PWRITE,
    output logic [STRB_WIDTH-1:0]     PSTRB,
    output logic [DATA_WIDTH-1:0]     PWDATA,
    input  logic [DATA_WIDTH-1:0]     PRDATA,
    input  logic                      PREADY,
    input  logic                      PSLVERR
);

    // 状态机
    typedef enum logic [4:0] {
        IDLE       = 5'b00001,
        APB_WRITE  = 5'b00010,
        WRITE_RESP = 5'b00100,
        APB_READ   = 5'b01000,
        READ_RESP  = 5'b10000
    } state_t;

    state_t state, next_state;

    // APB Master 接口信号
    logic                      apb_transfer;
    logic                      apb_write;
    logic [ADDR_WIDTH-1:0]     apb_addr;
    logic [DATA_WIDTH-1:0]     apb_wdata;
    logic [STRB_WIDTH-1:0]     apb_wmask;
    logic [DATA_WIDTH-1:0]     apb_rdata;
    logic                      apb_tran_done;

    // 锁存的事务信息
    logic [ID_WIDTH-1:0]       trans_id;
    logic                      trans_error;

    // AXI 握手信号
    logic aw_hs, w_hs, ar_hs;
    assign aw_hs = s_awvalid && s_awready;
    assign w_hs  = s_wvalid  && s_wready;
    assign ar_hs = s_arvalid && s_arready;

    // 写事务：需要 AW 和 W 都握手
    logic write_req_ready;
    assign write_req_ready = aw_hs && w_hs;

    // 状态转移
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (s_awvalid && s_wvalid)
                    next_state = APB_WRITE;
                else if (s_arvalid)
                    next_state = APB_READ;
            end

            APB_WRITE: begin
                if (apb_tran_done) begin
                    if (s_bready) begin
                        // 背靠背：检查是否有新请求
                        if (s_awvalid && s_wvalid)
                            next_state = APB_WRITE;
                        else if (s_arvalid)
                            next_state = APB_READ;
                        else
                            next_state = IDLE;
                    end
                end
            end

            APB_READ: begin
                if (apb_tran_done) begin
                    if (s_rready) begin
                        if (s_awvalid && s_wvalid)
                            next_state = APB_WRITE;
                        else if (s_arvalid)
                            next_state = APB_READ;
                        else
                            next_state = IDLE;
                    end
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // APB 控制信号
    always_comb begin
        apb_transfer = 1'b0;
        case (state)
            IDLE: begin
                if ((s_awvalid && s_wvalid) || s_arvalid) begin
                    apb_transfer = 1'b1;
                end
            end

            APB_WRITE: begin
                // 背靠背：在响应阶段就启动新事务
                if (s_bready && ((s_awvalid && s_wvalid) || s_arvalid)) begin
                    apb_transfer = 1'b1;
                end
            end

            APB_READ: begin
                if (s_rready && ((s_awvalid && s_wvalid) || s_arvalid)) begin
                    apb_transfer = 1'b1;
                end
            end

            default: ;
        endcase
    end
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        apb_addr     <= '0;
        apb_wdata    <= '0;
        apb_write    <= 1'b0;
        apb_wmask    <= '0;
    end else begin
        case (state)
            IDLE:
                if (s_awvalid && s_wvalid) begin
                    apb_write    <= 1'b1;
                    apb_addr     <= s_awaddr;
                    apb_wdata    <= s_wdata;
                    apb_wmask    <= s_wstrb;
                end else if (s_arvalid) begin
                    apb_write    <= 1'b0;
                    apb_addr     <= s_araddr;
                end
            APB_WRITE: begin
                // 背靠背：在响应阶段就启动新事务
                if (apb_tran_done && s_bready && s_awvalid && s_wvalid) begin
                    apb_write    <= 1'b1;
                    apb_addr     <= s_awaddr;
                    apb_wdata    <= s_wdata;
                    apb_wmask    <= s_wstrb;
                end else if (apb_tran_done && s_bready && s_arvalid) begin
                    apb_write    <= 1'b0;
                    apb_addr     <= s_araddr;
                end
            end
            READ_RESP: begin
                if (apb_tran_done && s_rready && s_awvalid && s_wvalid) begin
                    apb_write    <= 1'b1;
                    apb_addr     <= s_awaddr;
                    apb_wdata    <= s_wdata;
                    apb_wmask    <= s_wstrb;
                end else if (apb_tran_done && s_rready && s_arvalid) begin
                    apb_write    <= 1'b0;
                    apb_addr     <= s_araddr;
                end
            end
        endcase
    end
end

    // AXI Ready 信号 —— 单通道独立断言，不依赖其他通道的 valid，避免组合环路
    // AW/W 在 IDLE 时只要看到 valid 就置 ready（AXI-Lite 要求地址和数据同时有效）
    assign s_awready = (state == IDLE) || 
                       (state == APB_WRITE && apb_tran_done && s_bready) ||
                       (state == APB_READ  && apb_tran_done && s_rready);
    
    assign s_wready  = (state == IDLE) || 
                       (state == APB_WRITE && apb_tran_done && s_bready) ||
                       (state == APB_READ  && apb_tran_done && s_rready);
    
    assign s_arready = (state == IDLE) || 
                       (state == APB_WRITE && apb_tran_done && s_bready) ||
                       (state == APB_READ  && apb_tran_done && s_rready);

    // 锁存事务 ID 和错误状态
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trans_id    <= '0;
            trans_error <= 1'b0;
        end else begin
            if (write_req_ready)
                trans_id <= s_awid;
            else if (ar_hs)
                trans_id <= s_arid;
            
            if (apb_tran_done)
                trans_error <= PSLVERR;
        end
    end

    // AXI 响应信号
    assign s_bvalid = (state == APB_WRITE && apb_tran_done);
    assign s_bid    = trans_id;
    assign s_bresp  = {trans_error, 1'b0};

    assign s_rvalid = (state == APB_READ && apb_tran_done);
    assign s_rid    = trans_id;
    assign s_rdata  = apb_rdata;
    assign s_rresp  = {trans_error, 1'b0};
    assign s_rlast  = 1'b1;

    // 例化 APB Master
    APB_Master #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .ALIGN_BYTES (STRB_WIDTH)
    ) u_apb_master (
        .i_sys_clk    (clk),
        .i_rst_n      (rst_n),
        .i_transfer   (apb_transfer),
        .i_write      (apb_write),
        .i_addr       (apb_addr),
        .i_wdata      (apb_wdata),
        .i_wmask      (apb_wmask),
        .o_rdata      (apb_rdata),
        .o_tran_done  (apb_tran_done),
        .o_PADDR      (PADDR),
        .o_PSEL       (PSEL),
        .o_PENABLE    (PENABLE),
        .o_PWRITE     (PWRITE),
        .o_PSTRB      (PSTRB),
        .o_PWDATA     (PWDATA),
        .i_PRDATA     (PRDATA),
        .i_PREADY     (PREADY),
        .i_PSLVERR    (PSLVERR)
    );

endmodule
