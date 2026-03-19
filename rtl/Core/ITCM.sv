`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
// 暂时先实现BootROM在ITCM中，后续将在总线中实现
module ITCM #(
    parameter   ITCM_FILE    = `ITCM_FILE,
    parameter   ITCM_DEPTH   = `ITCM_DEPTH,
    parameter   ADDR_WIDTH  = `ADDR_WIDTH,
    parameter   DATA_WIDTH  = `DATA_WIDTH,
    parameter   ALIGN_BYTES = `ALIGN_BYTES,
    parameter   ALIGN_WIDTH = `ALIGN_WIDTH,
    localparam  ITCM_SIZE_WIDTH = $clog2(ITCM_DEPTH)+ALIGN_WIDTH,
    localparam  MROM_SIZE_WIDTH = $clog2(`MROM_DEPTH)+ALIGN_WIDTH,
    localparam  PATH        = `PATH,
    localparam  ITCM_FULL_PATH = {PATH,ITCM_FILE},
    localparam  MROM_FULL_PATH = {PATH,`MROM_FILE}
)( 
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic                       itcm_wr_en,
    input   logic   [ADDR_WIDTH-1:0]    itcm_wr_addr,
    input   logic   [DATA_WIDTH-1:0]    itcm_wr_data,
    input   logic   [ADDR_WIDTH-1:0]    inst_addr,
    output  logic   [DATA_WIDTH-1:0]    inst_o
);

logic [DATA_WIDTH-1:0] mrom_mem [0:`MROM_DEPTH-1];
initial begin
    $readmemh(MROM_FULL_PATH,mrom_mem);
end  

generate 
    if(`TCM_Reg_or_BRAM=="BRAM") begin
        // 例化Xilinx BRAM IP（单端口，字节写使能）
        // logic [ALIGN_BYTES-1:0]         bram_wea;
        // logic [ADDR_WIDTH-1:ALIGN_WIDTH]bram_addr;
        // logic [DATA_WIDTH-1:0]          bram_dout;
        // assign bram_wea = (itcm_update_en && itcm_wr_en) ? {ALIGN_BYTES{1'b1}} : {ALIGN_BYTES{1'b0}};
        // assign bram_addr = (itcm_update_en && itcm_wr_en) ? itcm_wr_addr[ADDR_WIDTH-1:ALIGN_WIDTH] : inst_addr[ADDR_WIDTH-1:ALIGN_WIDTH];
        // blk_mem_gen_itcm u_blk_mem_gen_itcm (//关闭 Primitive/Core Output Register
        //     .clka   (clk),          // 同步时钟
        //     .ena    (1'b1),         // BRAM使能
        //     .wea    (bram_wea),     // 写使能（全字写）
        //     .addra  (bram_addr),    // 写地址（对齐后）
        //     .dina   (itcm_wr_data), // 写数据（待更新的指令）
        //     .douta  (bram_dout)     // BRAM组合读数据
        // );
        // assign inst_o = (!rst_n || itcm_update_en || bram_addr >= DTCM_DEPTH) ? `INST_NOP : bram_dout;
    end else if(`TCM_Reg_or_BRAM=="Reg") begin
        logic [DATA_WIDTH-1:0] itcm_mem [0:ITCM_DEPTH-1];

        initial begin
            // $readmemh(ITCM_FULL_PATH,itcm_mem);
        end

        // always_ff @(posedge clk or negedge rst_n) begin
        //     if(!rst_n) begin
        //         inst_o <= `INST_NOP;
        //     end else if(itcm_update_en) begin
        //         inst_o <= `INST_NOP;
        //     end else begin
        //         // 同步读：clk沿采样地址，输出指令（符合同步ROM设计）
        //         inst_o <= itcm_mem[inst_addr[ADDR_WIDTH-1:ALIGN_WIDTH]];
        //     end
        // end

        assign inst_o = (!rst_n) ? `INST_NOP :
                        (inst_addr[DATA_WIDTH-1:16] == `BOOT_BASE_ADDR) ?
                        mrom_mem[inst_addr[MROM_SIZE_WIDTH-1:ALIGN_WIDTH]]   :
                        (inst_addr[DATA_WIDTH-1:16] == `ITCM_BASE_ADDR) ?
                        itcm_mem[inst_addr[ITCM_SIZE_WIDTH-1:ALIGN_WIDTH]]   :
                        `INST_NOP;

        always_ff @(posedge clk) begin
            if(itcm_wr_en && inst_addr[ADDR_WIDTH-1:16] != `ITCM_BASE_ADDR) begin
                itcm_mem[itcm_wr_addr[ITCM_SIZE_WIDTH-1:ALIGN_WIDTH]] <= itcm_wr_data;
            end
        end
    end
endgenerate

endmodule
