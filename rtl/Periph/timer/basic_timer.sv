// ============================================================================
// basic_timer.sv — 基本定时器（预分频/自动装载/16/32 位计数）
//
// BD32 — RV32IM Pipelined RISC-V SoC
// Copyright (c) 2026 BD32 Project
// SPDX-License-Identifier: Apache-2.0
//
// 参考来源（大幅改编）：
//   1) Opensoc 107_apb_timer/basic_timer.v（MIT License）
//      Copyright (c) 2024 Panda, 2257691535@qq.com
//   2) E203_RTL timer 模块（Apache-2.0, Nuclei System Technology, Inc.）
//   修改说明：宽度参数化、递增/递减计数、预分频重写
// ============================================================================
/*
 * basic_timer.sv - 基本定时器模块
 *
 * 功能描述：
 *   带预分频和自动装载功能的基本定时器
 *   支持16/32位计数器，支持递增/递减计数
 *   支持计数使能和复位
 *
 * 寄存器接口：
 *   - prescale: 预分频系数 (计数周期 = prescale + 1)
 *   - autoload: 自动重载值 (溢出值)
 *   - timer_cnt: 当前计数值
 *   - timer_en: 定时器使能
 *   - timer_clr: 定时器复位
 *   - timer_dir: 计数方向 (0=递增, 1=递减)
 *
 * 日期：2026/03/31
 */
`include "../../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;

module basic_timer #(
    parameter TIMER_WIDTH = 16  // 定时器位宽 (16或32)
)(
    // 时钟和复位
    input  logic                       clk,
    input  logic                       rst_n,

    // 定时器配置
    input  logic [TIMER_WIDTH-1:0]     prescale,    // 预分频系数 - 1
    input  logic [TIMER_WIDTH-1:0]     autoload,    // 自动重载值 - 1
    input  logic                       timer_en,    // 定时器使能
    input  logic                       timer_clr,   // 定时器复位
    input  logic                       timer_dir,   // 计数方向 (0=递增, 1=递减)

    // 计数值接口
    input  logic                       cnt_wr_en,   // 计数值写使能
    input  logic [TIMER_WIDTH-1:0]     cnt_wr_data, // 计数值写数据
    output logic [TIMER_WIDTH-1:0]     cnt_rd_data, // 计数值读数据

    // 状态输出
    output logic                       timer_expired,     // 计数溢出指示
    output logic                       timer_expired_req  // 溢出中断请求
);

    //////////////////////////////////////////////////////////////////
    //
    // 内部信号
    //

    // 预分频计数器
    logic [TIMER_WIDTH-1:0] prescale_cnt;
    logic [TIMER_WIDTH-1:0] prescale_shadow;
    logic                   prescale_match;

    // 定时计数器
    logic [TIMER_WIDTH-1:0] timer_cnt;
    logic                   timer_cnt_match;

    // 溢出延迟寄存器
    logic                   timer_expired_d;

    //////////////////////////////////////////////////////////////////
    //
    // 信号赋值
    //

    assign prescale_match = (prescale_cnt == prescale_shadow) && (prescale_shadow != 0);//严禁将预分频系数设为0
    assign timer_cnt_match = timer_dir ? (timer_cnt == '0) : (timer_cnt == autoload);

    assign cnt_rd_data = timer_cnt;
    assign timer_expired = timer_en & prescale_match & timer_cnt_match;
    assign timer_expired_req = timer_expired_d;

    //////////////////////////////////////////////////////////////////
    //
    // 预分频计数器
    //

    // 预分频影子寄存器 - 在定时器禁用或预分频计数完成时更新
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prescale_shadow <= #1 '0;
        end else if (!timer_en || (timer_en && prescale_match)) begin
            prescale_shadow <= #1 prescale;
        end
    end

    // 预分频计数器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prescale_cnt <= #1 '0;
        end else if (!timer_en || timer_clr) begin
            prescale_cnt <= #1 '0;
        end else if (prescale_match) begin
            prescale_cnt <= #1 '0;
        end else begin
            prescale_cnt <= #1 prescale_cnt + 1'b1;
        end
    end

    //////////////////////////////////////////////////////////////////
    //
    // 定时计数器
    //

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_cnt <= #1 '0;
        end else if (timer_clr || !timer_en) begin
            timer_cnt <= #1 '0;
        end else if (cnt_wr_en) begin
            // 软件写计数值
            timer_cnt <= #1 cnt_wr_data;
        end else if (timer_en && prescale_match) begin
            if (timer_cnt_match) begin
                // 溢出时重载
                timer_cnt <= #1 timer_dir ? autoload : '0;
            end else begin
                // 正常计数
                timer_cnt <= #1 timer_dir ? (timer_cnt - 1'b1) : (timer_cnt + 1'b1);
            end
        end
    end

    //////////////////////////////////////////////////////////////////
    //
    // 溢出中断请求
    //

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_expired_d <= #1 1'b0;
        end else begin
            timer_expired_d <= #1 timer_expired;
        end
    end

endmodule
