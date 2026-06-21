timeunit 1ns;
timeprecision 1ps;
// =========================================================================
// 同步 FIFO（先入先出缓冲器，标准单时钟域）
// 无旁路写端口，纯标准 FIFO 接口
// 读：rd_en → rd_data = mem[rd_ptr]（组合读出）
// =========================================================================
module sync_fifo #(
    parameter DEPTH      = 8,                  // FIFO 深度
    parameter DATA_WIDTH = 32,                 // 数据位宽
    localparam ADDR_WIDTH = $clog2(DEPTH)      // ceil(log2(DEPTH))
)(
    input   logic                       clk,
    input   logic                       rst_n,
    // 写端口
    input   logic                       wr_en,
    input   logic   [DATA_WIDTH-1:0]    wr_data,
    // 读端口
    input   logic                       rd_en,
    output  logic   [DATA_WIDTH-1:0]    rd_data,
    // 状态
    output  logic                       full,
    output  logic                       empty,
    output  logic   [ADDR_WIDTH:0]      count
);

logic   [DATA_WIDTH-1:0]    mem [DEPTH-1:0];
logic   [ADDR_WIDTH-1:0]    wr_ptr, rd_ptr;
logic   [ADDR_WIDTH:0]      cnt;
logic   [ADDR_WIDTH-1:0]    wr_ptr_nxt, rd_ptr_nxt;
logic   [ADDR_WIDTH:0]      cnt_nxt;
logic                       wr_fire, rd_fire;

assign  wr_fire = wr_en & ~full;
assign  rd_fire = rd_en & ~empty;
assign  empty   = (cnt == '0);
assign  full    = (cnt == DEPTH);
assign  count   = cnt;
assign  rd_data = mem[rd_ptr];

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

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr  <= '0;
        rd_ptr  <= '0;
        cnt     <= '0;
    end else begin
        if (wr_fire)
            mem[wr_ptr] <= wr_data;
        wr_ptr <= wr_ptr_nxt;
        rd_ptr <= rd_ptr_nxt;
        cnt    <= cnt_nxt;
    end
end

endmodule
