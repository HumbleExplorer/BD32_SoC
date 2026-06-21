`include "../SoC_Config.sv"

timeunit 1ns;
timeprecision 1ps;
module DTCM #(
    parameter DTCM_FILE     = `DTCM_FILE,
    parameter DTCM_DEPTH    = `DTCM_DEPTH,
    parameter ADDR_WIDTH    = `ADDR_WIDTH,
    parameter DATA_WIDTH    = `DATA_WIDTH,
    parameter ALIGN_WIDTH   = `ALIGN_WIDTH,
    parameter ALIGN_BYTES   = `ALIGN_BYTES,
    localparam DTCM_SIZE_WIDTH = $clog2(DTCM_DEPTH) + ALIGN_WIDTH,
    localparam TEST_PATH = `TEST_PATH,
    localparam FULL_PATH = {TEST_PATH,DTCM_FILE}
)( 
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic   [ADDR_WIDTH-1:0]    access_addr,
    input   logic                       wr_en,
    input   logic   [DATA_WIDTH-1:0]    wr_data,
    input   logic   [ALIGN_BYTES-1:0]   wr_mask,
    // UART 下载写端口
    input   logic                       dtcm_download_en,
    input   logic   [ADDR_WIDTH-1:0]    dtcm_download_addr,
    input   logic   [DATA_WIDTH-1:0]    dtcm_download_data,
    output  logic   [DATA_WIDTH-1:0]    rd_data
);

wire [DTCM_SIZE_WIDTH-1:0] dtcm_addr;
wire [ALIGN_BYTES-1:0]     dtcm_we;
wire [DATA_WIDTH-1:0]      dtcm_wdata;

// 下载写优先：下载使能时使用下载地址/数据，否则使用处理器访问
assign dtcm_addr  = dtcm_download_en ? dtcm_download_addr[DTCM_SIZE_WIDTH-1:0] : access_addr[DTCM_SIZE_WIDTH-1:0];
assign dtcm_we    = dtcm_download_en ? {ALIGN_BYTES{1'b1}} : (wr_en ? wr_mask : 4'b0000);
assign dtcm_wdata = dtcm_download_en ? dtcm_download_data : wr_data;

generate 
    if(`TCM_Reg_or_BRAM=="BRAM") begin : gen_bram
        //--------------------------------------------
        // BRAM 模式：使用 Vivado IP（同步读）
        //--------------------------------------------
        dmem u_dmem (
            .clka(clk),    // input wire clka
            .wea(dtcm_we),      // input wire [3 : 0] wea
            .addra(dtcm_addr[DTCM_SIZE_WIDTH-1:ALIGN_WIDTH]),  // input wire [13 : 0] addra
            .dina(dtcm_wdata),    // input wire [31 : 0] dina
            .douta(rd_data)  // output wire [31 : 0] douta
        );

    end else if(`TCM_Reg_or_BRAM=="Reg") begin : gen_reg
        //--------------------------------------------
        // Reg 模式：模拟 BRAM 同步读行为（用于仿真）
        // 写：同周期写入；读：下一拍输出
        //--------------------------------------------
        logic [DATA_WIDTH-1:0] ram_mem [0:DTCM_DEPTH-1];
        `ifdef DIRECT_LOAD
        initial begin
            $readmemh(FULL_PATH,ram_mem);
        end
        `endif

        integer i;
        always_ff @(posedge clk) begin
            if(|dtcm_we) begin
                for (i=0;i<ALIGN_BYTES;i=i+1) begin
                    if (dtcm_we[i]) begin
                        ram_mem[dtcm_addr[DTCM_SIZE_WIDTH-1:ALIGN_WIDTH]][i*8+:8] <= #1 dtcm_wdata[i*8+:8];
                    end
                end
            end
        end

        // 同步读：地址在本沿采样，数据下一沿输出（模拟 BRAM 行为）
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                rd_data <= #1 'h0;
            else
                rd_data <= #1 ram_mem[dtcm_addr[DTCM_SIZE_WIDTH-1:ALIGN_WIDTH]];
        end

    end
endgenerate

endmodule
