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
    input   logic   [CHANNEL_NUM-1:0]    channel_i,   // 通道输入
    output  logic   [CHANNEL_NUM-1:0]    channel_o,   // 通道输出
    output  logic   [CHANNEL_NUM-1:0]    channel_oe   // 通道输出使能
`else
    inout   wire    [CHANNEL_NUM-1:0]    channel_io   // 通道双向信号
`endif
);

    //////////////////////////////////////////////////////////////////
    //
    // 常量定义
    //

    // 寄存器地址
    typedef enum logic [3:0] { 
        TIMx_PSC    = 4'h0,  // 0x00
        TIMx_CNT    = 4'h1,  // 0x04
        TIMx_ARR    = 4'h2,  // 0x08
        TIMx_CR     = 4'h3,  // 0x0c
        TIMx_IER    = 4'h4,  // 0x10
        TIMx_SR     = 4'h5,  // 0x14
        TIMx_CCMR   = 4'h6,  // 0x18
        TIMx_CCER   = 4'h7,  // 0x1c
        TIMx_CCR1   = 4'h8,  // 0x20
        TIMx_CCR2   = 4'h9,  // 0x24
        TIMx_CCR3   = 4'hA,  // 0x28
        TIMx_CCR4   = 4'hB   // 0x2c
    } TIMx_reg_sel_e;

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
    logic   [CHANNEL_NUM-1:0]    channel_oe_n; // channel_oe取反

    assign  channel_oe = ~channel_oe_n;

    logic [3:0] reg_sel;
    assign reg_sel = PADDR[5:2];

    // 控制寄存器位域
    // TIMx_CR
    logic                       timer_en;     // 定时器使能
    logic                       timer_clr;    // 定时器复位
    logic                       timer_dir_sel; // 计数方向 (0=递增, 1=递减)

    // TIMx_PSC
    (* mark_debug = "true" *)logic [TIMER_WIDTH-1:0]     timer_prescaler; // 预分频系数

    // TIMx_ARR
    (* mark_debug = "true" *)logic [TIMER_WIDTH-1:0]     timer_arr;    // 自动重载值

    // TIMx_CNT
    (* mark_debug = "true" *)logic [TIMER_WIDTH-1:0]     timer_cnt;    // 当前计数值

    // TIMx_IER
    logic                       timer_int_en;         // 定时器中断使能
    logic                       timer_of_int_en;      // 溢出中断使能
    logic [CHANNEL_NUM-1:0]     timer_ic_oc_int_en;   // 各通道中断使能

    // TIMx_SR
    logic                       timer_int_of_pend;    // 溢出中断挂起
    logic [CHANNEL_NUM-1:0]     timer_int_trigger_pend; // 各通道触发中断挂起

    // TIMx_CCMR
    logic [CHANNEL_NUM-1:0]     timer_ic_oc_mode;      // 各通道模式 (0=捕获, 1=比较)
    logic [CHANNEL_NUM*4-1:0]   timer_filter_mode;     // 各通道滤波模式 (每个channel 4位)

    // TIMx_CCER
    logic [CHANNEL_NUM-1:0]     timer_ic_oc_en;        // 各通道使能
    logic [CHANNEL_NUM-1:0]     timer_ic_oc_polarity;  // 各通道极性
    logic [CHANNEL_NUM*2-1:0]   timer_trigger_mode;    // 各通道触发边沿

    // TIMx_CCR1-4
    (* mark_debug = "true" *)logic [TIMER_WIDTH-1:0]     timer_ccr_cmp [CHANNEL_NUM];   // APB 写比较值
    logic [TIMER_WIDTH-1:0]     timer_ccr_cap [CHANNEL_NUM];   // 硬件捕获值

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
    function automatic bit is_read();
        return PSEL & PENABLE & ~PWRITE;
    endfunction : is_read

    // Is this a valid write access?
    function automatic bit is_write();
        return PSEL & PENABLE & PWRITE;
    endfunction : is_write

    // Is this a valid write to address 0x...?
    function automatic bit is_write_to_addr(input [3:0] addr);//不加bit直接assign会变成不定态
        return is_write() & (TIMx_reg_sel_e'(reg_sel) == addr);
    endfunction : is_write_to_addr

    //////////////////////////////////////////////////////////////////
    //
    // APB Access
    //

    assign PREADY  = 1'b1; // Always ready
    assign PSLVERR = 1'b0; // Never an error

    //////////////////////////////////////////////////////////////////
    //
    // APB Writes (PSTRB assumed always all 1's, simplified)
    //

    // TIMx_PSC - 预分频系数寄存器
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            timer_prescaler <= {TIMER_WIDTH{1'b0}};
        else if (is_write_to_addr(TIMx_PSC))
            timer_prescaler <= PWDATA[TIMER_WIDTH-1:0];
    end

    // TIMx_ARR - 自动重载寄存器
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            timer_arr <= {TIMER_WIDTH{1'b0}};
        else if (is_write_to_addr(TIMx_ARR))
            timer_arr <= PWDATA[TIMER_WIDTH-1:0];
    end

    // TIMx_CR - 控制寄存器
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timer_en      <= 1'b0;
            timer_clr     <= 1'b0;
            timer_dir_sel <= 1'b0;
        end else if (is_write_to_addr(TIMx_CR)) begin
            timer_en      <= PWDATA[0];
            timer_clr     <= PWDATA[1];
            timer_dir_sel <= PWDATA[2];
        end else if (timer_clr) begin
            timer_clr <= 1'b0;
        end
    end

    // TIMx_IER - 中断使能寄存器
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timer_int_en       <= 1'b0;
            timer_of_int_en    <= 1'b0;
            timer_ic_oc_int_en <= {CHANNEL_NUM{1'b0}};
        end else if (is_write_to_addr(TIMx_IER)) begin
            timer_int_en    <= PWDATA[0];
            timer_of_int_en <= PWDATA[1];
            for (int i = 0; i < CHANNEL_NUM; i++)
                timer_ic_oc_int_en[i] <= PWDATA[2+i];
        end
    end

    // TIMx_SR - 状态寄存器 (写1清零)
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timer_int_of_pend      <= 1'b0;
            timer_int_trigger_pend <= {CHANNEL_NUM{1'b0}};
        end else if (is_write_to_addr(TIMx_SR)) begin
            // 写1清零
            if (PWDATA[0])
                timer_int_of_pend <= 1'b0;
            for (int i = 0; i < CHANNEL_NUM; i++)
                if (PWDATA[1+i])
                    timer_int_trigger_pend[i] <= 1'b0;
        end else begin
            // 中断挂起由硬件置位
            if (timer_expired_req && timer_of_int_en)
                timer_int_of_pend <= 1'b1;
            for (int i = 0; i < CHANNEL_NUM; i++)
                if (channel_ic_oc_irq[i] && timer_ic_oc_int_en[i])
                    timer_int_trigger_pend[i] <= 1'b1;
        end
    end

    // TIMx_CCMR - 输入捕获/输出比较模式寄存器
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timer_ic_oc_mode   <= {CHANNEL_NUM{1'b0}};
            timer_filter_mode  <= {CHANNEL_NUM*4{1'b0}};
        end else if (is_write_to_addr(TIMx_CCMR)) begin
            // 假设PWDATA低位为 mode，接着为 filter_mode
            for (int i = 0; i < CHANNEL_NUM; i++)
                timer_ic_oc_mode[i] <= PWDATA[i];
            for (int i = 0; i < CHANNEL_NUM*4; i++)
                timer_filter_mode[i] <= PWDATA[CHANNEL_NUM + i];
        end
    end

    // TIMx_CCER - 输入捕获/输出比较使能寄存器
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timer_ic_oc_en      <= {CHANNEL_NUM{1'b0}};
            timer_ic_oc_polarity<= {CHANNEL_NUM{1'b0}};
            timer_trigger_mode  <= {CHANNEL_NUM*2{1'b0}};
        end else if (is_write_to_addr(TIMx_CCER)) begin
            for (int i = 0; i < CHANNEL_NUM; i++)
                timer_ic_oc_en[i] <= PWDATA[i];
            for (int i = 0; i < CHANNEL_NUM; i++)
                timer_ic_oc_polarity[i] <= PWDATA[CHANNEL_NUM + i];
            for (int i = 0; i < CHANNEL_NUM*2; i++)
                timer_trigger_mode[i] <= PWDATA[2*CHANNEL_NUM + i];
        end
    end

    // TIMx_CCR1-4 - 各通道比较值寄存器 (APB 只写比较值)
    genvar ch;
    generate
        for (ch = 0; ch < CHANNEL_NUM; ch++) begin : ccr_write_gen
            localparam [3:0] CCR_ADDR = 4'(TIMx_CCR1) + ch[3:0];
            always_ff @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn)
                    timer_ccr_cmp[ch] <= {TIMER_WIDTH{1'b0}};
                else if (is_write_to_addr(CCR_ADDR))
                    timer_ccr_cmp[ch] <= PWDATA[TIMER_WIDTH-1:0];
            end
        end
    endgenerate

    //////////////////////////////////////////////////////////////////
    //
    // APB Reads
    //

    always_comb begin
        PRDATA = {DATA_WIDTH{1'b0}};
        case (TIMx_reg_sel_e'(reg_sel))
            TIMx_PSC:   PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timer_prescaler};
            TIMx_CNT:   PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timer_cnt};
            TIMx_ARR:   PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timer_arr};
            TIMx_CR:    PRDATA = {{(DATA_WIDTH-3){1'b0}}, timer_dir_sel, timer_clr, timer_en};
            TIMx_IER:   PRDATA = {{(DATA_WIDTH-2-CHANNEL_NUM){1'b0}}, timer_ic_oc_int_en, timer_of_int_en, timer_int_en};
            TIMx_SR:    PRDATA = {{(DATA_WIDTH-1-CHANNEL_NUM){1'b0}}, timer_int_trigger_pend, timer_int_of_pend};
            TIMx_CCMR:  PRDATA = {{(DATA_WIDTH-CHANNEL_NUM-4*CHANNEL_NUM){1'b0}}, timer_filter_mode, timer_ic_oc_mode};
            TIMx_CCER:  PRDATA = {{(DATA_WIDTH-CHANNEL_NUM-CHANNEL_NUM-2*CHANNEL_NUM){1'b0}}, timer_trigger_mode, timer_ic_oc_polarity, timer_ic_oc_en};
            TIMx_CCR1:  PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timer_ic_oc_mode[0] ? timer_ccr_cmp[0] : timer_ccr_cap[0]};
            TIMx_CCR2:  PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timer_ic_oc_mode[1] ? timer_ccr_cmp[1] : timer_ccr_cap[1]};
            TIMx_CCR3:  PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timer_ic_oc_mode[2] ? timer_ccr_cmp[2] : timer_ccr_cap[2]};
            TIMx_CCR4:  PRDATA = {{(DATA_WIDTH-TIMER_WIDTH){1'b0}}, timer_ic_oc_mode[3] ? timer_ccr_cmp[3] : timer_ccr_cap[3]};
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

        .prescale       (timer_prescaler),
        .autoload       (timer_arr),
        .timer_en       (timer_en),
        .timer_clr      (timer_clr),
        .timer_dir      (timer_dir_sel),

        .cnt_wr_en      (cnt_wr_en),
        .cnt_wr_data    (cnt_wr_data),
        .cnt_rd_data    (timer_cnt),

        .timer_expired  (timer_expired),
        .timer_expired_req (timer_expired_req)
    );

    // 中断输出逻辑
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            irq_o <= 1'b0;
        else
            irq_o <= timer_int_en &
                    ((timer_int_of_pend & timer_of_int_en) |
                    (|(timer_int_trigger_pend & timer_ic_oc_int_en)));
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
                .ext_out        (channel_o[ch_inst]),
                .ext_dir        (channel_oe_n[ch_inst]),

                .timer_cnt      (timer_cnt),
                .timer_dir_sel  (timer_dir_sel),
                .timer_en       (timer_en),
                .timer_expired  (timer_expired),

                .ic_oc_mode     (timer_ic_oc_mode[ch_inst]),
                .filter_mode    (timer_filter_mode[ch_inst*4 +: 4]),
                .ic_oc_en       (timer_ic_oc_en[ch_inst]),
                .polarity       (timer_ic_oc_polarity[ch_inst]),
                .trigger_mode   (timer_trigger_mode[ch_inst*2 +: 2]),
                .cmp_value      (timer_ccr_cmp[ch_inst]),
                .cap_value      (timer_ccr_cap[ch_inst]),

                .ic_oc_irq      (channel_ic_oc_irq[ch_inst])
            );
        end
    endgenerate

endmodule