// BD32 Debug Module 验证 Testbench
// 含 JTAG BFM + 测试序列：IDCODE / halt / GPR 读写 / resume
`include "./../rtl/SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;

module tb_debug;

parameter ADDR_WIDTH     = `ADDR_WIDTH;
parameter DATA_WIDTH     = `DATA_WIDTH;
parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH;
parameter REGFILE_NUM    = `REGFILE_NUM;
parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH;
parameter ALIGN_BYTES    = `ALIGN_BYTES;
parameter ALIGN_WIDTH    = `ALIGN_WIDTH;
parameter GPIO_NUM       = `GPIO_NUM;

localparam CPU_FREQ      = 75_000_000;
localparam CLK_PERIOD    = 1_000_000_000 / CPU_FREQ;  // 13.333ns
localparam TCK_PERIOD    = 100;  // 10MHz JTAG clock

// DMI 参数
localparam DMI_ADDR_BITS = 6;
localparam DMI_DATA_BITS = 32;
localparam DMI_OP_BITS   = 2;
localparam DMI_BITS      = DMI_ADDR_BITS + DMI_DATA_BITS + DMI_OP_BITS;  // 40

// IR 指令
localparam IR_IDCODE = 5'b00001;
localparam IR_DTMCS  = 5'b10000;
localparam IR_DMI    = 5'b10001;
localparam IR_BYPASS = 5'b11111;

// DMI 寄存器地址
localparam ADDR_DATA0      = 6'h04;
localparam ADDR_DMCONTROL  = 6'h10;
localparam ADDR_DMSTATUS   = 6'h11;
localparam ADDR_ABSTRACTCS = 6'h16;
localparam ADDR_COMMAND    = 6'h17;
localparam ADDR_SBCS       = 6'h38;
localparam ADDR_SBADDRESS0 = 6'h39;
localparam ADDR_SBDATA0    = 6'h3C;

// =========================================================================
// 信号
// =========================================================================
logic       sys_clk;
logic       rst_n;
logic       tck;
logic       tms;
logic       tdi;
logic       tdo;

// SoC 信号
logic                       uart_rx, uart_tx;
wire  [GPIO_NUM-1:0]        gpio_io;
wire  [`TIMER_CHANNEL_NUM-1:0] timer_channel_io;
logic                       timer_clk;

// Debug 信号（SoC_top ↔ debug_top）
logic                       dbg_halt_req;
logic                       dbg_halted;
logic                       dbg_resume_req;
logic                       dbg_step;
logic                       dbg_ebreakm;
logic                       dbg_reg_we;
logic [4:0]                 dbg_reg_addr;
logic [31:0]                dbg_reg_wdata;
logic [31:0]                dbg_reg_rdata;
logic [31:0]                dbg_dpc;
logic [31:0]                dbg_pc_wdata;

// SBA 信号（SoC_top ↔ debug_top）
logic                       sba_req_valid;
logic [31:0]                sba_addr;
logic [31:0]                sba_wdata;
logic                       sba_write;
logic [2:0]                 sba_size;
logic [3:0]                 sba_be;
logic                       sba_rsp_valid;
logic [31:0]                sba_rdata;
logic                       sba_error;

// Trigger 信号（SoC_top ↔ debug_top）
logic [`TRIGGER_NUM-1:0]    trigger_en;
logic [`TRIGGER_NUM-1:0]    trigger_exec_en;
logic [`TRIGGER_NUM-1:0]    trigger_load_en;
logic [`TRIGGER_NUM-1:0]    trigger_store_en;
logic [`TRIGGER_NUM*2-1:0]  trigger_size;
logic [`TRIGGER_NUM*32-1:0] trigger_addr;
logic                       trigger_hit;
logic                       ebreak_halt;
// Debug CSR（SoC_top <-> debug_top）
logic                       dbg_csr_we;
logic [11:0]                dbg_csr_addr;
logic [31:0]                dbg_csr_wdata;
logic [31:0]                dbg_csr_rdata;
// ndmreset：调试器复位 SoC
logic                       ndmreset;
// 板级复位门控（同 bd32_board_top）：SoC 域复位 = 全局复位 & ~ndmreset
wire                        soc_rst_n;
assign soc_rst_n = rst_n & ~ndmreset;

// GPIO 浮空上拉
assign gpio_io = {GPIO_NUM{1'bz}};
assign timer_channel_io = {`TIMER_CHANNEL_NUM{1'bz}};

// =========================================================================
// 时钟生成
// =========================================================================
initial sys_clk = 0;
always #(CLK_PERIOD/2) sys_clk = ~sys_clk;

initial tck = 0;
always #(TCK_PERIOD/2) tck = ~tck;

// 1MHz timer clk
initial timer_clk = 0;
always #500 timer_clk = ~timer_clk;

// =========================================================================
// DUT: SoC_top
// =========================================================================
SoC_top #(
    .ITCM_FILE       (`ITCM_FILE       ),
    .DTCM_FILE       (`DTCM_FILE       ),
    .ADDR_WIDTH      (ADDR_WIDTH       ),
    .DATA_WIDTH      (DATA_WIDTH       ),
    .REGFILE_NUM     (REGFILE_NUM      ),
    .REG_ADDR_WIDTH  (REG_ADDR_WIDTH   ),
    .CSR_ADDR_WIDTH  (CSR_ADDR_WIDTH   ),
    .ALIGN_BYTES     (ALIGN_BYTES      ),
    .ALIGN_WIDTH     (ALIGN_WIDTH      ),
    .GPIO_NUM        (GPIO_NUM         ),
    .TIMER_NUM       (`TIMER_NUM       ),
    .TIMER_CHANNEL_NUM (`TIMER_CHANNEL_NUM)
) u_SoC_top (
    .sys_clk          (sys_clk        ),
    .sys_rst_n        (soc_rst_n      ),
    .timer_clk_i      (timer_clk      ),
    .uart_rx          (uart_rx        ),
    .uart_tx          (uart_tx        ),
    .gpio_io          (gpio_io        ),
    .timer_channel_io (timer_channel_io),
    .dbg_halt_req     (dbg_halt_req   ),
    .dbg_halted       (dbg_halted     ),
    .dbg_resume_req   (dbg_resume_req ),
    .dbg_step         (dbg_step       ),
    .dbg_ebreakm      (dbg_ebreakm    ),
    .dbg_reg_we       (dbg_reg_we     ),
    .dbg_reg_addr     (dbg_reg_addr   ),
    .dbg_reg_wdata    (dbg_reg_wdata  ),
    .dbg_reg_rdata    (dbg_reg_rdata  ),
    .dbg_dpc          (dbg_dpc        ),
    .dbg_pc_wdata     (dbg_pc_wdata   ),
    .sba_req_valid    (sba_req_valid  ),
    .sba_addr         (sba_addr       ),
    .sba_wdata        (sba_wdata      ),
    .sba_write        (sba_write      ),
    .sba_size         (sba_size       ),
    .sba_be           (sba_be         ),
    .sba_rsp_valid    (sba_rsp_valid  ),
    .sba_rdata        (sba_rdata      ),
    .sba_error        (sba_error      ),
    .trigger_en       (trigger_en     ),
    .trigger_exec_en    (trigger_exec_en    ),
    .trigger_load_en    (trigger_load_en    ),
    .trigger_store_en   (trigger_store_en   ),
    .trigger_size       (trigger_size       ),
    .trigger_addr     (trigger_addr   ),
    .trigger_hit      (trigger_hit    ),
    .ebreak_halt      (ebreak_halt    ),
    .dbg_csr_we       (dbg_csr_we     ),
    .dbg_csr_addr     (dbg_csr_addr   ),
    .dbg_csr_wdata    (dbg_csr_wdata  ),
    .dbg_csr_rdata    (dbg_csr_rdata  )
);

// =========================================================================
// DUT: debug_top
// =========================================================================
debug_top u_debug_top (
    .clk              (sys_clk        ),
    .rst_n            (rst_n          ),
    .tck              (tck            ),
    .tms              (tms            ),
    .tdi              (tdi            ),
    .tdo              (tdo            ),
    .dbg_reg_we       (dbg_reg_we     ),
    .dbg_reg_addr     (dbg_reg_addr   ),
    .dbg_reg_wdata    (dbg_reg_wdata  ),
    .dbg_reg_rdata    (dbg_reg_rdata  ),
    .dbg_halt_req     (dbg_halt_req   ),
    .dbg_halted       (dbg_halted     ),
    .dbg_resume_req   (dbg_resume_req ),
    .dbg_step         (dbg_step       ),
    .dbg_ebreakm      (dbg_ebreakm    ),
    .dbg_dpc          (dbg_dpc        ),
    .dbg_pc_wdata     (dbg_pc_wdata   ),
    .sba_req_valid    (sba_req_valid  ),
    .sba_addr         (sba_addr       ),
    .sba_wdata        (sba_wdata      ),
    .sba_write        (sba_write      ),
    .sba_size         (sba_size       ),
    .sba_be           (sba_be         ),
    .sba_rsp_valid    (sba_rsp_valid  ),
    .sba_rdata        (sba_rdata      ),
    .sba_error        (sba_error      ),
    .trigger_en       (trigger_en     ),
    .trigger_exec_en    (trigger_exec_en    ),
    .trigger_load_en    (trigger_load_en    ),
    .trigger_store_en   (trigger_store_en   ),
    .trigger_size       (trigger_size       ),
    .trigger_addr     (trigger_addr   ),
    .trigger_hit      (trigger_hit    ),
    .ebreak_halt      (ebreak_halt    ),
    .dbg_csr_we       (dbg_csr_we     ),
    .dbg_csr_addr     (dbg_csr_addr   ),
    .dbg_csr_wdata    (dbg_csr_wdata  ),
    .dbg_csr_rdata    (dbg_csr_rdata  ),
    .ndmreset         (ndmreset       )
);

// =========================================================================
// JTAG BFM Tasks
// =========================================================================

// 单个 TCK 周期
task jtag_tick(input logic tms_val, input logic tdi_val);
    @(negedge tck);
    tms = tms_val;
    tdi = tdi_val;
    @(posedge tck);
    #1;
endtask

// TAP 复位：TMS=1 持续 5 个 TCK → Test-Logic-Reset
task jtag_reset;
    integer i;
    for (i = 0; i < 6; i = i + 1)
        jtag_tick(1'b1, 1'b0);
    // 进入 Run-Test/Idle
    jtag_tick(1'b0, 1'b0);
endtask

// 从 Run-Test/Idle 进入 Shift-IR
task enter_shift_ir;
    jtag_tick(1'b1, 1'b0);  // Select-DR-Scan
    jtag_tick(1'b1, 1'b0);  // Select-IR-Scan
    jtag_tick(1'b0, 1'b0);  // Capture-IR
    jtag_tick(1'b0, 1'b0);  // Shift-IR
endtask

// 从 Run-Test/Idle 进入 Shift-DR
task enter_shift_dr;
    jtag_tick(1'b1, 1'b0);  // Select-DR-Scan
    jtag_tick(1'b0, 1'b0);  // Capture-DR
    jtag_tick(1'b0, 1'b0);  // Shift-DR
endtask

// 退出 Shift 状态 → Run-Test/Idle
task exit_to_idle;
    jtag_tick(1'b1, 1'b0);  // Exit1-xR
    jtag_tick(1'b0, 1'b0);  // Run-Test/Idle
endtask

// 移入 IR（5 bit），LSB first
task shift_ir(input logic [4:0] ir_val);
    integer i;
    enter_shift_ir;
    for (i = 0; i < 5; i = i + 1) begin
        if (i == 4)
            jtag_tick(1'b1, ir_val[i]);  // 最后一位 TMS=1 → Exit1-IR
        else
            jtag_tick(1'b0, ir_val[i]);
    end
    // Update-IR → Run-Test/Idle
    jtag_tick(1'b1, 1'b0);  // Update-IR
    jtag_tick(1'b0, 1'b0);  // Run-Test/Idle
endtask

// 移入/移出 DR（N bit），LSB first，返回 TDO 捕获值
task shift_dr(input int num_bits, input logic [DMI_BITS-1:0] data_in,
              output logic [DMI_BITS-1:0] data_out);
    integer i;
    data_out = '0;
    enter_shift_dr;
    for (i = 0; i < num_bits; i = i + 1) begin
        if (i == num_bits - 1)
            jtag_tick(1'b1, data_in[i]);  // 最后位 TMS=1 → Exit1-DR
        else
            jtag_tick(1'b0, data_in[i]);
        data_out[i] = tdo;
    end
    // Update-DR → Run-Test/Idle
    jtag_tick(1'b1, 1'b0);  // Update-DR
    jtag_tick(1'b0, 1'b0);  // Run-Test/Idle
endtask

// 等待 N 个 TCK（Run-Test/Idle 状态）
task jtag_idle(input int n);
    integer i;
    for (i = 0; i < n; i = i + 1)
        jtag_tick(1'b0, 1'b0);
endtask

// =========================================================================
// DMI 操作封装
// =========================================================================
// DMI DR 格式: {addr[5:0], data[31:0], op[1:0]} = 40 bits

// 写 DMI
task dmi_write(input logic [5:0] addr, input logic [31:0] data);
    logic [DMI_BITS-1:0] dr_in, dr_out;
    dr_in = {addr, data, 2'b10};  // op=WRITE
    shift_ir(IR_DMI);
    shift_dr(DMI_BITS, dr_in, dr_out);
    jtag_idle(5);  // 等待 CDC 完成
endtask

// 读 DMI（第一次发 READ 请求，第二次 NOP 取回结果）
task dmi_read(input logic [5:0] addr, output logic [31:0] data);
    logic [DMI_BITS-1:0] dr_in, dr_out;
    // 第一次：发送 READ 请求
    dr_in = {addr, 32'b0, 2'b01};  // op=READ
    shift_ir(IR_DMI);
    shift_dr(DMI_BITS, dr_in, dr_out);
    jtag_idle(10);  // 等待 CDC + DM 处理
    // 第二次：NOP 取回响应
    dr_in = {6'b0, 32'b0, 2'b00};  // op=NOP
    shift_dr(DMI_BITS, dr_in, dr_out);
    data = dr_out[DMI_OP_BITS + DMI_DATA_BITS - 1 : DMI_OP_BITS];
    jtag_idle(5);
endtask

// =========================================================================
// 测试主流程
// =========================================================================
integer pass_cnt, fail_cnt;
logic [31:0] rd_data;

task check(input string name, input logic [31:0] actual, input logic [31:0] expected);
    if (actual === expected) begin
        $display("[PASS] %s: 0x%08h", name, actual);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL] %s: got 0x%08h, expect 0x%08h", name, actual, expected);
        fail_cnt = fail_cnt + 1;
    end
endtask






initial begin
    // 初始化
    rst_n = 0;
    tms   = 1;
    tdi   = 0;
    uart_rx = 1;
    pass_cnt = 0;
    fail_cnt = 0;

    // 复位
    #(CLK_PERIOD * 20);
    rst_n = 1;
    #(CLK_PERIOD * 100);  // 等 CPU 跑几条指令

    $display("\n========== BD32 Debug Module Test ==========\n");

    // ----------------------------------------------------------
    // Test 1: JTAG Reset + Read IDCODE
    // ----------------------------------------------------------
    $display("--- Test 1: IDCODE ---");
    jtag_reset;
    shift_ir(IR_IDCODE);
    shift_dr(32, {DMI_BITS{1'b0}}, rd_data);
    check("IDCODE", rd_data[31:0], 32'h1BD32_003);

    // ----------------------------------------------------------
    // Test 2: 配置 DTMCS（清 sticky，设 idle=0）
    // ----------------------------------------------------------
    $display("--- Test 2: DTMCS ---");
    shift_ir(IR_DTMCS);
    // DTMCS: {14'b0, dmihardreset, dmireset, idle[2:0], abits[5:0], version[3:0]}
    // 写 dmireset=1 清除 sticky
    shift_dr(32, {14'b0, 1'b0, 1'b1, 3'b0, 6'b0, 4'b0}, rd_data);
    jtag_idle(5);

    // ----------------------------------------------------------
    // Test 3: Halt CPU
    // ----------------------------------------------------------
    $display("--- Test 3: Halt ---");
    // dmcontrol: haltreq(bit31)=1, dmactive(bit0)=1
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    // 等待 CPU halt（OITF 排空需要几个周期）
    #(CLK_PERIOD * 50);

    dmi_read(ADDR_DMSTATUS, rd_data);
    check("dmstatus.allhalted", rd_data[9], 1'b1);
    check("dmstatus.anyhalted", rd_data[8], 1'b1);

    // ----------------------------------------------------------
    // Test 4: 写 GPR x1 = 0xDEAD_BEEF
    // ----------------------------------------------------------
    $display("--- Test 4: Write GPR x1 ---");
    // 先写 data0
    dmi_write(ADDR_DATA0, 32'hDEAD_BEEF);
    // Abstract Command: cmdtype=0, aarsize=2(32b), transfer=1, write=1, regno=0x1001
    // [31:24]=0, [23]=0, [22:20]=010, [19:18]=0, [17]=1, [16]=1, [15:0]=0x1001
    dmi_write(ADDR_COMMAND, 32'h0023_1001);
    jtag_idle(10);
    // 检查 cmderr
    dmi_read(ADDR_ABSTRACTCS, rd_data);
    check("abstractcs.cmderr", rd_data[10:8], 3'b0);

    // ----------------------------------------------------------
    // Test 5: 读回 GPR x1
    // ----------------------------------------------------------
    $display("--- Test 5: Read GPR x1 ---");
    // Abstract Command: transfer=1, write=0, regno=0x1001
    dmi_write(ADDR_COMMAND, 32'h0022_1001);
    jtag_idle(10);
    // 读 data0
    dmi_read(ADDR_DATA0, rd_data);
    check("x1 readback", rd_data, 32'hDEAD_BEEF);

    // ----------------------------------------------------------
    // Test 5b: CSR 读/写（abstract 通用 CSR 通道）
    // ----------------------------------------------------------
    $display("--- Test 5b: CSR read/write ---");
    // 读 misa：regno=0xC301（0.13 编码）
    dmi_write(ADDR_COMMAND, 32'h0022_C301);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("misa readback", rd_data, 32'h4000_1100);
    // 写 mtvec = 0x1234_5000 再读回
    dmi_write(ADDR_DATA0, 32'h1234_5000);
    dmi_write(ADDR_COMMAND, 32'h0023_C305);
    jtag_idle(10);
    dmi_write(ADDR_COMMAND, 32'h0022_C305);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("mtvec write/readback", rd_data, 32'h1234_5000);
    // 1.0 编码直读 mstatus：regno=0x300
    dmi_write(ADDR_COMMAND, 32'h0022_0300);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("mstatus readback (1.0 enc)", rd_data, 32'h0000_1800);

    // ----------------------------------------------------------
    // Test 6: 读 dpc（应为当前 halted PC）
    // ----------------------------------------------------------
    $display("--- Test 6: Read dpc ---");
    // Abstract Command: transfer=1, write=0, regno=0x7B1 (dpc)
    dmi_write(ADDR_COMMAND, 32'h0022_07B1);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    $display("[INFO] dpc = 0x%08h", rd_data);
    // dpc 应该在 ITCM 范围内 (0x0001_0000 ~ 0x0001_FFFF)
    if (rd_data[31:16] == 16'h0001) begin
        $display("[PASS] dpc in ITCM range");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("[FAIL] dpc out of ITCM range: 0x%08h", rd_data);
        fail_cnt = fail_cnt + 1;
    end

    // ----------------------------------------------------------
    // Test 7: Resume CPU
    // ----------------------------------------------------------
    $display("--- Test 7: Resume ---");
    // dmcontrol: resumereq(bit30)=1, dmactive(bit0)=1
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
    #(CLK_PERIOD * 20);

    dmi_read(ADDR_DMSTATUS, rd_data);
    check("dmstatus.allrunning", rd_data[11], 1'b1);

    // ----------------------------------------------------------
    // Test 8: SBA 写 DTCM
    // ----------------------------------------------------------
    $display("--- Test 8: SBA Write DTCM ---");
    // 先 halt
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 50);
    // 配置 sbcs: sbaccess=010(32-bit), 其余默认
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    // 写地址 0x0002_0000
    dmi_write(ADDR_SBADDRESS0, 32'h0002_0000);
    // 写数据（触发 SBA write）
    dmi_write(ADDR_SBDATA0, 32'hCAFE_BABE);
    #(CLK_PERIOD * 10);  // 等 SBA 完成
    // 检查 sbcs.sbbusy 已清、无错误
    dmi_read(ADDR_SBCS, rd_data);
    check("sbcs.sbbusy after write", rd_data[21], 1'b0);
    check("sbcs.sberror after write", rd_data[14:12], 3'b0);

    // ----------------------------------------------------------
    // Test 9: SBA 读 DTCM
    // ----------------------------------------------------------
    $display("--- Test 9: SBA Read DTCM ---");
    // 配置 sbcs: sbreadonaddr=1, sbaccess=010
    dmi_write(ADDR_SBCS, 32'h0014_0000);
    // 写地址（触发 SBA read）
    dmi_write(ADDR_SBADDRESS0, 32'h0002_0000);
    #(CLK_PERIOD * 10);  // 等 SBA 完成
    // 读 sbdata0
    dmi_read(ADDR_SBDATA0, rd_data);
    check("SBA DTCM readback", rd_data, 32'hCAFE_BABE);

    // ----------------------------------------------------------
    // Test 10: SBA 写 ITCM
    // ----------------------------------------------------------
    $display("--- Test 10: SBA Write ITCM ---");
    dmi_write(ADDR_SBCS, 32'h0004_0000);  // sbreadonaddr=0
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0100);
    dmi_write(ADDR_SBDATA0, 32'h1234_5678);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBCS, rd_data);
    check("sbcs.sbbusy after ITCM write", rd_data[21], 1'b0);

    // ----------------------------------------------------------
    // Test 11: SBA 读 ITCM
    // ----------------------------------------------------------
    $display("--- Test 11: SBA Read ITCM ---");
    dmi_write(ADDR_SBCS, 32'h0014_0000);  // sbreadonaddr=1
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0100);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("SBA ITCM readback", rd_data, 32'h1234_5678);

    // ----------------------------------------------------------
    // Test 12: Single-step (dcsr.step)
    // ----------------------------------------------------------
    $display("--- Test 12: Single-step ---");
    // CPU 当前已 halt（SBA 测试后）
    // 用 SBA 写一条指令到 ITCM 0x0001_0200: addi x1, x0, 42 = 0x02A00093
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    dmi_write(ADDR_SBDATA0, 32'h02A0_0093);
    #(CLK_PERIOD * 10);
    // 第二条: addi x2, x0, 99 = 0x06300113
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0204);
    dmi_write(ADDR_SBDATA0, 32'h0630_0113);
    #(CLK_PERIOD * 10);

    // 验证 ITCM 写入正确
    dmi_write(ADDR_SBCS, 32'h0014_0000);  // sbreadonaddr=1
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("ITCM verify @0x10200", rd_data, 32'h02A0_0093);

    // 写 dpc = 0x0001_0200
    dmi_write(ADDR_DATA0, 32'h0001_0200);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1);  // write dpc
    jtag_idle(10);

    // 写 dcsr: step=1 (bit2)
    dmi_write(ADDR_DATA0, 32'h0000_0004);
    dmi_write(ADDR_COMMAND, 32'h0023_07B0);  // write dcsr
    jtag_idle(10);

    // Resume（带 step）
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
    #(CLK_PERIOD * 50);  // 等 step 完成

    // 检查 CPU 重新 halt
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("step: dmstatus.allhalted", rd_data[9], 1'b1);

    // 读 dpc：应为 0x0001_0204（+4）
    dmi_write(ADDR_COMMAND, 32'h0022_07B1);  // read dpc
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("step: dpc advanced", rd_data, 32'h0001_0204);

    // 读 x1：应为 42
    dmi_write(ADDR_COMMAND, 32'h0022_1001);  // read x1
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("step: x1 = 42", rd_data, 32'd42);

    // 再 step 一次（执行第二条指令）
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("step2: dmstatus.allhalted", rd_data[9], 1'b1);

    // 读 x2：应为 99
    dmi_write(ADDR_COMMAND, 32'h0022_1002);  // read x2
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("step2: x2 = 99", rd_data, 32'd99);

    // 再读 x1（看 step1 的写入是否延迟生效）
    dmi_write(ADDR_COMMAND, 32'h0022_1001);  // read x1
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    $display("[INFO] x1 after step2 = 0x%08h", rd_data);

    // 清 dcsr.step（恢复正常模式）
    dmi_write(ADDR_DATA0, 32'h0000_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07B0);  // write dcsr, step=0
    jtag_idle(10);

    // ----------------------------------------------------------
    // Test 12b: Single-step over a taken jump (JAL)
    //   Regression: after stepping a jump, dpc must point to the
    //   jump target. OpenOCD's watchpoint dance (disable triggers ->
    //   step -> enable triggers) steps the current PC on hw-bp
    //   continue; if that instruction is JAL/JALR/branch the
    //   STEP_DRAIN phase must let the branch redirect take effect,
    //   otherwise the resumed PC is wrong (X+4 into a gap).
    // ----------------------------------------------------------
    $display("--- Test 12b: Single-step over JAL ---");
    // halt CPU
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 50);
    // ITCM 0x10200: jal x0, +0x10 = 0x0100006F (jump to 0x10210)
    dmi_write(ADDR_SBCS, 32'h0004_0000);  // sbaccess=32b, no readonaddr
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    dmi_write(ADDR_SBDATA0, 32'h0100_006F);
    #(CLK_PERIOD * 10);
    // ITCM 0x10210: nop = 0x00000013
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0210);
    dmi_write(ADDR_SBDATA0, 32'h0000_0013);
    #(CLK_PERIOD * 10);
    // dpc = 0x10200
    dmi_write(ADDR_DATA0, 32'h0001_0200);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1);  // write dpc
    jtag_idle(10);
    // dcsr.step = 1
    dmi_write(ADDR_DATA0, 32'h0000_0004);
    dmi_write(ADDR_COMMAND, 32'h0023_07B0);  // write dcsr
    jtag_idle(10);
    // resume (step)
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
    #(CLK_PERIOD * 50);
    // CPU should halt
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("step-jal: dmstatus.allhalted", rd_data[9], 1'b1);
    // dpc should point to jump target 0x10210
    dmi_write(ADDR_COMMAND, 32'h0022_07B1);  // read dpc
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("step-jal: dpc = jump target", rd_data, 32'h0001_0210);
    // clear step, back to normal mode
    dmi_write(ADDR_DATA0, 32'h0000_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07B0);  // write dcsr, step=0
    jtag_idle(10);
    // resume running (for later tests)
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
    #(CLK_PERIOD * 20);
    // ----------------------------------------------------------
    // Test 12c: Single-step over a trapping instruction
    //   Regression: stepping an instruction that traps (ecall /
    //   illegal) or mret must end with dpc at the trap target
    //   (mtvec / mepc), not X+4. STEP_DRAIN must let the exception/
    //   mret redirect take effect; interrupts stay excluded until
    //   after resume (dcsr.stepie=0 behavior).
    // ----------------------------------------------------------
    $display("--- Test 12c: Single-step over trap/mret ---");
    // reset halt first: Test 12b resumes into leftover ITCM contents,
    // so the CPU may be running/trapped with IF at an invalid address.
    // A pending IF access fault would suppress debug CSR writes.
    dmi_write(ADDR_DMCONTROL, 32'h8000_0003);  // haltreq + ndmreset
    #(CLK_PERIOD * 30);
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);  // release ndmreset, keep haltreq
    #(CLK_PERIOD * 200);
    // mtvec = 0x10210 (trap target)
    dmi_write(ADDR_DATA0, 32'h0001_0210);
    dmi_write(ADDR_COMMAND, 32'h0023_C305);  // write mtvec
    jtag_idle(10);
    // ITCM 0x10210: nop (handler landing pad)
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0210);
    dmi_write(ADDR_SBDATA0, 32'h0000_0013);
    #(CLK_PERIOD * 10);

    // 1) ecall @0x10200: after step, dpc=mtvec, mcause=11, mepc=0x10200
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    dmi_write(ADDR_SBDATA0, 32'h0000_0073);  // ecall
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_DATA0, 32'h0001_0200);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1);  // write dpc
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h0000_0004);
    dmi_write(ADDR_COMMAND, 32'h0023_07B0);  // write dcsr, step=1
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);  // resume (step)
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("step-ecall: dmstatus.allhalted", rd_data[9], 1'b1);
    dmi_write(ADDR_COMMAND, 32'h0022_07B1);  // read dpc
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("step-ecall: dpc = mtvec", rd_data, 32'h0001_0210);
    dmi_write(ADDR_COMMAND, 32'h0022_C342);  // read mcause
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("step-ecall: mcause=11", rd_data, 32'h0000_000B);
    dmi_write(ADDR_COMMAND, 32'h0022_C341);  // read mepc
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("step-ecall: mepc=0x10200", rd_data, 32'h0001_0200);

    // 2) illegal @0x10200: after step, dpc=mtvec, mcause=2
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    dmi_write(ADDR_SBDATA0, 32'hFFFF_FFFF);  // illegal encoding
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_DATA0, 32'h0001_0200);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1);  // write dpc
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);  // resume (step)
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("step-illegal: dmstatus.allhalted", rd_data[9], 1'b1);
    dmi_write(ADDR_COMMAND, 32'h0022_07B1);  // read dpc
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("step-illegal: dpc = mtvec", rd_data, 32'h0001_0210);
    dmi_write(ADDR_COMMAND, 32'h0022_C342);  // read mcause
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("step-illegal: mcause=2", rd_data, 32'h0000_0002);

    // 3) mret @0x10200 with mepc=0x10214: after step, dpc=mepc
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    dmi_write(ADDR_SBDATA0, 32'h3020_0073);  // mret
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0214);
    dmi_write(ADDR_SBDATA0, 32'h0000_0013);  // nop @0x10214
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_DATA0, 32'h0001_0214);
    dmi_write(ADDR_COMMAND, 32'h0023_C341);  // write mepc = 0x10214
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h0001_0200);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1);  // write dpc
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);  // resume (step)
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("step-mret: dmstatus.allhalted", rd_data[9], 1'b1);
    dmi_write(ADDR_COMMAND, 32'h0022_07B1);  // read dpc
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("step-mret: dpc = mepc", rd_data, 32'h0001_0214);

    // cleanup: dcsr.step=0, restore addi x1,42 @0x10200, resume
    dmi_write(ADDR_DATA0, 32'h0000_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07B0);  // write dcsr, step=0
    jtag_idle(10);
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    dmi_write(ADDR_SBDATA0, 32'h02A0_0093);  // addi x1,x0,42
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);  // resume
    #(CLK_PERIOD * 20);


    // ----------------------------------------------------------
    // Test 13: reset halt（ndmreset + haltreq 驻留 → 停在复位向量 0x0）
    // ----------------------------------------------------------
    $display("--- Test 13: Reset halt ---");
    // CPU 当前 running（Test 12 最终 resume 后）
    // dmcontrol: haltreq(31)=1, ndmreset(1)=1, dmactive(0)=1
    dmi_write(ADDR_DMCONTROL, 32'h8000_0003);
    #(CLK_PERIOD * 30);   // ndmreset 保持，CPU 复位
    // 释放 ndmreset，haltreq 保持驻留
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 200);  // 等 PC 收敛 + dpc 捕获
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("reset halt: dmstatus.allhalted", rd_data[9], 1'b1);
    // 读 dpc：应为复位向量（DIRECT_LOAD=ITCM 0x10000；板级 XILINX=BOOT 0x0）
    dmi_write(ADDR_COMMAND, 32'h0022_07B1);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
`ifdef DIRECT_LOAD
    check("reset halt: dpc = ITCM reset vector", rd_data,
          {`ITCM_BASE_TAG, {(ADDR_WIDTH-`DEVICE_TAG_WIDTH){1'b0}}});
`else
    check("reset halt: dpc = BOOT reset vector", rd_data,
          {`BOOT_BASE_TAG, {(ADDR_WIDTH-`DEVICE_TAG_WIDTH){1'b0}}});
`endif

    // ----------------------------------------------------------
    // Test 14: reset halt 后写 dpc 并 resume（验证取指从新 dpc 开始）
    // ----------------------------------------------------------
    $display("--- Test 14: reset halt -> set dpc -> resume ---");
    // SBA 写 0x10200: addi x1, x0, 42 = 0x02A00093；0x10204: NOP
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    dmi_write(ADDR_SBDATA0, 32'h02A0_0093);
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0204);
    dmi_write(ADDR_SBDATA0, 32'h0000_0013);
    #(CLK_PERIOD * 10);
    // 写 dpc = 0x10200
    dmi_write(ADDR_DATA0, 32'h0001_0200);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1);
    jtag_idle(10);
    // 变体 A：普通 resume（resumereq + dmactive，无 step 冲刷）
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("reset-halt plain resume: allrunning", rd_data[11], 1'b1);
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 50);
    dmi_write(ADDR_COMMAND, 32'h0022_1001);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("reset-halt plain resume: x1 = 42", rd_data, 32'd42);

    // 变体 B：带 step（dcsr.step=1，resume 时冲刷 IF-ID/ID-EX）
    dmi_write(ADDR_DATA0, 32'h0000_0004);
    dmi_write(ADDR_COMMAND, 32'h0023_07B0);  // dcsr.step=1
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h0001_0200);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1);  // dpc=0x10200
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("reset-halt step resume: allhalted", rd_data[9], 1'b1);
    dmi_write(ADDR_COMMAND, 32'h0022_1001);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("reset-halt step resume: x1 = 42", rd_data, 32'd42);

    // 变体 C：普通 halt（非 reset）后设 dpc 普通 resume（对照）
    dmi_write(ADDR_DATA0, 32'h0000_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07B0);  // dcsr.step=0
    jtag_idle(10);
    // 先 resume 跑一会再 halt，模拟普通 halt
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
    #(CLK_PERIOD * 20);
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);  // haltreq
    #(CLK_PERIOD * 50);
    dmi_write(ADDR_DATA0, 32'h0001_0200);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1);  // dpc=0x10200
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);  // 普通 resume
    #(CLK_PERIOD * 50);
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 50);
    dmi_write(ADDR_COMMAND, 32'h0022_1001);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("normal-halt plain resume: x1 = 42", rd_data, 32'd42);

    // ----------------------------------------------------------
    // Test 15: Trigger halt 锁存（清 trigger 后 CPU 应保持 halt）
    // ----------------------------------------------------------
    $display("--- Test 15: Trigger halt latch ---");
    // 0x10200: addi x1,42; 0x10204: NOP（Test 14 已写入）
    dmi_write(ADDR_DATA0, 32'h2800_0004);
    dmi_write(ADDR_COMMAND, 32'h0023_07A1);  // write tdata1（type2+execute）
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h0001_0204);
    dmi_write(ADDR_COMMAND, 32'h0023_07A2);  // write tdata2=0x10204
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h0001_0200);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1);  // dpc=0x10200
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);  // resume → 命中 0x10204 → halt
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("trigger halt: allhalted", rd_data[9], 1'b1);
    // 清 trigger（tdata1=0）：锁存后 CPU 应保持 halt
    dmi_write(ADDR_DATA0, 32'h2800_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A1);
    jtag_idle(10);
    #(CLK_PERIOD * 20);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("trigger cleared: still allhalted", rd_data[9], 1'b1);
    // resume → 恢复运行
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
    #(CLK_PERIOD * 20);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("after resume: allrunning", rd_data[11], 1'b1);
    // 恢复 halt，等待结束
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 50);

    // ----------------------------------------------------------
    // Test 16: ebreak 进调试模式（ebreakm=1 → halt，dcsr.cause=1，dpc=ebreak 地址）
    // ----------------------------------------------------------
    $display("--- Test 16: ebreak enters debug mode ---");
    // 1) dcsr.ebreakm=1
    dmi_write(ADDR_DATA0, 32'h0000_8000);
    dmi_write(ADDR_COMMAND, 32'h0023_07B0);  // write dcsr
    jtag_idle(10);
    // 2) SBA 把 0x10200 改成 ebreak
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    dmi_write(ADDR_SBDATA0, 32'h0010_0073);  // ebreak
    #(CLK_PERIOD * 10);
    // 3) dpc = 0x10200，resume → 执行 ebreak → halt
    dmi_write(ADDR_DATA0, 32'h0001_0200);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1);  // dpc=0x10200
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);  // resume
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("ebreak halt: allhalted", rd_data[9], 1'b1);
    // 4) dcsr.cause = 1 (ebreak)
    dmi_write(ADDR_COMMAND, 32'h0022_07B0);  // read dcsr
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("ebreak halt: dcsr.cause=1", rd_data[8:6], 3'd1);
    // 5) dpc = 0x10200（ebreak 指令自身地址）
    dmi_write(ADDR_COMMAND, 32'h0022_07B1);  // read dpc
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("ebreak halt: dpc=0x10200", rd_data, 32'h0001_0200);
    // 6) 锁存验证：清 dcsr.ebreakm 后 CPU 应保持 halt
    dmi_write(ADDR_DATA0, 32'h0000_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07B0);  // write dcsr (ebreakm=0)
    jtag_idle(10);
    #(CLK_PERIOD * 20);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("ebreak latch: still allhalted", rd_data[9], 1'b1);
    // 7) 恢复原指令并 resume：CPU 从 dpc 执行 addi x1,42
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    dmi_write(ADDR_SBDATA0, 32'h02A0_0093);  // addi x1,x0,42
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);  // resume
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("ebreak resume: allrunning", rd_data[11], 1'b1);
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);  // halt
    #(CLK_PERIOD * 50);
    dmi_write(ADDR_COMMAND, 32'h0022_1001);  // read x1
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("ebreak resume: x1 = 42", rd_data, 32'd42);
    // 恢复 halt，等待结束
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 50);

    // ----------------------------------------------------------
    // Test 17: 多硬件断点（TRIGGER_NUM=4，tselect 选择）
    // ----------------------------------------------------------
    $display("--- Test 17: multi-trigger ---");
    // 补程序：0x10200 addi x1,42; 0x10204 NOP; 0x10208 addi x2,99; 0x1020C NOP
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0208);
    dmi_write(ADDR_SBDATA0, 32'h0630_0113);  // addi x2,x0,99
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_020C);
    dmi_write(ADDR_SBDATA0, 32'h0000_0013);  // NOP
    #(CLK_PERIOD * 10);
    // trigger0 → 0x10204
    dmi_write(ADDR_DATA0, 32'h0000_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A0);  // tselect=0
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h2800_0004);
    dmi_write(ADDR_COMMAND, 32'h0023_07A1);  // tdata1 (type2+execute)
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h0001_0204);
    dmi_write(ADDR_COMMAND, 32'h0023_07A2);  // tdata2=0x10204
    jtag_idle(10);
    // trigger1 → 0x10208
    dmi_write(ADDR_DATA0, 32'h0000_0001);
    dmi_write(ADDR_COMMAND, 32'h0023_07A0);  // tselect=1
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h2800_0004);
    dmi_write(ADDR_COMMAND, 32'h0023_07A1);  // tdata1
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h0001_0208);
    dmi_write(ADDR_COMMAND, 32'h0023_07A2);  // tdata2=0x10208
    jtag_idle(10);
    // 读 tselect 应返回 1
    dmi_write(ADDR_COMMAND, 32'h0022_07A0);  // read tselect
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("tselect readback = 1", rd_data, 32'd1);
    // dpc=0x10200，resume → 先命中 trigger0 (0x10204)
    dmi_write(ADDR_DATA0, 32'h0001_0200);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1);  // dpc
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);  // resume
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("trig0 halt: allhalted", rd_data[9], 1'b1);
    dmi_write(ADDR_COMMAND, 32'h0022_07B0);  // read dcsr
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("trig0 halt: dcsr.cause=2", rd_data[8:6], 3'd2);
    dmi_write(ADDR_COMMAND, 32'h0022_07B1);  // read dpc
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("trig0 halt: dpc=0x10204", rd_data, 32'h0001_0204);
    // 清 trigger0，resume → 命中 trigger1 (0x10208)
    dmi_write(ADDR_DATA0, 32'h0000_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A0);  // tselect=0
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h2800_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A1);  // 清 tdata1
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h0001_0204);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1);  // dpc=0x10204
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);  // resume
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("trig1 halt: allhalted", rd_data[9], 1'b1);
    dmi_write(ADDR_COMMAND, 32'h0022_07B1);  // read dpc
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("trig1 halt: dpc=0x10208", rd_data, 32'h0001_0208);
    // 清 trigger1，resume 跑完
    dmi_write(ADDR_DATA0, 32'h0000_0001);
    dmi_write(ADDR_COMMAND, 32'h0023_07A0);  // tselect=1
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h2800_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A1);  // 清 tdata1
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);  // resume
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("trig cleared: allrunning", rd_data[11], 1'b1);
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);  // halt
    #(CLK_PERIOD * 50);
    dmi_write(ADDR_COMMAND, 32'h0022_1001);  // read x1
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("multi-trigger: x1 = 42", rd_data, 32'd42);
    dmi_write(ADDR_COMMAND, 32'h0022_1002);  // read x2
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("multi-trigger: x2 = 99", rd_data, 32'd99);
    // 恢复 halt，等待结束
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 50);

    // ----------------------------------------------------------
    // Test 18: SBA 字节/半字写（RMW 合并）
    // ----------------------------------------------------------
    $display("--- Test 18: SBA byte/halfword write ---");
    // 0x10200 当前 = 0x02A00093 (addi x1,42)
    // 1) 字节写 0x10201 = 0xAA → word = 0x02A0AA93
    dmi_write(ADDR_SBCS, 32'h0000_0000);  // sbaccess=0 (8-bit)
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0201);
    dmi_write(ADDR_SBDATA0, 32'h0000_00AA);
    #(CLK_PERIOD * 20);
    dmi_write(ADDR_SBCS, 32'h0014_0000);  // sbreadonaddr=1, sbaccess=2
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("SBA byte write @0x10201", rd_data, 32'h02A0_AA93);
    // 2) 半字写 0x10202 = 0x1234 → word = 0x1234AA93
    dmi_write(ADDR_SBCS, 32'h0002_0000);  // sbaccess=1 (16-bit)
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0202);
    dmi_write(ADDR_SBDATA0, 32'h0000_1234);
    #(CLK_PERIOD * 20);
    dmi_write(ADDR_SBCS, 32'h0014_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("SBA halfword write @0x10202", rd_data, 32'h1234_AA93);
    // 3) DTCM：全字写 0x00020000=0xCAFEBABE，再字节写 0x00020003=0x11
    dmi_write(ADDR_SBCS, 32'h0004_0000);  // sbaccess=2
    dmi_write(ADDR_SBADDRESS0, 32'h0002_0000);
    dmi_write(ADDR_SBDATA0, 32'hCAFE_BABE);
    #(CLK_PERIOD * 20);
    dmi_write(ADDR_SBCS, 32'h0000_0000);  // sbaccess=0
    dmi_write(ADDR_SBADDRESS0, 32'h0002_0003);
    dmi_write(ADDR_SBDATA0, 32'h0000_0011);
    #(CLK_PERIOD * 20);
    dmi_write(ADDR_SBCS, 32'h0014_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0002_0000);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("SBA DTCM byte write @0x00020003", rd_data, 32'h11FE_BABE);
    // 4) 恢复 0x10200 内容（addi x1,42）
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    dmi_write(ADDR_SBDATA0, 32'h02A0_0093);
    #(CLK_PERIOD * 20);
    // 恢复 halt，等待结束
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 50);

    // ----------------------------------------------------------
    // Test 19: SBA 访问外设总线（APB GPIO 0xE000_0000）
    // ----------------------------------------------------------
    $display("--- Test 19: SBA peripheral bus access ---");
    // 1) GPIO OUTPUT (0xE000_0008) 全字写读回
    dmi_write(ADDR_SBCS, 32'h0004_0000);  // sbaccess=2
    dmi_write(ADDR_SBADDRESS0, 32'hE000_0008);
    dmi_write(ADDR_SBDATA0, 32'hA5A5_A5A5);
    #(CLK_PERIOD * 50);  // 等总线完成
    dmi_write(ADDR_SBCS, 32'h0014_0000);  // sbreadonaddr=1
    dmi_write(ADDR_SBADDRESS0, 32'hE000_0008);
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("SBA GPIO word write/read", rd_data, 32'hA5A5_A5A5);
    // 2) 字节写 0xE000_0009=0x11 → 0xA5A511A5（byte1 = bits 15:8）
    dmi_write(ADDR_SBCS, 32'h0000_0000);  // sbaccess=0
    dmi_write(ADDR_SBADDRESS0, 32'hE000_0009);
    dmi_write(ADDR_SBDATA0, 32'h0000_0011);
    #(CLK_PERIOD * 50);
    dmi_write(ADDR_SBCS, 32'h0014_0000);
    dmi_write(ADDR_SBADDRESS0, 32'hE000_0008);
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("SBA GPIO byte write", rd_data, 32'hA5A5_11A5);
    // 3) 读 GPIO INPUT（仿真浮空→0）
    dmi_write(ADDR_SBADDRESS0, 32'hE000_000C);
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("SBA GPIO input read", rd_data, 32'h0);
    // 4) 未映射地址 → sberror
    dmi_write(ADDR_SBCS, 32'h0014_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h1234_5678);
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_SBCS, rd_data);
    check("SBA unmapped: sberror set", rd_data[14:12], 3'b010);
    // W1C 清 sberror：Debug Spec 1.0 要求错误非零时禁止发起新 SBA 访问，
    // 后续测试需要干净的错误状态
    dmi_write(ADDR_SBCS, 32'h0004_7000);   // sbaccess=2 + W1C sberror
    dmi_read(ADDR_SBCS, rd_data);
    check("SBA unmapped: sberror cleared", rd_data[14:12], 3'b0);
    // 5) 总线访问期间 halt 状态保持
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("SBA bus access: still allhalted", rd_data[9], 1'b1);
    // 恢复 halt，等待结束
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 50);

    // ----------------------------------------------------------
    // Test 20: 数据观察点（watchpoint：load/store 地址匹配）
    // ----------------------------------------------------------
    $display("--- Test 20: watchpoint ---");
    // 程序布局（ITCM）：
    //   0x10200 addi x1,x0,42    0x02A00093
    //   0x10204 lui  x2,0x20     0x00020137  -> x2 = 0x00020000
    //   0x10208 sw   x1,0(x2)    0x00112023  （写观察点目标）
    //   0x1020C nop              0x00000013
    //   0x10210 lw   x3,0(x2)    0x00012183  （读观察点目标）
    //   0x10214 sb   x1,0(x2)    0x00110023  （宽度过滤测试）
    //   0x10218 nop              0x00000013
    //   0x1021C jal  x0,self     0x000000EF  （安全自旋，防跑到未知区域）
    dmi_write(ADDR_SBCS, 32'h0004_0000);  // sbaccess=2
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    dmi_write(ADDR_SBDATA0, 32'h02A0_0093);
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0204);
    dmi_write(ADDR_SBDATA0, 32'h0002_0137);
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0208);
    dmi_write(ADDR_SBDATA0, 32'h0011_2023);
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_020C);
    dmi_write(ADDR_SBDATA0, 32'h0000_0013);
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0210);
    dmi_write(ADDR_SBDATA0, 32'h0001_2183);
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0214);
    dmi_write(ADDR_SBDATA0, 32'h0011_0023);
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0218);
    dmi_write(ADDR_SBDATA0, 32'h0000_0013);
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_021C);
    dmi_write(ADDR_SBDATA0, 32'h0000_00EF);
    #(CLK_PERIOD * 10);
    // 清零 DTCM 0x00020000（Test 18 遗留 0x11FEBABE）并读回确认
    // 回读验证全部程序字（sbreadonaddr 模式）
    dmi_write(ADDR_SBCS, 32'h0014_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0200);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("watchpoint prog @0001_0200", rd_data, 32'h02A0_0093);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0204);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("watchpoint prog @0001_0204", rd_data, 32'h0002_0137);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0208);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("watchpoint prog @0001_0208", rd_data, 32'h0011_2023);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_020C);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("watchpoint prog @0001_020C", rd_data, 32'h0000_0013);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0210);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("watchpoint prog @0001_0210", rd_data, 32'h0001_2183);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0214);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("watchpoint prog @0001_0214", rd_data, 32'h0011_0023);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_0218);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("watchpoint prog @0001_0218", rd_data, 32'h0000_0013);
    dmi_write(ADDR_SBADDRESS0, 32'h0001_021C);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("watchpoint prog @0001_021C", rd_data, 32'h0000_00EF);
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    dmi_write(ADDR_SBCS, 32'h0004_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0002_0000);
    dmi_write(ADDR_SBDATA0, 32'h0000_0000);
    #(CLK_PERIOD * 10);
    dmi_write(ADDR_SBCS, 32'h0014_0000);  // sbreadonaddr=1
    dmi_write(ADDR_SBADDRESS0, 32'h0002_0000);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("watchpoint: DTCM cleared", rd_data, 32'h0);

    // 1) 写观察点：trigger0 = store 0x00020000（tdata1=type2+dmode+store）
    dmi_write(ADDR_DATA0, 32'h0000_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A0);  // tselect=0
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h2800_0002);   // type=2, dmode=1, store=1
    dmi_write(ADDR_COMMAND, 32'h0023_07A1); // tdata1
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h0002_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A2); // tdata2=0x00020000
    jtag_idle(10);
    // 读回 tdata1 验证 load/store 位保留
    dmi_write(ADDR_COMMAND, 32'h0022_07A1);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("watchpoint: tdata1 readback", rd_data[1:0], 2'b10);
    // dpc=0x10200，resume → addi/lui 执行，sw 在 EX 命中 → halt
    dmi_write(ADDR_DATA0, 32'h0001_0200);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1); // dpc
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001); // resume
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("watchpoint store: allhalted", rd_data[9], 1'b1);
    // dcsr.cause = 2 (trigger)
    dmi_write(ADDR_COMMAND, 32'h0022_07B0);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("watchpoint store: dcsr.cause=2", rd_data[8:6], 3'd2);
    // dpc = 0x10208（sw 指令自身，而非下一条）
    dmi_write(ADDR_COMMAND, 32'h0022_07B1);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("watchpoint store: dpc=0x10208", rd_data, 32'h0001_0208);
    // 关键：before 时序，sw 未提交 → DTCM 仍为 0
    dmi_write(ADDR_SBCS, 32'h0014_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0002_0000);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("watchpoint store: DTCM not written", rd_data, 32'h0);
    // 清 trigger0 → resume → sw 真正执行，然后 halt 检查
    dmi_write(ADDR_DATA0, 32'h2800_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A1); // 清 tdata1
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001); // resume
    #(CLK_PERIOD * 30);
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001); // halt
    #(CLK_PERIOD * 50);
    dmi_write(ADDR_SBCS, 32'h0014_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0002_0000);
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("watchpoint store: DTCM=42 after resume", rd_data, 32'd42);

    // 2) 读观察点：trigger1 = load 0x00020000
    dmi_write(ADDR_DATA0, 32'h0000_0001);
    dmi_write(ADDR_COMMAND, 32'h0023_07A0);  // tselect=1
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h2800_0001);   // type=2, dmode=1, load=1
    dmi_write(ADDR_COMMAND, 32'h0023_07A1); // tdata1
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h0002_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A2); // tdata2
    jtag_idle(10);
    // 先清 x3（防止残留值干扰判断）
    dmi_write(ADDR_DATA0, 32'h0000_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_1003); // write x3=0
    jtag_idle(10);
    // dpc=0x10210（lw），resume → EX 命中 load → halt
    dmi_write(ADDR_DATA0, 32'h0001_0210);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1); // dpc
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("watchpoint load: allhalted", rd_data[9], 1'b1);
    dmi_write(ADDR_COMMAND, 32'h0022_07B1);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("watchpoint load: dpc=0x10210", rd_data, 32'h0001_0210);
    // x3 未被更新（load 未写回）
    dmi_write(ADDR_COMMAND, 32'h0022_1003);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("watchpoint load: x3 unchanged", rd_data, 32'h0);
    // 清 trigger1 → resume → lw 完成，x3=42
    dmi_write(ADDR_DATA0, 32'h2800_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A1); // 清 tdata1
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
    #(CLK_PERIOD * 30);
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001); // halt
    #(CLK_PERIOD * 50);
    dmi_write(ADDR_COMMAND, 32'h0022_1003);
    jtag_idle(10);
    dmi_read(ADDR_DATA0, rd_data);
    check("watchpoint load: x3=42 after resume", rd_data, 32'd42);

    // 3) 访问宽度过滤：store + sizelo=3(word)；sb 不匹配不 halt，sw 匹配 halt
    dmi_write(ADDR_DATA0, 32'h0000_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A0);  // tselect=0
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h2803_0002);   // type=2, dmode=1, size=3(32bit), store=1
    dmi_write(ADDR_COMMAND, 32'h0023_07A1); // tdata1
    jtag_idle(10);
    dmi_write(ADDR_DATA0, 32'h0002_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A2); // tdata2
    jtag_idle(10);
    // 从 0x10214（sb）跑：sb 是 8 位写，不应命中 word 观察点
    dmi_write(ADDR_DATA0, 32'h0001_0214);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1); // dpc
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001); // resume
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("watchpoint size: sb not matched (running)", rd_data[11], 1'b1);
    // halt，从 0x10208（sw）跑：word 写命中
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 50);
    dmi_write(ADDR_DATA0, 32'h0001_0208);
    dmi_write(ADDR_COMMAND, 32'h0023_07B1); // dpc
    jtag_idle(10);
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001); // resume
    #(CLK_PERIOD * 50);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("watchpoint size: sw matched (halted)", rd_data[9], 1'b1);
    // 清理 trigger
    dmi_write(ADDR_DATA0, 32'h2800_0000);
    dmi_write(ADDR_COMMAND, 32'h0023_07A1);
    jtag_idle(10);
    // 最终 resume，让程序停在自旋
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
    #(CLK_PERIOD * 30);
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 50);

    // ----------------------------------------------------------
    // ----------------------------------------------------------
    // Test 21: 对照实验——sb 操作数串位是否只在调试路径出现
    //   程序（ITCM 0x10000，复位向量）：
    //     0x10000 addi x1,x0,42    0x02A00093
    //     0x10004 lui  x2,0x20     0x00020137  -> x2=0x20000
    //     0x10008 nop              0x00000013
    //     0x1000C lw   x3,0(x2)    0x00012183
    //     0x10010 sb   x1,0(x2)    0x00110023
    //     0x10014 nop              0x00000013
    //     0x10018 jal  x0,self     0x000000EF
    //   A) ndmreset 复位自跑（无任何 halt/resume/trigger 介入）
    // ----------------------------------------------------------
    // Test 21: 对照实验——sb 操作数串位是否只在调试路径出现
    //   A1) 无调试自跑：lw x3 -> sb x1（byte store）
    //   A2) 无调试自跑：lw x3 -> sw x1（word store）
    // 汇总
    // ----------------------------------------------------------
    // Test 22: SBA 读 BootROM（0x0000_0000 区）——GDB/OpenOCD 在线调试 stop 判定路径
    //   0x0000_0000 应为 mrom.dat[0] = 0x00100293 (addi x5,x0,1)
    //   BootROM 只读：SBA 写 0x0 应报 sberror=010 且 ROM 内容不变
    // ----------------------------------------------------------
    $display("--- Test 22: SBA read BootROM ---");
    dmi_write(ADDR_SBCS, 32'h0004_0000);   // sbaccess=2, 写模式（清 sbreadonaddr）
    dmi_write(ADDR_SBADDRESS0, 32'h0000_0000);
    dmi_write(ADDR_SBCS, 32'h0014_0000);   // sbreadonaddr=1, sbaccess=2
    dmi_write(ADDR_SBADDRESS0, 32'h0000_0000);  // 触发 SBA read @0x0
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("SBA BootROM readback @0x0", rd_data, 32'h0010_0293);
    // 写保护：SBA 写 0x0 应报错
    dmi_write(ADDR_SBCS, 32'h0004_0000);   // sbaccess=2, 写模式
    dmi_write(ADDR_SBADDRESS0, 32'h0000_0000);
    dmi_write(ADDR_SBDATA0, 32'hDEAD_BEEF);  // 触发 SBA write @0x0
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBCS, rd_data);
    check("SBA BootROM write: sberror set", rd_data[14:12], 3'b010);
    // W1C 清 sberror，再重新读 @0x0 验证内容未变
    dmi_write(ADDR_SBCS, 32'h0000_7000);
    // 写失败后内容不变
    dmi_write(ADDR_SBCS, 32'h0004_0000);   // sbaccess=2, 写模式
    dmi_write(ADDR_SBADDRESS0, 32'h0000_0000);
    dmi_write(ADDR_SBCS, 32'h0014_0000);   // sbreadonaddr=1, sbaccess=2
    dmi_write(ADDR_SBADDRESS0, 32'h0000_0000);  // 再次读 @0x0
    #(CLK_PERIOD * 10);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("SBA BootROM unchanged after write", rd_data, 32'h0010_0293);

    // ----------------------------------------------------------
    // Test 23: reset halt（CPU 停在 BootROM 0x0）后 2 字节 SBA 读 0x0
    //   复刻板上 OpenOCD 场景：reset halt 后 GDB 以 sbaccess=1 读复位向量区
    //   验证不误报 sberror 且数据正确
    // ----------------------------------------------------------
    $display("--- Test 23: reset halt + subword SBA read BootROM ---");
    // ndmreset + haltreq 驻留 → reset halt
    dmi_write(ADDR_DMCONTROL, 32'h8000_0003);
    #(CLK_PERIOD * 30);
    dmi_write(ADDR_DMCONTROL, 32'h8000_0001);
    #(CLK_PERIOD * 200);
    dmi_read(ADDR_DMSTATUS, rd_data);
    check("reset-halt subword: allhalted", rd_data[9], 1'b1);
    // 2 字节 SBA 读 0x0（sbreadonaddr + sbaccess=1 + sbautoincrement）
    dmi_write(ADDR_SBCS, 32'h0000_7000);   // W1C 清掉 Test 22 残留的 sberror
    dmi_write(ADDR_SBCS, 32'h0013_0000);
    dmi_write(ADDR_SBADDRESS0, 32'h0000_0000);
    jtag_idle(4);
    dmi_read(ADDR_SBDATA0, rd_data);
    check("reset-halt subword: SBA read @0x0 data", rd_data, 32'h0010_0293);
    dmi_read(ADDR_SBCS, rd_data);
    check("reset-halt subword: no sberror", rd_data[14:12], 3'b0);
    // 清 sberror + 读回 sbaddress0 确认自增（0x0 + 2 = 0x2）
    dmi_write(ADDR_SBCS, 32'h0000_7000);
    dmi_read(ADDR_SBADDRESS0, rd_data);
    check("reset-halt subword: sbaddress0 autoincrement", rd_data, 32'h0000_0002);

    // ----------------------------------------------------------
    $display("\n========== Results: %0d PASS, %0d FAIL ==========\n", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
        $display("*** ALL TESTS PASSED ***");
    else
        $display("*** SOME TESTS FAILED ***");

    #(CLK_PERIOD * 10);
    $finish;
end

// 超时保护
initial begin
    #(CLK_PERIOD * 400_000);
    $display("[TIMEOUT] Simulation exceeded time limit");
    $finish;
end


endmodule
