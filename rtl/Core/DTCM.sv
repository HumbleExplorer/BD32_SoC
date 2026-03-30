`include "../SoC_Config.sv"

`timescale 1ns / 1ps
module DTCM #(
    parameter DTCM_FILE     = `DTCM_FILE,
    parameter DTCM_DEPTH    = `DTCM_DEPTH,
    parameter ADDR_WIDTH    = `ADDR_WIDTH,
    parameter DATA_WIDTH    = `DATA_WIDTH,
    parameter ALIGN_WIDTH   = `ALIGN_WIDTH,
    parameter ALIGN_BYTES   = `ALIGN_BYTES,
    localparam DTCM_SIZE_WIDTH = $clog2(DTCM_DEPTH) + ALIGN_WIDTH,
    localparam PATH = `PATH,
    localparam FULL_PATH = {PATH,DTCM_FILE}
)( 
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic   [ADDR_WIDTH-1:0]    access_addr,
    input   logic                       wr_en,
    input   logic   [DATA_WIDTH-1:0]    wr_data,
    input   logic   [ALIGN_BYTES-1:0]   wr_mask,
    output  logic   [DATA_WIDTH-1:0]    rd_data
);

wire [DTCM_SIZE_WIDTH-1:0] dtcm_addr = access_addr[DTCM_SIZE_WIDTH-1:0];
generate 
    if(`TCM_Reg_or_BRAM=="BRAM") begin
        // // 例化Xilinx BRAM IP（单端口，字节写使能
        // blk_mem_gen_dtcm u_blk_mem_gen_dtcm (
        // .clka   (clk),
        // .ena    (1'b1),
        // .wea    (wr_en ? wr_mask : 4'b0000),
        // .addra  (dtcm_addr[DTCM_SIZE_WIDTH-1:ALIGN_WIDTH]),
        // .dina   (wr_data),
        // .douta  (rd_data)
        // );
    end else if(`TCM_Reg_or_BRAM=="Reg") begin
        logic [DATA_WIDTH-1:0] ram_mem [0:DTCM_DEPTH-1];

        initial begin
            $readmemh(FULL_PATH,ram_mem);
        end

        integer i;
        always_ff @(posedge clk) begin
            if(wr_en) begin
                for (i=0;i<ALIGN_BYTES;i=i+1) begin
                    // 按wr_mask逐字节更新，未掩码的字节保持原样
                    if(wr_mask[i]) begin
                        ram_mem[dtcm_addr[DTCM_SIZE_WIDTH-1:ALIGN_WIDTH]][i*8+:8] <= #1 wr_data[i*8+:8];
                    end
                end
            end
        end

        assign rd_data = (!rst_n)? 'h0 :ram_mem[dtcm_addr[DTCM_SIZE_WIDTH-1:ALIGN_WIDTH]];
    end
endgenerate

endmodule
