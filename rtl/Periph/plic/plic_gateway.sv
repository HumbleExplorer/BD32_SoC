timeunit 1ns;
timeprecision 1ps;
// =============================================================================
// PLIC Gateway - 单中断源 Gateway
// 支持电平触发(LEVEL)与边沿触发(EDGE)两种模式，通过参数 TRIGGER_MODE 选择
// 电平触发: pending = irq_source & gateway_open
// 边沿触发: 检测上升沿，ip 寄存器保持 pending 直到 claim
// claim/complete 状态机确保同一中断不会被重复 claim
// =============================================================================
module plic_gateway #(
    parameter TRIGGER_MODE = 0  // 0 = LEVEL (电平), 1 = EDGE (边沿)
)(
    input  logic clk,
    input  logic rst_n,         // 异步复位，低有效

    input  logic irq_source,    // 来自外设的原始中断输入
    input  logic claim,         // 脉冲: 该源已被 claim
    input  logic complete,      // 脉冲: 该源处理完成

    output logic pending        // pending 状态
);

    // Gateway 状态标志: 1 = 开放接收中断, 0 = 已 claim 等待 complete
    logic gateway_open;

    generate
        // =====================================================================
        // 电平触发模式 (Level-Triggered)
        // =====================================================================
        if (TRIGGER_MODE == 0) begin : gen_level_triggered

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    gateway_open <= 1'b1;
                end else begin
                    if (claim) begin
                        // claim 关闭 gateway，防止重复 claim
                        gateway_open <= 1'b0;
                    end else if (complete) begin
                        // complete 重新开放 gateway
                        gateway_open <= 1'b1;
                    end
                end
            end

            assign pending = irq_source & gateway_open;

        // =====================================================================
        // 边沿触发模式 (Edge-Triggered)
        // =====================================================================
        end else begin : gen_edge_triggered

            logic ip;               // 内部 pending 锁存器
            logic irq_source_prev;  // 上一周期的 irq_source 采样

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    gateway_open    <= 1'b1;
                    ip              <= 1'b0;
                    irq_source_prev <= 1'b0;
                end else begin
                    irq_source_prev <= irq_source;

                    if (claim) begin
                        // claim 清除 ip 并关闭 gateway
                        ip           <= 1'b0;
                        gateway_open <= 1'b0;
                    end else if (complete) begin
                        // complete 重新开放 gateway
                        gateway_open <= 1'b1;
                    end else if (irq_source && !irq_source_prev && gateway_open) begin
                        // 上升沿检测且 gateway 开放时锁存 pending
                        ip <= 1'b1;
                    end
                end
            end

            assign pending = ip;

        end
    endgenerate

endmodule
