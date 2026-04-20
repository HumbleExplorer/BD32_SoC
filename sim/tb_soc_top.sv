`timescale 1ns / 1ps
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
localparam  CLK_PERIOD = 20;
localparam  DTCM_FILE  =  `DTCM_FILE;
localparam  ITCM_FILE  =  `ITCM_FILE;
localparam  PATH  = `PATH;//vsim路径
localparam  ITCM_FULL_PATH = {PATH,ITCM_FILE};
localparam  SAMPLE_PER_BIT = 16;

logic   clk;
logic   rst_n;
logic   download_en;
wire    [GPIO_NUM-1:0]  gpio_io;
// logic   clk_timer;
logic   uart_rx;
logic   uart_tx;
logic   download_done;
// Timer PWM channel outputs (4 channels)
wire    [`TIMER_CHANNEL_NUM-1:0] timer_channel_io;

// 存储指令的内存数组（32位宽，足够大的深度）
logic   [DATA_WIDTH-1:0] itcm_mem [0:`ITCM_DEPTH-1];
integer inst_cnt; // 实际读取的指令条数
assign  gpio_io[0] = download_en;
assign download_done = tb_soc_top.u_SoC_top.u_apb_uart.download_done;

// ------------------------ UART下载ITCM程序的核心Task ------------------------
// 功能：通过UART发送帧头+程序数据+帧尾，完成ITCM下载
// 参数说明：
//   - file_path: 程序文件路径（.dat/.bin，每行16进制数或二进制）
//   - baud_rate: UART波特率（默认115200）
//   - clk_period: 系统时钟周期（ns，默认10ns=100MHz）
//   - start_frame: 下载启动帧（32位，默认0xAABBAABB）
//   - end_frame: 下载结束帧（32位，默认0xCCDDCCDD）
task uart_download_itcm(
    input string  file_path,
    input logic [31:0] start_frame = 32'hBBAABBAA,//传0xAA 0xBB 0xAA 0xBB
    input logic [31:0] end_frame = 32'hFFEEFFEE//传0xEE 0xFF 0xEE 0xFF
);
    integer       i; // 循环变量

    $display("\n==================== UART Download Start ====================");
    $display("File Path: %s", file_path);
    $display("Start Frame: 0x%08h, End Frame: 0x%08h", start_frame, end_frame);
    $display("==============================================================\n");

    // 1. 核心：用$readmemh加载十六进制文件到内存数组
    // $readmemh格式说明：$readmemh("文件路径", 数组名); 自动按行读取32位十六进制数
    inst_cnt = 0; // 初始化指令计数
    $readmemh(file_path, itcm_mem);

    // 检查是否读取到指令（验证文件是否存在/格式是否正确）
    if(itcm_mem[0] === 32'hx) begin // 数组初始值为x，读取失败则仍为x
        $error("UART Download Error: $readmemh read file failed!");
        $error("Check: 1. File path: %s  2. File format (hex per line)", file_path);
        return;
    end

    // 统计实际读取的指令条数（遍历数组直到遇到x）
    for(i = 0; i < `ITCM_DEPTH; i++) begin
        if(itcm_mem[i] === 32'hx) begin
            inst_cnt = i;
            break;
        end
    end
    if(inst_cnt == 0) begin
        $error("UART Download Error: No valid instructions read!");
        return;
    end
    $display("Success read %0d instructions from file", inst_cnt);

    @(posedge u_SoC_top.u_apb_uart.clk_sample);
    #1;
    // 2. 发送启动帧（32位，小端传输）
    $display("Sending Start Frame...");
    send_uart_word(start_frame);

    // 3. 从内存数组逐字发送指令
    $display("Sending Program Data...");
    for(i = 0; i < inst_cnt; i++) begin
        send_uart_word(itcm_mem[i]); // 发送当前指令

        // 每10条打印进度
        if((i+1) % 100 == 0) begin
            $display("Sent %0d instructions (0x%08h)", i+1, itcm_mem[i]);
        end
    end

    // 4. 发送结束帧
    $display("Sending End Frame...");
    send_uart_word(end_frame);

    // 5. 下载完成
    $display("\n==================== UART Download Finish ====================");
    $display("Total Sent: %0d instructions + 2 frames (start/end)", inst_cnt);
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

always_ff @(posedge clk) begin
    tx_data_valid_d <= #1 tx_data_valid;
    if (tx_data_valid && ~tx_data_valid_d) begin
        // $write("%c",u_SoC_top.u_apb_uart.tx_data_in);
    end
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
            if (timer_channel_io[pwm_ch] && ~prev_pwm[pwm_ch]) begin
                // 跳过第一个周期（period_cnt 为 0 表示尚未开始计数）
                if (period_cnt[pwm_ch] > 0) begin
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
    $display("\n============================================================");
    $display("              RISC-V SoC Simulation Started                  ");
    $display("============================================================");
    $display("Timer Base Address: 0x%08h", `TIMER_BASE_ADDR);
    $display("Timer Channels: %0d", `TIMER_CHANNEL_NUM);
    $display("Expected PWM Period (ARR=255, PSC=1): 512 clocks");
    $display("Expected PWM Duty Cycle: 25%% (CCR1=64)");
    $display("============================================================\n");

end
initial  begin
    // 等待复位稳定后启动下载
    @(posedge rst_n);
    #50;// 增加稳定时间，避免复位中操作
    wait(tb_soc_top.u_SoC_top.u_apb_uart.download_en);
    #50; 
    uart_download_itcm(ITCM_FULL_PATH);
    if(u_SoC_top.u_RISC_V_Core.inst[0] == 32'hx) begin // 数组初始值为x，读取失败则仍为x
        $finish;
    end
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
    .rst_n   	    (rst_n      ),
    // .clk_timer      (clk_timer),
    .uart_rx     	(uart_rx    ),
    .uart_tx     	(uart_tx    ),
    .gpio_io     	(gpio_io    ),
    .timer_channel_io   (timer_channel_io )
);


endmodule

