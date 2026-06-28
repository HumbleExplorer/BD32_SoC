// =============================================================================
// nco_baudgen — NCO 波特率发生器
// 32 位相位累加器，产生 16× 波特率采样使能脉冲
// FCW = (Baud × 16 / Fclk) × 2^32
//   例：115200 baud → FCW = (115200 × 16 / 100M) × 2^32 ≈ 79,164,837
// =============================================================================
timeunit 1ns;
timeprecision 1ps;
module nco_baudgen #(
    parameter FCW_WIDTH = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [FCW_WIDTH-1:0]    fcw,            // 频率控制字
    output logic                    sample_pulse    // 1 周期宽采样使能脉冲
);

logic [FCW_WIDTH-1:0] phase_acc;
logic [FCW_WIDTH:0] sum, sum_r;

assign sum = phase_acc + fcw;

always_ff @(posedge clk or negedge rst_n)
begin
    if(!rst_n) begin
        phase_acc <= '0;
        sum_r     <= '0;
    end else begin
        phase_acc <= sum[FCW_WIDTH-1:0];
        sum_r     <= sum;            // 寄存器打一拍，过滤组合进位链毛刺
    end
end

assign sample_pulse = sum_r[FCW_WIDTH];

endmodule
