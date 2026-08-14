`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
// ITCM - 指令紧耦合存储器（单端口，同步读，结构同 DTCM）
// CPU 运行程序存放于此；取指 / LSU load / SBA 读共用一个读口（地址由上游 mux），
// LSU store / SBA 写 / UART 下载共用写口（字节使能）
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
    // 单端口：读/写共用地址（取指 / LSU / SBA 由上游 mux）
    input   logic   [ADDR_WIDTH-1:0]    itcm_access_addr,
    input   logic   [ALIGN_BYTES-1:0]   itcm_wr_en,     // 字节写使能（0 = 读）
    input   logic   [DATA_WIDTH-1:0]    itcm_wr_data,
    output  logic   [DATA_WIDTH-1:0]    itcm_inst,      // 同步读输出
    // UART 下载写端口（优先于 itcm_wr_en）
    input   logic                       itcm_download_en,
    input   logic   [ADDR_WIDTH-1:0]    itcm_download_addr,
    input   logic   [DATA_WIDTH-1:0]    itcm_download_data
);

// 下载优先：下载使能时使用下载地址/数据/全字使能，否则使用处理器访问
wire [ALIGN_BYTES-1:0] ram_we   = itcm_download_en ? {ALIGN_BYTES{1'b1}} : itcm_wr_en;
wire [ADDR_WIDTH-1:0]  ram_addr = itcm_download_en ? itcm_download_addr : itcm_access_addr;
wire [DATA_WIDTH-1:0]  ram_din  = itcm_download_en ? itcm_download_data : itcm_wr_data;

generate 
    `ifdef XILINX
        logic [DATA_WIDTH-1:0] inst;
        // 例化 Xilinx 单端口 BRAM IP（读+写共用 Port A）
        imem u_imem (
            .clka (clk),
            .wea  (ram_we),
            .addra(ram_addr[ITCM_SIZE_WIDTH-1:ALIGN_WIDTH]),
            .dina (ram_din),
            .douta(inst)
        );
        assign itcm_inst = rst_n ? inst : `INST_NOP;
    `else
        logic [DATA_WIDTH-1:0] itcm_mem [0:ITCM_DEPTH-1];

        `ifdef DIRECT_LOAD
            initial begin
                $readmemh(ITCM_FULL_PATH, itcm_mem);
            end
        `endif
        // 同步读：地址在上升沿采样，下一拍输出数据
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                itcm_inst <= #1 `INST_NOP;
            else
                itcm_inst <= #1 itcm_mem[ram_addr[ITCM_SIZE_WIDTH-1:ALIGN_WIDTH]];
        end

        // 同步写（UART 下载全字 / CPU store / SBA 写，按字节使能）
        integer i;
        always_ff @(posedge clk) begin
            if(|ram_we) begin
                for (i=0;i<ALIGN_BYTES;i=i+1) begin
                    if (ram_we[i]) begin
                        itcm_mem[ram_addr[ITCM_SIZE_WIDTH-1:ALIGN_WIDTH]][i*8+:8] <= #1 ram_din[i*8+:8];
                    end
                end
            end
        end
    `endif
endgenerate

endmodule
