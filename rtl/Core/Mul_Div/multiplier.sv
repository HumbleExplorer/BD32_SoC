
`timescale 1ns / 1ps
module multiplier #(
    parameter DATA_WIDTH = 32,  // 位宽16/32/64通用，与除法器一致
    localparam PP_NUM     = DATA_WIDTH / 2,    // 部分积数量 = 位宽/2
    localparam PROD_WIDTH = DATA_WIDTH * 2,    // 乘积位宽 = 2*乘数位宽
    localparam MAX_LEVEL  = $clog2(DATA_WIDTH/4) // 最大压缩层级
)(
    input   logic                    clk,
    input   logic                    rst_n,          // 异步复位，低有效
    input   logic                    enable,         // 运算使能：高有效
    input   logic [1:0]              func3_mode_i,   // 4种运算模式选择. 00:mul，01:mulh，10:mulhsu，11:mulhu
    input   logic [DATA_WIDTH-1:0]   a_i,            // 乘数A
    input   logic [DATA_WIDTH-1:0]   b_i,            // 乘数B
    output  logic [DATA_WIDTH*2-1:0] mul_o,          // 乘积结果:运算完成输出，其余周期0
    output  logic                    data_valid,     // 运算结果有效信号:高有效
    output  logic                    ready           // 就绪信号:空闲高、运算中低、结果周期高
);

//==========================================================================
// 状态机定义 
//==========================================================================
localparam IDLE      = 2'b00;
localparam COMPRESS  = 2'b01;
localparam CLA_CALC  = 2'b10;
localparam DONE      = 2'b11;
logic [1:0] state;

//==========================================================================
// 信号定义：完全保留原乘法器所有核心运算信号，无删减、无修改
// 第一级组合逻辑：Booth4编码 + 部分积生成
// 第二级组合逻辑：华莱士树42压缩器
// 第三级组合逻辑：CLA超前进位加法器
//==========================================================================
logic [DATA_WIDTH+1:0]  booth_o   [PP_NUM-1:0];
logic [PROD_WIDTH:0]    pp        [PP_NUM-1:0];
logic [PROD_WIDTH:0]    pp_reg    [0:PP_NUM-1]; // 周期1锁存：部分积存寄存器

logic [PROD_WIDTH+1:0]  cpr_res0, cpr_res1;
logic [PROD_WIDTH+1:0]  cpr_res0_reg, cpr_res1_reg;       // 周期2锁存：压缩结果存寄存器

logic [PROD_WIDTH-1:0]  mul_o_comb;
logic                   cout_comb;
logic [DATA_WIDTH-1:0]  fix_temp_reg;
logic [PROD_WIDTH-1:0]  prod_full;

logic   a_sign_en;  // a_i的符号使能：1=有符号(补符号位)，0=无符号(补0)
logic   b_sign_en;  // b_i的符号使能：1=有符号(补符号位)，0=无符号(补0)
logic   [DATA_WIDTH-1:0] a_reg;
logic   [DATA_WIDTH-1:0] b_reg;
logic   start;
assign  a_sign_en = (func3_mode_i == 2'b00) || (func3_mode_i == 2'b01) || (func3_mode_i == 2'b10);
assign  b_sign_en = (func3_mode_i == 2'b00) || (func3_mode_i == 2'b01);

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        a_reg <= #1 'h0;
        b_reg <= #1 'h0;
    end else if(ready) begin
        a_reg <= #1 'h0;
        b_reg <= #1 'h0;
    end else if (start) begin
        a_reg <= #1 a_i;
        b_reg <= #1 b_i;
    end
end
//==========================================================================
// 启动信号+就绪信号 
//==========================================================================
assign data_valid = (state == DONE);
assign ready      = (state == IDLE && ~enable) || (state == DONE); // 核心要求：空闲高、运算中低、结果周期高
assign start = (state == IDLE && enable);

//==========================================================================
// 周期1：组合逻辑 : Booth4编码 + 部分积生成 
//==========================================================================
generate
    genvar k;
    for(k = 0; k < PP_NUM; k++) begin : booth4_inst_gen
        if(k == 0) begin
            booth4code #(
                .DATA_WIDTH (DATA_WIDTH)
            )u_booth4code (
                .a_i      (a_i),
                .b_i      ({b_i[1:0], 1'b0}),
                .booth_o  (booth_o[k])
            );
        end else begin
            booth4code #(
                .DATA_WIDTH (DATA_WIDTH)
            )u_booth4code (
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

// 寄存器1：周期1锁存部分积 (时钟上升沿) 
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(int i=0; i<PP_NUM; i++) pp_reg[i] <= #1 'h0;
    end else if(start) begin // 运算态下正常锁存，与原逻辑一致
        for(int i=0; i<PP_NUM; i++) pp_reg[i] <= #1 pp[i];
    end
end

//==========================================================================
// 周期2：组合逻辑 : 通用化自适应华莱士树42压缩器 
//==========================================================================
generate
    genvar level, idx;
    for(level = 0; level < MAX_LEVEL; level++) begin : cpr_level_gen
        localparam COMPRESSOR_NUM = PP_NUM >> (level+1);
        logic [PROD_WIDTH+1:0] cpr_pipe_out [0:COMPRESSOR_NUM*2-1];
        for(idx = 0; idx < COMPRESSOR_NUM; idx++) begin : cpr_inst_gen
            localparam in_base_idx = idx * 4;
            logic cpr_cout [0:COMPRESSOR_NUM-1];
            if (level == 0) begin
            compressor42 #(
                .DATA_WIDTH (DATA_WIDTH)
            )u_compressor42(
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
                compressor42 #(
                    .DATA_WIDTH (DATA_WIDTH)
                )u_compressor42(
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

// 压缩器最终输出2路待加数据
assign cpr_res0 = cpr_level_gen[MAX_LEVEL-1].cpr_pipe_out[0];
assign cpr_res1 = cpr_level_gen[MAX_LEVEL-1].cpr_pipe_out[1];

// 寄存器2：周期2锁存压缩结果 (时钟上升沿) 
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cpr_res0_reg <= #1 '0;
        cpr_res1_reg <= #1 '0;
        fix_temp_reg <= #1 '0;
    end else if(state == COMPRESS) begin // 运算态下正常锁存，与原逻辑一致
        cpr_res0_reg <= #1 cpr_res0;
        cpr_res1_reg <= #1 cpr_res1;
        fix_temp_reg <= #1 ((!a_sign_en && a_reg[DATA_WIDTH-1]) ? b_reg : '0)+((!b_sign_en && b_reg[DATA_WIDTH-1]) ? a_reg : '0);
    end
end

//==========================================================================
// 周期3：组合逻辑 → CLA加法器 
//==========================================================================
cla #(
    .PRODUCT_WIDTH (PROD_WIDTH)
)u_cla (
    .op1    (cpr_res0_reg[PROD_WIDTH-1:0] << 1),
    .op2    (cpr_res1_reg[PROD_WIDTH-1:0]),
    .sum    (mul_o_comb),
    .cout   (cout_comb)
);
//==========================================================================
// 核心：状态机时序逻辑 
//==========================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state     <= #1 IDLE;
    end else begin
        case(state)
            // -------------------------- 空闲态 IDLE --------------------------
            IDLE: begin
                if(enable) begin // 使能+空闲=启动运算
                    state <= #1 COMPRESS; // 正常场景：进入运算态
                end
            end
            COMPRESS: begin
                state <= #1 CLA_CALC;
            end
            // -------------------------- 运算态 CALCULATE --------------------------
            CLA_CALC: begin
                state    <= #1 DONE;
            end
            // -------------------------- 结束态 DONE --------------------------
            DONE: begin
                // 结果输出完成后，自动回到空闲态，等待下一次运算触发
                state <= #1 IDLE;
            end
        endcase
    end
end

//==========================================================================
// 运算完成(DONE态)输出结果，其余周期输出0；组合逻辑输出，送后级寄存器锁存
//==========================================================================
assign prod_full = {fix_temp_reg + mul_o_comb[PROD_WIDTH-1:DATA_WIDTH], mul_o_comb[DATA_WIDTH-1:0]};
assign mul_o = (state == DONE) ? prod_full : {PROD_WIDTH{1'b0}};

endmodule