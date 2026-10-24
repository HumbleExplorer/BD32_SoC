`include "./../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;

import bd32_pkg::*;

module AXI_APB_Bridge #(
    parameter ADDR_WIDTH  = `ADDR_WIDTH,
    parameter DATA_WIDTH  = `DATA_WIDTH,
    parameter STRB_WIDTH  = `ALIGN_BYTES,
    parameter ID_WIDTH    = AXI_ID_WIDTH,
    parameter LEN_WIDTH   = AXI_LEN_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    // AXI4-Lite Slave 接口
    // AXI4 Slave 接口（接口，上游互联）
    axi_if.slave  s,

    // APB Master 接口
    apb_if.master                     apb         // APB 总线（下游互联/从机）
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
    logic                      apb_timeout;   // 从机超时无响应

    // 锁存的事务信息
    logic [ID_WIDTH-1:0]       trans_id;
    logic                      trans_error;

    // AXI 握手信号
    logic aw_hs, w_hs, ar_hs;
    assign aw_hs = s.awvalid && s.awready;
    assign w_hs  = s.wvalid  && s.wready;
    assign ar_hs = s.arvalid && s.arready;

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
                if (s.awvalid && s.wvalid)
                    next_state = APB_WRITE;
                else if (s.arvalid)
                    next_state = APB_READ;
            end

            APB_WRITE: begin
                if (apb_tran_done) begin
                    if (s.bready) begin
                        // 背靠背：检查是否有新请求
                        if (s.awvalid && s.wvalid)
                            next_state = APB_WRITE;
                        else if (s.arvalid)
                            next_state = APB_READ;
                        else
                            next_state = IDLE;
                    end
                end
            end

            APB_READ: begin
                if (apb_tran_done) begin
                    if (s.rready) begin
                        if (s.awvalid && s.wvalid)
                            next_state = APB_WRITE;
                        else if (s.arvalid)
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
                if ((s.awvalid && s.wvalid) || s.arvalid) begin
                    apb_transfer = 1'b1;
                end
            end

            APB_WRITE: begin
                // 背靠背：在响应阶段就启动新事务
                if (s.bready && ((s.awvalid && s.wvalid) || s.arvalid)) begin
                    apb_transfer = 1'b1;
                end
            end

            APB_READ: begin
                if (s.rready && ((s.awvalid && s.wvalid) || s.arvalid)) begin
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
                if (s.awvalid && s.wvalid) begin
                    apb_write    <= 1'b1;
                    apb_addr     <= s.awaddr;
                    apb_wdata    <= s.wdata;
                    apb_wmask    <= s.wstrb;
                end else if (s.arvalid) begin
                    apb_write    <= 1'b0;
                    apb_addr     <= s.araddr;
                end
            APB_WRITE: begin
                // 背靠背：在响应阶段就启动新事务
                if (apb_tran_done && s.bready && s.awvalid && s.wvalid) begin
                    apb_write    <= 1'b1;
                    apb_addr     <= s.awaddr;
                    apb_wdata    <= s.wdata;
                    apb_wmask    <= s.wstrb;
                end else if (apb_tran_done && s.bready && s.arvalid) begin
                    apb_write    <= 1'b0;
                    apb_addr     <= s.araddr;
                end
            end
            READ_RESP: begin
                if (apb_tran_done && s.rready && s.awvalid && s.wvalid) begin
                    apb_write    <= 1'b1;
                    apb_addr     <= s.awaddr;
                    apb_wdata    <= s.wdata;
                    apb_wmask    <= s.wstrb;
                end else if (apb_tran_done && s.rready && s.arvalid) begin
                    apb_write    <= 1'b0;
                    apb_addr     <= s.araddr;
                end
            end
        endcase
    end
end

    // AXI Ready 信号 —— 单通道独立断言，不依赖其他通道的 valid，避免组合环路
    // AW/W 在 IDLE 时只要看到 valid 就置 ready（AXI-Lite 要求地址和数据同时有效）
    assign s.awready = (state == IDLE) || 
                       (state == APB_WRITE && apb_tran_done && s.bready) ||
                       (state == APB_READ  && apb_tran_done && s.rready);
    
    assign s.wready  = (state == IDLE) || 
                       (state == APB_WRITE && apb_tran_done && s.bready) ||
                       (state == APB_READ  && apb_tran_done && s.rready);
    
    assign s.arready = (state == IDLE) || 
                       (state == APB_WRITE && apb_tran_done && s.bready) ||
                       (state == APB_READ  && apb_tran_done && s.rready);

    // 锁存事务 ID 和错误状态
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trans_id    <= '0;
            trans_error <= 1'b0;
        end else begin
            if (write_req_ready)
                trans_id <= s.awid;
            else if (ar_hs)
                trans_id <= s.arid;
            
            if (apb_tran_done)
                trans_error <= apb.pslverr | apb_timeout;
        end
    end

    // AXI 响应信号
    // s.bresp/s.rresp 直接用 apb.pslverr|apb_timeout（同周期有效），
    // 避免 trans_error 寄存器延迟一拍导致超时当拍响应为 OKAY。
    assign s.bvalid = (state == APB_WRITE && apb_tran_done);
    assign s.bid    = trans_id;
    assign s.bresp  = {apb.pslverr | apb_timeout, 1'b0};

    assign s.rvalid = (state == APB_READ && apb_tran_done);
    assign s.rid    = trans_id;
    assign s.rdata  = apb_rdata;
    assign s.rresp  = {apb.pslverr | apb_timeout, 1'b0};
    assign s.rlast  = 1'b1;

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
        .m            (apb),        .o_timeout    (apb_timeout)
    );

endmodule
