`include "../../SoC_Config.sv"
// 串口一键下载模块（适配RISC-V ITCM）
// 功能：接收串口数据，识别帧头/帧尾，将.bin文件写入ITCM，完成后切换到用户模式
`timescale 1ns / 1ps
module uart_download #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    parameter ALIGN_WIDTH =`ALIGN_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    // input   logic                       clk,
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic                       download_en,  //外部引脚
    input   logic   [7:0]               uart_rec_byte,//来自总线
    input   logic                       uart_rx_valid,//来自总线
    // ITCM写接口
    output  logic                       itcm_wr_en,   // ITCM写使能
    output  logic   [ADDR_WIDTH-1:0]    itcm_wr_addr, // ITCM写地址
    output  logic   [DATA_WIDTH-1:0]    itcm_wr_data, // ITCM写数据
    output  logic                       download_done   // 正在下载标志
);

// 帧头/帧尾定义（但其实有风险，万一指令里正好有和帧头帧尾相同的就完了，应该不会那么巧吧）
localparam START_FRAME = 32'hBBAABBAA;//传0xAA 0xBB 0xAA 0xBB
localparam END_FRAME   = 32'hFFEEFFEE;//传0xEE 0xFF 0xEE 0xFF
// 状态机定义
typedef enum logic [2:0] {
    IDLE         = 3'b001, // 空闲（一直在检测）
    RECV_DATA    = 3'b010, // 接收数据并拼接
    NORMAL_MODE  = 3'b100  // 切换到用户模式
} download_state_t;

// 内部寄存器
download_state_t current_state;
download_state_t next_state;
logic [ALIGN_WIDTH-1:0]   byte_cnt;         // 字节计数（0-3，32位拼接）
logic [DATA_WIDTH-1:0]    recv_data_q;      // 4字节缓冲（拼接32位指令）
logic [DATA_WIDTH-1:0]    recv_data_n;      // 4字节缓冲（拼接32位指令）
logic                     itcm_addr_access_valid;
logic                     detect_start_frame;
logic                     detect_end_frame;
logic                     word_ready;
logic                     uart_rx_valid_d;
logic                     uart_rx_valid_pos;
// 组合输出信号（再打一拍寄存器输出，切断 APB→ITCM 长组合路径）
logic                     itcm_wr_en_comb;
logic [DATA_WIDTH-1:0]    itcm_wr_data_comb;
// 传输程序：小端传输，低字节先传

always_ff @(posedge clk) begin
    uart_rx_valid_d <= #1 uart_rx_valid;
end
assign uart_rx_valid_pos = uart_rx_valid && ~uart_rx_valid_d;
// T0: recv A -> shift = {A,0,0,0}
// T1: recv B -> shift = {B,A,0,0}
// T2: recv A -> shift = {A,B,A,0}
// T3: recv B -> shift = {B,A,B,A}
assign recv_data_n = (uart_rx_valid_pos && ~download_done && download_en) ? 
{uart_rec_byte,recv_data_q[DATA_WIDTH-1:8]} : recv_data_q;
assign itcm_addr_access_valid = itcm_wr_addr[DATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `ITCM_BASE_TAG;
// 帧检测逻辑
assign detect_start_frame =  byte_cnt == 2'b11 && recv_data_n == START_FRAME;
assign detect_end_frame = byte_cnt == 2'b11 && recv_data_n == END_FRAME;
assign download_done = current_state == NORMAL_MODE || ~download_en;
assign word_ready = (byte_cnt == 2'b11) && uart_rx_valid_pos && !detect_start_frame && !detect_end_frame;
// 拼接4字节串口数据
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        recv_data_q <= #1 'h0;
    end else begin
        recv_data_q <= #1 recv_data_n;
    end
end
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= #1 IDLE;
    end
    else begin
        current_state <= #1 next_state;
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        byte_cnt <= #1 'h0;
    end else if (download_done || ~download_en) begin
        byte_cnt <= #1 'h0;
    end else if(uart_rx_valid_pos) begin
        byte_cnt <= #1 byte_cnt + 1;
    end
end

always_comb begin
    next_state = current_state;
    itcm_wr_data_comb = 'h0;
    itcm_wr_en_comb = 1'b0;
    case(current_state)
        IDLE: begin
            // 检测到启动帧，进入数据接收状态
            if(detect_start_frame) begin
                next_state = RECV_DATA;
            end
        end
        RECV_DATA: begin
            if (itcm_addr_access_valid) begin
                if(detect_start_frame) begin 
                    itcm_wr_en_comb = 1'b0;
                end else if (detect_end_frame) begin// 检测结束帧，退出数据接收
                    next_state = NORMAL_MODE;
                    itcm_wr_en_comb = 1'b0; // 停止写ITCM
                end else if (word_ready) begin
                    itcm_wr_data_comb = recv_data_n;
                    itcm_wr_en_comb = 1'b1;
                end
            end
        end
        NORMAL_MODE:;
        default: next_state = IDLE;
    endcase
end

// 寄存器输出（切断 APB→ITCM 长组合路径，串口下载速度慢，1 拍延迟无影响）
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        itcm_wr_en   <= #1 1'b0;
        itcm_wr_data <= #1 'h0;
    end else begin
        itcm_wr_en   <= #1 itcm_wr_en_comb;
        itcm_wr_data <= #1 itcm_wr_data_comb;
    end
end

// 核心状态机
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        itcm_wr_addr <= #1 {`ITCM_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
    end else begin
        case(current_state)
            RECV_DATA: begin
                if(itcm_addr_access_valid && itcm_wr_en) begin
                    itcm_wr_addr[DATA_WIDTH-1:ALIGN_WIDTH] <= #1 itcm_wr_addr[DATA_WIDTH-1:ALIGN_WIDTH] + 1;
                end
            end
            default:;
        endcase
    end
end

endmodule
