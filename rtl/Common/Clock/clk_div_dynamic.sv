// 分频系数作为输入信号，可动态调整，支持任意整数。
module clk_div_dynamic #(
    parameter DIV_WIDTH = 16
)(
    input   logic                   clk_in, // 输入时钟
    input   logic                   rst_n,  // 复位信号
    input   logic   [DIV_WIDTH-1:0] divisor,// 分频系数（≥2）
    output  logic                   clk_out // 输出时钟
);  

// 内部寄存器：循环计数器
logic [DIV_WIDTH-1:0] div_cnt;
always_ff @(posedge clk_in or negedge rst_n) begin
    if(!rst_n) begin
        // 复位时计数器清零
        div_cnt <= {DIV_WIDTH{1'b0}};
    end else begin
        if(div_cnt == divisor - 1'b1) begin
            // 计数到分频系数-1时，计数器清零（完成一次循环）
            div_cnt <= {DIV_WIDTH{1'b0}};
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
// 上升沿触发生成奇数分频中间信号clkp_div_r
always_ff @(posedge clk_in or negedge rst_n) begin
    if (!rst_n) begin
        clkp_div_r <= 1'b0;
    end
    else if (div_cnt == divisor[DIV_WIDTH-1:1] - 1) begin
        clkp_div_r <= 1'b0;
    end
    else if (div_cnt == divisor - 1'b1) begin
        clkp_div_r <= 1'b1;
    end
end
// 下降沿触发生成奇数分频中间信号clkn_div_r
always_ff @(negedge clk_in or negedge rst_n) begin
    if (!rst_n) begin
        clkn_div_r <= 1'b0;
    end
    else if (div_cnt == divisor[DIV_WIDTH-1:1] - 1) begin
        clkn_div_r <= 1'b0;
    end
    else if (div_cnt == divisor - 1) begin
        clkn_div_r <= 1'b1;
    end
end
assign clk_out = divisor[0] ? clkp_div_r | clkn_div_r://奇数分频
(div_cnt < divisor[DIV_WIDTH-1:1])? clkp_div_r : clkn_div_r;//偶数分频

endmodule