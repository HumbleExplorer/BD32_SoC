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
    output  logic   [ADDR_WIDTH-1:0]    pc,          // 下一条指令地址（给 ROM/RAM，提前一拍送地址）
    output  logic   [DATA_WIDTH-2:0]    exception_code,
    output  logic   [DATA_WIDTH-1:0]    exception_val,
    output  logic   [ADDR_WIDTH-1:0]    inst_addr_o  // 当前指令地址（给流水线，= 上一拍 pc）
);

logic [ADDR_WIDTH-1:0] inst_addr;

// 异常检查基于 inst_addr（已寄存器化的当前取指地址），避免与 pc 形成组合回路
assign exception_code = (inst_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH]==`BOOT_BASE_ADDR || inst_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH]==`ITCM_BASE_ADDR) ?
    (inst_addr[ALIGN_WIDTH-1:0] == 0 ? {DATA_WIDTH-1{1'b1}} : 'd0) : 'd1;//指令地址未对齐
assign exception_val = inst_addr;

always_comb begin
    pc = inst_addr + 4;
    if (jump_en)
        pc = {jump_addr[ADDR_WIDTH-1:ALIGN_WIDTH], {ALIGN_WIDTH{1'b0}}};
    else if (stall)
        pc = inst_addr;
    else if (predict_taken)
        pc = {predict_target[ADDR_WIDTH-1:ALIGN_WIDTH], {ALIGN_WIDTH{1'b0}}};
end

// inst_addr 寄存器：下一条要取的指令地址，给 BootROM/ITCM 的读地址端口
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        inst_addr <= #1 {`BOOT_BASE_ADDR,{BLOCK_SIZE_WIDTH{1'b0}}}-4;
    else
        inst_addr <= #1 pc;
end

assign inst_addr_o = inst_addr;
endmodule
