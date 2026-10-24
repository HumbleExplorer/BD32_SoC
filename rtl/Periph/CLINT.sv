`include "../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;
module CLINT #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES
)(
    input   logic                       PCLK,
    input   logic                       PRESETn,
    apb_if.slave           s,             // APB 从机接口
    input   logic                       timer_clk_i,
    // to Core
    output  logic   [2*DATA_WIDTH-1:0]  mtime_shadow,// 只读影子
    output  logic                       software_int,
    output  logic                       timer_int
);

// APB responses
assign s.pready  = 1'b1;            // CLINT is always ready
assign s.pslverr = 1'b0;            // Never an error

// APB access helpers
function automatic bit is_read();
    return s.psel & s.penable & ~s.pwrite;
endfunction : is_read

function automatic bit is_write();
    return s.psel & s.penable & s.pwrite;
endfunction : is_write

function automatic logic [DATA_WIDTH-1:0] get_write_value (input [DATA_WIDTH-1:0] original_val);
    for (int n=0; n < ALIGN_BYTES; n++)
    get_write_value[n*8 +: 8] = s.pstrb[n] ? s.pwdata[n*8 +: 8] : original_val[n*8 +: 8];
endfunction : get_write_value

logic   [2*DATA_WIDTH-1:0]  mtime;         // 0x0200BFF8 (64bit)
logic   [2*DATA_WIDTH-1:0]  mtimecmp;      // 0x02004000 (64bit)
logic   [DATA_WIDTH-1:0]    msip;          // 0x02000000 (32bit)

// logic                       illegal_inst;
// logic                       wr_addr_misalign;
localparam MTIME_ADDR    = 16'hBFF8;
localparam MTIMECMP_ADDR = 16'h4000;
localparam MSIP_ADDR     = 16'h0000;

assign mtime_shadow = mtime;
assign software_int = msip[0];
assign timer_int = mtime >= mtimecmp;

// -----------------------------------------------------------------------
// 1MHz timer_clk_i → PCLK 域同步 + 上升沿检测
// 两拍同步消除亚稳态，第三拍做边沿检测
// timer_clk_i 由板级 clk_div_static 对 50MHz 分频产生（独立于 clk_cpu 的时钟域）
// -----------------------------------------------------------------------
logic [1:0] timer_clk_sync;       // 2-FF 同步链
logic       timer_clk_sync_d1;    // 打一拍用于边沿检测
logic       timer_tick_rise;      // 上升沿脉冲（1 PCLK 周期宽）

always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        timer_clk_sync    <= '0;
        timer_clk_sync_d1 <= 1'b0;
    end else begin
        timer_clk_sync    <= {timer_clk_sync[0], timer_clk_i};
        timer_clk_sync_d1 <= timer_clk_sync[1];
    end
end

assign timer_tick_rise = timer_clk_sync[1] & ~timer_clk_sync_d1;

// assign wr_addr_misalign = s.psel && (s.pstrb != 'hF);
always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        mtime <= #1 'h0;
    end else if (is_write() && s.paddr[15:2] == MTIME_ADDR[15:2]) begin
        mtime[DATA_WIDTH-1:0] <= #1 get_write_value(mtime[DATA_WIDTH-1:0]);
    end else if (is_write() && s.paddr[15:2] == MTIME_ADDR[15:2] + 1) begin
        mtime[2*DATA_WIDTH-1:DATA_WIDTH] <= #1 get_write_value(mtime[2*DATA_WIDTH-1:DATA_WIDTH]);
    end else if (timer_tick_rise) begin
        mtime <= #1 mtime + 1'b1;
    end else begin
        mtime <= #1 mtime;
    end
end

always_ff @(posedge PCLK or negedge PRESETn) begin
    if(!PRESETn) begin
        msip <= #1 'h0;
        mtimecmp <= #1 {2*DATA_WIDTH{1'b1}};
    end else begin
        if (is_write()) begin
            case(s.paddr[15:2])
                MTIMECMP_ADDR[15:2]: mtimecmp[DATA_WIDTH-1:0] <= #1 get_write_value(mtimecmp[DATA_WIDTH-1:0]);
                MTIMECMP_ADDR[15:2] + 1: mtimecmp[2*DATA_WIDTH-1:DATA_WIDTH] <= #1 get_write_value(mtimecmp[2*DATA_WIDTH-1:DATA_WIDTH]);
                MSIP_ADDR[15:2] : msip <= #1 get_write_value(msip);
                default : ;
            endcase
        end
    end
end

always_comb begin
    s.prdata = 'h0;
    if (is_read()) begin 
        case (s.paddr[15:2])
            MTIME_ADDR[15:2] : s.prdata = mtime[DATA_WIDTH-1:0];
            MTIME_ADDR[15:2] + 1 : s.prdata = mtime[2*DATA_WIDTH-1:DATA_WIDTH];
            MTIMECMP_ADDR[15:2] : s.prdata = mtimecmp[DATA_WIDTH-1:0];
            MTIMECMP_ADDR[15:2] + 1 : s.prdata = mtimecmp[2*DATA_WIDTH-1:DATA_WIDTH];
            MSIP_ADDR[15:2] : s.prdata = msip;
            default : ;
        endcase
    end
end

`ifndef SYNTHESIS
// ===========================================================================
// SVA: timer_int 电平语义自检（mtime>=mtimecmp 时必须为高，reload 后立即撤销）
// 电平中断语义是"handler 必须重装 mtimecmp"约定（NMSIS/E203 同款）的硬件基础；
// 若比较逻辑被误改为边沿/脉冲语义，软件 reload 约定即失效，此断言立即触发。
// ===========================================================================
a_timer_int_level: assert property (
    @(posedge PCLK) disable iff (!PRESETn)
    (timer_int == (mtime >= mtimecmp)));
`endif

`ifdef ASSERT_MODULE
// ===== SVA L2：CLINT 深化——mtime 计数质量 =====
always @(posedge PCLK) begin
    if (PRESETn && $past(PRESETn)) begin
        // mtime 单调递增（1MHz tick；回绕周期 ~4295s 远超仿真窗口）
        a_l2_clint_mtime_mono: assert property (mtime >= $past(mtime));
        a_l2_clint_mtime_nox: assert property (!$isunknown(mtime));
    end
end
`endif

endmodule
