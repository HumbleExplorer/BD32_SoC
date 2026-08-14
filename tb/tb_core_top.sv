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
// parameter    ITCM_FILE    =  "rv32ui-p-beq.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-bge.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-bgeu.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-blt.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-bltu.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-bne.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-jal.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-jalr.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-lui.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-auipc.dat";

// parameter    ITCM_FILE    =  "rv32ui-p-addi.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-andi.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-ori.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-xori.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-slti.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-sltiu.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-slli.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-srli.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-srai.dat";

// parameter    ITCM_FILE    =  "rv32ui-p-add.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-sub.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-and.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-or.dat";                                                                                                                                                                                                                                                                                                                                                             
// parameter    ITCM_FILE    =  "rv32ui-p-xor.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-slt.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-sltu.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-sll.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-srl.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-sra.dat";

// parameter   ITCM_FILE    =  "rv32um-p-mul.dat";
// parameter    ITCM_FILE    =  "rv32um-p-mulh.dat";
// parameter    ITCM_FILE    =  "rv32um-p-mulhsu.dat";
// parameter    ITCM_FILE    =  "rv32um-p-mulhu.dat";
// parameter    ITCM_FILE    =  "rv32um-p-div.dat";
// parameter    ITCM_FILE    =  "rv32um-p-divu.dat";
// parameter    ITCM_FILE    =  "rv32um-p-rem.dat";
// parameter    ITCM_FILE    =  "rv32um-p-remu.dat";

// parameter    ITCM_FILE    =  "rv32ui-p-sb.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-sh.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-sw.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-lb.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-lbu.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-lh.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-lhu.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-lw.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-ld_st.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-ma_data.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-fence_i.dat";
// parameter    ITCM_FILE    =  "rv32ui-p-simple.dat";
// parameter    ITCM_FILE    =  "m_extension_stress.dat";
parameter    ITCM_FILE    =  "o3_pipeline_stress.dat";
parameter    DTCM_FILE    =  "o3_pipeline_stress.dat";
 
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
logic   bus_tran_done;
logic   bus_ready;
logic   [31:0]  bus_rdata;
logic   [1:0]   bus_resp;

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
`ifndef BUS_LATENCY
    bus_ready       = 1'b1;
    bus_rdata       = 'h0;
    bus_resp        = 'h0;
    bus_tran_done   = 'h0;
`endif
    #50;
    rst_n   = 1'b1;
    #30;
end

`ifdef BUS_LATENCY
// ============================================================================
// Bus latency model: simulates AXI slave with wait states.
// When bus_transfer asserts, bus_ready deasserts for BUS_WAIT_CYCLES,
// then bus_tran_done pulses for 1 cycle and bus_ready reasserts.
// This reproduces the ~bus_ready → id_ex_flush bug in Pipeline_Ctrl.
// ============================================================================
localparam BUS_WAIT_CYCLES = 3;
logic [3:0] bus_wait_cnt;
logic       bus_busy_q;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bus_wait_cnt  <= '0;
        bus_busy_q    <= 1'b0;
        bus_ready     <= 1'b1;
        bus_tran_done <= 1'b0;
        bus_rdata     <= 32'hCAFE_BABE;
        bus_resp      <= 2'b00;
    end else begin
        bus_tran_done <= 1'b0;  // default: single-cycle pulse
        if (bus_transfer && !bus_busy_q) begin
            // New bus access detected: start wait period
            bus_busy_q    <= 1'b1;
            bus_ready     <= 1'b0;
            bus_wait_cnt  <= BUS_WAIT_CYCLES;
        end else if (bus_busy_q) begin
            if (bus_wait_cnt == 1) begin
                // Wait complete: signal done, reassert ready
                bus_tran_done <= 1'b1;
                bus_ready     <= 1'b1;
                bus_busy_q    <= 1'b0;
            end else begin
                bus_wait_cnt <= bus_wait_cnt - 1;
            end
        end
    end
end
`endif
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
    .DTCM_FILE      (DTCM_FILE      ),
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
    .bus_tran_done      (bus_tran_done   ),
    .bus_ready          (bus_ready       ),
    .bus_rdata          (bus_rdata       ),
    .bus_resp           (bus_resp        ),
    .bus_transfer       (bus_transfer    ),
    .bus_access_write   (bus_access_write),
    .bus_access_addr    (bus_access_addr ),
    .bus_access_wstrb   (bus_access_wstrb),
    .bus_access_wdata   (bus_access_wdata),
    // Debug — 裸核测试不接调试模块，全部 tie off
    .dbg_halt_req       (1'b0        ),
    .dbg_halted         (            ),
    .dbg_resume_req     (1'b0        ),
    .dbg_step           (1'b0        ),
    .dbg_ebreakm        (1'b0        ),
    .dbg_reg_we         (1'b0        ),
    .dbg_reg_addr       (5'b0        ),
    .dbg_reg_wdata      (32'b0       ),
    .dbg_reg_rdata      (            ),
    .dbg_dpc            (            ),
    .dbg_pc_wdata       (32'b0       ),
    .dbg_csr_we         (1'b0        ),
    .dbg_csr_addr       (12'b0       ),
    .dbg_csr_wdata      (32'b0       ),
    .dbg_csr_rdata      (            ),
    // SBA — 不接系统总线访问
    .sba_req_valid      (1'b0        ),
    .sba_addr           (32'b0       ),
    .sba_wdata          (32'b0       ),
    .sba_write          (1'b0        ),
    .sba_size           (3'b0        ),
    .sba_be             (4'b0        ),
    .sba_rsp_valid      (            ),
    .sba_rdata          (            ),
    .sba_error          (            ),
    // Trigger — 不接硬件断点
    .trigger_en         (4'b0        ),
    .trigger_exec_en    (4'b0        ),
    .trigger_load_en    (4'b0        ),
    .trigger_store_en   (4'b0        ),
    .trigger_size       (8'b0        ),
    .trigger_addr       (128'b0      ),
    .trigger_hit        (            ),
    .ebreak_halt        (            )
);


endmodule
