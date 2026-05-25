`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
module Data_Hazard_Forward #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    input   logic                           clk,
    input   logic                           access_en_id,
    input   logic                           access_wr_id,
    input   logic   [REG_ADDR_WIDTH-1:0]    rd_rs1_addr_id,
    input   logic   [REG_ADDR_WIDTH-1:0]    rd_rs2_addr_id,
    input   logic                           access_en_ex,
    input   logic                           access_wr_ex,
    input   logic                           wr_reg_en_ex,
    input   logic   [REG_ADDR_WIDTH-1:0]    rd_rs1_addr_ex,
    input   logic   [REG_ADDR_WIDTH-1:0]    rd_rs2_addr_ex,
    input   logic   [REG_ADDR_WIDTH-1:0]    wr_reg_addr_ex,
    input   logic                           access_en_mem,
    input   logic                           access_wr_mem,
    input   logic                           wr_reg_en_mem,
    input   logic   [REG_ADDR_WIDTH-1:0]    wr_reg_addr_mem,
    input   logic                           wr_reg_en_wb,
    input   logic   [REG_ADDR_WIDTH-1:0]    wr_reg_addr_wb,
    input   logic   [DATA_WIDTH-1:0]        alu_op1_from_id_ex,
    input   logic   [DATA_WIDTH-1:0]        alu_op2_from_id_ex,
    input   logic   [DATA_WIDTH-1:0]        rd_rs2_data_ex,
    input   logic   [DATA_WIDTH-1:0]        wr_reg_data_mem,
    input   logic   [DATA_WIDTH-1:0]        wr_reg_data_wb,
    input   logic                           bus_sel,
    input   logic                           bus_rvalid_r1,
    input   logic                           bus_access_ready,
    // Load-Use冒险标志(停顿给pc_hold，if_id_hold，id_ex_clear)
    output  logic                           load_use_flag,
    (* MAX_FANOUT = 16 *)output  logic   [DATA_WIDTH-1:0]        alu_op1_o,
    output  logic   [DATA_WIDTH-1:0]        alu_op2_o,
    output  logic   [DATA_WIDTH-1:0]        wr_mem_data_temp
);

// ===================================== 第一步：ALU操作数前递逻辑（forwardA/forwardB） =====================================
// 前递优先级：EX阶段（EX->EX） > MEM阶段（MEM->EX） > 寄存器堆（默认）
// forwardA_o/forwardB_o 编码定义：
// 2'b00：不前递，使用寄存器堆原始数据
// 2'b01：从MEM阶段前递（MEM/WB寄存器的写数据）
// 2'b10：从EX阶段前递（EX/MEM寄存器的写数据）

logic   wr_mem_en_id;
logic   rd_mem_en_ex;
logic   wr_mem_en_ex;
logic   rd_mem_en_mem;

// ALU操作数1前递选择（EX阶段使用）
logic   [1:0]                   forward_A;
// ALU操作数2前递选择（EX阶段使用）
logic   [1:0]                   forward_B;
// Store指令rs2数据前递选择（EX阶段使用，解决Load->Store无停顿）
`ifdef FORWARD_C_EN
logic                           forward_C;
`endif

assign wr_mem_en_id = access_en_id & access_wr_id;
assign rd_mem_en_ex = access_en_ex & ~access_wr_ex;
assign wr_mem_en_ex = access_en_ex & access_wr_ex;
assign rd_mem_en_mem = access_en_mem & ~access_wr_mem;

// ALU操作数1（rs1）的前递选择
assign forward_A[0] = wr_reg_en_wb && (wr_reg_addr_wb == rd_rs1_addr_ex) && (rd_rs1_addr_ex != 0);
assign forward_A[1] = wr_reg_en_mem && (wr_reg_addr_mem == rd_rs1_addr_ex) && (rd_rs1_addr_ex != 0);

// ALU操作数2（rs2）的前递选择
assign forward_B[0] = wr_reg_en_wb && (wr_reg_addr_wb == rd_rs2_addr_ex) && (rd_rs2_addr_ex != 0);
assign forward_B[1] = wr_reg_en_mem && (wr_reg_addr_mem == rd_rs2_addr_ex) && (rd_rs2_addr_ex != 0);


// ===================================== 第二步：Load-Use冒险逻辑（load_use_flag_o） =====================================
//如果是load后跟着store指令，并且load指令的rd与store指令的rs2相同，rs1不同，则不需要停顿，只需要将MEM/WB寄存器的数据前递到MEM阶段。
//rs2是数据，前递能补，rs1是地址，不能补。


`ifdef FORWARD_C_EN
// load-store前递（解决Load->Store无停顿）
assign forward_C = (wr_reg_en_mem && (wr_reg_addr_mem == rd_rs2_addr_ex) && (wr_reg_addr_mem != rd_rs1_addr_ex)
&& (rd_rs2_addr_ex != 0) && rd_mem_en_mem && wr_mem_en_ex);

assign load_use_flag = (rd_mem_en_ex && (wr_reg_addr_ex != 'h0) &&//load
((wr_mem_en_id &&//store
(wr_reg_addr_ex == rd_rs1_addr_id)) ||
((!wr_mem_en_id &&//非store
(wr_reg_addr_ex == rd_rs2_addr_id)) || (wr_reg_addr_ex == rd_rs1_addr_id))))
&& ~bus_sel;
`else
assign load_use_flag = (rd_mem_en_ex && (wr_reg_addr_ex != 'h0) &&//load
((wr_reg_addr_ex == rd_rs2_addr_id) || (wr_reg_addr_ex == rd_rs1_addr_id)))
&& ~bus_sel;
`endif

logic   [DATA_WIDTH-1:0]        wr_mem_data;
always_comb begin
    case(forward_A)
        2'b00: alu_op1_o = alu_op1_from_id_ex;
        2'b01: alu_op1_o = wr_reg_data_wb;
        2'b10: alu_op1_o = wr_reg_data_mem;
        2'b11: alu_op1_o = bus_rvalid_r1 ? wr_reg_data_wb : wr_reg_data_mem;  // bus_rvalid=bus_rvalid延迟1拍，此时WB已有数据
        default: alu_op1_o = alu_op1_from_id_ex;
    endcase
end

always_comb begin
    case(forward_B)
        2'b00: alu_op2_o = alu_op2_from_id_ex;
        2'b01: alu_op2_o = wr_reg_data_wb;
        2'b10: alu_op2_o = wr_reg_data_mem;
        2'b11: alu_op2_o = bus_rvalid_r1 ? wr_reg_data_wb : wr_reg_data_mem;
        default: alu_op2_o = alu_op2_from_id_ex;
    endcase
end

always_comb begin
    case(forward_B)
        2'b00: wr_mem_data = rd_rs2_data_ex;
        2'b01: wr_mem_data = wr_reg_data_wb;
        2'b10: wr_mem_data = wr_reg_data_mem;
        2'b11: wr_mem_data = bus_rvalid_r1 ? wr_reg_data_wb : wr_reg_data_mem;
        default: wr_mem_data = rd_rs2_data_ex;
    endcase
end

`ifdef FORWARD_C_EN
assign  wr_mem_data_temp = forward_C ? wr_reg_data_mem : wr_mem_data;
`else
assign  wr_mem_data_temp = wr_mem_data;
`endif

endmodule