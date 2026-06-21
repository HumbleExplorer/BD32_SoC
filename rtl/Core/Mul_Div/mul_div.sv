`include "./../../SoC_Config.sv"
`include "../../RV32_Inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
module mul_div #(
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH
)(
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic                       start,
    input   logic [REG_ADDR_WIDTH-1:0]  reg_rs1_raddr,
    input   logic [REG_ADDR_WIDTH-1:0]  reg_rs2_raddr,
    input   logic [REG_ADDR_WIDTH-1:0]  reg_rd_waddr,
    input   logic [2:0]                 func3_i,
    input   logic [DATA_WIDTH-1:0]      a_i,
    input   logic [DATA_WIDTH-1:0]      b_i,
    // OITF 独立 MUL/DIV 结果
    output  logic [DATA_WIDTH-1:0]      mul_result_o,
    output  logic [DATA_WIDTH-1:0]      div_result_o,
    output  logic                       mul_ready_o,
    output  logic                       div_ready_o,
    output  logic                       mul_valid_o,
    output  logic                       div_valid_o
);

// ==========================================================================
// 内部信号
// ==========================================================================
logic                           mul_en, div_en;
logic                           mul_ready, div_ready;
logic                           mul_valid, div_valid;
logic   [1:0]                   func3_mode_i;
logic   [1:0]                   mul_func3_mode;     // 乘法器锁存 func3_mode
logic   [1:0]                   div_func3_mode;     // 除法器锁存 func3_mode
logic   [DATA_WIDTH*2-1:0]      mul_o;
logic   [DATA_WIDTH*2-1:0]      quot_rem_o;
logic                           data_valid;


assign func3_mode_i  = func3_i[1:0];
assign data_valid    = mul_valid || div_valid;
assign mul_ready_o   = mul_ready;
assign div_ready_o   = div_ready;

assign mul_en       = (!func3_i[2] && start);           // 流水线，不需要融合
assign mul_valid_o  = mul_valid;

assign div_en       = (func3_i[2]  && start);
assign div_valid_o  = div_valid;

// ==========================================================================
// 乘法器实例化
// ==========================================================================
multiplier #(
    .DATA_WIDTH     (DATA_WIDTH),
`ifdef MULT_PIPELINE
    .PIPELINE       (1) // 流水线模式
`else
    .PIPELINE       (0) // 状态机模式
`endif
) u_multiplier (
    .clk            (clk),
    .rst_n          (rst_n),
    .start          (mul_en),
    .func3_mode_i   (func3_mode_i),
    .a_i            (a_i),
    .b_i            (b_i),
    .mul_o          (mul_o),
    .func3_mode_o   (mul_func3_mode),
    .data_valid     (mul_valid),
    .ready          (mul_ready)
);

// ==========================================================================
// 除法器实例化
// ==========================================================================
divider #(
    .DATA_WIDTH     (DATA_WIDTH)
) u_divider (
    .clk            (clk),
    .rst_n          (rst_n),
    .start          (div_en),
    .func3_mode_i   (func3_mode_i),
    .dividend       (a_i),
    .divisor        (b_i),
    .quot_rem_o     (quot_rem_o),
    .func3_mode_o   (div_func3_mode),
    .data_valid     (div_valid),
    .ready          (div_ready)
);

// ==========================================================================
// 32位结果截取（使用锁存的 func3_sel）
// ==========================================================================
always_comb begin
    case(mul_func3_mode)
        2'b00:  mul_result_o = mul_o[DATA_WIDTH-1:0];             // MUL
        2'b01:  mul_result_o = mul_o[2*DATA_WIDTH-1:DATA_WIDTH];  // MULH
        2'b10:  mul_result_o = mul_o[2*DATA_WIDTH-1:DATA_WIDTH];  // MULHU
        2'b11:  mul_result_o = mul_o[2*DATA_WIDTH-1:DATA_WIDTH];  // MULHSU
        default: mul_result_o = '0;
    endcase
end

always_comb begin
    case(div_func3_mode)
        2'b00:  div_result_o = quot_rem_o[DATA_WIDTH-1:0];             // DIV
        2'b01:  div_result_o = quot_rem_o[DATA_WIDTH-1:0];             // DIVU
        2'b10:  div_result_o = quot_rem_o[2*DATA_WIDTH-1:DATA_WIDTH];  // REM
        2'b11:  div_result_o = quot_rem_o[2*DATA_WIDTH-1:DATA_WIDTH];  // REMU
        default: div_result_o = '0;
    endcase
end

endmodule
