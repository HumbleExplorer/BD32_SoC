`include "../SoC_Config.sv"
`timescale 1ns / 1ps
module PC_counter #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_WIDTH =`ALIGN_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
)( 
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic                       jump_en,
    input   logic   [ADDR_WIDTH-1:0]    jump_addr,
    input   logic                       predict_taken,
    input   logic   [DATA_WIDTH-1:0]    predict_target,
    input   logic                       stall,
    output  logic   [ADDR_WIDTH-1:0]    pc,//下一条指令地址（给ROM，因为有一周期的读延迟）
    output  logic   [DATA_WIDTH-2:0]    exception_code,
    output  logic   [DATA_WIDTH-1:0]    exception_val
    // output  logic   [ADDR_WIDTH-1:0]    inst_addr_o//当前指令地址（给流水线，即当前取出的指令对应的地址）
);

logic [ADDR_WIDTH-1:0] pc_next;

assign exception_code = (pc[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH]==`BOOT_BASE_ADDR || pc[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH]==`ITCM_BASE_ADDR) ? //指令访问错误，即越界
(pc[ALIGN_WIDTH-1:0] == 0 ? {DATA_WIDTH-1{1'b1}} : 'd0) : 'd1;//指令地址未对齐
assign exception_val = pc_next;

always_comb begin
    pc_next = pc + 4;
    if (jump_en)
        pc_next = {jump_addr[ADDR_WIDTH-1:ALIGN_WIDTH], {ALIGN_WIDTH{1'b0}}};
    else if (stall)
        pc_next = pc;
    else if (predict_taken)
        pc_next = {predict_target[ADDR_WIDTH-1:ALIGN_WIDTH], {ALIGN_WIDTH{1'b0}}};
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        pc <= {`BOOT_BASE_ADDR,{BLOCK_SIZE_WIDTH{1'b0}}};
    else
        pc <= #1 pc_next;
end

// DelayUnit #(
//     .DATA_WIDTH (ADDR_WIDTH)
// )
// u_DelayUnit(
//     .clk       	(clk        ),
//     .rst_n     	(rst_n      ),
//     .enable    	(stall      ),
//     .data_in   	(pc         ),
//     .delay_out 	(inst_addr_o)
// );


endmodule
