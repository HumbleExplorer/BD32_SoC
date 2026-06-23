timeunit 1ns;
timeprecision 1ps;

module tb_core_top;
`include "./../rtl/SoC_Config.sv"

parameter ADDR_WIDTH = `ADDR_WIDTH;
parameter DATA_WIDTH = `DATA_WIDTH;
parameter REG_ADDR_WIDTH =`REG_ADDR_WIDTH;
parameter REGFILE_NUM = `REGFILE_NUM;
parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH;
parameter ALIGN_BYTES = `ALIGN_BYTES;
parameter ALIGN_WIDTH = `ALIGN_WIDTH;
localparam CLK_PERIOD = 10;
// localparam    ITCM_FILE    =  "rv32ui-p-beq.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-bge.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-bgeu.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-blt.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-bltu.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-bne.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-jal.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-jalr.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-lui.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-auipc.dat";

// localparam    ITCM_FILE    =  "rv32ui-p-addi.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-andi.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-ori.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-xori.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-slti.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-sltiu.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-slli.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-srli.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-srai.dat";

localparam    ITCM_FILE    =  "rv32ui-p-add.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-sub.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-and.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-or.dat";                                                                                                                                                                                                                                                                                                                                                             
// localparam    ITCM_FILE    =  "rv32ui-p-xor.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-slt.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-sltu.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-sll.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-srl.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-sra.dat";

// localparam    ITCM_FILE    =  "rv32um-p-mul.dat";
// localparam    ITCM_FILE    =  "rv32um-p-mulh.dat";
// localparam    ITCM_FILE    =  "rv32um-p-mulhsu.dat";
// localparam    ITCM_FILE    =  "rv32um-p-mulhu.dat";
// localparam    ITCM_FILE    =  "rv32um-p-div.dat";
// localparam    ITCM_FILE    =  "rv32um-p-divu.dat";
// localparam    ITCM_FILE    =  "rv32um-p-rem.dat";
// localparam    ITCM_FILE    =  "rv32um-p-remu.dat";

// localparam    ITCM_FILE    =  "rv32ui-p-sb.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-sh.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-sw.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-lb.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-lbu.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-lh.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-lhu.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-lw.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-ld_st.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-ma_data.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-fence_i.dat";
// localparam    ITCM_FILE    =  "rv32ui-p-simple.dat";

 
logic   clk;
logic   rst_n;
logic   itcm_download_en;
logic   [31:0]  itcm_download_addr;
logic   [31:0]  itcm_download_data;
logic   dtcm_download_en;
logic   [31:0]  dtcm_download_addr;
logic   [31:0]  dtcm_download_data;
logic   external_int;
logic   software_int;
logic   timer_int;
logic   [31:0]  bus_rdata;
logic   bus_tran_done;
logic   bus_transfer;
logic   bus_access_write;
logic   [31:0]  bus_access_addr;
logic   [3:0]   bus_access_wstrb;
logic   [31:0]  bus_access_wdata;
logic   [63:0]  mtime_shadow;
logic   [31:0]  test;
logic   [31:0]  x3;
logic   [31:0]  x26;
logic   [31:0]  x27;

assign  x3= tb_core_top.u_RISC_V_Core.u_RegFile.regs[3];
assign x26= tb_core_top.u_RISC_V_Core.u_RegFile.regs[26];
assign x27= tb_core_top.u_RISC_V_Core.u_RegFile.regs[27];

always #(CLK_PERIOD/2)   clk = ~clk;
initial begin
    clk     = 1'b0;
    rst_n   = 1'b0;
    itcm_download_en   = 1'b0;
    itcm_download_addr = 'h0;
    itcm_download_data = 'h0;
    dtcm_download_en   = 1'b0;
    dtcm_download_addr = 'h0;
    dtcm_download_data = 'h0;
    external_int = 1'b0;
    software_int = 1'b0;
    timer_int = 1'b0;
    mtime_shadow = 'h0;
    bus_rdata       = 'h0;
    bus_tran_done   = 'h0;
    #50;
    rst_n   = 1'b1;
    #30;
end
initial  begin
    forever begin
        test = x3;
        @(posedge clk);
        if(test != x3)
            $display("test[%d]",x3);
        else if(x26 == 32'h1) begin
            repeat(10) @(posedge clk);
            if(x27 == 32'h1) begin
                $display("\n");
                $display("**************************************************");
                $display("\n");
                $display("%s",ITCM_FILE," test passed !!!!! ");
                $display("\n");
                $display("**************************************************");
                $display("\n");
                // for(int i=0;i<32;i++) begin
                //     $display("%d register value is %d",i,tb_core_top.u_RISC_V_Core.u_RegFile.regs[i]);
                // end
                $finish;
            end
            else begin
                $display("**************************************************");
                $display("\n");
                $display("%s",ITCM_FILE,"  test failed !!!!! ");
                $display("\n");
                $display("**************************************************");
                $display("Tht failed test case is test[%d]",x3);
                // for(int i=0;i<32;i++) begin
                //     $display("%d register value is %d",i,tb_core_top.u_RISC_V_Core.u_RegFile.regs[i]);
                // end
                $finish;
            end
        end
    end
end

RISC_V_Core #(
    .ITCM_FILE      (ITCM_FILE      ),
    .DTCM_FILE      (ITCM_FILE      ),
    .ADDR_WIDTH     (ADDR_WIDTH     ),
    .DATA_WIDTH     (DATA_WIDTH     ),
    .REGFILE_NUM    (REGFILE_NUM    ),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH ),
    .CSR_ADDR_WIDTH (CSR_ADDR_WIDTH ),
    .ALIGN_BYTES    (ALIGN_BYTES    ),
    .ALIGN_WIDTH    (ALIGN_WIDTH    )
) u_RISC_V_Core (
    .clk                (clk         ),
    .rst_n              (rst_n       ),
    .itcm_download_en   (itcm_download_en      ),
    .itcm_download_addr (itcm_download_addr    ),
    .itcm_download_data (itcm_download_data    ),
    .dtcm_download_en   (dtcm_download_en      ),
    .dtcm_download_addr (dtcm_download_addr    ),
    .dtcm_download_data (dtcm_download_data    ),
    .mtime_shadow       (mtime_shadow    ),
    .software_int       (software_int    ),
    .timer_int          (timer_int       ),
    .external_int       (external_int    ),
    .bus_rdata          (bus_rdata       ),
    .bus_tran_done      (bus_tran_done   ),
    .bus_transfer       (bus_transfer    ),
    .bus_access_write   (bus_access_write),
    .bus_access_addr    (bus_access_addr ),
    .bus_access_wstrb   (bus_access_wstrb),
    .bus_access_wdata   (bus_access_wdata)

);


endmodule

