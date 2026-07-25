timeunit 1ns;
timeprecision 1ps;
module tb_soc_top;
`include "./../rtl/SoC_Config.sv"

parameter ADDR_WIDTH = `ADDR_WIDTH;
parameter DATA_WIDTH = `DATA_WIDTH;
parameter REG_ADDR_WIDTH =`REG_ADDR_WIDTH;
parameter REGFILE_NUM = `REGFILE_NUM;
parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH;
parameter ALIGN_BYTES = `ALIGN_BYTES;
parameter ALIGN_WIDTH = `ALIGN_WIDTH;
parameter GPIO_NUM = `GPIO_NUM;

localparam  DTCM_FILE  =  `DTCM_FILE;
localparam  ITCM_FILE  =  `ITCM_FILE;
localparam  PATH  = `PATH;//vsim路径
localparam  ITCM_FULL_PATH = {PATH,ITCM_FILE};
localparam  CPU_FREQUENCY = 80_000_000;
localparam  CLK_PERIOD = 1_000_000_000 / CPU_FREQUENCY; // 1ns/80MHz
// 真实波特率周期 (ns)：模拟真实串口助手的发送节拍
localparam  BAUD_PERIOD_NS = 1_000_000_000 / 115200;  // ~8680ns per bit @ 115200

logic   clk;
logic   rst_n;
logic   download_en;
logic   key0_val;
wire    [GPIO_NUM-1:0]  gpio_io;
// GPIO[0] (MODE_SEL) 浮空，BootROM 读到 0 → 进入 UART 下载模式
// 注：GPIO_SIM 模式下 gpio_io 不连到 apb_gpio（用 gpio_i/gpio_o/gpio_oe 替代）
logic   uart_rx;
logic   uart_tx;
logic   download_done;
// Timer PWM channel outputs (4 channels)
wire    [`TIMER_CHANNEL_NUM-1:0] timer_channel_io;

// 存储指令的内存数组（32位宽，足够大的深度）
logic   [DATA_WIDTH-1:0] itcm_mem [0:`ITCM_DEPTH-1];
integer inst_cnt; // 实际读取的指令条数
// GPIO[0] (MODE_SEL): download_en=1 模拟跳线帽接3.3V → UART下载模式
assign  gpio_io[0] = download_en;

/* KEY0 模拟: 三态驱动 (z = 不驱动，外部上拉) */
assign  gpio_io[1] = key0_val;
assign download_done = tb_soc_top.u_SoC_top.u_apb_uart.download_done;

// ------------------------ UART下载ITCM程序的核心Task ------------------------
// 功能：通过UART发送完整的.uartbin文件（计数协议版）
// .uartbin 格式： [START_FRAME(4B)][ITCM_COUNT(4B)][ITCM数据(N×4B)][DTCM_COUNT(4B)][DTCM数据(M×4B)]
// 直接发送全部字节，无需额外处理帧头帧尾
task uart_download_program(
    input string  file_path
);
    integer       fd, byte_val, bytes_sent;

    $display("\n==================== UART Download Start ====================");
    $display("File PATH: %s", file_path);
    $display("==============================================================\n");

    fd = $fopen(file_path, "rb");  // 二进制模式，避免 0x1A (Ctrl-Z) 误判 EOF
    if (fd == 0) begin
        $error("UART Download Error: Cannot open file %s", file_path);
        return;
    end

    // 逐字节发送（$fgetc 每次读 1 字节）
    bytes_sent = 0;
    #($urandom_range(BAUD_PERIOD_NS, 0));
    while (!$feof(fd)) begin
        byte_val = $fgetc(fd);
        if ($feof(fd)) break;
        send_uart_byte(byte_val[7:0]);
        bytes_sent++;
        if (bytes_sent % 20 == 0)
            $display("  Sent %0d bytes", bytes_sent);
    end

    $fclose(fd);

    $display("\n==================== UART Download Finish ====================");
    $display("Sent: %0d bytes", bytes_sent);
    $display("==============================================================\n");
endtask


// ================================================================
// UART 发送 Task（真实串口助手行为）
// ================================================================
// 使用真实时间延迟 `#(BAUD_PERIOD_NS)`，不依赖 SoC 内部 sample_pulse
// 起始位时机与 SoC 采样时钟无任何对齐关系，真实复现串口助手行为
task send_uart_bit(input logic bit_val);
    uart_rx = bit_val;
    #(BAUD_PERIOD_NS);                          // 真实 bit 时间
endtask
task send_uart_byte(input logic[7:0] byte_data);
    int bit_idx;
    // 起始位
    send_uart_bit(1'b0);  // 起始位
    // 8 位数据（LSB 先行）
    for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
        send_uart_bit(byte_data[bit_idx]);  // 8位数据（LSB 先行）
    end
    send_uart_bit(1'b1);  // 停止位
endtask
// ------------------------ 辅助Task：发送32位数据（小端UART传输） ------------------------
task send_uart_word(
    input logic [31:0] word_data  // 32位数据
);
    // 小端传输：先传最低字节（word_data[7:0]），再传次低字节，依此类推
    send_uart_byte(word_data[7:0]);
    send_uart_byte(word_data[15:8]);
    send_uart_byte(word_data[23:16]);
    send_uart_byte(word_data[31:24]);
endtask

// ------------------------ 辅助Task：发送UART字符串 ------------------------
task send_uart_string(input string s);
    for (int i = 0; i < s.len(); i++)
        send_uart_byte(s[i]);
endtask

// ------------------------ 辅助Task：发送UART字符串+换行 ------------------------
task send_uart_line(input string s);
    send_uart_string(s);
    send_uart_byte(8'h0D);
    send_uart_byte(8'h0A);
endtask

always #(CLK_PERIOD/2)   clk = ~clk;

// CLINT 1MHz timer clock (独立时钟域，由 TB 直接产生)
logic timer_clk;
initial timer_clk = 1'b0;
always #500 timer_clk = ~timer_clk;   // 1MHz = 1000ns period

logic tx_data_valid;
assign tx_data_valid = u_SoC_top.u_apb_uart.tx_start && ~u_SoC_top.u_apb_uart.tx_busy;
logic tx_data_valid_d;

// 监测 UART 发送数据，并打印到 console
logic uart_tx_complete;  // UART 发送完成标志（TEMT=1 时置位）
logic lsr6_d;

always_ff @(posedge clk) begin
    tx_data_valid_d <= #1 tx_data_valid;
    if (tx_data_valid && ~tx_data_valid_d) begin
        $write("%c",u_SoC_top.u_apb_uart.tx_data_in);
        // $write("[%t]:%c\n", $time, u_SoC_top.u_apb_uart.tx_data_in);
    end
    // 检测 UART TX 完全完成：TEMT (LSR[6]) 上升沿
    // TEMT=1 表示发送 FIFO 空 && 移位寄存器空闲，所有字符已发完
    lsr6_d <= #1 u_SoC_top.u_apb_uart.lsr[6];
    if (u_SoC_top.u_apb_uart.lsr[6] && ~lsr6_d)
        uart_tx_complete <= #1 1'b1;
    else
        uart_tx_complete <= #1 1'b0;
end

// ------------------------ PWM Output Monitoring ------------------------
// 功能：监测 timer_channel_io 各通道的 PWM 波形，统计每个周期的时长和占空比
// 工作机制：
//   1. 每个周期结束时（检测到上升沿）输出统计信息
//   2. period_count：累计本周期已过的时钟数
//   3. high_count：累计本周期中高电平持续的时钟数（持续累加，不只在边沿计数）
//   4. prev_pwm：记录上一拍的 PWM 电平，用于边沿检测
//   5. 跳过第一个周期（prev_pwm 全 0 时 period_count 为 0），避免初始态干扰
logic [`TIMER_CHANNEL_NUM-1:0] prev_pwm;
integer period_cnt [`TIMER_CHANNEL_NUM];  // 本周期已过的时钟数
integer high_cnt  [`TIMER_CHANNEL_NUM];   // 本周期中高电平的时钟数
integer pwm_ch;

always @(posedge clk) begin
    if (~rst_n) begin
        prev_pwm <= 0;
        for (pwm_ch = 0; pwm_ch < `TIMER_CHANNEL_NUM; pwm_ch++) begin
            period_cnt[pwm_ch] <= 0;
            high_cnt[pwm_ch]   <= 0;
        end
    end else begin
        for (pwm_ch = 0; pwm_ch < `TIMER_CHANNEL_NUM; pwm_ch++) begin
            // 上升沿检测：上一拍低、当前拍高 → 本周期结束，输出统计
            // 仅在 UART 发送完成后才打印 PWM 信息，避免输出交替
            if (timer_channel_io[pwm_ch] && ~prev_pwm[pwm_ch]) begin
                // 跳过第一个周期（period_cnt 为 0 表示尚未开始计数）
                if (period_cnt[pwm_ch] > 0 && uart_tx_complete) begin
                    $display("[%t] PWM Ch%0d: Period=%0d clocks, Duty=%0d%%",
                             $time, pwm_ch, period_cnt[pwm_ch] + 1,
                             ((high_cnt[pwm_ch]+1) * 100) / (period_cnt[pwm_ch]+1));
                end
                // 重置本通道计数器，开始统计下一个周期
                period_cnt[pwm_ch] <= 0;
                high_cnt[pwm_ch]   <= 0;
            end else begin
                // 周期计数器：每个时钟 +1，上限防溢出
                if (period_cnt[pwm_ch] < 100000)
                    period_cnt[pwm_ch] <= period_cnt[pwm_ch] + 1;

                // 高电平计数器：当前为高则 +1（持续累加，不是边沿触发）
                if (timer_channel_io[pwm_ch])
                    high_cnt[pwm_ch] <= high_cnt[pwm_ch] + 1;
            end
        end
        prev_pwm <= timer_channel_io;
    end
end

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    uart_rx = 1'b1;// UART空闲电平为高
`ifdef DIRECT_LOAD
    download_en = 1'b0;
`else
    download_en = 1'b1;
`endif
    #35;
    rst_n   = 1'b1;
    `ifdef XILINX
    $display("Xilinx FPGA");
    `ifdef SIMULATION
    $display("Simulation Mode");
    `endif
    `endif
    $display("\n============================================================");
    $display("              RISC-V SoC Simulation Started                  ");
    $display("============================================================");
    $display("Timer Channels: %0d", `TIMER_CHANNEL_NUM);
    $display("Expected PWM Period (ARR=255, PSC=1): 512 clocks");
    $display("Expected PWM Duty Cycle: 25%% (CCR1=64)");
    $display("============================================================\n");

end
`ifdef RESET_REDOWNLOAD_TEST
// =====================================================================
// 复位后重新下载测试（RESET_REDOWNLOAD_TEST）
// =====================================================================
// 测试流程：
//   Phase 1: 正常 UART 下载 hello.uartbin，程序运行
//   Phase 2: 按下复位（rst_n=0），保持一段时间后释放
//   Phase 3: MROM 应重新进入 download_mode，TB 再次发送程序
//   判定：若 Phase 3 中 download_en 未置位 → MROM 未进入下载模式 → BUG 复现
// =====================================================================
localparam RESET_HOLD_NS   = 1000;      // 复位保持时间 1us
localparam RUN_BEFORE_RST  = 5_000_000; // 复位前程序运行时间 5ms
localparam DOWNLOAD_TIMEOUT = 15_000_000; // 第二次下载等待超时 2ms

integer reset_phase;  // 0=第一次启动, 1=复位后第二次启动

initial begin
    reset_phase = 0;
    @(posedge rst_n);
    #50;

    // === Phase 1: 第一次下载 ===
    $display("\n============================================================");
    $display("  [RESET_REDOWNLOAD] Phase 1: First UART Download");
    $display("============================================================");
    wait(tb_soc_top.u_SoC_top.u_apb_uart.download_en);
    $display("[%0t] download_en asserted, starting download...", $time);
    #50;
    uart_download_program(ITCM_FULL_PATH);

    // 等下载完成
    wait(download_done);
    $display("[%0t] First download DONE. Program running in ITCM...", $time);
    #(RUN_BEFORE_RST);

    // === Phase 2: 复位 ===
    $display("\n============================================================");
    $display("  [RESET_REDOWNLOAD] Phase 2: Asserting RESET");
    $display("============================================================");
    $display("[%0t] rst_n = 0 (reset asserted)", $time);
    reset_phase = 1;
    rst_n = 1'b0;
    #(RESET_HOLD_NS);
    rst_n = 1'b1;
    $display("[%0t] rst_n = 1 (reset released)", $time);
    #50;

    // === Phase 3: 等待第二次下载 ===
    $display("\n============================================================");
    $display("  [RESET_REDOWNLOAD] Phase 3: Waiting for 2nd download_en");
    $display("============================================================");

    fork
        begin : wait_download
            wait(tb_soc_top.u_SoC_top.u_apb_uart.download_en);
            $display("[%0t] SUCCESS: download_en asserted after reset!", $time);
            $display("  MROM correctly entered download_mode.");
        end
        begin : timeout_guard
            #(DOWNLOAD_TIMEOUT);
            $display("\n[%0t] *** FAILURE: TIMEOUT ***", $time);
            $display("  download_en NOT asserted within %0d ns after reset.", DOWNLOAD_TIMEOUT);
            $display("  MROM failed to enter download_mode after soft reset.");
            $display("  This reproduces the hardware bug.");
            $display("");
            $display("  Debug info at timeout:");
            $display("    PC (inst_addr_if) = 0x%08x", tb_soc_top.u_SoC_top.u_RISC_V_Core.inst_addr_if);
            $display("    gpio_io[0]     = %b", gpio_io[0]);
            $display("    download_en(tb)= %b", download_en);
            $display("    uart dl state  = %0d", tb_soc_top.u_SoC_top.u_apb_uart.u_uart_download.current_state);
            $display("    OITF empty     = %b", tb_soc_top.u_SoC_top.u_RISC_V_Core.u_OITF.empty);
            $finish;
        end
    join_any
    disable fork;

    // 第二次下载
    #50;
    uart_download_program(ITCM_FULL_PATH);
    wait(download_done);
    $display("\n[%0t] Second download DONE. === TEST PASSED ===", $time);
    #(RUN_BEFORE_RST);
    $finish;
end

// --- 复位后 MROM 执行跟踪 ---
// 记录复位后 MROM 的每条指令 PC，帮助定位卡死/跑飞位置
integer mrom_trace_fd;
logic   prev_rst_n;
logic   in_mrom_range;

initial begin
    mrom_trace_fd = $fopen("mrom_trace_after_reset.log", "w");
    $fwrite(mrom_trace_fd, "# PC trace after 2nd reset (reset_phase==1)\n");
end

always @(posedge clk) begin
    prev_rst_n <= #1 rst_n;
    // 复位释放后，跟踪 MROM 地址范围内的 PC
    if (reset_phase == 1 && rst_n) begin
        in_mrom_range = (tb_soc_top.u_SoC_top.u_RISC_V_Core.inst_addr_if < 32'h0000_1000);
        if (in_mrom_range && tb_soc_top.u_SoC_top.u_RISC_V_Core.reg_rd_wen) begin
            $fwrite(mrom_trace_fd, "[%0t] PC=0x%08x  rd=x%0d  wdata=0x%08x\n",
                $time,
                tb_soc_top.u_SoC_top.u_RISC_V_Core.inst_addr_wb,
                tb_soc_top.u_SoC_top.u_RISC_V_Core.reg_rd_waddr,
                tb_soc_top.u_SoC_top.u_RISC_V_Core.reg_rd_wdata);
        end
    end
end

// --- 关键信号实时打印（复位后） ---
always @(posedge clk) begin
    if (reset_phase == 1 && rst_n && ~prev_rst_n) begin
        // 复位刚释放的第一拍
        $display("[%0t] Reset released. Monitoring MROM boot...", $time);
    end
end

`else
// =====================================================================
// 普通模式：单次 UART 下载（原始行为）
// =====================================================================
initial  begin
    @(posedge rst_n);
    #50;
`ifdef DIRECT_LOAD
    // DIRECT_LOAD: PC_counter 直接跳转到 ITCM 启动，BootROM 被跳过
    // 所以 download_en 永远不会被置位，跳过它的 wait
    $display("DIRECT_LOAD mode: ITCM pre-initialized, skip UART download");
    $display("File PATH: %s", ITCM_FULL_PATH);
    #100;
`else
    // 正常 UART 下载模式：等待 BootROM 启动后置位 download_en
    wait(tb_soc_top.u_SoC_top.u_apb_uart.download_en);
    #50;
    uart_download_program(ITCM_FULL_PATH);
`endif
    #200;
end
`endif

// =====================================================================
// UART Echo 测试：模拟用户输入，验证回显
// =====================================================================
// 使用方式：在 SoC_Config.sv 中定义 `define UART_ECHO_TEST
// 或者编译时加 -D UART_ECHO_TEST
//
// 测试流程：
//   1. 等 SoC 发送完欢迎语（BD32 UART Echo ...）
//   2. 注入 "Hello\n"（内容 + 换行符，换行符触发退出）
//   3. 观察回显和 Done! 输出
// =====================================================================
// initial begin
//     // 等 SoC 启动完毕（等待 welcome 输出）
//     #25_000_000;  

//     $display("\n============================================================");
//     $display("  UART Echo Test: Injecting test characters");
//     $display("============================================================");

//     $display("[TX->SoC] Sending: \"Hello World!\"");
//     send_uart_line("Hello World!");

//     #3_000_000;
//     $display("  UART Echo Test Complete - check console for echo output");
//     $display("============================================================\n");
// end

// initial begin
//     key0_val = 1;  /* 初始高 */
//     wait(tb_soc_top.u_SoC_top.u_RISC_V_Core.u_CSR_Reg_Access.mstatus[3]
//      && tb_soc_top.u_SoC_top.u_RISC_V_Core.u_CSR_Reg_Access.mie[11]);
//     #10000000;
//     key0_val = 0;  /* 按下 */
//     #5000000;
//     key0_val = 1;  /* 松开 */
//     #5000000;
//     key0_val = 0;  /* 按下 */
//     #5000000;
//     key0_val = 1;  /* 松开 */
//     #5000000;
//     key0_val = 0;  /* 按下 */
//     #5000000;
//     key0_val = 1;  /* 松开 */
// end

initial begin
    key0_val = 1;  /* 初始高 */
    wait(tb_soc_top.u_SoC_top.u_RISC_V_Core.u_CSR_Reg_Access.wfi_req);
    #10000000;
    key0_val = 0;  /* 按下 */
    #5000000;
    key0_val = 1;  /* 松开 */
    // #5000000;
    // key0_val = 0;  /* 按下 */
    // #5000000;
    // key0_val = 1;  /* 松开 */
    // #5000000;
    // key0_val = 0;  /* 按下 */
    // #5000000;
    // key0_val = 1;  /* 松开 */
end


SoC_top #(
    .ITCM_FILE      	(ITCM_FILE       ),
    .DTCM_FILE      	(DTCM_FILE       ),
    .ADDR_WIDTH     	(ADDR_WIDTH      ),
    .DATA_WIDTH     	(DATA_WIDTH      ),
    .REGFILE_NUM    	(REGFILE_NUM     ),
    .REG_ADDR_WIDTH 	(REG_ADDR_WIDTH  ),
    .CSR_ADDR_WIDTH 	(CSR_ADDR_WIDTH  ),
    .ALIGN_BYTES    	(ALIGN_BYTES     ),
    .ALIGN_WIDTH    	(ALIGN_WIDTH     ),
    .GPIO_NUM       	(GPIO_NUM        )
)u_SoC_top(
    .sys_clk     	(clk        ),
    .sys_rst_n   	(rst_n      ),
    .timer_clk_i    (timer_clk  ),
    .uart_rx     	(uart_rx    ),
    .uart_tx     	(uart_tx    ),
    .gpio_io     	(gpio_io    ),
    .timer_channel_io   (timer_channel_io )
);

// ------------------------ Write-back Trace (debug) ------------------------
// 记录所有"逻辑写回"：Port1(WB) + Port2(OITF retire)。
// forwarding 只是提前使用，最终值仍会写回 RegFile，故这里能捕获所有最终写回。
// 格式：PC rd data（带 PC 信息，便于定位出错指令）
`ifdef WB_TRACE
integer wb_fd;
initial begin
    wb_fd = $fopen("wb_trace.log", "w");
end
always @(posedge clk) begin
    if (u_SoC_top.u_RISC_V_Core.reg_rd_wen && (u_SoC_top.u_RISC_V_Core.reg_rd_waddr != 0))
        $fwrite(wb_fd, "%08x %2d %08x\n", u_SoC_top.u_RISC_V_Core.inst_addr_wb, 
                u_SoC_top.u_RISC_V_Core.reg_rd_waddr, u_SoC_top.u_RISC_V_Core.reg_rd_wdata);
    if (u_SoC_top.u_RISC_V_Core.oitf_retire_valid && u_SoC_top.u_RISC_V_Core.oitf_retire_rd_wen && (u_SoC_top.u_RISC_V_Core.oitf_retire_rd_addr != 0))
        $fwrite(wb_fd, "%08x %2d %08x\n", u_SoC_top.u_RISC_V_Core.inst_addr_wb, 
                u_SoC_top.u_RISC_V_Core.oitf_retire_rd_addr, u_SoC_top.u_RISC_V_Core.oitf_retire_rd_data);
end
`endif


endmodule

