`include "../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;
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
    input   logic                       dbg_load_en,    // resume 时加载 dpc
    input   logic   [ADDR_WIDTH-1:0]    dbg_load_addr,  // dpc 值
    (* MAX_FANOUT = 16 *)output  logic   [ADDR_WIDTH-1:0]    pc,          // 下一条指令地址（给 ROM/RAM，提前一拍送地址）
    output  logic                       if_addr_misalign,  // 指令地址未对齐
    output  logic                       if_access_fault,   // 指令访问错误（地址不在合法范围）
    (* MAX_FANOUT = 16 *)output  logic   [ADDR_WIDTH-1:0]    inst_addr_o  // 当前指令地址（给流水线，= 上一拍 pc）
);
logic [ADDR_WIDTH-1:0] inst_addr;

// 异常条件（纯 1-bit，编码由 RISC_V_Core 统一完成）
logic inst_addr_legal;
assign inst_addr_legal  = (inst_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH]==`BOOT_BASE_TAG || inst_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH]==`ITCM_BASE_TAG);
assign if_addr_misalign = inst_addr_legal && (inst_addr[ALIGN_WIDTH-1:0] != 0);
assign if_access_fault  = ~inst_addr_legal;
assign inst_addr_o = inst_addr;
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
    `ifdef DIRECT_LOAD
        inst_addr <= #1 {`ITCM_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}}-4;
    `else
        inst_addr <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}}-4;
    `endif
    else if (dbg_load_en)
        inst_addr <= #1 dbg_load_addr;
    else
        inst_addr <= #1 pc;
end


endmodule
