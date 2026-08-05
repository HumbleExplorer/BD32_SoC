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

localparam CPU_FREQ      = 80_000_000;
localparam CLK_PERIOD    = 1_000_000_000 / CPU_FREQ;  // 12.5ns
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
logic                       sba_rsp_valid;
logic [31:0]                sba_rdata;
logic                       sba_error;

// Trigger 信号（SoC_top ↔ debug_top）
logic                       trigger_en;
logic [31:0]                trigger_addr;
logic                       trigger_hit;
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
    .sba_rsp_valid    (sba_rsp_valid  ),
    .sba_rdata        (sba_rdata      ),
    .sba_error        (sba_error      ),
    .trigger_en       (trigger_en     ),
    .trigger_addr     (trigger_addr   ),
    .trigger_hit      (trigger_hit    ),
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
    .sba_rsp_valid    (sba_rsp_valid  ),
    .sba_rdata        (sba_rdata      ),
    .sba_error        (sba_error      ),
    .trigger_en       (trigger_en     ),
    .trigger_addr     (trigger_addr   ),
    .trigger_hit      (trigger_hit    ),
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
    // 写地址 0x2000_0000
    dmi_write(ADDR_SBADDRESS0, 32'h2000_0000);
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
    dmi_write(ADDR_SBADDRESS0, 32'h2000_0000);
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

    // 最终 resume
    dmi_write(ADDR_DMCONTROL, 32'h4000_0001);
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
    // 汇总
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
    #(CLK_PERIOD * 100_000);
    $display("[TIMEOUT] Simulation exceeded time limit");
    $finish;
end

endmodule
