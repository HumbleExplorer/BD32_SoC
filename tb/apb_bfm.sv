// ============================================================================
// apb_bfm.sv — APB3 Master 总线功能模型（BFM）
//
// BD32 — RV32IM Pipelined RISC-V SoC
// Copyright (c) 2026 BD32 Project
// SPDX-License-Identifier: Apache-2.0
// APB3 协议时序：SETUP 相位（m.psel=1, m.penable=0）→ ACCESS 相位
// （m.penable=1）→ 等待 m.pready → 撤销传输。
//
// 传输结果状态：每次 write/read 完成后更新 last_error（ACCESS 完成拍采样的
// m.pslverr）；超时置 timeout_flag 并打印 $error 后返回（避免 TB 无限等待）。
// ============================================================================
timeunit 1ns;
timeprecision 1ps;

module apb_master_bfm #(
    parameter PADDR_WIDTH = 32,
    parameter PDATA_WIDTH = 32,
    parameter int TIMEOUT_CYCLES = 4096   // m.pready 等待上限（防止 TB 无限等待）
)(
    input   logic                       PRESETn,
                                        PCLK,
    apb_if.master                       m
);

// ----------------------------------------------------------------------------
// 完成拍采样 clocking block：input #1step = 沿前稳定值，等价于原
// "完成沿活跃区读未过 NBA 更新值" 的采样意图，且无读写竞争。
// ----------------------------------------------------------------------------
logic [PDATA_WIDTH-1:0] prdata_s;
logic                   pslverr_s;
logic                   pready_s;
always_comb begin
    prdata_s  = m.prdata;
    pslverr_s = m.pslverr;
    pready_s  = m.pready;
end
clocking apb_cb @(posedge PCLK);
    default input #1step;
    input prdata  = prdata_s;
    input pslverr = pslverr_s;
    input pready  = pready_s;
endclocking


// ----------------------------------------------------------------------------
// 传输结果状态（write/read 完成后有效）
// ----------------------------------------------------------------------------
logic last_error;      // 完成拍采样的 m.pslverr
logic timeout_flag;    // 最近一次传输是否 m.pready 超时

function automatic bit get_last_error();
    return last_error;
endfunction

// ----------------------------------------------------------------------------
// 总线空闲态（复位后 / 传输间隙）
// ----------------------------------------------------------------------------
task automatic bus_idle();
    m.psel      = 1'b0;
    m.penable   = 1'b0;
    m.paddr     = {PADDR_WIDTH{1'bx}};
    m.pstrb     = {PDATA_WIDTH/8{1'bx}};
    m.pwdata    = {PDATA_WIDTH{1'bx}};
    m.pwrite    = 1'bx;
endtask

// ----------------------------------------------------------------------------
// 复位：总线进入空闲态，等待 PRESETn 释放
// ----------------------------------------------------------------------------
task automatic reset();
    bus_idle();
    last_error   = 1'b0;
    timeout_flag = 1'b0;
    @(posedge PRESETn);
    #1;
endtask

// ----------------------------------------------------------------------------
// ACCESS 相位公共体：m.penable 已置 1，等待 m.pready 完成拍并采样错误。
// 在完成沿的活跃区采样（读的是该 ACCESS 拍的值，未过 NBA 更新）；
// 返回后调用方先采样 m.prdata 再 #1 做 bus_idle（避开与从机状态寄存器的同沿竞争）。
// ----------------------------------------------------------------------------
task automatic wait_access_complete(input [PADDR_WIDTH-1:0] address);
    int unsigned wait_cnt;
    // 经 clocking block 等待：事件同步与采样都在 Observed 区完成，
    // cb.pready/cb.pslverr = 完成沿的 #1step 预沿值（与原活跃区读未过
    // NBA 更新值语义一致，且无读写竞争）
    @(apb_cb);
    wait_cnt = 0;
    while (apb_cb.pready !== 1'b1 && wait_cnt < TIMEOUT_CYCLES) begin
        @(apb_cb);
        wait_cnt++;
    end
    if (apb_cb.pready !== 1'b1) begin
        timeout_flag = 1'b1;
        $error("[APB-BFM] m.pready timeout (%0d cycles) @%0t addr=%h",
               TIMEOUT_CYCLES, $time, address);
        last_error = 1'b0;
    end else begin
        last_error   = apb_cb.pslverr;
        timeout_flag = 1'b0;
    end
endtask

// ----------------------------------------------------------------------------
// 写传输：SETUP 一拍 → ACCESS 相位等待 m.pready → 结束
// ----------------------------------------------------------------------------
task automatic write (
    input [PADDR_WIDTH  -1:0] address,
    input [PDATA_WIDTH/8-1:0] strb,
    input [PDATA_WIDTH  -1:0] data
);
    // SETUP 相位
    m.psel    = 1'b1;
    m.penable = 1'b0;
    m.paddr   = address;
    m.pstrb   = strb;
    m.pwdata  = data;
    m.pwrite  = 1'b1;
    @(posedge PCLK);
    #1;

    // ACCESS 相位，等待从机就绪
    m.penable = 1'b1;
    wait_access_complete(address);
    #1;

    // 传输结束，总线回到空闲
    bus_idle();
endtask

// ----------------------------------------------------------------------------
// 读传输：SETUP 一拍 → ACCESS 相位等待 m.pready → 采样 m.prdata → 结束。
// 与 write 对称：完成拍即回空闲（m.psel 不多挂一拍，避免无 SETUP 的幻影 ACCESS）。
// ----------------------------------------------------------------------------
task automatic read (
    input  [PADDR_WIDTH -1:0] address,
    output [PDATA_WIDTH -1:0] data
);
    // SETUP 相位
    m.psel    = 1'b1;
    m.penable = 1'b0;
    m.paddr   = address;
    m.pstrb   = '0;               // 读传输 m.pstrb 无意义，驱动 0 便于 X 传播检查
    m.pwdata  = {PDATA_WIDTH{1'bx}};
    m.pwrite  = 1'b0;
    @(posedge PCLK);
    #1;

    // ACCESS 相位，等待从机就绪后采样数据
    m.penable = 1'b1;
    wait_access_complete(address);
    data = apb_cb.prdata;

    // 结束后回到空闲
    #1;
    bus_idle();
endtask

endmodule : apb_master_bfm
