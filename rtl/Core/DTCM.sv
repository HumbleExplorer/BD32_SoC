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

`ifdef DTCM_ASYNC_READ
// ============================================
// 以下为原始异步读实现（已弃用，仅供参考）
// 同步读模式下 DTCM 读延迟 1 拍，
// 需要配合 Mem_Access / Forward / Pipeline_Ctrl 调整
// 如需恢复异步读，取消 DTCM_ASYNC_READ 定义并替换上方逻辑
// ============================================
//
    (* RAM_STYLE="distributed"*) logic [DATA_WIDTH-1:0] ram_mem [0:DTCM_DEPTH-1];

    initial begin
        $readmemh(FULL_PATH,ram_mem);
    end

    integer i;
    always_ff @(posedge clk) begin
        if(wr_en) begin
            for (i=0;i<ALIGN_BYTES;i=i+1) begin
                if (wr_mask[i]) begin
                    ram_mem[dtcm_addr[DTCM_SIZE_WIDTH-1:ALIGN_WIDTH]][i*8+:8] <= #1 wr_data[i*8+:8];
                end
            end
        end
    end

    assign rd_data = (!rst_n)? 'h0 :ram_mem[dtcm_addr[DTCM_SIZE_WIDTH-1:ALIGN_WIDTH]];
`else
generate 
    if(`TCM_Reg_or_BRAM=="BRAM") begin : gen_bram
        //--------------------------------------------
        // BRAM 模式：使用 Vivado IP（同步读）
        //--------------------------------------------
        dmem u_dmem (
            .clka(clk),    // input wire clka
            .wea(wr_en ? wr_mask : 4'b0000),      // input wire [3 : 0] wea
            .addra(dtcm_addr[DTCM_SIZE_WIDTH-1:ALIGN_WIDTH]),  // input wire [13 : 0] addra
            .dina(wr_data),    // input wire [31 : 0] dina
            .douta(rd_data)  // output wire [31 : 0] douta
        );

    end else if(`TCM_Reg_or_BRAM=="Reg") begin : gen_reg
        //--------------------------------------------
        // Reg 模式：模拟 BRAM 同步读行为（用于仿真）
        // 写：同周期写入；读：下一拍输出
        //--------------------------------------------
        logic [DATA_WIDTH-1:0] ram_mem [0:DTCM_DEPTH-1];

        initial begin
            $readmemh(FULL_PATH,ram_mem);
        end

        integer i;
        always_ff @(posedge clk) begin
            if(wr_en) begin
                for (i=0;i<ALIGN_BYTES;i=i+1) begin
                    if (wr_mask[i]) begin
                        ram_mem[dtcm_addr[DTCM_SIZE_WIDTH-1:ALIGN_WIDTH]][i*8+:8] <= #1 wr_data[i*8+:8];
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
`endif // DTCM_ASYNC_READ

endmodule
