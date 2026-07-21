`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
module Data_Hazard_Forward #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    input   logic                           clk,
    input   logic                           access_en_id,
    input   logic                           access_wr_id,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rs1_raddr_id,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rs2_raddr_id,
    input   logic                           access_en_ex,
    input   logic                           access_wr_ex,
    input   logic                           reg_rd_wen_ex,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rs1_raddr_ex,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rs2_raddr_ex,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rd_waddr_ex,
    input   logic                           access_en_mem,
    input   logic                           access_wr_mem,
    input   logic                           reg_rd_wen_mem,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rd_waddr_mem,
    input   logic                           reg_rd_wen_wb,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rd_waddr_wb,
    // OITF 退休前递源
    input   logic                           lp_retire_valid,
    input   logic   [REG_ADDR_WIDTH-1:0]    lp_retire_waddr,
    input   logic   [DATA_WIDTH-1:0]        lp_retire_wdata,
    input   logic   [DATA_WIDTH-1:0]        alu_op1_from_id_ex,
    input   logic   [DATA_WIDTH-1:0]        alu_op2_from_id_ex,
    input   logic   [DATA_WIDTH-1:0]        reg_rs2_rdata_ex,
    input   logic   [DATA_WIDTH-1:0]        reg_rd_wdata_mem,
    input   logic   [DATA_WIDTH-1:0]        reg_rd_wdata_wb,
    input   logic                           bus_sel,

    input   logic                           bus_ready,
    // Load-Use冒险标志(停顿给pc_hold，if_id_hold，id_ex_clear)
    output  logic                           load_use_flag,
    (* MAX_FANOUT = 16 *)output  logic   [DATA_WIDTH-1:0]        alu_op1_o,
    output  logic   [DATA_WIDTH-1:0]        alu_op2_o,
    output  logic   [DATA_WIDTH-1:0]        access_wdata_temp,
    // 前递命中标志：当前有前递源正在驱动 alu_op1_o / alu_op2_o。
    // 供 ID_EX 在停顿期间锁存前递值，避免 OITF 退休的 1 拍前递脉冲丢失。
    output  logic                           fwd_a_hit,
    output  logic                           fwd_b_hit
);

// ===================================== 第一步：ALU操作数前递逻辑（forwardA/forwardB） =====================================
// 前递优先级：MEM阶段（MEM->EX） > WB阶段（WB->EX） > OITF退休 > 寄存器堆（默认）
// forwardA_o/forwardB_o 编码定义：
// 3'b000：不前递，使用寄存器堆原始数据
// 3'b001：从OITF退休前递
// 3'b010：从WB阶段前递
// 3'b011：从MEM阶段前递（MEM/WB寄存器的写数据）
// 3'b100：从EX阶段前递（EX/MEM寄存器的写数据）

logic   access_wen_id;
logic   access_ren_ex;
logic   access_wen_ex;
logic   access_ren_mem;

// ALU操作数1前递选择（EX阶段使用）
logic   [2:0]                   forward_A;
// ALU操作数2前递选择（EX阶段使用）
logic   [2:0]                   forward_B;
// Store指令rs2数据前递选择（EX阶段使用，解决Load->Store无停顿）
`ifdef FORWARD_C_EN
logic                           forward_C;
`endif

assign access_wen_id = access_en_id & access_wr_id;
assign access_ren_ex = access_en_ex & ~access_wr_ex;
assign access_wen_ex = access_en_ex & access_wr_ex;
assign access_ren_mem = access_en_mem & ~access_wr_mem;

// ALU操作数1（rs1）的前递选择
// 优先级：MEM > WB > OITF_retire（新指令值覆盖旧值）
assign forward_A[0] = lp_retire_valid && (lp_retire_waddr == reg_rs1_raddr_ex) && (reg_rs1_raddr_ex != 0);
assign forward_A[1] = reg_rd_wen_wb && (reg_rd_waddr_wb == reg_rs1_raddr_ex) && (reg_rs1_raddr_ex != 0);
assign forward_A[2] = reg_rd_wen_mem && (reg_rd_waddr_mem == reg_rs1_raddr_ex) && (reg_rs1_raddr_ex != 0);

// ALU操作数2（rs2）的前递选择
assign forward_B[0] = lp_retire_valid && (lp_retire_waddr == reg_rs2_raddr_ex) && (reg_rs2_raddr_ex != 0);
assign forward_B[1] = reg_rd_wen_wb && (reg_rd_waddr_wb == reg_rs2_raddr_ex) && (reg_rs2_raddr_ex != 0);
assign forward_B[2] = reg_rd_wen_mem && (reg_rd_waddr_mem == reg_rs2_raddr_ex) && (reg_rs2_raddr_ex != 0);

// 前递命中：任一前递源有效。供 ID_EX 在停顿期间锁存前递值。
assign fwd_a_hit = |forward_A;
assign fwd_b_hit = |forward_B;


// ===================================== 第二步：Load-Use冒险逻辑（load_use_flag_o） =====================================
//如果是load后跟着store指令，并且load指令的rd与store指令的rs2相同，rs1不同，则不需要停顿，只需要将MEM/WB寄存器的数据前递到MEM阶段。
//rs2是数据，前递能补，rs1是地址，不能补。


`ifdef FORWARD_C_EN
// load-store前递（解决Load->Store无停顿）
assign forward_C = (reg_rd_wen_mem && (reg_rd_waddr_mem == reg_rs2_raddr_ex) && (reg_rd_waddr_mem != reg_rs1_raddr_ex)
&& (reg_rs2_raddr_ex != 0) && access_ren_mem && access_wen_ex);

assign load_use_flag = (access_ren_ex && (reg_rd_waddr_ex != 'h0) &&//load
((access_wen_id &&//store
(reg_rd_waddr_ex == reg_rs1_raddr_id)) ||
((!access_wen_id &&//非store
(reg_rd_waddr_ex == reg_rs2_raddr_id)) || (reg_rd_waddr_ex == reg_rs1_raddr_id))))
&& ~bus_sel;
`else
assign load_use_flag = (access_ren_ex && (reg_rd_waddr_ex != 'h0) &&//load
((reg_rd_waddr_ex == reg_rs2_raddr_id) || (reg_rd_waddr_ex == reg_rs1_raddr_id)))
&& ~bus_sel;
`endif

logic   [DATA_WIDTH-1:0]        access_wdata;
// 前递优先级（修正）：OITF退休 > MEM阶段 > WB阶段 > 寄存器堆（默认）
// 关键修正点：OITF退休前递必须拥有最高优先级。
// 依赖指令因 OITF RAW 停顿、直到被依赖的长指令（MUL/DIV）经 OITF 退休拍释放；
// 该拍依赖指令要的正是 OITF 退休写回值（程序序上最新的相关写）。
// 原 case 写法在 OITF 与 WB/MEM 同时命中同一 rs 时错误地选了 WB/MEM（旧值），
// 导致 mul->依赖 这类链前递失效（coremark CRC 全错、listprobe 数组初始化错）。
always_comb begin
    if      (forward_A[0]) alu_op1_o = lp_retire_wdata;     // OITF退休（最高）
    else if (forward_A[2]) alu_op1_o = reg_rd_wdata_mem;    // MEM
    else if (forward_A[1]) alu_op1_o = reg_rd_wdata_wb;     // WB
    else                   alu_op1_o = alu_op1_from_id_ex;   // 寄存器堆
end

always_comb begin
    if      (forward_B[0]) alu_op2_o = lp_retire_wdata;
    else if (forward_B[2]) alu_op2_o = reg_rd_wdata_mem;
    else if (forward_B[1]) alu_op2_o = reg_rd_wdata_wb;
    else                   alu_op2_o = alu_op2_from_id_ex;
end

always_comb begin
    if      (forward_B[0]) access_wdata = lp_retire_wdata;
    else if (forward_B[2]) access_wdata = reg_rd_wdata_mem;
    else if (forward_B[1]) access_wdata = reg_rd_wdata_wb;
    else                   access_wdata = reg_rs2_rdata_ex;
end

`ifdef FORWARD_C_EN
assign  access_wdata_temp = forward_C ? reg_rd_wdata_mem : access_wdata;
`else
assign  access_wdata_temp = access_wdata;
`endif

endmodule
