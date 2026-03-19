module uart_rx (
    input  logic          clk_sample, // 16倍波特率采样时钟
    input  logic          rst_n,      // 异步复位（低有效）
    input  logic          rx_i,  // 异步UART接收信号
    input  logic [7:0]    lcr,        // 8位完整LCR寄存器
    input  logic          rx_fifo_wr_full,// rx FIFO写满
    output logic [7:0]    rx_o,    // 接收数据输出
    output logic          rx_valid_o, // 接收数据有效
    output logic [3:0]    rx_err      // [3]BI/[2]FE/[1]PE/[0]OE
);

// LCR位定义：数字位号
localparam LCR_DAT0        = 0;   // 数据位bit0
localparam LCR_DAT1        = 1;   // 数据位bit1
localparam LCR_STOP        = 2;   // 停止位配置
localparam LCR_PARITY_EN   = 3;   // 校验使能
localparam LCR_PARITY_ODD  = 4;   // 奇偶校验选择
localparam LCR_PARITY_FOR  = 5;   // 强制校验位
localparam LCR_BREAK_CTRL  = 6;   // Break控制
localparam LCR_DLAB        = 7;   // DLAB位（预留）

// 接收状态机枚举
typedef enum logic[2:0] {
    RX_IDLE    = 3'b000,
    RX_START   = 3'b001,
    RX_DATA    = 3'b010,
    RX_PARITY  = 3'b011,
    RX_STOP    = 3'b100
} uart_rx_state_e;

// 内部信号
logic[2:0]           rx_in_sync_reg;  // RX信号三级同步，消除亚稳态
logic                rx_in_sync_fall; // 同步后RX下降沿（检测起始位）
logic[3:0]           sample_cnt;   // 16倍过采样计数器
logic[2:0]           data_bit_cnt; // 数据位计数器
logic                stop_bit_cnt; // 停止位计数器
logic[3:0]           vote_cnt_1;   // 中间8周期高电平计数（多数判决）
logic                bit_val;      // 多数判决后的比特值
uart_rx_state_e      rx_state;     // 接收状态机
logic[7:0]           rx_shift;     // 接收移位寄存器
logic                parity_calc;  // 计算的校验位
logic                parity_rx;    // 接收的校验位
// 错误信号（单独定义，便于维护）
logic                oe_err;       // [0]溢出错误
logic                pe_err;       // [1]奇偶错误
logic                fe_err;       // [2]帧错误
logic                bi_err;       // [3]断错误
logic[2:0]           s_target_data_bits;
always_comb begin
    // 根据LCR数据位配置，判断是否发送完成
    unique case (lcr[LCR_DAT1:LCR_DAT0])
        2'b00: s_target_data_bits = 3'd4; // 5位数据
        2'b01: s_target_data_bits = 3'd5; // 6位数据
        2'b10: s_target_data_bits = 3'd6; // 7位数据
        2'b11: s_target_data_bits = 3'd7; // 8位数据
    endcase
end

assign bit_val         = vote_cnt_1 >= 4'd4;
assign s_data_bit_done = (data_bit_cnt == s_target_data_bits);
assign oe_err          = (rx_fifo_wr_full && rx_state == RX_DATA);// 溢出错误OE：FIFO满时仍有新数据接收
assign bi_err          = lcr[LCR_BREAK_CTRL];// 断错误BI：LCR Break位为1时触发
assign fe_err          = rx_state == RX_STOP && bit_val != 1'b1 && sample_cnt == 4'd15; // 帧错误FE：停止位非高
assign pe_err          = rx_state == RX_PARITY && sample_cnt == 4'd15 ? // 奇偶错误PE：奇偶校验错误
                        (lcr[LCR_PARITY_FOR] ? // 强制校验位
                        (lcr[LCR_PARITY_ODD] ? (bit_val != 1'b1) : (bit_val != 1'b0)) :
                        (lcr[LCR_PARITY_ODD] ? (parity_calc != bit_val) : (parity_calc == bit_val))) : 1'b0;
// 1. 三级同步消除RX异步信号亚稳态
always_ff @(posedge clk_sample or negedge rst_n) begin
    if(!rst_n) begin
        rx_in_sync_reg <= 3'b111; // 空闲状态RX为高
    end else begin
        rx_in_sync_reg <= {rx_in_sync_reg[1:0], rx_i};
    end
end
assign rx_in_sync_fall = rx_in_sync_reg[2] & ~rx_in_sync_reg[1]; // 检测起始位下降沿

// 2. 16倍过采样计数器
always_ff @(posedge clk_sample or negedge rst_n) begin
    if(!rst_n) begin
        sample_cnt <= 4'd0;
    end else begin
        sample_cnt <= (rx_state == RX_IDLE) ? 4'd0 : ((sample_cnt == 4'd15) ? 4'd0 : sample_cnt + 1'b1);
    end
end

// 3. 中间8周期多数判决（提升采样容错，16550标准）
always_ff @(posedge clk_sample or negedge rst_n) begin
    if(!rst_n) begin
        vote_cnt_1 <= 4'd0;
    end else begin
        if(sample_cnt[3] ^ sample_cnt[2]) begin // 第4~11采样周期统计
            if(rx_in_sync_reg[1]) vote_cnt_1 <= vote_cnt_1 + 1'b1;
        end else if(sample_cnt == 4'd15) begin // 第15周期判决，清零计数器
            vote_cnt_1 <= 4'd0;
        end
    end
end

// 4. 核心接收状态机 + 错误检测
always_ff @(posedge clk_sample or negedge rst_n) begin
    if(!rst_n) begin
        rx_state       <= RX_IDLE;
        data_bit_cnt   <= 3'd0;
        stop_bit_cnt   <= 1'd0;
        rx_shift       <= 8'd0;
        parity_calc    <= 1'b0;
        parity_rx      <= 1'b0;
        rx_o           <= 8'd0;
        rx_valid_o     <= 1'b0;
    end else begin
        // 默认值：清除就绪标志
        rx_valid_o  <= 1'b0;
        case (rx_state)
            RX_IDLE: begin // 空闲状态：检测起始位下降沿
                if(rx_in_sync_fall) begin
                    rx_state     <= RX_START;
                end
            end

            RX_START: begin // 起始位检测：验证有效性（多数判决为0）
                if(sample_cnt == 4'd15) begin
                    if(bit_val == 1'b0) begin // 起始位有效
                        rx_state     <= RX_DATA;
                        data_bit_cnt <= 3'd0;
                        rx_shift     <= 8'd0;
                        parity_calc  <= 1'b0;
                    end else begin // 起始位无效，回到空闲
                        rx_state     <= RX_IDLE;
                    end
                end
            end

            RX_DATA: begin // 数据位接收：低位先行，按LCR配置位数接收
                if(sample_cnt == 4'd15) begin
                    rx_shift <= {bit_val, rx_shift[7:1]};
                    // 计算奇偶校验（仅校验使能时）
                    if(lcr[LCR_PARITY_EN]) begin
                        parity_calc <= parity_calc ^ bit_val;
                    end
                    rx_state <= s_data_bit_done ? (lcr[LCR_PARITY_EN] ? RX_PARITY : RX_STOP) : RX_DATA;
                    data_bit_cnt <= data_bit_cnt + 1'b1;
                end
            end

            RX_PARITY: begin // 校验位接收：验证奇偶/强制校验位
                if(sample_cnt == 4'd15) begin
                    parity_rx <= bit_val;
                    // 奇偶错误PE判断
                    rx_state <= RX_STOP;
                end
            end

            RX_STOP: begin // 停止位接收：验证有效性（必须为高）
                if(sample_cnt == 4'd15) begin
                    // // 根据LCR停止位配置，判断是否接收完成
                    // if(lcr[LCR_STOP]) begin // 1.5/2位停止位
                    //     if(stop_bit_cnt == 1'd1) begin
                    //         rx_state <= RX_IDLE;
                    //     end else begin
                    //         stop_bit_cnt <= stop_bit_cnt + 1'b1;
                    //     end
                    // end else begin // 1位停止位
                    //     rx_state <= RX_IDLE;
                    // end
                                        // 停止位计数处理（1/1.5/2位）
                    if(lcr[LCR_STOP]) begin
                        if(stop_bit_cnt == 1'd1) begin
                            stop_bit_cnt <= 1'd0;
                            // 停止位结束后：若RX=0 → 直接启动下一帧，不回IDLE
                            rx_state <= rx_in_sync_fall ? RX_START : RX_IDLE;
                        end else begin
                            stop_bit_cnt <= stop_bit_cnt + 1'b1;
                        end
                    end else begin
                        // 1位停止位：结束直接判断是否为新起始位
                        rx_state <= rx_in_sync_fall ? RX_START : RX_IDLE;
                    end

                    // 接收完成：输出数据和就绪信号
                    if((!lcr[LCR_STOP]) || (stop_bit_cnt == 1'd1)) begin
                        rx_o       <= rx_shift;
                        rx_valid_o <= 1'b1;
                    end
                end
            end

            default: rx_state <= RX_IDLE;
        endcase
    end
end


// 错误信号拼接（严格遵循16550手册位序：[3]BI/[2]FE/[1]PE/[0]OE）
assign rx_err = {bi_err, fe_err, pe_err, oe_err};
endmodule