`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
// ITCM - 指令紧耦合存储器（同步读）
// CPU 运行程序存放于此，UART 下载写入，取指同步读
// 地址区域：0x0001_0000 ~ 0x0001_FFFF（由 ITCM_DEPTH 决定）
// 同步读：地址在周期 N 给出，数据在周期 N+1 输出
module ITCM #(
    parameter   ITCM_FILE    = `ITCM_FILE,
    parameter   ITCM_DEPTH   = `ITCM_DEPTH,
    parameter   ADDR_WIDTH   = `ADDR_WIDTH,
    parameter   DATA_WIDTH   = `DATA_WIDTH,
    parameter   ALIGN_BYTES  = `ALIGN_BYTES,
    parameter   ALIGN_WIDTH  = `ALIGN_WIDTH,
    localparam  ITCM_SIZE_WIDTH = $clog2(ITCM_DEPTH)+ALIGN_WIDTH,
    localparam  PATH         = `PATH,
    localparam  ITCM_FULL_PATH = {PATH,ITCM_FILE}
)( 
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic                       itcm_download_en,
    input   logic   [ADDR_WIDTH-1:0]    itcm_download_addr,
    input   logic   [DATA_WIDTH-1:0]    itcm_download_data,
    input   logic   [ADDR_WIDTH-1:0]    inst_addr,  // 读地址（= PC_counter.pc，提前一拍）
    output  logic   [DATA_WIDTH-1:0]    inst_o      // 同步读输出
);

generate 
    `ifdef XILINX
        logic [DATA_WIDTH-1:0] inst;
        // 例化 Xilinx BRAM IP
        imem u_imem (
            .clka(clk),            // input wire clka
            .wea(itcm_download_en),              // input wire [0 : 0] wea
            .addra(itcm_download_addr[15:2]),          // input wire [13 : 0] addra
            .dina(itcm_download_data),            // input wire [31 : 0] dina
            .clkb(clk),            // input wire clkb
            .addrb(inst_addr[15:2]),          // input wire [13 : 0] addrb
            .doutb(inst)          // output wire [31 : 0] doutb
        );
        assign inst_o = rst_n ? inst : `INST_NOP;
    `else
        logic [DATA_WIDTH-1:0] itcm_mem [0:ITCM_DEPTH-1];

        `ifdef ITCM_DIRECT_LOAD
            initial begin
                $readmemh(ITCM_FULL_PATH, itcm_mem);
            end
        `endif
        // 同步读：地址在上升沿采样，下一拍输出数据
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                inst_o <= #1 `INST_NOP;
            else
                inst_o <= #1 itcm_mem[inst_addr[ITCM_SIZE_WIDTH-1:ALIGN_WIDTH]];
        end

        // 同步写（UART 下载程序时写入）
        always_ff @(posedge clk) begin
            if(itcm_download_en) begin
                itcm_mem[itcm_download_addr[ITCM_SIZE_WIDTH-1:ALIGN_WIDTH]] <= #1 itcm_download_data;
            end
        end
    `endif
endgenerate

endmodule
