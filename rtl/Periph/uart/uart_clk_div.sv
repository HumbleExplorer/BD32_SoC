// 注意：此处divisor = SYS_CLK_FREQ/BAUD/16
// 经计算，当主频为50MHz，波特率为115200时，波特率偏差为0.47%
module uart_clk_div (
    input  logic        clk,        // 任意频率系统时钟
    input  logic        rst_n,      // 异步复位，低有效
    input  logic[15:0]  divisor,    // 16位整数除数（兼容16550，≥2）
    output logic        clk_sample, // 16x 采样时钟（50%占空比）
    output logic        clk_uart    // 1x 发送时钟（50%占空比）
);
localparam SAMPLE_DIV = 16;        // 16x采样时钟再分频为1x发送时钟的系数
// 内部寄存器：循环计数器
logic [15:0] div_cnt;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        // 复位时计数器清零
        div_cnt <= {16{1'b0}};
    end else begin
        if(div_cnt == divisor - 1'b1) begin
            // 计数到分频系数-1时，计数器清零（完成一次循环）
            div_cnt <= {16{1'b0}};
        end else begin
            // 未计数到最大值时，计数器自增1
            div_cnt <= div_cnt + 1'b1;
        end
    end
end
// 内部参数与信号定义
// 中间寄存器：奇数分频专用
logic clkp_div_r;
logic clkn_div_r;
logic [3:0]  uart_cnt;             // 16x采样时钟的分频计数器（用于clk_uart）
// 上升沿触发生成奇数分频中间信号clkp_div_r
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        clkp_div_r <= 1'b0;
    end
    else if (div_cnt == divisor[15:1] - 1) begin
        clkp_div_r <= 1'b0;
    end
    else if (div_cnt == divisor - 1'b1) begin
        clkp_div_r <= 1'b1;
    end
end
// 下降沿触发生成奇数分频中间信号clkn_div_r
always_ff @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
        clkn_div_r <= 1'b0;
    end
    else if (div_cnt == divisor[15:1] - 1) begin
        clkn_div_r <= 1'b0;
    end
    else if (div_cnt == divisor - 1) begin
        clkn_div_r <= 1'b1;
    end
end
assign clk_sample = divisor[0] ? clkp_div_r | clkn_div_r://奇数分频
(div_cnt < divisor[15:1]);//偶数分频
                    


// 第二级分频：16x采样时钟分频为1x发送时钟（固定16分频）
always_ff @(posedge clk_sample or negedge rst_n) begin
    if (!rst_n) begin
        uart_cnt <= '0;
        clk_uart <= 1'b0;
    end else begin
        if (uart_cnt == (SAMPLE_DIV - 1)) begin
            uart_cnt <= '0;
            clk_uart <= ~clk_uart;
        end else begin
            uart_cnt <= uart_cnt + 1'b1;
            // 16分频（偶数），中间点翻转保证50%占空比
            if (uart_cnt == (SAMPLE_DIV >> 1) - 1) begin
                clk_uart <= ~clk_uart;
            end
        end
    end
end

endmodule