`include "../SoC_Config.sv"
`include "../RV32_Inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
module CLINT #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES
)(
    input   logic                       PCLK,
    input   logic                       PRESETn,
    input   logic   [ADDR_WIDTH-1:0]    PADDR,
    input   logic                       PSEL,
    input   logic                       PENABLE,
    input   logic                       PWRITE,
    input   logic   [ALIGN_BYTES-1:0]   PSTRB,
    input   logic   [DATA_WIDTH-1:0]    PWDATA,
    output  logic   [DATA_WIDTH-1:0]    PRDATA,
    output  logic                       PREADY,
    output  logic                       PSLVERR,
    // to Core
    output  logic   [2*DATA_WIDTH-1:0]  mtime_shadow,// 只读影子
    output  logic                       software_int,
    output  logic                       timer_int
);

// APB responses
assign PREADY  = 1'b1;            // CLINT is always ready
assign PSLVERR = 1'b0;            // Never an error

// APB access helpers
function automatic bit is_read();
    return PSEL & PENABLE & ~PWRITE;
endfunction : is_read

function automatic bit is_write();
    return PSEL & PENABLE & PWRITE;
endfunction : is_write

function automatic logic [DATA_WIDTH-1:0] get_write_value (input [DATA_WIDTH-1:0] original_val);
    for (int n=0; n < ALIGN_BYTES; n++)
    get_write_value[n*8 +: 8] = PSTRB[n] ? PWDATA[n*8 +: 8] : original_val[n*8 +: 8];
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

// assign wr_addr_misalign = PSEL && (PSTRB != 'hF);
always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        mtime <= #1 'h0;
    end else if (is_write() && PADDR[15:2] == MTIME_ADDR[15:2]) begin
        mtime[DATA_WIDTH-1:0] <= #1 get_write_value(mtime[DATA_WIDTH-1:0]);
    end else if (is_write() && PADDR[15:2] == MTIME_ADDR[15:2] + 1) begin
        mtime[2*DATA_WIDTH-1:DATA_WIDTH] <= #1 get_write_value(mtime[2*DATA_WIDTH-1:DATA_WIDTH]);
    end else begin
        mtime <= #1 mtime + 1'b1;
    end
end

always_ff @(posedge PCLK or negedge PRESETn) begin
    if(!PRESETn) begin
        msip <= #1 'h0;
        mtimecmp <= #1 {2*DATA_WIDTH{1'b1}};
    end else begin
        if (is_write()) begin
            case(PADDR[15:2])
                MTIMECMP_ADDR[15:2]: mtimecmp[DATA_WIDTH-1:0] <= #1 get_write_value(mtimecmp[DATA_WIDTH-1:0]);
                MTIMECMP_ADDR[15:2] + 1: mtimecmp[2*DATA_WIDTH-1:DATA_WIDTH] <= #1 get_write_value(mtimecmp[2*DATA_WIDTH-1:DATA_WIDTH]);
                MSIP_ADDR[15:2] : msip <= #1 get_write_value(msip);
                default : ;
            endcase
        end
    end
end

always_comb begin
    PRDATA = 'h0;
    if (is_read()) begin 
        case (PADDR[15:2])
            MTIME_ADDR[15:2] : PRDATA = mtime[DATA_WIDTH-1:0];
            MTIME_ADDR[15:2] + 1 : PRDATA = mtime[2*DATA_WIDTH-1:DATA_WIDTH];
            MTIMECMP_ADDR[15:2] : PRDATA = mtimecmp[DATA_WIDTH-1:0];
            MTIMECMP_ADDR[15:2] + 1 : PRDATA = mtimecmp[2*DATA_WIDTH-1:DATA_WIDTH];
            MSIP_ADDR[15:2] : PRDATA = msip;
            default : ;
        endcase
    end
end

endmodule
