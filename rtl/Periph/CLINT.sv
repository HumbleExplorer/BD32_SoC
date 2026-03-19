`include "../SoC_Config.sv"
`include "../RV32_Inst_Define.sv"
module CLINT #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES
)( 
    input   logic                       clk,
    input   logic                       rst_n,
    // from PLL
    // input   logic                       clk_timer,
    // from Core
    input   logic                       clint_sel,
    input   logic   [ADDR_WIDTH-1:0]    mmio_addr,
    input   logic                       wr_en,
    input   logic   [DATA_WIDTH-1:0]    wr_data,
    input   logic   [ALIGN_BYTES-1:0]   wr_mask,
    // to Core
    output  logic   [DATA_WIDTH-1:0]    rd_data,
    output  logic   [2*DATA_WIDTH-1:0]  mtime_shadow,// 只读影子
    output  logic                       software_int,
    output  logic                       timer_int
);

logic   [2*DATA_WIDTH-1:0]  mtime;// 0x0200BFF8 (64bit)
logic   [2*DATA_WIDTH-1:0]  mtimecmp;// 0x02004000 (64bit)
logic   [DATA_WIDTH-1:0]    msip;// 0x02000000 (32bit)
// logic                       illegal_inst;
// logic                       wr_addr_misalign;
localparam MTIME_ADDR = 32'h0200BFF8;
localparam MTIMECMP_ADDR = 32'h02004000;
localparam MSIP_ADDR = 32'h02000000;

assign mtime_shadow = mtime;
assign software_int = msip[0];
assign timer_int = mtime >= mtimecmp;

// assign wr_addr_misalign = clint_sel && (wr_mask != 'hF);
//==================================================
// 1. 跨时钟域处理 (CDC)：慢 -> 快
//==================================================
// 目的：将 clk_timer (1MHz) 的上升沿转换为 clk (100MHz) 域的单周期脉冲
// logic time_inc_pulse; // 在 clk 域下的递增脉冲

// Cdc_Pulse u_timer_tick_cdc (
//     .dst_clk    (clk),           // 目标是系统时钟
//     .dst_rst_n  (rst_n),
//     .src_pulse  (clk_timer),     // 源是慢速时钟
//     .dst_pulse  (time_inc_pulse) // 输出同步后的脉冲
// );

// mtime 计数
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        mtime <= 'h0;
    // end else if (time_inc_pulse) begin
    end else begin
        mtime <= mtime + 1'b1;
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    msip <= 'h0;
    mtimecmp <= {2*DATA_WIDTH{1'b1}};
    if(!rst_n) begin
        msip <= 'h0;
        mtimecmp <= {2*DATA_WIDTH{1'b1}};
    end else if (wr_en && clint_sel) begin
        if (wr_mask == 'hF) begin
            case(mmio_addr[15:2])
                MTIMECMP_ADDR[15:2]: mtimecmp[DATA_WIDTH-1:0] <= wr_data;
                MTIMECMP_ADDR[15:2] + 1: mtimecmp[2*DATA_WIDTH-1:DATA_WIDTH] <= wr_data;
                MSIP_ADDR : msip[0] <= wr_data;
                default : ;
            endcase
        end
    end
end

always_comb begin
    rd_data = 'h0;
    if (!rst_n) begin
        rd_data = 'h0;
    end else if (clint_sel) begin 
        case (mmio_addr[15:2])
            MTIME_ADDR[15:2] : rd_data = mtime[DATA_WIDTH-1:0];
            MTIME_ADDR[15:2] + 1 : rd_data = mtime[2*DATA_WIDTH-1:DATA_WIDTH];
            MTIMECMP_ADDR[15:2] : rd_data = mtimecmp[DATA_WIDTH-1:0];
            MTIMECMP_ADDR[15:2] + 1 : rd_data = mtimecmp[2*DATA_WIDTH-1:DATA_WIDTH];
            MSIP_ADDR[15:2] : rd_data = msip;
            default : rd_data = msip; 
        endcase
    end
end

endmodule
