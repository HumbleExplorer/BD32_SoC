// ==========================================================================
// 同步 FIFO（先入先出缓冲器）
//
// 支持两种写入方式：
//   1. 正常写：wr_en + wr_data → 写入 wr_ptr 位置，wr_ptr 前进
//   2. 旁路写：bp_wr_en + bp_addr + bp_data → 写入任意指定位置（不移动指针）
//
// 旁路写用于 OITF 场景——乘除法器算完后需要把结果写回 FIFO 中间的某个条目
// （partial update），这个条目之前已经通过正常写入了。
//
// 读：rd_en → rd_data = mem[rd_ptr]（组合读出，延迟 0）
// ==========================================================================

module sync_fifo #(
    parameter DEPTH      = 8,                  // FIFO 深度
    parameter DATA_WIDTH = 32,                 // 数据位宽
    parameter ADDR_WIDTH = $clog2(DEPTH)       // ceil(log2(DEPTH))
)(
    input   logic                       clk,
    input   logic                       rst_n,

    // ======== 正常写端口 ========
    input   logic                       wr_en,          // 写使能（写入 wr_ptr 位置）
    input   logic   [DATA_WIDTH-1:0]    wr_data,        // 写入数据

    // ======== 旁路写端口（写入任意地址，不移动指针）========
    input   logic                       bp_wr_en,       // 旁路写使能
    input   logic   [ADDR_WIDTH-1:0]    bp_wr_addr,     // 旁路写地址（任意）
    input   logic   [DATA_WIDTH-1:0]    bp_wr_data,     // 旁路写数据

    // ======== 读端口 ========
    input   logic                       rd_en,          // 读使能
    output  logic   [DATA_WIDTH-1:0]    rd_data,        // 读出数据（mem[rd_ptr]）

    // ======== 状态 ========
    output  logic                       full,           // 已满
    output  logic                       empty,          // 已空
    output  logic   [ADDR_WIDTH:0]      count,          // 占用数
    output  logic   [ADDR_WIDTH-1:0]    wr_ptr,         // 写指针
    output  logic   [ADDR_WIDTH-1:0]    rd_ptr          // 读指针
);


// ==========================================================================
// 内部信号
// ==========================================================================
logic   [DATA_WIDTH-1:0]    mem [DEPTH-1:0];           // 存储阵列
logic   [ADDR_WIDTH-1:0]    wr_ptr_nxt;
logic   [ADDR_WIDTH-1:0]    rd_ptr_nxt;
logic   [ADDR_WIDTH:0]      cnt;
logic   [ADDR_WIDTH:0]      cnt_nxt;

logic   wr_fire;                                       // 正常写触发
logic   rd_fire;                                       // 读触发

assign  wr_fire = wr_en & ~full;
assign  rd_fire = rd_en & ~empty;

// ==========================================================================
// 空满判断
// ==========================================================================
assign  empty   = (cnt == '0);
assign  full    = (cnt == DEPTH);
assign  count   = cnt;

// ==========================================================================
// 指针更新（组合逻辑）
// ==========================================================================
always_comb begin
    wr_ptr_nxt = wr_ptr;
    rd_ptr_nxt = rd_ptr;
    cnt_nxt    = cnt;

    if (wr_fire) begin
        wr_ptr_nxt = (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1;
        cnt_nxt    = cnt + 1'b1;
    end

    if (rd_fire) begin
        rd_ptr_nxt = (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1;
        cnt_nxt    = cnt_nxt - 1'b1;
    end
end

// ==========================================================================
// 读出数据（组合逻辑）
// ==========================================================================
assign  rd_data = mem[rd_ptr];

// ==========================================================================
// 时序逻辑
// ==========================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr  <= '0;
        rd_ptr  <= '0;
        cnt     <= '0;
    end else begin
        // 正常写（写指针位置）
        if (wr_fire) begin
            mem[wr_ptr] <= wr_data;
        end
        // 旁路写（任意地址，用于 partial update）
        if (bp_wr_en) begin
            mem[bp_wr_addr] <= bp_wr_data;
        end
        wr_ptr  <= wr_ptr_nxt;
        rd_ptr  <= rd_ptr_nxt;
        cnt     <= cnt_nxt;
    end
end

endmodule
