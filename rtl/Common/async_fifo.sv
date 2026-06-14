/*
Description: 异步FIFO- 适配UART 16550
读数据为组合逻辑输出，即Vivado中First Word Fall Through
后面可以尝试用vivado ip核进行替换。
*/

timeunit 1ns;
timeprecision 1ps;
module async_fifo 
#(
    parameter int DEPTH  = 16,  // UART 16550标准FIFO深度
    parameter int WIDTH  = 8,    // 字节宽（UART数据位宽）
    // 地址 & 指针位宽定义
    localparam int ADDR_W       = $clog2(DEPTH),       // RAM地址位宽
    localparam int PTR_W        = ADDR_W + 1,          // 指针位宽（多1位用于空满判断）
    localparam int PTR_VALID_W  = PTR_W - 1           // 指针有效位（去掉多的1位）
)
(
    input  logic             wclk,          // 写时钟
    input  logic             rclk,          // 读时钟
    input  logic             rst_n,         // 异步复位（低有效）
    input  logic             clr,
    input  logic             wr_en,         // 写使能
    input  logic             rd_en,         // 读使能
    input  logic [WIDTH-1:0] wr_data,       // 写数据
    output logic [WIDTH-1:0] rd_data,       // 读数据
    output logic             wr_full,       // 写满
    output logic             rd_empty,      // 读空
    output logic [PTR_W-1:0] elements_num,  // FIFO元素个数（读时钟域）
    output logic             almost_wr_full,// 几乎满（剩余1个空间）
    output logic             almost_rd_empty// 几乎空（仅剩1个数据）
);

// 内部信号定义
logic [WIDTH-1:0] data [DEPTH-1:0];                // FIFO存储RAM
logic [PTR_W-1:0] wr_ptr;                          // 写指针（二进制）
logic [PTR_W-1:0] rd_ptr;                          // 读指针（二进制）
logic [PTR_W-1:0] wr_ptr_gray;                     // 写指针（格雷码）
logic [PTR_W-1:0] rd_ptr_gray;                     // 读指针（格雷码）

// 跨时钟域两级同步寄存器
logic [PTR_W-1:0] rd_ptr_gray_sync1;               // 读指针格雷码同步到写时钟域-第一级
logic [PTR_W-1:0] rd_ptr_gray_sync2;               // 读指针格雷码同步到写时钟域-第二级
logic [PTR_W-1:0] wr_ptr_gray_sync1;               // 写指针格雷码同步到读时钟域-第一级
logic [PTR_W-1:0] wr_ptr_gray_sync2;               // 写指针格雷码同步到读时钟域-第二级

// 同步后的格雷码转二进制（用于计算元素个数）
logic [PTR_W-1:0] wr_ptr_sync_bin;                 // 写指针格雷码转二进制（读时钟域）
logic [PTR_W-1:0] rd_ptr_sync_bin;                 // 读指针格雷码转二进制（写时钟域）

// RAM实际访问地址（指针低ADDR_W位）
logic [ADDR_W-1:0] wr_addr;
logic [ADDR_W-1:0] rd_addr;

// 地址映射
assign wr_addr = wr_ptr[ADDR_W-1:0];
assign rd_addr = rd_ptr[ADDR_W-1:0];

// 二进制转格雷码
assign wr_ptr_gray = ((wr_ptr) >> 1) ^ wr_ptr;
assign rd_ptr_gray = ((rd_ptr) >> 1) ^ rd_ptr;

// 空、满判断
assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);
assign wr_full  = (wr_ptr_gray == { ~rd_ptr_gray_sync2[PTR_W-1 : PTR_W-2],
                                    rd_ptr_gray_sync2[PTR_W-3:0] });
assign elements_num = wr_ptr_sync_bin - rd_ptr;

// 工程常用：几乎满/几乎空（UART上层可提前处理）
assign almost_wr_full = ( (wr_ptr[PTR_VALID_W-1:0] + 1'b1) == rd_ptr_sync_bin[PTR_VALID_W-1:0] ) 
                     && (wr_ptr[PTR_W-1] != rd_ptr_sync_bin[PTR_W-1]);
assign almost_rd_empty = ( (rd_ptr[PTR_VALID_W-1:0] + 1'b1) == wr_ptr_sync_bin[PTR_VALID_W-1:0] ) 
                      && (wr_ptr_sync_bin[PTR_W-1] == rd_ptr[PTR_W-1]);

// ---------------------------------------------------------
// 格雷码转二进制（同步后的指针）
// ---------------------------------------------------------
// 读时钟域：同步后的写指针格雷码转二进制
function [PTR_W-1:0] gray2bin(input [PTR_W-1:0] gray);
    integer i;
begin
    gray2bin[PTR_W-1] = gray[PTR_W-1];
    for(i = PTR_W-2; i >= 0; i = i - 1) begin
        gray2bin[i] = gray2bin[i+1] ^ gray[i];
    end
end
endfunction

assign wr_ptr_sync_bin = gray2bin(wr_ptr_gray_sync2); // 读时钟域的写指针（二进制）
assign rd_ptr_sync_bin = gray2bin(rd_ptr_gray_sync2); // 写时钟域的读指针（二进制）

// ---------------------------------------------------------
// 写时钟域：写指针 & 写数据（加仿真初始化+写保护）
// ---------------------------------------------------------
always_ff @(posedge wclk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr <= #1 '0;
        // 仿真友好：初始化数据数组（综合工具自动忽略）
        foreach(data[i]) data[i] <= #1 '0;
    end else if (clr) begin
        wr_ptr <= #1 '0;
    end else begin
        // 写使能有效且非满时，写入数据+指针+1
        if (wr_en && !wr_full) begin
            data[wr_addr] <= #1 wr_data;
            wr_ptr        <= #1 wr_ptr + 1'b1;
        end
    end
end

// ---------------------------------------------------------
// 读时钟域：读指针 & 读数据（加读保护）
// ---------------------------------------------------------
always_ff @(posedge rclk or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr  <= #1 '0;
    end else if (clr) begin
        rd_ptr  <= #1 '0;
    end else begin
        // 读使能有效且非空时，读出数据+指针+1
        if (rd_en && !rd_empty) begin
            rd_ptr  <= #1 rd_ptr + 1'b1;
        end
    end
end

// ---------------------------------------------------------
// 读指针格雷码 同步到 写时钟域（两级同步，避免亚稳态）
// ---------------------------------------------------------
always_ff @(posedge wclk or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr_gray_sync1 <= #1 '0;
        rd_ptr_gray_sync2 <= #1 '0;
    end else begin
        rd_ptr_gray_sync1 <= #1 rd_ptr_gray;
        rd_ptr_gray_sync2 <= #1 rd_ptr_gray_sync1;
    end
end

// ---------------------------------------------------------
// 写指针格雷码 同步到 读时钟域（两级同步，避免亚稳态）
// ---------------------------------------------------------
always_ff @(posedge rclk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr_gray_sync1 <= #1 '0;
        wr_ptr_gray_sync2 <= #1 '0;
    end else begin
        wr_ptr_gray_sync1 <= #1 wr_ptr_gray;
        wr_ptr_gray_sync2 <= #1 wr_ptr_gray_sync1;
    end
end

assign rd_data = (rd_en && !rd_empty) ? data[rd_addr] : 'h0;
endmodule