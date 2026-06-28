`include "../../SoC_Config.sv"
// 串口一键下载模块（计数协议版，无帧冲突风险）
// 协议：  START_FRAME → ITCM_COUNT → ITCM数据 → DTCM_COUNT → DTCM数据
// 不再使用 END_FRAME / DTCM_MARKER，彻底避免数据内容与帧标记冲突
timeunit 1ns;
timeprecision 1ps;
module uart_download #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    parameter ALIGN_WIDTH =`ALIGN_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic                       download_en,
    input   logic   [7:0]               uart_rec_byte,
    input   logic                       uart_rx_valid,
    // ITCM写接口
    output  logic                       itcm_download_en,
    output  logic   [ADDR_WIDTH-1:0]    itcm_download_addr,
    output  logic   [DATA_WIDTH-1:0]    itcm_download_data,
    // DTCM写接口
    output  logic                       dtcm_download_en,
    output  logic   [ADDR_WIDTH-1:0]    dtcm_download_addr,
    output  logic   [DATA_WIDTH-1:0]    dtcm_download_data,
    output  logic                       download_done
);

localparam START_FRAME = 32'hBBAABBAA;

// 状态机（二进制编码）
typedef enum logic [5:0] {
    IDLE           = 6'b000001,
    RECV_ITCM_CNT  = 6'b000010,
    RECV_ITCM      = 6'b000100,
    RECV_DTCM_CNT  = 6'b001000,
    RECV_DTCM      = 6'b010000,
    NORMAL_MODE    = 6'b100000
} state_t;

(* mark_debug = "true" *) state_t current_state, next_state;

(* mark_debug = "true" *) logic [1:0]       byte_cnt;
(* mark_debug = "true" *) logic [31:0]      recv_data_q, recv_data_n;
(* mark_debug = "true" *) logic [31:0]      word_count;      // 待接收的字数
(* mark_debug = "true" *) logic             start_frame_det;
logic             uart_rx_valid_d, uart_rx_valid_pos;

// 寄存器输出打拍
logic             itcm_download_en_comb, dtcm_download_en_comb;
logic [31:0]      itcm_download_data_comb, dtcm_download_data_comb;

// uart_rx_valid 上升沿检测
always_ff @(posedge clk) uart_rx_valid_d <= #1 uart_rx_valid;
assign uart_rx_valid_pos = uart_rx_valid && ~uart_rx_valid_d;

// 4 字节拼接移位
assign recv_data_n = (uart_rx_valid_pos && ~download_done && download_en) ?
    {uart_rec_byte, recv_data_q[31:8]} : recv_data_q;

// 帧检测：只有 START_FRAME 需要识别
assign start_frame_det = (byte_cnt == 2'b11) && uart_rx_valid_pos && (recv_data_n == START_FRAME);
assign download_done   = (current_state == NORMAL_MODE) || ~download_en;

// 接收缓冲区
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) recv_data_q <= #1 'h0;
    else       recv_data_q <= #1 recv_data_n;
end

// 状态机
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) current_state <= #1 IDLE;
    else       current_state <= #1 next_state;
end

// 字节计数
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) byte_cnt <= #1 'h0;
    else if (download_done || ~download_en) byte_cnt <= #1 'h0;
    else if(uart_rx_valid_pos) byte_cnt <= #1 byte_cnt + 1;
end

// 字数计数器：从串口收到 count 后加载，每写一字减 1
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) word_count <= #1 'h0;
    else begin
        if ((current_state == RECV_ITCM_CNT || current_state == RECV_DTCM_CNT)
            && (byte_cnt == 2'b11) && uart_rx_valid_pos) begin
            word_count <= #1 recv_data_n;  // 加载 count
        end else if ((current_state == RECV_ITCM && itcm_download_en_comb)
                   || (current_state == RECV_DTCM && dtcm_download_en_comb)) begin
            word_count <= #1 word_count - 1;  // 每写一字减 1
        end
    end
end

// 组合逻辑：状态转移 + 写信号
always_comb begin
    next_state = current_state;
    itcm_download_en_comb = 1'b0;
    dtcm_download_en_comb = 1'b0;
    itcm_download_data_comb = 'h0;
    dtcm_download_data_comb = 'h0;

    case(current_state)
        IDLE: begin
            if(start_frame_det) next_state = RECV_ITCM_CNT;
        end

        RECV_ITCM_CNT: begin
            // 接收 1 个字作为 ITCM 长度，收到后自动跳转
            if((byte_cnt == 2'b11) && uart_rx_valid_pos) begin
                next_state = RECV_ITCM;
            end
        end

        RECV_ITCM: begin
            if (word_count > 0 && (byte_cnt == 2'b11) && uart_rx_valid_pos) begin
                itcm_download_en_comb = 1'b1;
                itcm_download_data_comb = recv_data_n;
            end else if (word_count == 0) begin
                // 上一笔已写完，跳转 DTCM 长度接收
                next_state = RECV_DTCM_CNT;
            end
        end

        RECV_DTCM_CNT: begin
            if((byte_cnt == 2'b11) && uart_rx_valid_pos) begin
                if (recv_data_n == 0) begin
                    next_state = NORMAL_MODE;  // 没有 DTCM 数据
                end else begin
                    next_state = RECV_DTCM;
                end
            end
        end

        RECV_DTCM: begin
            if (word_count > 0 && (byte_cnt == 2'b11) && uart_rx_valid_pos) begin
                dtcm_download_en_comb = 1'b1;
                dtcm_download_data_comb = recv_data_n;
            end else if (word_count == 0) begin
                next_state = NORMAL_MODE;
            end
        end

        NORMAL_MODE: ;
        default: next_state = IDLE;
    endcase
end

// 寄存器输出
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        itcm_download_en   <= #1 1'b0;
        itcm_download_data <= #1 'h0;
        dtcm_download_en   <= #1 1'b0;
        dtcm_download_data <= #1 'h0;
    end else begin
        itcm_download_en   <= #1 itcm_download_en_comb;
        itcm_download_data <= #1 itcm_download_data_comb;
        dtcm_download_en   <= #1 dtcm_download_en_comb;
        dtcm_download_data <= #1 dtcm_download_data_comb;
    end
end

// 地址递增
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        itcm_download_addr <= #1 {`ITCM_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        dtcm_download_addr <= #1 {`DTCM_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
    end else begin
        // ITCM 地址复位
        if (current_state == IDLE && next_state == RECV_ITCM_CNT) begin
            itcm_download_addr <= #1 {`ITCM_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        end else if (current_state == RECV_ITCM && itcm_download_en) begin
            itcm_download_addr[31:ALIGN_WIDTH] <= #1 itcm_download_addr[31:ALIGN_WIDTH] + 1;
        end

        // DTCM 地址复位
        if (current_state == RECV_DTCM_CNT && next_state == RECV_DTCM) begin
            dtcm_download_addr <= #1 {`DTCM_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        end else if (current_state == RECV_DTCM && dtcm_download_en) begin
            dtcm_download_addr[31:ALIGN_WIDTH] <= #1 dtcm_download_addr[31:ALIGN_WIDTH] + 1;
        end
    end
end

endmodule
