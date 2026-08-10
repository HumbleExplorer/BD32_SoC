// ============================================================================
// debug_cdc.sv — JTAG TCK 域 ↔ 系统 clk 域 DMI 跨时钟域传输
//
// BD32 — RV32IM Pipelined RISC-V SoC
// Copyright (c) 2026 BD32 Project
// SPDX-License-Identifier: Apache-2.0
//
// 改编自 tinyriscv full_handshake_tx/rx（Apache-2.0）：
//   合并为单文件，参数化数据位宽
// ============================================================================
// BD32 Debug CDC — 4相全握手跨时钟域传输
// 用于 TCK 域 ↔ 系统 clk 域之间的 DMI 数据传输
`include "./../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;

// ============================================================
// 发送端（TX）：发起请求，等待对方 ack
// ============================================================
module debug_cdc_tx #(
    parameter DW = 40
)(
    input  logic            clk,
    input  logic            rst_n,
    // 对端应答（经 2FF 同步）
    input  logic            ack_i,
    // 本端请求
    input  logic            req_i,          // 持续一拍即可
    input  logic [DW-1:0]   req_data_i,
    // 状态
    output logic            idle_o,
    // 到对端
    output logic            req_o,
    output logic [DW-1:0]   req_data_o
);

localparam S_IDLE     = 2'b01;
localparam S_ASSERT   = 2'b10;
localparam S_DEASSERT = 2'b11;

logic [1:0] state;
logic ack_sync1, ack_sync2;
logic req_r;
logic [DW-1:0] data_r;
logic idle_r;

// 2FF 同步 ack
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ack_sync1 <= 1'b0;
        ack_sync2 <= 1'b0;
    end else begin
        ack_sync1 <= ack_i;
        ack_sync2 <= ack_sync1;
    end
end

// 状态转移
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= S_IDLE;
    else case (state)
        S_IDLE:     if (req_i)      state <= S_ASSERT;
        S_ASSERT:   if (ack_sync2)  state <= S_DEASSERT;
        S_DEASSERT: if (!ack_sync2) state <= S_IDLE;
        default:    state <= S_IDLE;
    endcase
end

// 数据锁存 + req 控制
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        req_r   <= 1'b0;
        data_r  <= '0;
        idle_r  <= 1'b1;
    end else case (state)
        S_IDLE: begin
            if (req_i) begin
                req_r   <= 1'b1;
                data_r  <= req_data_i;
                idle_r  <= 1'b0;
            end else begin
                idle_r  <= 1'b1;
            end
        end
        S_ASSERT: begin
            if (ack_sync2)
                req_r <= 1'b0;
        end
        S_DEASSERT: begin
            if (!ack_sync2)
                idle_r <= 1'b1;
        end
        default: ;
    endcase
end

assign idle_o     = idle_r;
assign req_o      = req_r;
assign req_data_o = data_r;

endmodule

// ============================================================
// 接收端（RX）：等待请求，采样数据，回复 ack
// ============================================================
module debug_cdc_rx #(
    parameter DW = 40
)(
    input  logic            clk,
    input  logic            rst_n,
    // 对端请求（经 2FF 同步）
    input  logic            req_i,
    input  logic [DW-1:0]   req_data_i,
    // 本端应答
    output logic            ack_o,
    // 本端输出
    output logic [DW-1:0]   recv_data_o,
    output logic            recv_rdy_o      // 持续一拍
);

localparam S_IDLE     = 1'b0;
localparam S_DEASSERT = 1'b1;

logic state;
logic req_sync1, req_sync2;
logic ack_r;
logic [DW-1:0] data_r;
logic rdy_r;

// 2FF 同步 req
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        req_sync1 <= 1'b0;
        req_sync2 <= 1'b0;
    end else begin
        req_sync1 <= req_i;
        req_sync2 <= req_sync1;
    end
end

// 状态转移
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= S_IDLE;
    else case (state)
        S_IDLE:     if (req_sync2)  state <= S_DEASSERT;
        S_DEASSERT: if (!req_sync2) state <= S_IDLE;
        default:    state <= S_IDLE;
    endcase
end

// 采样数据 + ack 控制
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ack_r  <= 1'b0;
        rdy_r  <= 1'b0;
        data_r <= '0;
    end else case (state)
        S_IDLE: begin
            rdy_r <= 1'b0;
            if (req_sync2) begin
                ack_r  <= 1'b1;
                rdy_r  <= 1'b1;
                data_r <= req_data_i;
            end
        end
        S_DEASSERT: begin
            rdy_r <= 1'b0;
            if (!req_sync2)
                ack_r <= 1'b0;
        end
        default: ;
    endcase
end

assign ack_o       = ack_r;
assign recv_data_o = data_r;
assign recv_rdy_o  = rdy_r;

endmodule
