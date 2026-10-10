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

logic[2:0]           rx_in_sync_reg;    // RX信号三级同步，消除亚稳态
logic                rx_in_sync_fall;   // 同步后RX下降沿（检测起始位）
logic[3:0]           sample_cnt;        // 16倍过采样计数器
logic[2:0]           data_bit_cnt;      // 数据位计数器
logic                stop_bit_cnt;      // 停止位计数器
logic[3:0]           vote_cnt_1;        // 中间8周期高电平计数（多数判决）
logic                bit_val;           // 多数判决后的比特值
uart_rx_state_e      rx_state;          // 接收状态机
logic[7:0]           rx_shift;          // 接收移位寄存器
logic                parity_calc;       // 计算的校验位

logic                oe_err;            // [0]溢出错误
logic                pe_err;            // [1]奇偶错误
logic                fe_err;            // [2]帧错误
logic                bi_err;            // [3]断错误
logic[2:0]           s_target_data_bits;

always_comb begin// 根据LCR数据位配置，判断是否发送完成
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
// 停止位槽的两种完成事件（每帧单拍）：
//   · 提前触发：rx 变低且本槽早段仍为高（bit_val=1）＝下一帧起始沿已到（背靠背帧），
//     当拍输出并同拍重同步到 RX_START（新帧相位从该沿起算，避免逐帧漂移累积）；
//   · 采样点完成：sample_cnt==15（单帧收尾 / 第二位停止位）。
// FE 帧（整槽为低，bit_val=0）走 cnt15 路径，不经提前触发。
assign rx_valid_o      = sample_pulse && rx_state == RX_STOP &&
                         ((~rx_in_sync_reg[1] && bit_val) ||
                          (sample_cnt == 4'd15 && (!lcr[LCR_STOP] || (stop_bit_cnt == 1'd1))));
// 数据右对齐输出（16550 语义）：5/6/7 数据位时移位寄存器把数据收在高位 [7:3]/[7:2]/[7:1]，
// 需右移回低位 [4:0]/[5:0]/[6:0]；8 位模式不移位。与 TX（按低 N 位发送）对称。
assign rx_o            = rx_valid_o ? (rx_shift >> (3'd3 - {1'b0, lcr[LCR_DAT1:LCR_DAT0]})) : 8'd0;
assign oe_err          = (rx_fifo_wr_full && rx_state == RX_DATA);// 溢出错误OE：FIFO满时仍有新数据接收
assign bi_err          = lcr[LCR_BREAK_CTRL];// 断错误BI：LCR Break位为1时触发
// 帧错误FE：停止位非高。投票窗完成后（sample_cnt>=12）多数判决为 0 即判 FE——
// 停止位整槽为低时 4..11 采样多数为 0；背靠背下一起始沿只污染槽尾，多数仍为高，不误判。
assign fe_err          = (rx_state == RX_STOP) && (sample_cnt >= 4'd12) && (bit_val != 1'b1);
assign pe_err          = rx_state == RX_PARITY && sample_cnt == 4'd15 ?// 奇偶错误PE：奇偶校验错误
                        (lcr[LCR_PARITY_FOR] ?// 强制校验位：报错 = 校验位偏离 LCR 指定值
                        (lcr[LCR_PARITY_ODD] ? (bit_val != 1'b1) : (bit_val != 1'b0)) :
                        // 真校验：奇校验正确帧 pc!=bit_val，偶校验正确帧 pc==bit_val，报错条件取其反
                        (lcr[LCR_PARITY_ODD] ? (parity_calc == bit_val) : (parity_calc != bit_val))) : 1'b0;

// 1. 三级同步消除RX异步信号亚稳态
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        rx_in_sync_reg <= #1 3'b111;
    else if(sample_pulse)
        rx_in_sync_reg <= #1 {rx_in_sync_reg[1:0], rx_i};
end

assign rx_in_sync_fall = rx_in_sync_reg[2] & ~rx_in_sync_reg[1];

// 3. 16倍过采样计数器
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        sample_cnt <= #1 4'd0;
    else if(sample_pulse) begin
        sample_cnt <= #1 (rx_state == RX_IDLE || rx_valid_o || sample_cnt == 4'd15) ? 4'd0 : sample_cnt + 1'b1;
    end
end

// 4. 中间8周期多数判决
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        vote_cnt_1 <= #1 4'd0;
    else if(sample_pulse) begin
        if(sample_cnt>=4 && sample_cnt<=11) begin
            if(rx_in_sync_reg[1]) vote_cnt_1 <= #1 vote_cnt_1 + 1'b1;
        end else if(sample_cnt == 4'd15 || rx_valid_o) begin
            vote_cnt_1 <= #1 4'd0;
        end
    end
end

// 5. 核心接收状态机
// IDLE 和非 IDLE 状态统一受 sample_pulse 门控
// 避免 90MHz 高频检测引入的伪起始位噪声
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rx_state       <= #1 RX_IDLE;
        data_bit_cnt   <= #1 3'd0;
        stop_bit_cnt   <= #1 1'd0;
        rx_shift       <= #1 8'd0;
        parity_calc    <= #1 1'b0;
    end else if(sample_pulse) begin
        case (rx_state)
            RX_IDLE: begin // 空闲状态：检测起始位下降沿
                if(rx_in_sync_fall) begin
                    rx_state     <= #1 RX_START;
                end
            end
            RX_START: begin// 起始位检测：验证有效性（多数判决为0）
                if(sample_cnt == 4'd15) begin
                    if(bit_val == 1'b0) begin
                        rx_state     <= #1 RX_DATA;
                        stop_bit_cnt <= #1 1'd0;
                        data_bit_cnt <= #1 3'd0;
                        rx_shift     <= #1 8'd0;
                        parity_calc  <= #1 1'b0;
                    end else begin
                        rx_state     <= #1 RX_IDLE;
                    end
                end
            end

            RX_DATA: begin// 数据位接收：低位先行，按LCR配置位数接收
                if(sample_cnt == 4'd15) begin
                    rx_shift     <= #1 {bit_val, rx_shift[7:1]};
                    if(lcr[LCR_PARITY_EN])
                        parity_calc <= #1 parity_calc ^ bit_val;
                    rx_state     <= #1 s_data_bit_done ? (lcr[LCR_PARITY_EN] ? RX_PARITY : RX_STOP) : RX_DATA;
                    data_bit_cnt <= #1 data_bit_cnt + 1'b1;
                end
            end

            RX_PARITY: begin// 校验位接收：验证奇偶/强制校验位
                if(sample_cnt == 4'd15) begin
                    rx_state  <= #1 RX_STOP;
                end
            end

            RX_STOP: begin// 停止位接收：验证有效性（必须为高）
                if(sample_cnt == 4'd15) begin
                    if(lcr[LCR_STOP]) begin
                        if(stop_bit_cnt == 1'd1) begin
                            stop_bit_cnt <= #1 1'd0;
                            // 收尾转移：rx 低且本槽多数为高 = 下一帧起始沿已到 → 直接重同步；
                            // 否则（含 FE 帧 bit_val=0）回 IDLE 重新捕获起始沿
                            rx_state     <= #1 (~rx_in_sync_reg[1] && bit_val) ? RX_START : RX_IDLE;
                        end else begin
                            stop_bit_cnt <= #1 stop_bit_cnt + 1'b1;
                        end
                    end else begin
                        rx_state <= #1 (~rx_in_sync_reg[1] && bit_val) ? RX_START : RX_IDLE;
                    end
                end else begin
                    // 提前退出（相位校正）：仅当 rx 变低"且"本槽多数为高（bit_val=1）时判定
                    // 为下一帧起始沿并重同步；bit_val=0（停止位整槽低 = FE 帧）则保持本槽，
                    // 待 cnt15 收尾（防止把 FE 帧的低停止位误当起始沿、生成幻影帧）。
                    rx_state <= #1 (~rx_in_sync_reg[1] && bit_val) ? RX_START : RX_STOP;
                end
            end

            default: rx_state <= #1 RX_IDLE;
        endcase
    end
end

assign rx_err = {bi_err, fe_err, pe_err, oe_err};
endmodule
