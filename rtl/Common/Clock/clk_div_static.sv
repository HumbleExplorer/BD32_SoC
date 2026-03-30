// 分频系数参数化，不能动态调整，支持任意整数
`timescale 1ns / 1ps
module clk_div_static #(
    parameter DIV_NUM = 10,
    localparam CNT_WIDTH = $clog2(DIV_NUM)
)(
    input   logic   clk_in, // 输入时钟
    input   logic   rst_n,  // 复位信号（低电平有效）
    output  logic   clk_out // 分频后输出时钟
);

// 内部寄存器：循环计数器
logic [CNT_WIDTH-1:0] div_cnt;
always_ff @(posedge clk_in or negedge rst_n) begin
    if(!rst_n) begin
        // 复位时计数器清零
        div_cnt <= #1 {CNT_WIDTH{1'b0}};
    end else begin
        if(div_cnt == DIV_NUM - 1'b1) begin
            // 计数到分频系数-1时，计数器清零（完成一次循环）
            div_cnt <= #1 {CNT_WIDTH{1'b0}};
        end else begin
            // 未计数到最大值时，计数器自增1
            div_cnt <= #1 div_cnt + 1'b1;
        end
    end
end

generate
    if(DIV_NUM[0] == 0) begin // 偶数分频
        assign clk_out = (div_cnt < (DIV_NUM >> 1)) ? 1'b1 : 1'b0;
    end else begin // 奇数分频
        // 中间寄存器
        logic clkp_div_r;
        logic clkn_div_r;
        // 上升沿触发生成奇数分频中间信号clkp_div_r
        always_ff @(posedge clk_in or negedge rst_n) begin
            if (!rst_n) begin
                clkp_div_r <= 1'b0;
            end
            else if (div_cnt == (DIV_NUM >> 1) - 1) begin
                clkp_div_r <= 1'b0;
            end
            else if (div_cnt == DIV_NUM - 1'b1) begin
                clkp_div_r <= 1'b1;
            end
        end

        // 下降沿触发生成奇数分频中间信号clkn_div_r
        always_ff @(negedge clk_in or negedge rst_n) begin
            if (!rst_n) begin
                clkn_div_r <= 1'b0;
            end
            else if (div_cnt == (DIV_NUM >> 1) - 1) begin
                clkn_div_r <= 1'b0;
            end
            else if (div_cnt == DIV_NUM - 1) begin
                clkn_div_r <= 1'b1;
            end
        end

        // 或操作合并两个中间信号，生成50%占空比奇数分频输出
        assign clk_out = clkp_div_r | clkn_div_r ;
    end
endgenerate

endmodule