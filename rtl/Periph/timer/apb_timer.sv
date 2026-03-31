/*
 * apb_timer.sv - APB Timer 模块
 *
 * 功能描述：
 *   基于APB总线的高级定时器，支持：
 *   - 16/32位计数器
 *   - 预分频器
 *   - 自动重载
 *   - 递增/递减计数
 *   - 4通道输入捕获/输出比较
 *   - 中断管理
 *
 * 寄存器映射：
 *   0x00 TIMx_PSC   - 预分频系数寄存器
 *   0x04 TIMx_CNT   - 计数器寄存器
 *   0x08 TIMx_ARR   - 自动重载寄存器
 *   0x0c TIMx_CR    - 控制寄存器
 *   0x10 TIMx_IER   - 中断使能寄存器
 *   0x14 TIMx_SR    - 状态寄存器
 *   0x18 TIMx_CCMR  - 输入捕获/输出比较模式寄存器
 *   0x1c TIMx_CCER  - 输入捕获/输出比较使能寄存器
 *   0x20 TIMx_CCR1  - 通道1捕获/比较值
 *   0x24 TIMx_CCR2  - 通道2捕获/比较值
 *   0x28 TIMx_CCR3  - 通道3捕获/比较值
 *   0x2c TIMx_CCR4  - 通道4捕获/比较值
 *
 * 作者：
 * 日期：2026/03/31
 */
`include "../../SoC_Config.sv"
`timescale 1ns / 1ps

module apb_timer #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    parameter TIMER_WIDTH = 16,  // 定时器位宽 (16或32)
    parameter CHANNEL_NUM = 4    // 通道数量
)(
    input   logic                       PCLK,
    input   logic                       PRESETn,
    input   logic   [ADDR_WIDTH-1:0]    PADDR,
    input   logic                       PSEL,
    input   logic                       PENABLE,
    input   logic                       PWRITE,
    input   logic   [ALIGN_BYTES-1:0]   PSTRB,
    input   logic   [DATA_WIDTH-1:0]    PWDATA,
    output  logic   [DATA_WIDTH-1:0]    PRDATA,
    output  logic                       PREADY,
    output  logic                       PSLVERR,

    output  logic                       irq_o,  // 定时器中断输出

    // 外部通道接口 (输入捕获/输出比较)
`ifdef TIMER_SIM
    (* mark_debug = "true" *)input   logic   [CHANNEL_NUM-1:0]    channel_i,   // 通道输入
    (* mark_debug = "true" *)output  logic   [CHANNEL_NUM-1:0]    channel_o,   // 通道输出
    (* mark_debug = "true" *)output  logic   [CHANNEL_NUM-1:0]    channel_oe   // 通道输出使能
`else
    inout   logic   [CHANNEL_NUM-1:0]    channel_io   // 通道双向信号
`endif
);

    //////////////////////////////////////////////////////////////////
    //
    // 常量定义
    //

    // 寄存器地址
    localparam TIMx_PSC    = 4'h0;  // 0x00
    localparam TIMx_CNT    = 4'h1;  // 0x04
    localparam TIMx_ARR    = 4'h2;  // 0x08
    localparam TIMx_CR     = 4'h3;  // 0x0c
    localparam TIMx_IER    = 4'h4;  // 0x10
    localparam TIMx_SR     = 4'h5;  // 0x14
    localparam TIMx_CCMR   = 4'h6;  // 0x18
    localparam TIMx_CCER   = 4'h7;  // 0x1c
    localparam TIMx_CCR1   = 4'h8;  // 0x20
    localparam TIMx_CCR2   = 4'h9;  // 0x24
    localparam TIMx_CCR3   = 4'hA;  // 0x28
    localparam TIMx_CCR4   = 4'hB;  // 0x2c

    localparam CHANNEL_WIDTH = 1;  // 每个通道用1位表示使能/模式

    // 触发边沿类型
    localparam TRIG_RISING  = 2'b00;
    localparam TRIG_FALLING = 2'b01;
    localparam TRIG_BOTH    = 2'b10;

    //////////////////////////////////////////////////////////////////
    //
    // 内部信号
    //

`ifndef TIMER_SIM
    logic   [CHANNEL_NUM-1:0]    channel_i;   // 通道输入
    logic   [CHANNEL_NUM-1:0]    channel_o;   // 通道输出
    logic   [CHANNEL_NUM-1:0]    channel_oe;   // 通道输出使能
    genvar g;
    generate
        for(g=0; g<CHANNEL_NUM; g++) begin : channel_tristate
            assign channel_io[g] = channel_oe[g] ? channel_o[g] : 1'bz;
            assign channel_i[g] = channel_io[g];
        end
    endgenerate
`endif

    logic [3:0] reg_sel;
    assign reg_sel = PADDR[5:2];

    // 控制寄存器位域
    // TIMx_CR
    logic                       timerx_en;     // 定时器使能
    logic                       timerx_clr;    // 定时器复位
    logic                       timerx_dir_sel; // 计数方向 (0=递增, 1=递减)

    // TIMx_PSC
    logic [TIMER_WIDTH-1:0]     timerx_prescaler; // 预分频系数

    // TIMx_ARR
    logic [TIMER_WIDTH-1:0]     timerx_arr;    // 自动重载值

    // TIMx_CNT
    logic [TIMER_WIDTH-1:0]     timerx_cnt;    // 当前计数值

    // TIMx_IER
    logic                       timer_int_en;         // 定时器中断使能
    logic                       timer_of_int_en;      // 溢出中断使能
    logic [CHANNEL_NUM-1:0]     timer_ic_oc_int_en;   // 各通道中断使能

    // TIMx_SR
    logic                       timer_int_pend;       // 定时器中断挂起
    logic                       timer_int_of_pend;    // 溢出中断挂起
    logic [CHANNEL_NUM-1:0]     timer_int_trigger_pend; // 各通道触发中断挂起

    // TIMx_CCMR
    logic [CHANNEL_NUM-1:0]     timer_ic_oc_mode;      // 各通道模式 (0=捕获, 1=比较)
    logic [CHANNEL_NUM*11-1:0]  timer_filter_mode;     // 各通道滤波模式 (每个channel 11位)

    // TIMx_CCER
    logic [CHANNEL_NUM-1:0]     timer_ic_oc_en;        // 各通道使能
    logic [CHANNEL_NUM-1:0]     timer_ic_oc_polarity;  // 各通道极性
    logic [CHANNEL_NUM*2-1:0]   timer_trigger_mode;    // 各通道触发边沿

    // TIMx_CCR1-4
    logic [TIMER_WIDTH-1:0]     timer_ic_oc_num [CHANNEL_NUM]; // 各通道捕获/比较值

    // 内部信号
    logic                       timer_expired;     // 定时器溢出信号
    logic                       timer_expired_req; // 定时器溢出中断请求
    logic                       cnt_wr_en;         // 计数值写使能
    logic [TIMER_WIDTH-1:0]     cnt_wr_data;       // 计数值写数据

    logic [CHANNEL_NUM-1:0]     channel_ic_oc_irq; // 各通道中断

    //////////////////////////////////////////////////////////////////
    //
    // Functions
    //

    // Is this a valid read access?
    function automatic is_read();
        return PSEL & PENABLE & ~PWRITE;
    endfunction : is_read

    // Is this a valid write access?
    function automatic is_write();
        return PSEL & PENABLE & PWRITE;
    endfunction : is_write

    // Is this a valid write to address 0x...?
    function automatic is_write_to_addr(input [3:0] addr);
        return is_write() & (reg_sel == addr);
    endfunction : is_write_to_addr

    // What data is written?
    function automatic [DATA_WIDTH-1:0] get_write_value (input [DATA_WIDTH-1:0] original_val);
        for (int n=0; n < ALIGN_BYTES; n++)
            get_write_value[n*8 +: 8] = PSTRB[n] ? PWDATA[n*8 +: 8] : original_val[n*8 +: 8];
    endfunction : get_write_value

    // Clear bits on write (写1清零)
    function automatic [DATA_WIDTH-1:0] get_clearonwrite_value (input [DATA_WIDTH-1:0] original_val);
        for (int n=0; n < ALIGN_BYTES; n++)
            get_clearonwrite_value[n*8 +: 8] = PSTRB[n] ? original_val[n*8 +: 8] & ~PWDATA[n*8 +: 8] : original_val[n*8 +: 8];
    endfunction : get_clearonwrite_value

    //////////////////////////////////////////////////////////////////
    //
    // APB Access
    //

    assign PREADY  = 1'b1; // Always ready
    assign PSLVERR = 1'b0; // Never an error

    //////////////////////////////////////////////////////////////////
    //
    // APB Writes
    //

    // TIMx_PSC - 预分频系数寄存器
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timerx_prescaler <= #1 {TIMER_WIDTH{1'b0}};
        end else if (is_write_to_addr(TIMx_PSC)) begin
            timerx_prescaler <= #1 get_write_value(timerx_prescaler);
        end
    end

    // TIMx_CNT - 计数器寄存器 (软件可以写入)
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timerx_cnt <= #1 {TIMER_WIDTH{1'b0}};
        end else if (is_write_to_addr(TIMx_CNT)) begin
            timerx_cnt <= #1 get_write_value(timerx_cnt);
        end
    end

    // TIMx_ARR - 自动重载寄存器
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timerx_arr <= #1 {TIMER_WIDTH{1'b0}};
        end else if (is_write_to_addr(TIMx_ARR)) begin
            timerx_arr <= #1 get_write_value(timerx_arr);
        end
    end

    // TIMx_CR - 控制寄存器
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timerx_en <= #1 1'b0;
            timerx_clr <= #1 1'b0;
            timerx_dir_sel <= #1 1'b0;
        end else if (is_write_to_addr(TIMx_CR)) begin
            timerx_en <= #1 get_write_value({31'b0, timerx_en})[0];
            timerx_clr <= #1 get_write_value({31'b0, timerx_clr})[0];
            timerx_dir_sel <= #1 get_write_value({31'b0, timerx_dir_sel})[0];
        end else if (timerx_clr) begin
            // 复位信号自动清除
            timerx_clr <= #1 1'b0;
        end
    end

    // TIMx_IER - 中断使能寄存器
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timer_int_en <= #1 1'b0;
            timer_of_int_en <= #1 1'b0;
            timer_ic_oc_int_en <= #1 {CHANNEL_NUM{1'b0}};
        end else if (is_write_to_addr(TIMx_IER)) begin
            timer_int_en <= #1 get_write_value({31'b0, timer_int_en})[0];
            timer_of_int_en <= #1 get_write_value({31'b0, timer_of_int_en})[0];
            for (int i = 0; i < CHANNEL_NUM; i++) begin
                timer_ic_oc_int_en[i] <= #1 get_write_value({31'b0, timer_ic_oc_int_en[i]})[0];
            end
        end
    end

    // TIMx_SR - 状态寄存器 (写1清零)
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timer_int_pend <= #1 1'b0;
            timer_int_of_pend <= #1 1'b0;
            timer_int_trigger_pend <= #1 {CHANNEL_NUM{1'b0}};
        end else if (is_write_to_addr(TIMx_SR)) begin
            timer_int_pend <= #1 get_clearonwrite_value({31'b0, timer_int_pend})[0];
            timer_int_of_pend <= #1 get_clearonwrite_value({31'b0, timer_int_of_pend})[0];
            for (int i = 0; i < CHANNEL_NUM; i++) begin
                timer_int_trigger_pend[i] <= #1 get_clearonwrite_value({31'b0, timer_int_trigger_pend[i]})[0];
            end
        end else begin
            // 中断挂起由硬件置位
            if (timer_expired_req && timer_of_int_en) begin
                timer_int_of_pend <= #1 1'b1;
            end
            for (int i = 0; i < CHANNEL_NUM; i++) begin
                if (channel_ic_oc_irq[i] && timer_ic_oc_int_en[i]) begin
                    timer_int_trigger_pend[i] <= #1 1'b1;
                end
            end
        end
    end

    // TIMx_CCMR - 输入捕获/输出比较模式寄存器
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timer_ic_oc_mode <= #1 {CHANNEL_NUM{1'b0}};
            timer_filter_mode <= #1 {CHANNEL_NUM*11{1'b0}};
        end else if (is_write_to_addr(TIMx_CCMR)) begin
            for (int i = 0; i < CHANNEL_NUM; i++) begin
                timer_ic_oc_mode[i] <= #1 get_write_value({31'b0, timer_ic_oc_mode[i]})[0];
            end
            for (int i = 0; i < CHANNEL_NUM * 11; i++) begin
                timer_filter_mode[i] <= #1 get_write_value({{DATA_WIDTH{1'b0}}, timer_filter_mode})[i];
            end
        end
    end

    // TIMx_CCER - 输入捕获/输出比较使能寄存器
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timer_ic_oc_en <= #1 {CHANNEL_NUM{1'b0}};
            timer_ic_oc_polarity <= #1 {CHANNEL_NUM{1'b0}};
            timer_trigger_mode <= #1 {CHANNEL_NUM*2{1'b0}};
        end else if (is_write_to_addr(TIMx_CCER)) begin
            for (int i = 0; i < CHANNEL_NUM; i++) begin
                timer_ic_oc_en[i] <= #1 get_write_value({31'b0, timer_ic_oc_en[i]})[0];
            end
            for (int i = 0; i < CHANNEL_NUM; i++) begin
                timer_ic_oc_polarity[i] <= #1 get_write_value({31'b0, timer_ic_oc_polarity[i]})[0];
            end
            for (int i = 0; i < CHANNEL_NUM * 2; i++) begin
                timer_trigger_mode[i] <= #1 get_write_value({{DATA_WIDTH{1'b0}}, timer_trigger_mode})[i];
            end
        end
    end

    // TIMx_CCR1-4 - 各通道捕获/比较值寄存器
    genvar ch;
    generate
        for (ch = 0; ch < CHANNEL_NUM; ch++) begin : ccr_write_gen
            localparam CCR_ADDR = (ch == 0) ? TIMx_CCR1 :
                                  (ch == 1) ? TIMx_CCR2 :
                                  (ch == 2) ? TIMx_CCR3 : TIMx_CCR4;

            always_ff @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    timer_ic_oc_num[ch] <= #1 {TIMER_WIDTH{1'b0}};
                end else if (is_write_to_addr(CCR_ADDR)) begin
                    timer_ic_oc_num[ch] <= #1 get_write_value(timer_ic_oc_num[ch]);
                end
            end
        end
    endgenerate

    //////////////////////////////////////////////////////////////////
    //
    // APB Reads
    //

    always_comb begin
        case (reg_sel)
            TIMx_PSC:   PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timerx_prescaler};
            TIMx_CNT:   PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timerx_cnt};
            TIMx_ARR:   PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timerx_arr};
            TIMx_CR:    PRDATA = {{(DATA_WIDTH-3){1'b0}}, timerx_dir_sel, timerx_clr, timerx_en};
            TIMx_IER:   PRDATA = {{(DATA_WIDTH-2-CHANNEL_NUM){1'b0}}, timer_ic_oc_int_en, 1'b0, timer_of_int_en, timer_int_en};
            TIMx_SR:    PRDATA = {{(DATA_WIDTH-2-CHANNEL_NUM){1'b0}}, timer_int_trigger_pend, 1'b0, timer_int_of_pend, timer_int_pend};
            TIMx_CCMR:  begin
                            PRDATA = {(DATA_WIDTH-1-CHANNEL_NUM*11){1'b0}};
                            for (int i = 0; i < CHANNEL_NUM; i++) begin
                                PRDATA[CHANNEL_NUM +: 11] = {timer_filter_mode[i*11+:11], timer_ic_oc_mode[i]};
                            end
                        end
            TIMx_CCER:  PRDATA = {{(DATA_WIDTH-CHANNEL_NUM*4){1'b0}}, timer_trigger_mode, timer_ic_oc_polarity, timer_ic_oc_en};
            TIMx_CCR1:  PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timer_ic_oc_num[0]};
            TIMx_CCR2:  PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timer_ic_oc_num[1]};
            TIMx_CCR3:  PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timer_ic_oc_num[2]};
            TIMx_CCR4:  PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timer_ic_oc_num[3]};
            default:    PRDATA = {DATA_WIDTH{1'b0}};
        endcase
    end

    //////////////////////////////////////////////////////////////////
    //
    // 内部逻辑
    //

    // 计数值写使能
    assign cnt_wr_en = is_write_to_addr(TIMx_CNT);
    assign cnt_wr_data = PWDATA[TIMER_WIDTH-1:0];

    // 定时器核心实例
    basic_timer #(
        .TIMER_WIDTH (TIMER_WIDTH)
    ) basic_timer_inst (
        .clk            (PCLK),
        .rst_n          (PRESETn),

        .prescale       (timerx_prescaler),
        .autoload       (timerx_arr),
        .timer_en       (timerx_en),
        .timer_clr      (timerx_clr),
        .timer_dir      (timerx_dir_sel),

        .cnt_wr_en      (cnt_wr_en),
        .cnt_wr_data    (cnt_wr_data),
        .cnt_rd_data    (timerx_cnt),

        .timer_expired  (timer_expired),
        .timer_expired_req (timer_expired_req)
    );

    // 中断输出逻辑
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            irq_o <= #1 1'b0;
        end else begin
            irq_o <= #1 (timer_int_pend & timer_int_en) |
                            (timer_int_of_pend & timer_of_int_en) |
                            (|timer_int_trigger_pend & |timer_ic_oc_int_en);
        end
    end

    //////////////////////////////////////////////////////////////////
    //
    // 通道实例化 (输入捕获/输出比较)
    //

    genvar ch_inst;
    generate
        for (ch_inst = 0; ch_inst < CHANNEL_NUM; ch_inst++) begin : channel_gen
            timer_ic_oc #(
                .TIMER_WIDTH (TIMER_WIDTH)
            ) timer_ic_oc_inst (
                .clk            (PCLK),
                .rst_n          (PRESETn),

                .ext_in         (channel_i[ch_inst]),
                .ext_out         (channel_o[ch_inst]),
                .ext_dir         (channel_oe[ch_inst]),

                .timer_cnt       (timerx_cnt),
                .timer_en        (timerx_en),
                .timer_expired   (timer_expired),

                .ic_oc_mode      (timer_ic_oc_mode[ch_inst]),
                .filter_mode     (timer_filter_mode[ch_inst*11 +: 4]),
                .ic_oc_en        (timer_ic_oc_en[ch_inst]),
                .polarity        (timer_ic_oc_polarity[ch_inst]),
                .trigger_mode    (timer_trigger_mode[ch_inst*2 +: 2]),
                .cmp_value       (timer_ic_oc_num[ch_inst]),
                .cap_value       (timer_ic_oc_num[ch_inst]),

                .ic_oc_irq       (channel_ic_oc_irq[ch_inst])
            );
        end
    endgenerate

endmodule
