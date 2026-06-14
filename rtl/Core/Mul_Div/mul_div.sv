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

// DIV 融合（流水线乘法器不需要融合）
logic                           data_valid_reg;
logic   [REG_ADDR_WIDTH-1:0]    reg_rs1_raddr_reg;
logic   [REG_ADDR_WIDTH-1:0]    reg_rs2_raddr_reg;
`ifndef MULT_PIPELINE
logic   [DATA_WIDTH-1:0]        mul_fuse_result_reg;
logic                           mul_fuse_hit;
`endif
logic   [DATA_WIDTH-1:0]        div_fuse_result_reg;
logic                           div_fuse_hit;
logic   [2:0]                   op_func3_reg;
logic                           fuse_hit;
logic   [DATA_WIDTH*2-1:0]      mul_full_result;
logic   [DATA_WIDTH*2-1:0]      div_full_result;

assign func3_mode_i  = func3_i[1:0];
assign data_valid    = mul_valid || div_valid;
assign mul_ready_o   = mul_ready;
assign div_ready_o   = div_ready;


// MUL/DIV 使能（融合命中时关闭对应单元）
`ifdef MULT_PIPELINE
assign mul_en       = (!func3_i[2] && start);           // 流水线，不需要融合
assign mul_valid_o  = mul_valid;
assign fuse_hit     = div_fuse_hit;
`else
assign mul_en       = (!func3_i[2] && start) && ~mul_fuse_hit; // 状态机，融合节省周期
assign mul_valid_o  = mul_valid || mul_fuse_hit;
assign fuse_hit     = mul_fuse_hit || div_fuse_hit;

`endif
assign div_en       = (func3_i[2]  && start) && ~div_fuse_hit;
assign div_valid_o  = div_valid;
// ==========================================================================
// 融合检测
// ==========================================================================
always_ff @(posedge clk) begin
    data_valid_reg <= #1 data_valid;
end
`ifndef MULT_PIPELINE
assign mul_fuse_hit = start && data_valid_reg
                && (reg_rs1_raddr == reg_rs1_raddr_reg)
                && (reg_rs2_raddr == reg_rs2_raddr_reg)
                && (reg_rs1_raddr != reg_rd_waddr)
                && (reg_rs2_raddr != reg_rd_waddr)
                && ((op_func3_reg == `INST_MULH   && func3_i == `INST_MUL)
                ||  (op_func3_reg == `INST_MULHU  && func3_i == `INST_MUL)
                ||  (op_func3_reg == `INST_MULHSU && func3_i == `INST_MUL));
`endif
assign div_fuse_hit = start && data_valid_reg
                && (reg_rs1_raddr == reg_rs1_raddr_reg)
                && (reg_rs2_raddr == reg_rs2_raddr_reg)
                && (reg_rs1_raddr != reg_rd_waddr)
                && (reg_rs2_raddr != reg_rd_waddr)
                && ((op_func3_reg == `INST_DIV    && func3_i == `INST_REM)
                ||  (op_func3_reg == `INST_DIVU   && func3_i == `INST_REMU));

// 融合结果锁存
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        reg_rs1_raddr_reg <= #1 '0;
        reg_rs2_raddr_reg <= #1 '0;
`ifndef MULT_PIPELINE
        mul_fuse_result_reg <= #1 '0;
`endif
        div_fuse_result_reg <= #1 '0;
        op_func3_reg    <= #1 '0;
    end else if(data_valid) begin
        reg_rs1_raddr_reg <= #1 reg_rs1_raddr;
        reg_rs2_raddr_reg <= #1 reg_rs2_raddr;
        op_func3_reg    <= #1 func3_i;
`ifndef MULT_PIPELINE
        mul_fuse_result_reg <= #1 mul_o[DATA_WIDTH-1:0];
`endif
        div_fuse_result_reg <= #1 quot_rem_o[DATA_WIDTH*2-1:DATA_WIDTH];
    end
end

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
// 64位源结果选择（融合优先）
// ==========================================================================
`ifdef MULT_PIPELINE
assign mul_full_result = mul_o;
`else
assign mul_full_result = mul_fuse_hit ? {{DATA_WIDTH{1'b0}},mul_fuse_result_reg} : mul_o;//fuse不需要管低32位
`endif
assign div_full_result = div_fuse_hit ? {div_fuse_result_reg,{DATA_WIDTH{1'b0}}} : quot_rem_o;//fuse不需要管低32位

// ==========================================================================
// 32位结果截取（使用锁存的 func3_sel）
// ==========================================================================
always_comb begin
    case(mul_func3_mode)
        2'b00:  mul_result_o = mul_full_result[DATA_WIDTH-1:0];             // MUL
        2'b01:  mul_result_o = mul_full_result[2*DATA_WIDTH-1:DATA_WIDTH];  // MULH
        2'b10:  mul_result_o = mul_full_result[2*DATA_WIDTH-1:DATA_WIDTH];  // MULHU
        2'b11:  mul_result_o = mul_full_result[2*DATA_WIDTH-1:DATA_WIDTH];  // MULHSU
        default: mul_result_o = '0;
    endcase
end

always_comb begin
    case(div_func3_mode)
        2'b00:  div_result_o = div_full_result[DATA_WIDTH-1:0];             // DIV
        2'b01:  div_result_o = div_full_result[DATA_WIDTH-1:0];             // DIVU
        2'b10:  div_result_o = div_full_result[2*DATA_WIDTH-1:DATA_WIDTH];  // REM
        2'b11:  div_result_o = div_full_result[2*DATA_WIDTH-1:DATA_WIDTH];  // REMU
        default: div_result_o = '0;
    endcase
end

endmodule
