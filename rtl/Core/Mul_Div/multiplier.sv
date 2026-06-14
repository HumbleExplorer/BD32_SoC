timeunit 1ns;
timeprecision 1ps;
module multiplier #(
    parameter DATA_WIDTH = 32,
    parameter PIPELINE = 1,
    localparam PP_NUM     = DATA_WIDTH / 2,
    localparam PROD_WIDTH = DATA_WIDTH * 2,
    localparam MAX_LEVEL  = $clog2(DATA_WIDTH/4)
)(
    input   logic                    clk,
    input   logic                    rst_n,
(*MAX_FANOUT = 32*)input   logic                    start,
    input   logic [1:0]              func3_mode_i,
    input   logic [DATA_WIDTH-1:0]   a_i,
    input   logic [DATA_WIDTH-1:0]   b_i,
    output  logic [DATA_WIDTH*2-1:0] mul_o,
    output  logic [1:0]              func3_mode_o,
    output  logic                    data_valid,
    output  logic                    ready
);

//==========================================================================
// 公共信号：所有核心运算模块
//==========================================================================
logic [DATA_WIDTH+1:0]  booth_o   [PP_NUM-1:0];
logic [PROD_WIDTH:0]    pp        [PP_NUM-1:0];
logic [PROD_WIDTH:0]    pp_reg    [0:PP_NUM-1];

logic [PROD_WIDTH+1:0]  cpr_res0, cpr_res1;
logic [PROD_WIDTH+1:0]  cpr_res0_reg, cpr_res1_reg;

logic [PROD_WIDTH-1:0]  mul_o_comb;
logic                   cout_comb;
logic [DATA_WIDTH-1:0]  fix_temp_reg;
logic [PROD_WIDTH-1:0]  prod_full;
logic [PROD_WIDTH-1:0]  mul_o_comb_reg;
logic [DATA_WIDTH-1:0]  prod_high_reg;

logic   a_sign_en, b_sign_en;

//==========================================================================
// 流水线版本 / 状态机版本 选择
//==========================================================================
generate if(PIPELINE==1) begin : MULT_PIPELINE

// ┌─────────────────────────────────────────────────────────────┐
// │ 流水线乘法器（4 级: S0→S1→S2→S3，每拍可接受新输入）                  │
// └─────────────────────────────────────────────────────────────┘

// --- Pipeline valid bits ---
logic valid_s1, valid_s2, valid_s3;

// --- Pipeline operand registers ---
logic [DATA_WIDTH-1:0] a_s1, b_s1, a_s2, b_s2;
logic [1:0] func3_s1, func3_s2, func3_s3;

// --- S下沿：operand latch + valid shift ---
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_s1 <= #1 1'b0;
        valid_s2 <= #1 1'b0;
        valid_s3 <= #1 1'b0;
        a_s1     <= #1 '0;  b_s1     <= #1 '0;
        a_s2     <= #1 '0;  b_s2     <= #1 '0;
        func3_s1 <= #1 '0;  func3_s2 <= #1 '0;  func3_s3 <= #1 '0;
    end else begin
        valid_s1 <= #1 start;
        valid_s2 <= #1 valid_s1;
        valid_s3 <= #1 valid_s2;
        if (start)    begin a_s1 <= #1 a_i; b_s1 <= #1 b_i; func3_s1 <= #1 func3_mode_i; end
        if (valid_s1) begin a_s2 <= #1 a_s1; b_s2 <= #1 b_s1; func3_s2 <= #1 func3_s1; end
        if (valid_s2) begin func3_s3 <= #1 func3_s2; end
    end
end

assign ready      = 1'b1;
assign data_valid = valid_s3;
assign func3_mode_o = valid_s3 ? func3_s3 : '0;

// --- S0→S1: pp_reg（使用原始 start 使能，组合逻辑 pp 由此拍 a_i/b_i 算出）---
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(int i=0; i<PP_NUM; i++) pp_reg[i] <= #1 'h0;
    end else if(start) begin
        for(int i=0; i<PP_NUM; i++) pp_reg[i] <= #1 pp[i];
    end
end

// --- S1→S2: S1 operands + cpr_reg ---
assign a_sign_en = (func3_s1 == 2'b00) || (func3_s1 == 2'b01) || (func3_s1 == 2'b10);
assign b_sign_en = (func3_s1 == 2'b00) || (func3_s1 == 2'b01);

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cpr_res0_reg <= #1 '0;
        cpr_res1_reg <= #1 '0;
        fix_temp_reg <= #1 '0;
    end else if(valid_s1) begin
        cpr_res0_reg <= #1 cpr_res0;
        cpr_res1_reg <= #1 cpr_res1;
        fix_temp_reg <= #1 ((!a_sign_en && a_s1[DATA_WIDTH-1]) ? b_s1 : '0)
                           + ((!b_sign_en && b_s1[DATA_WIDTH-1]) ? a_s1 : '0);
    end
end

// --- S2→S3 result latch ---
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        mul_o_comb_reg <= #1 '0;
        prod_high_reg  <= #1 '0;
    end else if(valid_s2) begin
        mul_o_comb_reg <= #1 mul_o_comb;
        prod_high_reg  <= #1 fix_temp_reg + mul_o_comb[PROD_WIDTH-1:DATA_WIDTH];
    end
end

// --- Result output ---
assign prod_full = {prod_high_reg, mul_o_comb_reg[DATA_WIDTH-1:0]};
assign mul_o = (valid_s3) ? prod_full : {PROD_WIDTH{1'b0}};

end else begin : MULT_NO_PIPELINE

// ┌─────────────────────────────────────────────────────────────┐
// │ 原始 4 态状态机（IDLE→COMPRESS→CLA_CALC→DONE）               │
// └─────────────────────────────────────────────────────────────┘

typedef enum logic [3:0] {
    IDLE      = 4'b0001,
    COMPRESS  = 4'b0010,
    CLA_CALC  = 4'b0100,
    DONE      = 4'b1000
} state_t;
(*MAX_FANOUT = 32*)state_t state;

logic   [DATA_WIDTH-1:0] a_reg;
logic   [DATA_WIDTH-1:0] b_reg;
logic   [1:0]            func3_sm_latched;
assign  a_sign_en = (func3_sm_latched == 2'b00) || (func3_sm_latched == 2'b01) || (func3_sm_latched == 2'b10);
assign  b_sign_en = (func3_sm_latched == 2'b00) || (func3_sm_latched == 2'b01);

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        a_reg <= #1 'h0;
        b_reg <= #1 'h0;
        func3_sm_latched <= #1 '0;
    end else if(ready) begin
        a_reg <= #1 'h0;
        b_reg <= #1 'h0;
    end else if (start) begin
        a_reg <= #1 a_i;
        b_reg <= #1 b_i;
        func3_sm_latched <= #1 func3_mode_i;
    end
end

assign data_valid = (state == DONE);
assign ready      = (state == IDLE && ~start) || (state == DONE);

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(int i=0; i<PP_NUM; i++) pp_reg[i] <= #1 'h0;
    end else if(start) begin
        for(int i=0; i<PP_NUM; i++) pp_reg[i] <= #1 pp[i];
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cpr_res0_reg <= #1 '0;
        cpr_res1_reg <= #1 '0;
        fix_temp_reg <= #1 '0;
    end else if(state == COMPRESS) begin
        cpr_res0_reg <= #1 cpr_res0;
        cpr_res1_reg <= #1 cpr_res1;
        fix_temp_reg <= #1 ((!a_sign_en && a_reg[DATA_WIDTH-1]) ? b_reg : '0)
                           + ((!b_sign_en && b_reg[DATA_WIDTH-1]) ? a_reg : '0);
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        mul_o_comb_reg <= #1 '0;
        prod_high_reg  <= #1 '0;
    end else if(state == CLA_CALC) begin
        mul_o_comb_reg <= #1 mul_o_comb;
        prod_high_reg  <= #1 fix_temp_reg + mul_o_comb[PROD_WIDTH-1:DATA_WIDTH];
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state <= #1 IDLE;
    end else begin
        case(state)
            IDLE:     if(start) state <= #1 COMPRESS;
            COMPRESS:           state <= #1 CLA_CALC;
            CLA_CALC:           state <= #1 DONE;
            DONE:               state <= #1 IDLE;
        endcase
    end
end

assign prod_full = {prod_high_reg, mul_o_comb_reg[DATA_WIDTH-1:0]};
assign mul_o = (state == DONE) ? prod_full : {PROD_WIDTH{1'b0}};
assign func3_mode_o = (state == DONE) ? func3_sm_latched : '0;

end
endgenerate

//==========================================================================
// 公共组合逻辑（两版本共享）
//==========================================================================
// Booth4编码 + 部分积生成
generate
    genvar k;
    for(k = 0; k < PP_NUM; k++) begin : booth4_inst_gen
        if(k == 0) begin
            booth4code #(.DATA_WIDTH (DATA_WIDTH))u_booth4code (
                .a_i      (a_i),
                .b_i      ({b_i[1:0], 1'b0}),
                .booth_o  (booth_o[k])
            );
        end else begin
            booth4code #(.DATA_WIDTH (DATA_WIDTH))u_booth4code (
                .a_i      (a_i),
                .b_i      (b_i[2*k+1 : 2*k-1]),
                .booth_o  (booth_o[k])
            );
        end
    end
endgenerate

generate
    genvar m;
    for(m = 0; m < PP_NUM; m++) begin : pp_gen
        localparam EXT_BIT = (PROD_WIDTH + 1) - (DATA_WIDTH + 2)- 2*m;
        assign pp[m] = {{EXT_BIT{booth_o[m][DATA_WIDTH+1]}}, booth_o[m], {2*m{1'b0}}};
    end
endgenerate

// 华莱士树压缩
generate
    genvar level, idx;
    for(level = 0; level < MAX_LEVEL; level++) begin : cpr_level_gen
        localparam COMPRESSOR_NUM = PP_NUM >> (level+1);
        logic [PROD_WIDTH+1:0] cpr_pipe_out [0:COMPRESSOR_NUM*2-1];
        for(idx = 0; idx < COMPRESSOR_NUM; idx++) begin : cpr_inst_gen
            localparam in_base_idx = idx * 4;
            logic cpr_cout [0:COMPRESSOR_NUM-1];
            if (level == 0) begin
            compressor42 #(.DATA_WIDTH (DATA_WIDTH))u_compressor42(
                .in1    (pp_reg[in_base_idx  ]),
                .in2    (pp_reg[in_base_idx+1]),
                .in3    (pp_reg[in_base_idx+2]),
                .in4    (pp_reg[in_base_idx+3]),
                .cin    (1'b0),
                .out1   (cpr_level_gen[level].cpr_pipe_out[idx*2]),
                .out2   (cpr_level_gen[level].cpr_pipe_out[idx*2+1]),
                .cout   (cpr_cout[idx])
            );
            end else begin
                compressor42 #(.DATA_WIDTH (DATA_WIDTH))u_compressor42(
                    .in1    (cpr_level_gen[level-1].cpr_pipe_out[in_base_idx  ][PROD_WIDTH:0]<<1),
                    .in2    (cpr_level_gen[level-1].cpr_pipe_out[in_base_idx+1][PROD_WIDTH:0]),
                    .in3    (cpr_level_gen[level-1].cpr_pipe_out[in_base_idx+2][PROD_WIDTH:0]<<1),
                    .in4    (cpr_level_gen[level-1].cpr_pipe_out[in_base_idx+3][PROD_WIDTH:0]),
                    .cin    (1'b0),
                    .out1   (cpr_level_gen[level].cpr_pipe_out[idx*2]),
                    .out2   (cpr_level_gen[level].cpr_pipe_out[idx*2+1]),
                    .cout   (cpr_cout[idx])
                );
            end
        end
    end
endgenerate

assign cpr_res0 = cpr_level_gen[MAX_LEVEL-1].cpr_pipe_out[0];
assign cpr_res1 = cpr_level_gen[MAX_LEVEL-1].cpr_pipe_out[1];

// CLA 加法器
cla #(.PRODUCT_WIDTH (PROD_WIDTH))u_cla (
    .op1    (cpr_res0_reg[PROD_WIDTH-1:0] << 1),
    .op2    (cpr_res1_reg[PROD_WIDTH-1:0]),
    .sum    (mul_o_comb),
    .cout   (cout_comb)
);

endmodule
