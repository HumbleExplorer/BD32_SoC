// ============================================================================
// axi_lite_bfm.sv — AXI4-Lite Master 总线功能模型（BFM）
//
// BD32 — RV32IM Pipelined RISC-V SoC
// Copyright (c) 2026 BD32 Project
// SPDX-License-Identifier: Apache-2.0
// 用途：驱动 AXI_Interconnect / AXI_APB_Bridge 等从属 DUT 的独立仿真。
// 单笔在途（awlen=0），AW 与 W 同拍发起；valid 保持到 ready 握手。
// 结果状态：write/read 完成后 resp 有效；超时置 ok=0 并打印 $error
// （AW 超时即短路返回，不再尝试 W/B——未路由地址无从机握手）。
// 握手循环内联展开（不用 task 传 ready 引用：ModelSim 对端口按 net 处理，
// ref/const ref 均非法），等待循环实时采样 ready（边沿活跃区 pre-NBA 值）。
// ============================================================================
timeunit 1ns;
timeprecision 1ps;

module axi_lite_master_bfm #(
    parameter ADDR_WIDTH     = 32,
    parameter DATA_WIDTH     = 32,
    parameter STRB_WIDTH     = DATA_WIDTH/8,
    parameter ID_WIDTH       = 4,
    parameter int TIMEOUT_CYCLES = 4096    // 各通道握手等待上限（防止 TB 无限等待）
)(
    input  logic                       clk,
    input  logic                       rst_n,

    // --- 写地址通道 (AW) ---
    output logic [ID_WIDTH-1:0]        m_awid,
    output logic [ADDR_WIDTH-1:0]      m_awaddr,
    output logic [7:0]                 m_awlen,
    output logic [2:0]                 m_awsize,
    output logic [1:0]                 m_awburst,
    output logic                       m_awlock,
    output logic [3:0]                 m_awcache,
    output logic [2:0]                 m_awprot,
    output logic [3:0]                 m_awqos,
    output logic [3:0]                 m_awregion,
    output logic                       m_awvalid,
    input  logic                       m_awready,

    // --- 写数据通道 (W) ---
    output logic [DATA_WIDTH-1:0]      m_wdata,
    output logic [STRB_WIDTH-1:0]      m_wstrb,
    output logic                       m_wlast,
    output logic                       m_wvalid,
    input  logic                       m_wready,

    // --- 写响应通道 (B) ---
    input  logic [ID_WIDTH-1:0]        m_bid,
    input  logic [1:0]                 m_bresp,
    input  logic                       m_bvalid,
    output logic                       m_bready,

    // --- 读地址通道 (AR) ---
    output logic [ID_WIDTH-1:0]        m_arid,
    output logic [ADDR_WIDTH-1:0]      m_araddr,
    output logic [7:0]                 m_arlen,
    output logic [2:0]                 m_arsize,
    output logic [1:0]                 m_arburst,
    output logic                       m_arlock,
    output logic [3:0]                 m_arcache,
    output logic [2:0]                 m_arprot,
    output logic [3:0]                 m_arqos,
    output logic [3:0]                 m_arregion,
    output logic                       m_arvalid,
    input  logic                       m_arready,

    // --- 读数据通道 (R) ---
    input  logic [ID_WIDTH-1:0]        m_rid,
    input  logic [DATA_WIDTH-1:0]      m_rdata,
    input  logic [1:0]                 m_rresp,
    input  logic                       m_rlast,
    input  logic                       m_rvalid,
    output logic                       m_rready
);

localparam RESP_DECERR = 2'b11;

// ----------------------------------------------------------------------------
// 写传输：AW+W 同拍发起 → 各自握手 → B 响应
// ----------------------------------------------------------------------------
task automatic write (
    input  [ADDR_WIDTH-1:0] addr,
    input  [DATA_WIDTH-1:0] data,
    input  [STRB_WIDTH-1:0] strb,
    output [1:0]            resp,
    output bit              ok
);
    int unsigned wait_cnt;
    ok = 1'b1;

    m_awid     = '0;
    m_awaddr   = addr;
    m_awlen    = 8'd0;
    m_awsize   = 3'd2;          // 4 bytes
    m_awburst  = 2'b01;         // INCR
    m_awlock   = 1'b0;
    m_awcache  = 4'd0;
    m_awprot   = 3'd0;
    m_awqos    = 4'd0;
    m_awregion = 4'd0;
    m_awvalid  = 1'b1;
    m_wdata    = data;
    m_wstrb    = strb;
    m_wlast    = 1'b1;
    m_wvalid   = 1'b1;

    // AW 握手（W 握手完成前保持 m_awaddr 稳定：互联按 awaddr 组合路由 W）
    @(posedge clk);
    wait_cnt = 0;
    while (!m_awready && wait_cnt < TIMEOUT_CYCLES) begin
        @(posedge clk);
        wait_cnt++;
    end
    m_awvalid = 1'b0;
    if (!m_awready) begin
        m_wvalid = 1'b0;        // AW 无握手：短路，不再尝试 W/B
        ok = 1'b0;
        resp = RESP_DECERR;
        $error("[AXI-BFM] AW handshake timeout @%0t addr=%h", $time, addr);
        return;
    end

    // W 握手
    wait_cnt = 0;
    while (!m_wready && wait_cnt < TIMEOUT_CYCLES) begin
        @(posedge clk);
        wait_cnt++;
    end
    m_wvalid = 1'b0;
    if (!m_wready) begin
        ok = 1'b0;
        resp = RESP_DECERR;
        $error("[AXI-BFM] W handshake timeout @%0t addr=%h", $time, addr);
        return;
    end

    // B 响应
    m_bready = 1'b1;
    @(posedge clk);
    wait_cnt = 0;
    while (!m_bvalid && wait_cnt < TIMEOUT_CYCLES) begin
        @(posedge clk);
        wait_cnt++;
    end
    if (!m_bvalid) begin
        ok = 1'b0;
        resp = RESP_DECERR;
        $error("[AXI-BFM] B response timeout @%0t addr=%h", $time, addr);
    end else begin
        resp = m_bresp;         // 完成拍采样（pre-NBA）
    end
    m_bready = 1'b0;
endtask

// ----------------------------------------------------------------------------
// 读传输：AR 握手 → R 数据
// ----------------------------------------------------------------------------
task automatic read (
    input  [ADDR_WIDTH-1:0] addr,
    output [DATA_WIDTH-1:0] data,
    output [1:0]            resp,
    output bit              ok
);
    int unsigned wait_cnt;
    ok = 1'b1;

    m_arid     = '0;
    m_araddr   = addr;
    m_arlen    = 8'd0;
    m_arsize   = 3'd2;
    m_arburst  = 2'b01;
    m_arlock   = 1'b0;
    m_arcache  = 4'd0;
    m_arprot   = 3'd0;
    m_arqos    = 4'd0;
    m_arregion = 4'd0;
    m_arvalid  = 1'b1;

    @(posedge clk);
    wait_cnt = 0;
    while (!m_arready && wait_cnt < TIMEOUT_CYCLES) begin
        @(posedge clk);
        wait_cnt++;
    end
    m_arvalid = 1'b0;
    if (!m_arready) begin
        ok = 1'b0;
        data = '0;
        resp = RESP_DECERR;
        $error("[AXI-BFM] AR handshake timeout @%0t addr=%h", $time, addr);
        return;
    end

    // R 数据
    m_rready = 1'b1;
    @(posedge clk);
    wait_cnt = 0;
    while (!m_rvalid && wait_cnt < TIMEOUT_CYCLES) begin
        @(posedge clk);
        wait_cnt++;
    end
    if (!m_rvalid) begin
        ok   = 1'b0;
        data = '0;
        resp = RESP_DECERR;
        $error("[AXI-BFM] R response timeout @%0t addr=%h", $time, addr);
    end else begin
        data = m_rdata;         // 完成拍采样（pre-NBA）
        resp = m_rresp;
    end
    m_rready = 1'b0;
endtask

// ----------------------------------------------------------------------------
// 复位：各通道回空闲，等待 rst_n 释放（电平等待，可在任意时刻调用）
// ----------------------------------------------------------------------------
task automatic reset();
    m_awvalid = 1'b0;
    m_wvalid  = 1'b0;
    m_bready  = 1'b0;
    m_arvalid = 1'b0;
    m_rready  = 1'b0;
    m_awaddr  = '0;
    m_araddr  = '0;
    wait (rst_n === 1'b1);
    @(posedge clk);
endtask

endmodule : axi_lite_master_bfm
