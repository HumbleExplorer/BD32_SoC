timeunit 1ns;
timeprecision 1ps;
module uart_tx (
    input  logic          clk_uart,   // 1倍波特率发送时钟
    input  logic          rst_n,      // 异步复位（低有效）
    input  logic[7:0]     tx_i,    // 待发送数据（来自FIFO）
    input  logic          tx_start,// 发送开始信号
    input  logic[7:0]     lcr,        // 8位完整LCR寄存器
    output logic          tx_o,     // UART发送信号（空闲高）
    output logic          tx_busy    // 发送忙标志（高有效）
);

// LCR位定义：数字位号
localparam LCR_DAT0        = 0;   // 数据位bit0
localparam LCR_DAT1        = 1;   // 数据位bit1
localparam LCR_STOP        = 2;   // 停止位配置
localparam LCR_PARITY_EN   = 3;   // 校验使能
localparam LCR_PARITY_ODD  = 4;   // 奇偶校验选择
localparam LCR_PARITY_FOR  = 5;   // 强制校验位
localparam LCR_BREAK_CTRL  = 6;   // Break控制（预留）
localparam LCR_DLAB        = 7;   // DLAB位（预留）

// 发送状态机枚举
typedef enum logic[4:0] {
    TX_IDLE    = 5'b00001,
    TX_START   = 5'b00010,
    TX_DATA    = 5'b00100,
    TX_PARITY  = 5'b01000,
    TX_STOP    = 5'b10000
} uart_tx_state_e;

// 内部信号
uart_tx_state_e tx_state;     // 发送状态机
logic   [2:0]   data_bit_cnt; // 数据位计数器
logic           stop_bit_cnt; // 停止位计数器
logic   [7:0]   tx_shift;     // 发送移位寄存器
logic           parity_calc;  // 计算的校验位
logic   [2:0]   s_target_data_bits;
logic           s_data_bit_done;

assign s_data_bit_done = (data_bit_cnt == s_target_data_bits);
always_comb begin
    // 根据LCR数据位配置，判断是否发送完成
    unique case (lcr[LCR_DAT1:LCR_DAT0])
        2'b00: s_target_data_bits = 3'd4; // 5位数据
        2'b01: s_target_data_bits = 3'd5; // 6位数据
        2'b10: s_target_data_bits = 3'd6; // 7位数据
        2'b11: s_target_data_bits = 3'd7; // 8位数据
        default: s_target_data_bits = 3'd0;
    endcase
end
// 1. 核心发送状态机 + 单周期FIFO读使能
always_ff @(posedge clk_uart or negedge rst_n) begin
    if(!rst_n) begin
        tx_state       <= #1 TX_IDLE;
        data_bit_cnt   <= #1 3'd0;
        stop_bit_cnt   <= #1 1'd0;
        tx_shift       <= #1 8'd0;
        parity_calc    <= #1 1'b0;
        tx_o           <= #1 1'b1; // 空闲状态为高
    end else begin
        case (tx_state)
            TX_IDLE: begin // 空闲状态：FIFO非空则触发发送
                tx_o            <= #1 1'b1;
                tx_state        <= #1 tx_start ? TX_START : TX_IDLE;
                tx_shift        <= #1 tx_start ? tx_i : tx_shift;
                data_bit_cnt    <= #1 3'd0;
                parity_calc     <= #1 1'b0;
            end
            TX_START: begin 
                tx_o            <= #1 1'b0;
                tx_state        <= #1 TX_DATA;
            end
            TX_DATA: begin // 数据位发送：低位先行，按LCR配置位数发送
                tx_o <= #1 tx_shift[0];
                // 计算奇偶校验（仅校验使能时）
                if(lcr[LCR_PARITY_EN]) begin
                    parity_calc <= #1 parity_calc ^ tx_shift[0];
                end
                tx_state     <= #1 s_data_bit_done ? (lcr[LCR_PARITY_EN] ? TX_PARITY : TX_STOP) : TX_DATA;
                tx_shift     <= #1 {1'b0, tx_shift[7:1]};
                data_bit_cnt <= #1 data_bit_cnt + 1'b1;
            end

            TX_PARITY: begin // 校验位发送：奇偶/强制校验位
                if(lcr[LCR_PARITY_FOR]) begin // 强制校验位
                    tx_o <= #1 lcr[LCR_PARITY_ODD] ? 1'b1 : 1'b0;
                end else begin // 正常奇偶校验
                    tx_o <= #1 lcr[LCR_PARITY_ODD] ? ~parity_calc : parity_calc;
                end
                tx_shift <= #1 'h0;
                tx_state <= #1 TX_STOP;
                stop_bit_cnt <= #1 1'd0;
            end

            TX_STOP: begin // 停止位发送：高电平，按LCR配置位数发送
                tx_o <= #1 1'b1;
                if(lcr[LCR_STOP]) begin // 1.5/2位停止位
                    if(stop_bit_cnt == 1'd1) begin
                        tx_state <= #1 tx_start ? TX_START : TX_IDLE;
                        tx_shift <= #1 tx_start ? tx_i : tx_shift;
                        stop_bit_cnt <= #1 0;
                    end else begin
                        stop_bit_cnt <= #1 stop_bit_cnt + 1'b1;
                    end
                end else begin // 1位停止位
                    tx_state <= #1 tx_start ? TX_START : TX_IDLE;
                    tx_shift <= #1 tx_start ? tx_i : tx_shift;
                end
                data_bit_cnt <= #1 0;
                parity_calc  <= #1 0;
            end

            default: tx_state <= #1 TX_IDLE;
        endcase
    end
end
assign tx_busy = (tx_state != TX_IDLE);
endmodule