`include "./../../SoC_Config.sv"
`include "../../RV32_Inst_Define.sv"
`timescale 1ns / 1ps
module mul_div #(
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH
)(
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic                       enable,
    input   logic [REG_ADDR_WIDTH-1:0]  rd_rs1_addr,
    input   logic [REG_ADDR_WIDTH-1:0]  rd_rs2_addr,
    input   logic [REG_ADDR_WIDTH-1:0]  wr_rd_addr,
    input   logic [2:0]                 func3_i,
    input   logic [DATA_WIDTH-1:0]      a_i,    // 乘数A (来自forward)
    input   logic [DATA_WIDTH-1:0]      b_i,    // 乘数B (来自forward)
    output  logic [DATA_WIDTH-1:0]      result_o,  // 乘积结果(组合输出，送EX_MEM寄存器锁存)
    output  logic                       data_valid,
    output  logic                       ready   // 就绪信号:高表示运算完成，下一周期可输入新数据
);

logic                           mul_en;
logic                           div_en;
logic                           mul_ready;
logic                           div_ready;
logic                           mul_valid;
logic                           div_valid;
logic   [1:0]                   func3_mode_i;
logic   [DATA_WIDTH*2-1:0]      mul_o;
logic   [DATA_WIDTH*2-1:0]      quot_rem_o;
logic   [REG_ADDR_WIDTH-1:0]    rd_rs1_addr_reg;    // 锁存上一次运算的操作数a_i
logic   [REG_ADDR_WIDTH-1:0]    rd_rs2_addr_reg;    // 锁存上一次运算的操作数b_i
logic   [DATA_WIDTH*2-1:0]      full_result_reg;    // 锁存上一次运算的完整64位结果
logic   [2:0]                   op_func3_reg;       // 锁存上一次运算的func3_i指令编码
(* MAX_FANOUT = 16 *)logic                           fuse_hit;    // 融合命中标志：1=命中融合指令，0=正常独立运算
logic   [DATA_WIDTH*2-1:0]      full_result_sel;// 选择后的64位源结果（融合/独立运算）

assign mul_en = (!func3_i[2] && enable) && ~fuse_hit;// 融合命中时关闭乘法使能
assign div_en = (func3_i[2]  && enable) && ~fuse_hit;// 融合命中时关闭除法使能
assign func3_mode_i = func3_i[1:0];
assign data_valid   = mul_valid || div_valid;
assign ready        = data_valid || ~enable;
//==========================================================================
// 3. 融合运算核心：锁存寄存器 + 融合检测信号【少量寄存器，无额外运算开销】
//==========================================================================

// 融合检测核心逻辑
// 规则：使能+源寄存器地址相同+读写寄存器不同+是融合指令对(MULHx+MUL / DIVx+REMx)
assign fuse_hit = enable && (rd_rs1_addr == rd_rs1_addr_reg) && (rd_rs2_addr == rd_rs2_addr_reg)
                    && (rd_rs1_addr != wr_rd_addr) && (rd_rs2_addr != wr_rd_addr) // 读和写的不能是一个寄存器
                    && (((op_func3_reg == `INST_MULH  && func3_i == `INST_MUL)
                    ||   (op_func3_reg == `INST_MULHU && func3_i == `INST_MUL)
                    ||   (op_func3_reg == `INST_MULHSU&& func3_i == `INST_MUL)) // 乘法融合对
                    ||  ((op_func3_reg == `INST_DIV   && func3_i == `INST_REM)
                    ||   (op_func3_reg == `INST_DIVU  && func3_i == `INST_REMU))  // 除法融合对
                    );

//==========================================================================
// 5. 融合结果锁存时序逻辑【异步复位，仅在运算完成时锁存，无冗余】
//==========================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rd_rs1_addr_reg <= #1 '0;
        rd_rs2_addr_reg <= #1 '0;
        full_result_reg <= #1 '0;
        op_func3_reg    <= #1 '0;
    end else if(data_valid && !fuse_hit) begin
        // 仅在【独立运算完成】时，锁存操作数+完整结果+指令类型
        rd_rs1_addr_reg <= #1 rd_rs1_addr;
        rd_rs2_addr_reg <= #1 rd_rs2_addr;
        op_func3_reg    <= #1 func3_i;
        full_result_reg <= #1 func3_i[2] ? quot_rem_o : mul_o; // bit2=1:除法结果，0:乘法结果
    end
end

multiplier #(
    .DATA_WIDTH 	(DATA_WIDTH)
)u_multiplier(
    .clk          	(clk           ),
    .rst_n        	(rst_n         ),
    .enable       	(mul_en        ),
    .func3_mode_i 	(func3_mode_i  ),
    .a_i          	(a_i           ),
    .b_i          	(b_i           ),
    .mul_o        	(mul_o         ),
    .data_valid   	(mul_valid     ),
    .ready        	(mul_ready     )
);

divider #(
    .DATA_WIDTH 	(DATA_WIDTH)
)u_divider(
    .clk          	(clk           ),
    .rst_n        	(rst_n         ),
    .enable       	(div_en        ),
    .func3_mode_i 	(func3_mode_i  ),
    .dividend     	(a_i           ),
    .divisor      	(b_i           ),
    .quot_rem_o   	(quot_rem_o    ),
    .data_valid   	(div_valid     ),
    .ready        	(div_ready     )
);

//==========================================================================
// 第一步：64位源结果选择 → 融合结果 或 独立运算结果
//==========================================================================
assign full_result_sel = fuse_hit ? full_result_reg : (func3_i[2] ? quot_rem_o : mul_o);

//==========================================================================
// 第二步：核心32位结果截取逻辑
// 乘法类：MUL→低32位，MULH/MULHU/MULHSU→高32位
// 除法类：DIV/DIVU→低32位(商)，REM/REMU→高32位(余数)
//==========================================================================
always_comb begin
    case(func3_i)
        `INST_MUL:     result_o = full_result_sel[DATA_WIDTH-1:0];      // MUL  - 乘积低32位
        `INST_MULH:    result_o = full_result_sel[2*DATA_WIDTH-1:DATA_WIDTH];//MULH-乘积高32位
        `INST_MULHU:   result_o = full_result_sel[2*DATA_WIDTH-1:DATA_WIDTH];//MULHU-乘积高32位
        `INST_MULHSU:  result_o = full_result_sel[2*DATA_WIDTH-1:DATA_WIDTH];//MULHSU-乘积高32位
        `INST_DIV:     result_o = full_result_sel[DATA_WIDTH-1:0];      // DIV  - 商(低32位)
        `INST_DIVU:    result_o = full_result_sel[DATA_WIDTH-1:0];      // DIVU - 商(低32位)
        `INST_REM:     result_o = full_result_sel[2*DATA_WIDTH-1:DATA_WIDTH];//REM  - 余数(高32位)
        `INST_REMU:    result_o = full_result_sel[2*DATA_WIDTH-1:DATA_WIDTH];//REMU - 余数(高32位)
        default:       result_o = '0;
    endcase
end

endmodule