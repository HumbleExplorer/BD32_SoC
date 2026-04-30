`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
// BootROM - 只读启动存储器（同步读）
// CPU 上电后从此处取指，执行 bootloader 后跳转到 ITCM
// 地址区域：0x0000_0000 ~ 0x0000_0FFF（1K×4B = 4KB）
// 同步读：地址在周期 N 给出，数据在周期 N+1 输出
module BootROM #(
    parameter   MROM_DEPTH   = `MROM_DEPTH,
    parameter   ADDR_WIDTH   = `ADDR_WIDTH,
    parameter   DATA_WIDTH   = `DATA_WIDTH,
    parameter   ALIGN_WIDTH  = `ALIGN_WIDTH,
    localparam  MROM_SIZE_WIDTH = $clog2(MROM_DEPTH) + ALIGN_WIDTH,
    localparam  PATH         = `PATH,
    localparam  MROM_FULL_PATH = {PATH, `MROM_FILE}
)(
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic   [ADDR_WIDTH-1:0]    inst_addr,  // 读地址（= PC_counter.pc，提前一拍）
    output  logic   [DATA_WIDTH-1:0]    inst_o      // 同步读输出
);
generate
    `ifdef XILINX
        logic [DATA_WIDTH-1:0] inst;
            // 例化 Xilinx BRAM IP（单端口，字节写使能）
        mrom u_BootROM (
            .clka(clk),            // input wire clka
            .wea(1'b0),              // input wire [0 : 0] wea
            .addra(inst_addr[MROM_SIZE_WIDTH-1:ALIGN_WIDTH]),// input wire [9 : 0] addra
            .dina(0),            // input wire [31 : 0] dina
            .douta(inst)          // output wire [31 : 0] douta
        );
        assign inst_o = rst_n ? inst : `INST_NOP;

    `else
        logic [DATA_WIDTH-1:0] mrom_mem [0:MROM_DEPTH-1];

        initial begin
            $readmemh(MROM_FULL_PATH, mrom_mem);
        end

        // 同步读：地址在上升沿采样，下一拍输出数据
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                inst_o <= `INST_NOP;
            else
                inst_o <= mrom_mem[inst_addr[MROM_SIZE_WIDTH-1:ALIGN_WIDTH]];
        end

    `endif
endgenerate


endmodule
