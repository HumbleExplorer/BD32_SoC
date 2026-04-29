// File: Cdc_Sync.sv
// 功能：将 async_sig 同步到 dst_clk 时钟域（慢到快）
// 说明：这是一个标准 IP，不要随意修改内部逻辑
// 用于同步简单的电平信号（比如复位信号、状态标志）。
`timescale 1ns / 1ps
module Cdc_Sync #(
    parameter WIDTH = 1,      // 信号位宽，通常为1
    parameter RESET_VAL = 0,   // 复位后的默认值
    parameter DELAY_STAGES = 2  // 同步延迟，默认为2
)(
    input  logic                dst_clk,  // 目标时钟
    input  logic                dst_rst_n,// 异步复位（低有效）
    input  logic [WIDTH-1:0]    async_sig,// 异步输入信号
    output logic [WIDTH-1:0]    sync_sig  // 同步输出信号
);
generate
    if (DELAY_STAGES == 0) begin
        assign sync_sig = async_sig;
    end else begin
        // 使用两级触发器进行同步
        (* ASYNC_REG = "TRUE" *)logic [WIDTH-1:0] sync_reg [DELAY_STAGES-1:0];

        always_ff @(posedge dst_clk or negedge dst_rst_n) begin
            if (!dst_rst_n) begin
                for (int n=0; n<DELAY_STAGES; n++) begin
                    sync_reg[n] <= #1 RESET_VAL;
                end
            end else begin
                for (int n=0; n<DELAY_STAGES; n++) begin
                    if (n==0)   sync_reg[n] <= #1 async_sig;
                    else        sync_reg[n] <= #1 sync_reg[n-1];
                end
            end
        end
        assign sync_sig = sync_reg[DELAY_STAGES-1];
    end
endgenerate
    

endmodule
