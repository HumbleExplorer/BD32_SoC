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
localparam  CLK_PERIOD = 10;
localparam  DTCM_FILE  =  `DTCM_FILE;
localparam  ITCM_FILE  =  `ITCM_FILE;
localparam  PATH  = `PATH;//vsim路径
localparam  ITCM_FULL_PATH = {PATH,ITCM_FILE};
localparam  SAMPLE_PER_BIT = 16;

logic   clk;
logic   rst_n;
logic   download_en;
logic   key0_val;
wire    [GPIO_NUM-1:0]  gpio_io;
// GPIO[0] (MODE_SEL) 浮空，BootROM 读到 0 → 进入 UART 下载模式
// 注：GPIO_SIM 模式下 gpio_io 不连到 apb_gpio（用 gpio_i/gpio_o/gpio_oe 替代）
// logic   clk_timer;
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
    $display("File Path: %s", file_path);
    $display("==============================================================\n");

    fd = $fopen(file_path, "rb");  // 二进制模式，避免 0x1A (Ctrl-Z) 误判 EOF
    if (fd == 0) begin
        $error("UART Download Error: Cannot open file %s", file_path);
        return;
    end

    // 逐字节发送（$fgetc 每次读 1 字节）
    bytes_sent = 0;
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

// -------------------------- 通用封装任务 --------------------------
// 任务1: 发送单个UART bit（基于clk_sample对齐，避免偏移）
task send_uart_bit(input logic bit_val);
    // 设置当前bit电平
    uart_rx = bit_val;
    // 等待16个clk_sample周期（1个完整bit周期）
    repeat(SAMPLE_PER_BIT) @(posedge u_SoC_top.u_apb_uart.clk_sample);
endtask

// 任务2: 发送完整UART字节（包含起始位+8位数据+停止位）
task send_uart_byte(input logic[7:0] byte_data);
    int bit_idx;
    // $display("Sending UART Byte: 0x%02h", byte_data);
    uart_rx = 1'b1;
    // 1. 发送起始位（低电平）
    send_uart_bit(1'b0);
    
    // 2. 发送8位数据位（LSB先行）
    for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
        send_uart_bit(byte_data[bit_idx]);
    end
    
    // 3. 发送停止位（高电平）
    send_uart_bit(1'b1);

    // 4. 恢复空闲电平（高）
    uart_rx = 1'b1;
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

always #(CLK_PERIOD/2)   clk = ~clk;
// always #(1000/2)   clk_timer = ~clk_timer;

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
    clk     = 1'b0;
    rst_n   = 1'b0;
    download_en = 1'b1;
    // clk_timer = 1'b0;
    uart_rx = 1'b1;// UART空闲电平为高
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
initial  begin
    @(posedge rst_n);
    #50;
`ifdef DIRECT_LOAD
    // DIRECT_LOAD: PC_counter 直接跳转到 ITCM 启动，BootROM 被跳过
    // 所以 download_en 永远不会被置位，跳过它的 wait
    $display("DIRECT_LOAD mode: ITCM pre-initialized, skip UART download");
    $display("File Path: %s", ITCM_FULL_PATH);
    #100;
`else
    // 正常 UART 下载模式：等待 BootROM 启动后置位 download_en
    wait(tb_soc_top.u_SoC_top.u_apb_uart.download_en);
    #50;
    uart_download_program(ITCM_FULL_PATH);
`endif
    #200;
end

/* KEY0 模拟: 等 UART 开始输出（中断已开）后再按 */
initial begin
    key0_val = 1;  /* 初始高 */
    wait(tb_soc_top.u_SoC_top.u_RISC_V_Core.u_CSR_Reg_Access.mstatus[3]
     && tb_soc_top.u_SoC_top.u_RISC_V_Core.u_CSR_Reg_Access.mie[11]);
    #10000000;
    key0_val = 0;  /* 按下 */
    #5000000;
    key0_val = 1;  /* 松开 */
    #5000000;
    key0_val = 0;  /* 按下 */
    #5000000;
    key0_val = 1;  /* 松开 */
    #5000000;
    key0_val = 0;  /* 按下 */
    #5000000;
    key0_val = 1;  /* 松开 */
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
    .sys_rst_n   	    (rst_n      ),
    // .clk_timer      (clk_timer),
    .uart_rx     	(uart_rx    ),
    .uart_tx     	(uart_tx    ),
    .gpio_io     	(gpio_io    ),
    .timer_channel_io   (timer_channel_io )
);


endmodule

