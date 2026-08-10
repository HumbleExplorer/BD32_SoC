// ============================================================================
// apb_bfm.sv — APB3 Master 总线功能模型（BFM）
//
// BD32 — RV32IM Pipelined RISC-V SoC
// Copyright (c) 2026 BD32 Project
// SPDX-License-Identifier: Apache-2.0
// APB3 协议时序：SETUP 相位（PSEL=1, PENABLE=0）→ ACCESS 相位
// （PENABLE=1）→ 等待 PREADY → 撤销传输。
// ============================================================================
timeunit 1ns;
timeprecision 1ps;

module apb_master_bfm #(
    parameter PADDR_WIDTH = 32,
    parameter PDATA_WIDTH = 32
)(
    input   logic                       PRESETn,
                                        PCLK,

    // APB Master Interface
    output  logic                       PSEL,
    output  logic                       PENABLE,
    output  logic   [PADDR_WIDTH  -1:0] PADDR,
    output  logic   [PDATA_WIDTH/8-1:0] PSTRB,
    output  logic   [PDATA_WIDTH  -1:0] PWDATA,
    input   logic   [PDATA_WIDTH  -1:0] PRDATA,
    output  logic                       PWRITE,
    input   logic                       PREADY,
    input   logic                       PSLVERR
);

// ----------------------------------------------------------------------------
// 总线空闲态（复位后 / 传输间隙）
// ----------------------------------------------------------------------------
task automatic bus_idle();
    PSEL      = 1'b0;
    PENABLE   = 1'b0;
    PADDR     = {PADDR_WIDTH{1'bx}};
    PSTRB     = {PDATA_WIDTH/8{1'bx}};
    PWDATA    = {PDATA_WIDTH{1'bx}};
    PWRITE    = 1'bx;
endtask

// ----------------------------------------------------------------------------
// 复位：总线进入空闲态，等待 PRESETn 释放
// ----------------------------------------------------------------------------
task automatic reset();
    bus_idle();
    @(posedge PRESETn);
    #1;
endtask

// ----------------------------------------------------------------------------
// 写传输：SETUP 一拍 → ACCESS 相位等待 PREADY → 结束
// ----------------------------------------------------------------------------
task automatic write (
    input [PADDR_WIDTH  -1:0] address,
    input [PDATA_WIDTH/8-1:0] strb,
    input [PDATA_WIDTH  -1:0] data
);
    // SETUP 相位
    PSEL    = 1'b1;
    PENABLE = 1'b0;
    PADDR   = address;
    PSTRB   = strb;
    PWDATA  = data;
    PWRITE  = 1'b1;
    @(posedge PCLK);
    #1;

    // ACCESS 相位，等待从机就绪
    PENABLE = 1'b1;
    @(posedge PCLK);  // PENABLE 保持一个完整周期，保证从机在沿上采样到写
    while (!PREADY)
        @(posedge PCLK);
    #1;

    // 传输结束，总线回到空闲
    bus_idle();
endtask

// ----------------------------------------------------------------------------
// 读传输：SETUP 一拍 → ACCESS 相位等待 PREADY → 采样 PRDATA → 结束
// ----------------------------------------------------------------------------
task automatic read (
    input  [PADDR_WIDTH -1:0] address,
    output [PDATA_WIDTH -1:0] data
);
    // SETUP 相位
    PSEL    = 1'b1;
    PENABLE = 1'b0;
    PADDR   = address;
    PSTRB   = {PDATA_WIDTH/8{1'bx}};
    PWDATA  = {PDATA_WIDTH{1'bx}};
    PWRITE  = 1'b0;
    @(posedge PCLK);
    #1;

    // ACCESS 相位，等待从机就绪后采样数据
    PENABLE = 1'b1;
    while (!PREADY)
        @(posedge PCLK);
    #1;
    data = PRDATA;

    // 结束一拍后回到空闲
    @(posedge PCLK);
    #1;
    bus_idle();
endtask

endmodule : apb_master_bfm
