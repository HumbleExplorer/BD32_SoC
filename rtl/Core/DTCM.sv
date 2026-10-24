`include "../SoC_Config.sv"

timeunit 1ns;
timeprecision 1ps;
import bd32_pkg::*;

module DTCM #(
    parameter DTCM_FILE     = `DTCM_FILE,
    parameter DTCM_DEPTH    = DTCM_DEPTH,
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
        logic [DATA_WIDTH-1:0] ram_mem [0:DTCM_DEPTH-1] = '{default: '0};
        `ifdef DIRECT_LOAD
            // 声明处零默认：未覆盖区域为 0，对齐 FPGA BRAM 上电态
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

        // 同步读：地址在本沿采样，数据下一沿输出。
        // WRITE_FIRST 语义（与 dmem BRAM IP 一致）：同沿写读同地址时读出本沿写入的新值
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                rd_data <= #1 'h0;
            else if (|dtcm_we)
                rd_data <= #1 dtcm_wdata;
            else
                rd_data <= #1 ram_mem[dtcm_addr[DTCM_SIZE_WIDTH-1:ALIGN_WIDTH]];
        end

        `ifndef SYNTHESIS
        // SVA: WRITE_FIRST 语义自检——有写的下一拍 rd_data 必须是写入值。
        // 本断言固定 Reg 分支与 dmem BRAM IP 的语义一致性：
        // 若有人把 WRITE_FIRST 分支删掉（同沿写读回退为 READ_FIRST）立即触发。
        a_write_first_readback: assert property (
            @(posedge clk) disable iff (!rst_n)
            (|dtcm_we) |=> (rd_data == $past(dtcm_wdata)));
        `endif

    end
endgenerate

`ifdef ASSERT_MODULE
// ===== SVA L2：DTCM 深化——读写数据质量 =====
always @(posedge clk) begin
    if (rst_n) begin
        // 读出数据无 X（BRAM 读质量）
        a_l2_dtcm_rd_nox: assert property (!$isunknown(rd_data));
        // CPU 写路径数据/字节掩码无 X
        if (wr_en) a_l2_dtcm_wr_nox: assert property (!$isunknown(wr_data) && !$isunknown(wr_mask));
    end
end
`endif


endmodule
