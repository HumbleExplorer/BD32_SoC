// File: Cdc_Pulse.sv
// 功能：检测 src_clk 域的脉冲，在 dst_clk 域产生单周期脉冲
// 适用：慢时钟域 -> 快时钟域 (如 1MHz -> 100MHz)
// 把慢时钟的"宽脉冲"变成快时钟的"单周期脉冲"。
`timescale 1ns / 1ps
module Cdc_Pulse (
    input  logic dst_clk,   // 目标时钟 (如 100MHz)
    input  logic dst_rst_n,
    input  logic src_pulse, // 源时钟域的脉冲 (如 1MHz 时钟本身)
    output logic dst_pulse  // 同步后的单周期脉冲
);

    // 1. 先把脉冲信号（当作电平）同步到目标域
    logic sync_level;
    
    Cdc_Sync #(
        .WIDTH(1),
        .RESET_VAL(0),
        .DELAY_STAGES(2)
    ) u_sync_level (
        .dst_clk   (dst_clk),
        .dst_rst_n (dst_rst_n),
        .async_sig (src_pulse),
        .sync_sig  (sync_level)
    );

    // 2. 在目标域检测上升沿
    logic sync_level_prev;
    
    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            sync_level_prev <= #1 1'b0;
        end else begin
            sync_level_prev <= #1 sync_level;
        end
    end

    // 3. 输出脉冲
    assign dst_pulse = sync_level & (~sync_level_prev);

endmodule
