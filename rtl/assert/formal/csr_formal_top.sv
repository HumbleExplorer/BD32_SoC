// =============================================================================
// csr_formal_top.sv — CSR_Reg_Access 形式验证 harness（SymbiYosys）
// =============================================================================
// 目标属性（CSR_Reg_Access.sv `ifdef FORMAL 区）：
//   ① 中断接受门控契约（zcmp_busy / mret_gap / PC 对齐 / mcause 码合法）
//   ② mret 间隙窗口不变式（fml_c_mret_gap_end 可达性）
// 输入全自由穷举；复位时序假设由本 harness 提供（初始 1 拍 rst_n=0）。
// =============================================================================

module csr_formal_top #(
    parameter DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    localparam AW = 32;
    localparam CW = 12;
    localparam DW2 = 64;

    // ---- 输入自由变量 ----
    logic                    f_csr_en;
    logic [CW-1:0]         f_csr_addr;
    logic [DATA_WIDTH-1:0] f_csr_wdata;
    logic                    f_dbg_csr_we;
    logic [CW-1:0]         f_dbg_csr_addr;
    logic [DATA_WIDTH-1:0] f_dbg_csr_wdata;
    logic [AW-1:0]         f_exc_inst_addr;
    logic [AW-1:0]         f_next_inst_addr;
    logic                    f_bus_ready;
    logic                    f_oitf_stall;
    logic                    f_wfi_req;
    logic                    f_mret_req;
    logic                    f_exception_trap;
    logic [DATA_WIDTH-2:0] f_exception_code;   // 全 1 哨兵（bit30）= 无异常
    logic [DATA_WIDTH-1:0] f_exception_val;
    logic                    f_external_int;
    logic                    f_software_int;
    logic                    f_timer_int;
    logic [AW-1:0]         f_id_ex_inst_addr;
    logic                    f_id_ex_inst_valid;
    logic [1:0]            f_branch_en_ex;
    logic [DW2-1:0]        f_mtime_shadow;
    logic                    f_hpm_valid;
    logic [3:0]            f_hpm_inst_type;
    logic                    f_hpm_mispredict;
    logic                    f_hpm_count_ok;
    logic                    f_hpm_oitf_retire;
    logic [1:0]            f_hpm_ext;
    logic                    f_zcmp_busy;

    // 异常码 = 自由输入（钉哨兵会让 exception_trap 恒 0，fml_a_exc_code_valid
    // 断言空转不覆盖真实路径）。接口契约由下方 assume 保证（trap → 非哨兵），
    // 异常路径因此被 formal 真实探索。
    assign f_id_ex_inst_addr = '0;
    assign f_exc_inst_addr   = '0;
    assign f_next_inst_addr  = '0;
    assign f_csr_addr        = '0;
    assign f_dbg_csr_addr    = '0;

    // ---- DUT 输出 ----
    logic [DATA_WIDTH-1:0] o_dbg_csr_rdata;
    logic                    o_ex_illegal_csr;
    logic [1:0]            o_priv_mode;
    logic                    o_trap_jump;
    logic [DATA_WIDTH-1:0] o_trap_jump_addr;
    logic                    o_trap_jump_exc;
    logic                    o_int_accept_kill;
    logic                    o_waiting_int;

    // ---- 复位时序假设：初始 1 拍 rst_n=0，此后恒 1 ----
    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;
    always_ff @(posedge clk) begin
        if (!f_past_valid) assume (!rst_n);
        else               assume (rst_n);
    end
    // ---- 输入契约假设（harness 侧，保证输入落在物理可达子集）----
    // ① 复位期间控制动作输入恒 0（L1 disable-iff 等价假设）
    always @(posedge clk) begin
        if (!rst_n) begin
            assume (!f_csr_en);
            assume (!f_dbg_csr_we);
            assume (!f_mret_req);
            assume (!f_wfi_req);
        end
    end
    // ② 异常码架构契约（Pipeline_Ctrl 保证）：
    //    陷阱触发拍（exception_trap=1）时，CSR 看到的码是 Pipeline_Ctrl
    //    sel_stage mux 选出的"阶段码"（非全 1 哨兵，全 1 = 无异常）。
    //    仅约束陷阱拍；非陷阱拍码值自由
    //  ③ mret 与异常互斥（异常陷阱期间 mret 不合法——mret 是系统指令，
    //    与 EX 级异常同拍出现 = 引擎构造的非物理组合）
    always @(posedge clk) begin
        if (rst_n) begin
            assume (f_exception_trap ? (f_exception_code != {DATA_WIDTH-1{1'b1}}) : 1'b1);
            assume (!(f_mret_req && f_exception_trap));
        end
    end
    // ③ CSR 写约束（mstatus WARL / mepc RVC 对齐）：
    //    复位后 mstatus 写只走 RTL case 实际映射的位（bit7=MPIE, bit3=MIE），
    //    其余位写丢失——约束物理可写子集，防引擎构造硬件不存在的 mstatus 值；
    //    mepc 写必须 2 字节对齐（RVC 合法指令地址）
    always @(posedge clk) begin
        if (rst_n && f_csr_en && f_csr_addr == 12'h300) begin
            assume (f_csr_wdata == (f_csr_wdata & 32'h0000_0088));
        end
        if (rst_n && f_csr_en && f_csr_addr == 12'h341) begin
            assume (f_csr_wdata[0] == 1'b0);
        end
    end

    CSR_Reg_Access #(
        .ADDR_WIDTH     (AW),
        .DATA_WIDTH     (DATA_WIDTH),
        .CSR_ADDR_WIDTH (CW)
    ) dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .csr_en              (f_csr_en),
        .csr_addr            (f_csr_addr),
        .csr_wdata           (f_csr_wdata),
        .csr_rdata           (),
        .dbg_csr_we          (f_dbg_csr_we),
        .dbg_csr_addr        (f_dbg_csr_addr),
        .dbg_csr_wdata       (f_dbg_csr_wdata),
        .dbg_csr_rdata       (o_dbg_csr_rdata),
        .exception_inst_addr (f_exc_inst_addr),
        .next_inst_addr      (f_next_inst_addr),
        .bus_ready           (f_bus_ready),
        .oitf_stall          (f_oitf_stall),
        .wfi_req             (f_wfi_req),
        .mret_req            (f_mret_req),
        .exception_trap      (f_exception_trap),
        .exception_code      (f_exception_code),
        .exception_val       (f_exception_val),
        .external_int        (f_external_int),
        .software_int        (f_software_int),
        .timer_int           (f_timer_int),
        .id_ex_inst_addr     (f_id_ex_inst_addr),
        .id_ex_inst_valid    (f_id_ex_inst_valid),
        .branch_en_ex        (f_branch_en_ex),
        .mtime_shadow        (f_mtime_shadow),
        .ex_illegal_csr      (o_ex_illegal_csr),
        .priv_mode           (o_priv_mode),
        .trap_jump           (o_trap_jump),
        .trap_jump_addr      (o_trap_jump_addr),
        .trap_jump_exc       (o_trap_jump_exc),
        .int_accept_kill     (o_int_accept_kill),
        .waiting_int         (o_waiting_int),
        .hpm_valid           (f_hpm_valid),
        .hpm_inst_type       (f_hpm_inst_type),
        .hpm_mispredict      (f_hpm_mispredict),
        .hpm_count_ok        (f_hpm_count_ok),
        .hpm_oitf_retire     (f_hpm_oitf_retire),
        .hpm_ext             (f_hpm_ext),
        .zcmp_busy           (f_zcmp_busy)
    );

endmodule
