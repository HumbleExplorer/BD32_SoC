timeunit 1ns;
timeprecision 1ps;
module uart_tx (
    input  logic          clk,            // 系统时钟
    input  logic          tx_uart_pulse,      // NCO 采样使能脉冲
    input  logic          rst_n,
    input  logic[7:0]     tx_i,
    input  logic          tx_start,
    input  logic[7:0]     lcr,
    output logic          tx_o,
    output logic          tx_busy
);

localparam LCR_DAT0        = 0;
localparam LCR_DAT1        = 1;
localparam LCR_STOP        = 2;
localparam LCR_PARITY_EN   = 3;
localparam LCR_PARITY_ODD  = 4;
localparam LCR_PARITY_FOR  = 5;
localparam LCR_BREAK_CTRL  = 6;
localparam LCR_DLAB        = 7;

typedef enum logic[4:0] {
    TX_IDLE    = 5'b00001,
    TX_START   = 5'b00010,
    TX_DATA    = 5'b00100,
    TX_PARITY  = 5'b01000,
    TX_STOP    = 5'b10000
} uart_tx_state_e;

uart_tx_state_e tx_state;
logic   [2:0]   data_bit_cnt;
logic           stop_bit_cnt;
logic   [7:0]   tx_shift;
logic           parity_calc;
logic   [2:0]   s_target_data_bits;
logic           s_data_bit_done;

assign s_data_bit_done = (data_bit_cnt == s_target_data_bits);
always_comb begin
    unique case (lcr[LCR_DAT1:LCR_DAT0])
        2'b00: s_target_data_bits = 3'd4;
        2'b01: s_target_data_bits = 3'd5;
        2'b10: s_target_data_bits = 3'd6;
        2'b11: s_target_data_bits = 3'd7;
        default: s_target_data_bits = 3'd0;
    endcase
end

// 核心发送状态机
// 控制信号（tx_start）每周期检测，不依赖 sample_pulse
// 位推进（移位、计数）只在 sample_pulse && tx_bit_pulse 时执行
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        tx_state       <= #1 TX_IDLE;
        data_bit_cnt   <= #1 3'd0;
        stop_bit_cnt   <= #1 1'd0;
        tx_shift       <= #1 8'd0;
        parity_calc    <= #1 1'b0;
        tx_o           <= #1 1'b1;
    end else begin
        // 非 IDLE 状态：位推进受 sample_pulse && tx_bit_pulse 门控
        if(tx_uart_pulse) begin
            unique case (tx_state)
                TX_IDLE: begin
                    tx_o            <= #1 1'b1;
                    if (tx_start) begin
                        tx_state    <= #1 TX_START;
                        tx_shift    <= #1 tx_i;
                    end
                end
                TX_START: begin
                    tx_o       <= #1 1'b0;
                    tx_state   <= #1 TX_DATA;
                    data_bit_cnt<= #1 3'd0;
                    parity_calc <= #1 1'b0;
                end
                TX_DATA: begin
                    tx_o <= #1 tx_shift[0];
                    if(lcr[LCR_PARITY_EN])
                        parity_calc <= #1 parity_calc ^ tx_shift[0];
                    tx_state     <= #1 s_data_bit_done ? (lcr[LCR_PARITY_EN] ? TX_PARITY : TX_STOP) : TX_DATA;
                    tx_shift     <= #1 {1'b0, tx_shift[7:1]};
                    data_bit_cnt <= #1 data_bit_cnt + 1'b1;
                end
                TX_PARITY: begin
                    if(lcr[LCR_PARITY_FOR])
                        tx_o <= #1 lcr[LCR_PARITY_ODD] ? 1'b1 : 1'b0;
                    else
                        tx_o <= #1 lcr[LCR_PARITY_ODD] ? ~parity_calc : parity_calc;
                    tx_shift     <= #1 'h0;
                    tx_state     <= #1 TX_STOP;
                    stop_bit_cnt <= #1 1'd0;
                end
                TX_STOP: begin
                    tx_o <= #1 1'b1;
                    if(lcr[LCR_STOP]) begin
                        if(stop_bit_cnt == 1'd1) begin
                            // 连续帧：tx_start 已在 STOP 结束时由 tx_fifo_rd_en 建立
                            tx_state     <= #1 tx_start ? TX_START : TX_IDLE;
                            tx_shift     <= #1 tx_start ? tx_i : tx_shift;
                            stop_bit_cnt <= #1 0;
                        end else begin
                            stop_bit_cnt <= #1 stop_bit_cnt + 1'b1;
                        end
                    end else begin
                        // 1位停止位：同上，连续帧检测
                        tx_state <= #1 tx_start ? TX_START : TX_IDLE;
                        tx_shift <= #1 tx_start ? tx_i : tx_shift;
                    end
                end
                default: tx_state <= #1 TX_IDLE;
            endcase
        end
    end
end

assign tx_busy = (tx_state != TX_IDLE);
endmodule
