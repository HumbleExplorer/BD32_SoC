timeunit 1ns;
timeprecision 1ps;
module uart_rx (
    input  logic          clk,            // 系统时钟
    input  logic          sample_pulse,      // NCO 采样使能脉冲
    input  logic          rst_n,
    input  logic          rx_i,
    input  logic [7:0]    lcr,
    input  logic          rx_fifo_wr_full,
    output logic [7:0]    rx_o,
    output logic          rx_valid_o,
    output logic [3:0]    rx_err
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
    RX_IDLE    = 5'b00001,
    RX_START   = 5'b00010,
    RX_DATA    = 5'b00100,
    RX_PARITY  = 5'b01000,
    RX_STOP    = 5'b10000
} uart_rx_state_e;

logic[2:0]           rx_in_sync_reg;
logic                rx_in_sync_fall;
logic                rx_fall_q;          // 锁存下降沿，确保 sample_pulse 采样到
logic[3:0]           sample_cnt;
logic[2:0]           data_bit_cnt;
logic                stop_bit_cnt;
logic[3:0]           vote_cnt_1;
logic                bit_val;
uart_rx_state_e      rx_state;
logic[7:0]           rx_shift;
logic                parity_calc;
logic                parity_rx;
logic                oe_err;
logic                pe_err;
logic                fe_err;
logic                bi_err;
logic[2:0]           s_target_data_bits;

always_comb begin
    unique case (lcr[LCR_DAT1:LCR_DAT0])
        2'b00: s_target_data_bits = 3'd4;
        2'b01: s_target_data_bits = 3'd5;
        2'b10: s_target_data_bits = 3'd6;
        2'b11: s_target_data_bits = 3'd7;
        default: s_target_data_bits = 3'd0;
    endcase
end

assign bit_val         = vote_cnt_1 >= 4'd4;
assign s_data_bit_done = (data_bit_cnt == s_target_data_bits);
assign rx_valid_o      = sample_pulse && (rx_state == RX_STOP && sample_cnt == 4'd15 && (!lcr[LCR_STOP] || (stop_bit_cnt == 1'd1)));
assign rx_o            = rx_valid_o ? rx_shift[7:0] : 8'd0;
assign oe_err          = (rx_fifo_wr_full && rx_state == RX_DATA);
assign bi_err          = lcr[LCR_BREAK_CTRL];
assign fe_err          = rx_state == RX_STOP && bit_val != 1'b1 && sample_cnt == 4'd15;
assign pe_err          = rx_state == RX_PARITY && sample_cnt == 4'd15 ?
                        (lcr[LCR_PARITY_FOR] ?
                        (lcr[LCR_PARITY_ODD] ? (bit_val != 1'b1) : (bit_val != 1'b0)) :
                        (lcr[LCR_PARITY_ODD] ? (parity_calc != bit_val) : (parity_calc == bit_val))) : 1'b0;

// 1. 三级同步消除RX异步信号亚稳态
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        rx_in_sync_reg <= #1 3'b111;
    else
        rx_in_sync_reg <= #1 {rx_in_sync_reg[1:0], rx_i};
end

assign rx_in_sync_fall = rx_in_sync_reg[2] & ~rx_in_sync_reg[1];

// 2. 锁存下降沿（防止被 sample_pulse 错过）
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        rx_fall_q <= #1 1'b0;
    else if(sample_pulse)
        rx_fall_q <= #1 1'b0;
    else if(rx_in_sync_fall)
        rx_fall_q <= #1 1'b1;
end

wire rx_fall_detected = rx_in_sync_fall | rx_fall_q;

// 3. 16倍过采样计数器
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        sample_cnt <= #1 4'd0;
    else if(sample_pulse) begin
        sample_cnt <= #1 (rx_state == RX_IDLE) ? 4'd0 : ((sample_cnt == 4'd15) ? 4'd0 : sample_cnt + 1'b1);
    end
end

// 4. 中间8周期多数判决
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        vote_cnt_1 <= #1 4'd0;
    else if(sample_pulse) begin
        if(sample_cnt>=4 && sample_cnt<=11) begin
            if(rx_in_sync_reg[1]) vote_cnt_1 <= #1 vote_cnt_1 + 1'b1;
        end else if(sample_cnt == 4'd15) begin
            vote_cnt_1 <= #1 4'd0;
        end
    end
end

// 5. 核心接收状态机
// RX_IDLE 每周期检测下降沿，不依赖 sample_pulse
// 其余状态在 sample_pulse 时推进采样/计数
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rx_state       <= #1 RX_IDLE;
        data_bit_cnt   <= #1 3'd0;
        stop_bit_cnt   <= #1 1'd0;
        rx_shift       <= #1 8'd0;
        parity_calc    <= #1 1'b0;
        parity_rx      <= #1 1'b0;
    end else begin

        if (rx_state == RX_IDLE) begin
            // IDLE 每周期检测，下降沿立即响应
            if (rx_fall_detected)
                rx_state <= #1 RX_START;
        end else begin
            // 非 IDLE 状态：采样推进受 sample_pulse 门控
            if (sample_pulse) begin
                case (rx_state)
                    RX_START: begin
                        if(sample_cnt == 4'd15) begin
                            if(bit_val == 1'b0) begin
                                rx_state     <= #1 RX_DATA;
                                data_bit_cnt <= #1 3'd0;
                                rx_shift     <= #1 8'd0;
                                parity_calc  <= #1 1'b0;
                            end else begin
                                rx_state     <= #1 RX_IDLE;
                            end
                        end
                    end

                    RX_DATA: begin
                        if(sample_cnt == 4'd15) begin
                            rx_shift     <= #1 {bit_val, rx_shift[7:1]};
                            if(lcr[LCR_PARITY_EN])
                                parity_calc <= #1 parity_calc ^ bit_val;
                            rx_state     <= #1 s_data_bit_done ? (lcr[LCR_PARITY_EN] ? RX_PARITY : RX_STOP) : RX_DATA;
                            data_bit_cnt <= #1 data_bit_cnt + 1'b1;
                        end
                    end

                    RX_PARITY: begin
                        if(sample_cnt == 4'd15) begin
                            parity_rx <= #1 bit_val;
                            rx_state  <= #1 RX_STOP;
                        end
                    end

                    RX_STOP: begin
                        if(sample_cnt == 4'd15) begin
                            if(lcr[LCR_STOP]) begin
                                if(stop_bit_cnt == 1'd1) begin
                                    stop_bit_cnt <= #1 1'd0;
                                    rx_state     <= #1 ~rx_in_sync_reg[1] ? RX_START : RX_IDLE;
                                end else begin
                                    stop_bit_cnt <= #1 stop_bit_cnt + 1'b1;
                                end
                            end else begin
                                rx_state <= #1 ~rx_in_sync_reg[1] ? RX_START : RX_IDLE;
                            end
                        end
                    end

                    default: rx_state <= #1 RX_IDLE;
                endcase
            end
        end
    end
end

assign rx_err = {bi_err, fe_err, pe_err, oe_err};
endmodule
