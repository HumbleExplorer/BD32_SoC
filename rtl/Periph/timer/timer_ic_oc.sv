/*
 * timer_ic_oc.sv - 输入捕获/输出比较模块
 *
 * 功能描述：
 *   支持输入捕获和输出比较功能
 *   输入捕获：捕获上升沿/下降沿/双沿，支持输入滤波
 *   输出比较：计数值与比较值匹配时产生输出
 *
 * 寄存器接口：
 *   - ic_oc_mode: 输入捕获/输出比较模式选择 (0=捕获, 1=比较)
 *   - filter_mode: 输入滤波阈值
 *   - ic_oc_en: 输入捕获/输出比较使能
 *   - polarity: 输出极性
 *   - trigger_mode: 捕获触发边沿类型 (00=上升沿, 01=下降沿, 10=双沿)
 *   - cmp_value: 比较值 (来自APB)
 *   - cap_value: 捕获值 (输出到顶层)
 *
 * 作者：
 * 日期：2026/03/31
 */
`include "../../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;

module timer_ic_oc #(
    parameter TIMER_WIDTH = 16  // 定时器位宽
)(
    // 时钟和复位
    input  logic                       clk,
    input  logic                       rst_n,

    // 外部信号接口
    input  logic                       ext_in,      // 外部输入信号 (捕获)
    output logic                       ext_out,     // 外部输出信号 (比较)
    output logic                       ext_dir,     // 三态门方向 (0=输出, 1=输入)

    // 定时器接口
    input  logic [TIMER_WIDTH-1:0]     timer_cnt,   // 当前计数值
    input  logic                       timer_dir_sel, // 计数方向选择 (0=正向, 1=反向)
    input  logic                       timer_en,    // 定时器使能
    input  logic                       timer_expired, // 定时器溢出

    // 配置接口
    input  logic                       ic_oc_mode,  // 模式选择 (0=捕获, 1=比较)
    input  logic [3:0]                 filter_mode, // 滤波阈值
    input  logic                       ic_oc_en,    // 使能
    input  logic                       polarity,    // 输出极性
    input  logic [1:0]                 trigger_mode, // 触发边沿类型
    input  logic [TIMER_WIDTH-1:0]     cmp_value,   // 比较值 (来自APB)
    output logic [TIMER_WIDTH-1:0]     cap_value,   // 捕获值 (输出到顶层)

    // 中断输出
    output logic                       ic_oc_irq    // 输入捕获中断
);

    //////////////////////////////////////////////////////////////////
    //
    // 常量定义
    //

    // 触发边沿类型
    typedef enum logic [1:0] {
        EDGE_RISING  = 2'b00,  // 上升沿
        EDGE_FALLING = 2'b01,  // 下降沿
        EDGE_BOTH    = 2'b10   // 双沿 
    }trigger_mode_e;

    // 输入捕获状态
    typedef enum logic [3:0] {
        IC_IDLE     = 4'b0001,  // 空闲
        IC_FILTER   = 4'b0010,  // 滤波中
        IC_CONFIRM  = 4'b0100,  // 确认
        IC_CAPTURE  = 4'b1000   // 捕获
    }ic_state_e;

    //////////////////////////////////////////////////////////////////
    //
    // 内部信号
    //

    // 输入捕获相关
    logic [3:0]               ext_in_dly;       // 输入延迟 (用于边沿检测)
    logic                     rising_edge;      // 上升沿检测
    logic                     falling_edge;     // 下降沿检测
    logic                     valid_edge;       // 有效边沿

    ic_state_e                ic_state;         // 输入捕获状态
    logic [TIMER_WIDTH-1:0]   captured_value;   // 捕获的值
    logic                     captured_edge;    // 捕获的边沿类型 (0=下降沿, 1=上升沿)
    logic [3:0]               filter_cnt;       // 滤波计数器
    logic [3:0]               filter_th_latch;  // 锁存的滤波阈值
    logic                     filter_done;      // 滤波完成

    logic                     capture_trigger;  // 捕获触发信号
    logic                     capture_trigger_d;// 延迟的捕获触发

    // 输出比较相关
    logic                     cmp_match;        // 比较匹配
    logic                     cmp_output;       // 比较输出
    logic                     cmp_output_d;     // 延迟的比较输出

    // 内部比较寄存器
    logic [TIMER_WIDTH-1:0]   cmp_reg;

    //////////////////////////////////////////////////////////////////
    //
    // 信号赋值
    //

    assign rising_edge  = ext_in_dly[2] & ~ext_in_dly[3];
    assign falling_edge = ~ext_in_dly[2] & ext_in_dly[3];

    assign valid_edge = timer_en & ~ic_oc_mode & ic_oc_en & ( // 输入捕获模式有效边沿检测
        (trigger_mode == EDGE_RISING  && rising_edge)  ||
        (trigger_mode == EDGE_FALLING && falling_edge) ||
        (trigger_mode == EDGE_BOTH    && (rising_edge || falling_edge))
    );

    assign filter_done = (filter_cnt == filter_th_latch);
    assign capture_trigger = (ic_state == IC_CAPTURE);

    assign cmp_match = timer_en & ic_oc_mode & ic_oc_en &
          (timer_dir_sel ? (timer_cnt <= cmp_reg) : (timer_cnt >= cmp_reg)); // 输出比较匹配
    assign cmp_output = polarity ? ~cmp_match : cmp_match;// 输出极性控制

    assign cap_value   = captured_value;
    assign ic_oc_irq   = capture_trigger_d;
    assign ext_out     = cmp_output_d;
    assign ext_dir     = ~(ic_oc_mode & ic_oc_en);  // 比较模式且使能时为输出

    //////////////////////////////////////////////////////////////////
    //
    // 输入延迟 (用于边沿检测)
    //

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ext_in_dly <= '0;
        end else begin
            ext_in_dly <= {ext_in_dly[2:0], ext_in};
        end
    end

    //////////////////////////////////////////////////////////////////
    //
    // 输入捕获状态机
    //

    // 状态机
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ic_state <= IC_IDLE;
        end else begin
            case (ic_state)
                IC_IDLE: begin
                    if (valid_edge) begin
                        ic_state <= IC_FILTER;
                    end
                end
                IC_FILTER: begin
                    if (filter_done) begin
                        ic_state <= IC_CONFIRM;
                    end
                end
                IC_CONFIRM: begin
                    // 确认边沿是否稳定
                    if (ext_in_dly[2] == captured_edge) begin
                        ic_state <= IC_CAPTURE;
                    end else begin
                        ic_state <= IC_IDLE;
                    end
                end
                IC_CAPTURE: begin
                    ic_state <= IC_IDLE;
                end
                default: begin
                    ic_state <= IC_IDLE;
                end
            endcase
        end
    end

    // 捕获值锁存
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            captured_value <= '0;
            captured_edge  <= 1'b0;
            filter_th_latch <= '0;
        end else if (ic_state == IC_IDLE && valid_edge) begin
            captured_value <= timer_cnt;
            captured_edge  <= rising_edge;
            filter_th_latch <= filter_mode;
        end
    end

    // 滤波计数器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            filter_cnt <= '0;
        end else if (ic_state == IC_IDLE) begin
            filter_cnt <= '0;
        end else if (ic_state == IC_FILTER) begin
            filter_cnt <= filter_cnt + 1'b1;
        end
    end

    // 捕获触发延迟
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            capture_trigger_d <= 1'b0;
        end else begin
            capture_trigger_d <= capture_trigger;
        end
    end

    //////////////////////////////////////////////////////////////////
    //
    // 输出比较寄存器加载
    //

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmp_reg <= '0;
        end else if (!timer_en || timer_expired) begin
            cmp_reg <= cmp_value;
        end
    end

    //////////////////////////////////////////////////////////////////
    //
    // 输出比较
    //

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmp_output_d <= 1'b0;
        end else begin
            cmp_output_d <= cmp_output;
        end
    end

endmodule