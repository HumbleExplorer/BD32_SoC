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
    // AXI4 Master 接口（接口）
    axi_if.master m
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

    m.awid     = '0;
    m.awaddr   = addr;
    m.awlen    = 8'd0;
    m.awsize   = 3'd2;          // 4 bytes
    m.awburst  = 2'b01;         // INCR
    m.awlock   = 1'b0;
    m.awcache  = 4'd0;
    m.awprot   = 3'd0;
    m.awqos    = 4'd0;
    m.awregion = 4'd0;
    m.awvalid  = 1'b1;
    m.wdata    = data;
    m.wstrb    = strb;
    m.wlast    = 1'b1;
    m.wvalid   = 1'b1;

    // AW 握手（W 握手完成前保持 m.awaddr 稳定：互联按 awaddr 组合路由 W）
    @(posedge clk);
    wait_cnt = 0;
    while (!m.awready && wait_cnt < TIMEOUT_CYCLES) begin
        @(posedge clk);
        wait_cnt++;
    end
    m.awvalid = 1'b0;
    if (!m.awready) begin
        m.wvalid = 1'b0;        // AW 无握手：短路，不再尝试 W/B
        ok = 1'b0;
        resp = RESP_DECERR;
        $error("[AXI-BFM] AW handshake timeout @%0t addr=%h", $time, addr);
        return;
    end

    // W 握手
    wait_cnt = 0;
    while (!m.wready && wait_cnt < TIMEOUT_CYCLES) begin
        @(posedge clk);
        wait_cnt++;
    end
    m.wvalid = 1'b0;
    if (!m.wready) begin
        ok = 1'b0;
        resp = RESP_DECERR;
        $error("[AXI-BFM] W handshake timeout @%0t addr=%h", $time, addr);
        return;
    end

    // B 响应
    m.bready = 1'b1;
    @(posedge clk);
    wait_cnt = 0;
    while (!m.bvalid && wait_cnt < TIMEOUT_CYCLES) begin
        @(posedge clk);
        wait_cnt++;
    end
    if (!m.bvalid) begin
        ok = 1'b0;
        resp = RESP_DECERR;
        $error("[AXI-BFM] B response timeout @%0t addr=%h", $time, addr);
    end else begin
        resp = m.bresp;         // 完成拍采样（pre-NBA）
    end
    m.bready = 1'b0;
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

    m.arid     = '0;
    m.araddr   = addr;
    m.arlen    = 8'd0;
    m.arsize   = 3'd2;
    m.arburst  = 2'b01;
    m.arlock   = 1'b0;
    m.arcache  = 4'd0;
    m.arprot   = 3'd0;
    m.arqos    = 4'd0;
    m.arregion = 4'd0;
    m.arvalid  = 1'b1;

    @(posedge clk);
    wait_cnt = 0;
    while (!m.arready && wait_cnt < TIMEOUT_CYCLES) begin
        @(posedge clk);
        wait_cnt++;
    end
    m.arvalid = 1'b0;
    if (!m.arready) begin
        ok = 1'b0;
        data = '0;
        resp = RESP_DECERR;
        $error("[AXI-BFM] AR handshake timeout @%0t addr=%h", $time, addr);
        return;
    end

    // R 数据
    m.rready = 1'b1;
    @(posedge clk);
    wait_cnt = 0;
    while (!m.rvalid && wait_cnt < TIMEOUT_CYCLES) begin
        @(posedge clk);
        wait_cnt++;
    end
    if (!m.rvalid) begin
        ok   = 1'b0;
        data = '0;
        resp = RESP_DECERR;
        $error("[AXI-BFM] R response timeout @%0t addr=%h", $time, addr);
    end else begin
        data = m.rdata;         // 完成拍采样（pre-NBA）
        resp = m.rresp;
    end
    m.rready = 1'b0;
endtask

// ----------------------------------------------------------------------------
// 复位：各通道回空闲，等待 rst_n 释放（电平等待，可在任意时刻调用）
// ----------------------------------------------------------------------------
task automatic reset();
    m.awvalid = 1'b0;
    m.wvalid  = 1'b0;
    m.bready  = 1'b0;
    m.arvalid = 1'b0;
    m.rready  = 1'b0;
    m.awaddr  = '0;
    m.araddr  = '0;
    wait (rst_n === 1'b1);
    @(posedge clk);
endtask

endmodule : axi_lite_master_bfm
