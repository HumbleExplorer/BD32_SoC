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

`ifdef HPM_AUDIT
// ============================================================================
// HPM 审计参考模型：独立译码 + 退休计账，与 DUT mhpmcounter 对账
// 独立性：类别从 inst_wb 位域独立解码，不复用 RTL 的 wb_inst_cat/递增逻辑；
// MUL/DIV 影子（OP+funct7=0000001）不计主 WB 退休，改计 OITF 退休拍。
// ============================================================================
integer ref_cycles;
integer ref_instret;
integer ref_main_cnt;
integer ref_shadow;
integer ref_oitf;
integer ref_overlap;
integer ref_cnt  [0:8];          // 0 OTHER 1 ALU 2 LOAD 3 STORE 4 BR 5 JMP 6 MULDIV 7 CSR 8 SYS
logic   audit_started;
integer latch_at;
logic   audit_latched;
integer snap_cycles, snap_instret, snap_cnt[0:8], snap_overlap;
integer dut_mcycle, dut_instret, dut_cnt[0:14];
integer dut_cls[1:8];

function automatic integer ref_class(input logic [31:0] inst);
    begin
        case (inst[6:0])
            7'b0110011: ref_class = (inst[31:25] == 7'b0000001) ? 6 : 1; // OP: MULDIV 影子 / ALU
            7'b0000011: ref_class = 2;                                   // LOAD
            7'b0100011: ref_class = 3;                                   // STORE
            7'b1100011: ref_class = 4;                                   // BRANCH
            7'b1101111,
            7'b1100111: ref_class = 5;                                   // JAL/JALR
            7'b1110011: ref_class = (inst[14:12] == 3'b000) ? 8 : 7;     // SYSTEM/CSR
            7'b0001111: ref_class = 8;                                   // fence
            7'b0110111,
            7'b0010111,
            7'b0010011: ref_class = 1;                                   // LUI/AUIPC/OP-IMM = ALU 类
            default:    ref_class = 0;
        endcase
    end
endfunction

always @(posedge clk) begin
    if (rst_n === 1'b1) begin
        // —— 同沿双快照：在最前面用"本沿累加前"的值锁存，与 DUT 的 NBA 前值对齐 ——
        if (!audit_started) begin
            if (x26 === 1'b1) begin
                audit_started <= 1'b1;
                latch_at      <= ref_cycles + 80;   // 触发沿也是累加前值
            end
        end else if (!audit_latched && ref_cycles == latch_at) begin
            audit_latched <= 1'b1;
            snap_cycles   <= ref_cycles;            // 以下右侧全是累加前值
            snap_instret  <= ref_instret;
            snap_overlap  <= ref_overlap;
            for (integer k = 0; k < 9; k = k + 1) snap_cnt[k] <= ref_cnt[k];
            dut_mcycle  <= u_RISC_V_Core.u_CSR_Reg_Access.mcycle[31:0];
            dut_instret <= u_RISC_V_Core.u_CSR_Reg_Access.minstret[31:0];
            for (integer k2 = 0; k2 < 15; k2 = k2 + 1)
                dut_cnt[k2] <= u_RISC_V_Core.u_CSR_Reg_Access.mhpmcounter[k2][31:0];
        end
        ref_cycles = ref_cycles + 1;
        if (u_RISC_V_Core.mem_wb_valid && !u_RISC_V_Core.mem_wb_stall) begin
            if (ref_class(u_RISC_V_Core.inst_wb) == 6) begin
                ref_shadow = ref_shadow + 1;          // 乘除影子：不计退休（OITF 拍计）
            end else begin
                ref_main_cnt = ref_main_cnt + 1;
                ref_instret  = ref_instret + 1;
                ref_cnt[ref_class(u_RISC_V_Core.inst_wb)] =
                    ref_cnt[ref_class(u_RISC_V_Core.inst_wb)] + 1;
                if (u_RISC_V_Core.oitf_retire_valid)
                    ref_overlap = ref_overlap + 1;    // 主 WB 与 OITF 退休同拍
            end
        end
        if (u_RISC_V_Core.oitf_retire_valid) begin
            ref_oitf    = ref_oitf + 1;
            ref_instret = ref_instret + 1;
            ref_cnt[6]  = ref_cnt[6] + 1;
        end
`ifdef HPM_AUDIT_TRACE
        if (u_RISC_V_Core.mem_wb_valid && !u_RISC_V_Core.mem_wb_stall
            && ref_class(u_RISC_V_Core.inst_wb) == 5)
            $display("[JMP_TRACE] %0t pc=%08x", $time, u_RISC_V_Core.inst_addr_wb);
`endif
    end
end

task automatic hpm_audit_report;
    integer i;
    integer rtl_l, ref_v;
    integer fails;
    integer sum_classes;
    begin
        // 等 x26 触发 → 80 拍后同沿快照
        wait (audit_latched === 1'b1);
        fails = 0;
        sum_classes = 0;
        $display("==== HPM AUDIT: DUT vs reference model (latched @cycle %0d) ====", snap_cycles);
        // mcycle（±2 容差：复位释放沿归属）
        if (dut_mcycle > snap_cycles + 2 || dut_mcycle < snap_cycles - 2) begin
            $display("  [AUDIT FAIL] mcycle      dut=%0d ref=%0d", dut_mcycle, snap_cycles);
            fails = fails + 1;
        end else
            $display("  [AUDIT PASS] mcycle      dut=%0d ref=%0d", dut_mcycle, snap_cycles);
        // minstret（同拍重叠：RTL 每拍最多 +1，容差 = ref_overlap）
        if (dut_instret != snap_instret) begin
            $display("  [AUDIT FAIL] minstret    dut=%0d ref=%0d overlap=%0d",
                     dut_instret, snap_instret, snap_overlap);
            fails = fails + 1;
        end else
            $display("  [AUDIT PASS] minstret    dut=%0d ref=%0d overlap=%0d",
                     dut_instret, snap_instret, snap_overlap);
        // 各指令类（精确相等）
        begin
            string names [0:8];
            integer dut_idx [0:8];
            names[1]="ALU"; names[2]="LOAD"; names[3]="STORE"; names[4]="BRANCH";
            names[5]="JUMP"; names[6]="MULDIV"; names[7]="CSR"; names[8]="SYS";
            for (i = 1; i <= 8; i = i + 1) begin
                // RTL 数组下标映射：1-5 → [0-4]，6 → [5]（OITF 退休计数），7 → [10]，8 → [11]
                case (i)
                    1,2,3,4,5: dut_idx[i] = i-1;
                    6:         dut_idx[i] = 5;
                    7:         dut_idx[i] = 10;
                    8:         dut_idx[i] = 11;
                endcase
                dut_cls[i] = dut_cnt[dut_idx[i]];
                rtl_l = dut_cls[i];
                ref_v = snap_cnt[i];
                if (rtl_l !== ref_v) begin
                    $display("  [AUDIT FAIL] %-6s    dut=%0d ref=%0d", names[i], rtl_l, ref_v);
                    fails = fails + 1;
                end else
                    $display("  [AUDIT PASS] %-6s    dut=%0d ref=%0d", names[i], rtl_l, ref_v);
                sum_classes = sum_classes + rtl_l;
            end
        end
        // DUT 侧不变式：类计数之和 == minstret（低 32 位）
        if (sum_classes !== dut_instret) begin
            $display("  [AUDIT FAIL] invariant  sum(class)=%0d != minstret=%0d",
                     sum_classes, dut_instret);
            fails = fails + 1;
        end else
            $display("  [AUDIT PASS] invariant  sum(class)=%0d == minstret", sum_classes);
        $display("  [AUDIT INFO] shadow=%0d oitf=%0d overlap=%0d other=%0d",
                 ref_shadow, ref_oitf, snap_overlap, snap_cnt[0]);
        if (fails == 0)
            $display("HPM AUDIT: ALL PASS");
        else
            $display("HPM AUDIT: %0d FAILURES", fails);
    end
endtask
`endif

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
`ifdef HPM_AUDIT
    ref_cycles = 0; ref_instret = 0; ref_main_cnt = 0;
    ref_shadow = 0; ref_oitf = 0; ref_overlap = 0;
    for (integer ai = 0; ai < 9; ai = ai + 1) ref_cnt[ai] = 0;
    audit_started = 1'b0;
    audit_latched = 1'b0;
    latch_at = 0;
`endif
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
`ifdef HPM_AUDIT
            hpm_audit_report;
`endif
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
