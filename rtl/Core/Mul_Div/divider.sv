`timescale 1ns / 1ps
module divider #(
    parameter DATA_WIDTH = 32  // 位宽可配置：16/32/64位通用，默认32位
)(
    input   logic                    clk,            // 系统时钟
    input   logic                    rst_n,          // 异步复位，低有效
    input   logic                    start,         // 运算使能：高有效，触发除法运算启动
    input   logic [1:0]              func3_mode_i,   // 4种运算模式选择
    input   logic [DATA_WIDTH-1:0]   dividend,       // 被除数 (补码形式，直接参与运算)
    input   logic [DATA_WIDTH-1:0]   divisor,        // 除数 (补码形式，直接参与运算)
    output  logic [DATA_WIDTH*2-1:0] quot_rem_o,     // 商+余数组合输出：高N位=余数，低N位=商
    output  logic                    data_valid,     // 结果有效信号: 高有效，结果出时=低
    output  logic                    ready           // 就绪信号: 空闲=高,运算中=低,结果出的周期=高
);

typedef enum logic [2:0] {
    IDLE      = 3'b001,
    CALCULATE = 3'b010,   // 等待计算完成
    DONE      = 3'b100   // 等待写响应
} state_t;

state_t state;

logic  div_rem;         // 0:除法  1:取余
logic  is_unsigned;     // 1:无符号运算  0:有符号运算
assign div_rem     = func3_mode_i[1];
assign is_unsigned = func3_mode_i[0];

//==========================================================================
// 2. 核心参数定义 - 适配恢复余数法，无冗余位宽
//==========================================================================
localparam CNT_WIDTH  = $clog2(DATA_WIDTH) + 1;  // 计数器位宽，自动适配
localparam DONE_CNT   = DATA_WIDTH;              // 固定运算周期 = 位宽次数

//==========================================================================
// 3. 特殊场景判定 (RISC-V标准，无修改，极简逻辑)
// 除零/除数>被除数/除法溢出，三种场景直接输出结果，无需迭代运算
//==========================================================================
logic [DATA_WIDTH-1:0] dividend_abs;
logic [DATA_WIDTH-1:0] divisor_abs;
logic div0;
logic div0_reg;                // 除数为0标记
logic divisor_larger;      // 除数绝对值 > 被除数绝对值 标记
logic divisor_larger_reg;
logic div_overflow;        // 除法溢出标记：仅DIV模式 0x80000000 / 0xffffffff
logic div_overflow_reg;
assign dividend_abs = dividend[DATA_WIDTH-1] ? (~dividend+1) : dividend;
assign divisor_abs = divisor[DATA_WIDTH-1] ? (~divisor+1) : divisor;
assign div0         = ~(|divisor);
assign divisor_larger = is_unsigned ? divisor > dividend : divisor_abs > dividend_abs;
assign div_overflow = (!is_unsigned) && (dividend == {1'b1,{DATA_WIDTH-1{1'b0}}}) && (divisor == {DATA_WIDTH{1'b1}});

//==========================================================================
// 4. 运算节拍计数器 + 状态信号 + ready信号 
// start:运算启动  running:运算中  finish:运算完成
// ready信号：严格满足要求 → 空闲高、运算中低、结果周期高，无任何延迟
//==========================================================================
logic [CNT_WIDTH-1:0] div_cnt;
assign data_valid = (state == DONE);
assign ready = (state == IDLE && ~start) || (state == DONE);

logic [2*DATA_WIDTH:0] dividend_reg;  // 整合余数+商的寄存器: 高N位=余数，低N位=商
//低k次迭代结束时[k:0]保存中间结果，[31：k+1]保存被除数中未参与计算的数据，[63:32]保存每次迭代的被减数
logic [DATA_WIDTH-1:0] divisor_reg;   // 除数寄存器
logic [DATA_WIDTH-1:0] temp_dividend; // 被除数绝对值
logic [DATA_WIDTH-1:0] temp_divisor;  // 除数绝对值
logic [DATA_WIDTH:0] div_temp;      // 减法临时结果，33位防溢出
logic dividend_sign_reg;
logic result_sign_reg;

// 核心减法逻辑：余数 - 除数
assign div_temp = {1'b0,dividend_reg[2*DATA_WIDTH-1:DATA_WIDTH]} - {1'b0,divisor_reg};
assign temp_dividend = is_unsigned ? dividend : dividend_abs;
assign temp_divisor = is_unsigned ? divisor : divisor_abs;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state               <= #1 IDLE;
        div_cnt             <= #1 '0;
        dividend_reg        <= #1 '0;
        divisor_reg         <= #1 '0;
        result_sign_reg     <= #1 '0;
        div0_reg            <= #1 '0;
        divisor_larger_reg  <= #1 '0;
        div_overflow_reg    <= #1 '0;
        dividend_sign_reg   <= #1 '0;
    end else begin
        case(state)
            // -------------------------- 空闲态 --------------------------
            IDLE: begin
                div_cnt             <= #1 '0;
                div0_reg            <= #1 '0;
                divisor_larger_reg  <= #1 '0;
                div_overflow_reg    <= #1 '0;
                if(start) begin // 使能+空闲=启动运算
                    if(div0 || divisor_larger || div_overflow) begin
                        // 特殊场景：直接进入结束态
                        state               <= #1 DONE;
                        div0_reg            <= #1 div0;
                        divisor_larger_reg  <= #1 divisor_larger;
                        div_overflow_reg    <= #1 div_overflow;
                        dividend_reg[2*DATA_WIDTH:DATA_WIDTH+1]<= #1 dividend;
                        divisor_reg         <= #1 divisor;
                    end else begin
                        // 初始化：先取绝对值，有符号运算预处理
                        state                        <= #1 CALCULATE;
                        dividend_reg[2*DATA_WIDTH:0] <= #1 '0;
                        dividend_reg[DATA_WIDTH:1]   <= #1 temp_dividend;
                        divisor_reg                  <= #1 temp_divisor;
                        result_sign_reg              <= #1 dividend[DATA_WIDTH-1] ^ divisor[DATA_WIDTH-1];
                        dividend_sign_reg            <= #1 dividend[DATA_WIDTH-1];
                    end
                end
            end

            // -------------------------- 运算态 --------------------------
            CALCULATE: begin
                div_cnt <= #1 div_cnt + 1'b1;
                // 标准恢复余数法：试商核心步骤
                if(div_temp[DATA_WIDTH] == 1'b1) begin//余数 - 除数 < 0
                    // 不够减：余数恢复原值，商置0，整体左移1位，将被除数还没有参与运算的最高位加入到下一次迭代的被减数中
                    dividend_reg <= #1 {dividend_reg[2*DATA_WIDTH-1:0], 1'b0};//被减数原值即dividend_reg[2*DATA_WIDTH-1:DATA_WIDTH]
                end else begin
                    // 够减：余数更新为减法结果，商置1，整体左移1位,将被除数还没有参与运算的最高位加入到下一次迭代的被减数中
                    dividend_reg <= #1 {div_temp[DATA_WIDTH-1:0], dividend_reg[DATA_WIDTH-1:0], 1'b1};//被减数减法结果即div_temp[DATA_WIDTH-1:0]
                end
                if(div_cnt == DONE_CNT - 1'b1) begin
                    div_cnt <= #1 '0;
                    state   <= #1 DONE; // 进入结束态
                end
            end
            // -------------------------- 结束态：DivEnd --------------------------
            DONE: begin
                // 结果输出完成后，回到空闲态，等待下一次运算
                state <= #1 IDLE;

            end
        endcase
    end
end


//==========================================================================
// 5. 最终结果修正 (极简逻辑，仅2处，严格遵循RISC-V标准)
// ① 特殊场景结果赋值 ② 有符号取余：余数符号必须与被除数一致 (唯一的符号修正)
//==========================================================================
logic [DATA_WIDTH-1:0] final_qt;
logic [DATA_WIDTH-1:0] final_rem;

always_comb begin
    // 场景1：除零，保留你的原逻辑
    if(div0_reg) begin
        if (is_unsigned)
            final_qt  = {1'b1, {DATA_WIDTH-1{1'b0}}};
        else
            final_qt  = {DATA_WIDTH{1'b1}};
        final_rem = dividend_reg[2*DATA_WIDTH:DATA_WIDTH+1];
    // 场景2：除法溢出，保留你的原逻辑
    end else if(div_overflow_reg) begin
        final_qt  = dividend_reg[2*DATA_WIDTH:DATA_WIDTH+1];
        final_rem = {DATA_WIDTH{1'b0}};
    // 场景3：除数>被除数，保留你的原逻辑
    end else if(divisor_larger_reg) begin
        final_qt  = {DATA_WIDTH{1'b0}};
        final_rem = dividend_reg[2*DATA_WIDTH:DATA_WIDTH+1];
    end else if(!is_unsigned) begin // 32次迭代完成：符号修正（仅对有符号运算）；向0取整，余数和被除数同号
        // 修正商的符号：被除数和除数符号异或 → 商取负
        if(result_sign_reg) begin
            final_qt = ~dividend_reg[DATA_WIDTH-1:0] + 1'b1;
        end else begin
            final_qt = dividend_reg[DATA_WIDTH-1:0];
        end
        // 修正余数的符号：余数符号必须和被除数一致，RISC-V标准
        if(dividend_sign_reg ^ dividend_reg[2*DATA_WIDTH]) begin
            final_rem = ~dividend_reg[2*DATA_WIDTH:DATA_WIDTH+1] + 1'b1;
        end else begin
            final_rem = dividend_reg[2*DATA_WIDTH:DATA_WIDTH+1];
        end

    end else begin
        // 默认逻辑：从整合寄存器中拆分 余数+商
        final_rem = dividend_reg[2*DATA_WIDTH:DATA_WIDTH+1];
        final_qt  = dividend_reg[DATA_WIDTH-1:0];
    end
end

//==========================================================================
// 6. 最终输出 (完全保留原代码逻辑)
// 运算完成(finish)时输出结果，其余周期输出0；高N位=余数，低N位=商
//==========================================================================
assign quot_rem_o = (state == DONE) ? {final_rem, final_qt} : {DATA_WIDTH*2{1'b0}};

endmodule