`timescale 1ns/1ps

module tb_apb_uart;

// -------------------------- 时钟与复位配置 --------------------------
parameter CLK_FREQ    = 100_000_000;    // 系统时钟50MHz
parameter BAUD_RATE   = 115200;        // 波特率
localparam SAMPLE_PER_BIT = 16;        // 每个bit对应16个采样时钟
localparam DIVISOR_VAL = CLK_FREQ/(SAMPLE_PER_BIT*BAUD_RATE); // 分频系数计算


// -------------------------- 测试平台信号定义 --------------------------
logic                       PCLK;
logic                       PRESETn;
logic                       uart_rx_i;
logic                       uart_tx_o;
logic   [31:0]              PADDR;
logic                       PSEL;
logic                       PENABLE;
logic                       PWRITE;
logic   [31:0]              PWDATA;
logic   [31:0]              PRDATA;
logic                       PREADY;
logic                       PSLVERR;
logic                       irq_o;
logic                       test_pass;
int                         error_count;
logic   [7:0]               tx_test_data;
logic   [7:0]               rx_test_data;

// -------------------------- DUT例化 --------------------------
apb_uart #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32)
) u_apb_uart (
    .PCLK        (PCLK),
    .PRESETn      (PRESETn),
    .uart_rx_i    (uart_rx_i),
    .uart_tx_o    (uart_tx_o),
    .PADDR      (PADDR),
    .PSEL       (PSEL),
    .PENABLE    (PENABLE),
    .PWRITE     (PWRITE),
    .PWDATA     (PWDATA),
    .PRDATA     (PRDATA),
    .PREADY     (PREADY),
    .PSLVERR    (PSLVERR),
    .irq_o      (irq_o)
);

// -------------------------- 时钟生成 --------------------------
initial begin
    PCLK = 1'b0;
    forever #10 PCLK = ~PCLK;  // 50MHz时钟（周期20ns）
end

// -------------------------- 测试流程 --------------------------
initial begin
    // 初始化
    PRESETn      = 1'b0;
    PADDR      = 32'h0000_0000;
    PSEL       = 1'b0;
    PENABLE    = 1'b0;
    PWRITE     = 1'b0;
    PWDATA     = 32'h0000_0000;
    uart_rx_i    = 1'b1;       // UART空闲状态为高
    test_pass  = 1'b1;
    error_count = 0;

    // 复位释放
    #100;
    PRESETn = 1'b1;
    #100;

    $display("==================== UART Top Module Test Start ====================");

    // 测试1: 初始化寄存器配置
    test_reg_config();
    
    // 测试2: UART发送功能验证
    tx_test_data = 8'h5A;
    test_uart_tx(tx_test_data);
    
    // 测试3: UART接收功能验证
    rx_test_data = 8'hA5;
    test_uart_rx(rx_test_data);
    
    // 测试4: 中断功能验证
    test_uart_irq();

    // 测试结果汇总
    #1000;
    if (error_count == 0) begin
        $display("==================== All Tests Passed! ====================");
    end else begin
        test_pass = 1'b0;
        $display("==================== Test Failed! Total Errors: %0d ====================", error_count);
    end

    $finish;
end

// -------------------------- 通用封装任务 --------------------------
// 任务1: 发送单个UART bit（基于clk_sample对齐，避免偏移）
task send_uart_bit(input logic bit_val);
    int sample_cnt;
    // 设置当前bit电平
    uart_rx_i = bit_val;
    // 等待16个clk_sample周期（1个完整bit周期）
    for (sample_cnt = 0; sample_cnt < SAMPLE_PER_BIT; sample_cnt++) begin
        @(posedge u_apb_uart.clk_sample);
    end
endtask

// 任务2: 发送完整UART字节（包含起始位+8位数据+停止位）
task send_uart_byte(input logic[7:0] byte_data);
    int bit_idx;
    $display("Sending UART Byte: 0x%02h", byte_data);
    @(posedge u_apb_uart.clk_sample);
    #1;
    uart_rx_i = 1'b1;
    // 1. 发送起始位（低电平）
    send_uart_bit(1'b0);
    
    // 2. 发送8位数据位（LSB先行）
    for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
        send_uart_bit(byte_data[bit_idx]);
    end
    
    // 3. 发送停止位（高电平）
    send_uart_bit(1'b1);

    // 4. 恢复空闲电平（高）
    uart_rx_i = 1'b1;
endtask

// -------------------------- 基础总线任务 --------------------------
// 任务3: APB写寄存器
task apb_write(input logic[31:0] addr, input logic[31:0] data);
    #1;
    PSEL    = 1'b1;
    PENABLE = 1'b0;
    PADDR   = addr;
    PWRITE  = 1'b1;
    PWDATA  = data;
    
    @(posedge PCLK);
    #1;
    PENABLE = 1'b1;
    #1;
    wait(PREADY);
    
    @(posedge PCLK);
    #1;
    PSEL    = 1'b0;
    PENABLE = 1'b0;
    $display("APB Write: Addr=0x%08h, Data=0x%08h", addr, data);
endtask

// 任务4: APB读寄存器
task apb_read(input logic[31:0] addr, output logic[31:0] data);
    #1;
    PSEL    = 1'b1;
    PENABLE = 1'b0;
    PADDR   = addr;
    PWRITE  = 1'b0;
    
    @(posedge PCLK);
    #1;
    PENABLE = 1'b1;
    #1;
    wait(PREADY);
    #1;
    data    = PRDATA;

    @(posedge PCLK);
    #1;
    PSEL    = 1'b0;
    PENABLE = 1'b0;
    $display("APB Read:  Addr=0x%08h, Data=0x%08h", addr, data);
endtask

// -------------------------- 功能测试任务 --------------------------
// 任务5: 寄存器配置测试
task test_reg_config();
    logic[31:0] read_data;
    
    $display("\n--- Test 1: Register Configuration ---");
    @(posedge PCLK);
    // 1. 设置波特率分频系数
    apb_write(32'h0000_000C, 32'h0000_0080);  // LCR[7]=1，使能DLAB
    apb_write(32'h0000_0000, {24'h000000,DIVISOR_VAL[7:0]});  // 写入DLL
    apb_write(32'h0000_0004, {24'h000000,DIVISOR_VAL[15:8]});  // 写入DLM
    
    // 2. 配置LCR为8N1（8位数据，无校验，1位停止位）
    apb_write(32'h0000_000C, 32'h0000_0003);  // LCR=0x03，关闭DLAB
    
    // 3. 使能FIFO
    apb_write(32'h0000_0008, 32'h0000_0000);  // FCR=0x00，使能FIFO
    
    // 4. 读取验证LCR寄存器
    apb_read(32'h0000_000C, read_data);
    if (read_data[7:0] != 8'h03) begin
        $display("Error: LCR register read error, expected 0x03, got 0x%02h", read_data[7:0]);
        error_count++;
    end
    
    // 5. 读取验证除数寄存器（重新使能DLAB）
    apb_write(32'h0000_000C, 32'h0000_0080);
    apb_read(32'h0000_0000, read_data);
    if (read_data[7:0] != DIVISOR_VAL[7:0]) begin
        $display("Error: DLL register read error, expected 0x%02h, got 0x%02h", DIVISOR_VAL[7:0], read_data[7:0]);
        error_count++;
    end
    apb_read(32'h0000_0004, read_data);
    if (read_data[7:0] != DIVISOR_VAL[15:8]) begin
        $display("Error: DLM register read error, expected 0x%02h, got 0x%02h", DIVISOR_VAL[15:8], read_data[7:0]);
        error_count++;
    end
    apb_write(32'h0000_000C, 32'h0000_0003);  // 恢复LCR配置
    
    $display("--- Test 1 Completed ---");
endtask

// 任务6: UART发送测试
task test_uart_tx(input logic[7:0] tx_data);
    logic       tx_bit;
    int         bit_cnt;
    logic[31:0] lsr_data;
    
    $display("\n--- Test 2: UART TX Function (Data=0x%02h) ---", tx_data);
    @(posedge PCLK);
    // 写入发送数据到THR寄存器
    apb_write(32'h0000_0000, {24'h000000, tx_data});
    
    // 等待发送开始并捕获TX线上的数据
    @(negedge uart_tx_o);  // 检测起始位
    $display("UART TX Start Bit Detected");

    // 等一个时钟周期越过起始位，进入 TX_DATA 阶段
    @(posedge u_apb_uart.clk_uart);

    // 采样8位数据位（下降沿采样）
    for (bit_cnt = 0; bit_cnt < 8; bit_cnt++) begin
        @(negedge u_apb_uart.clk_uart);
        tx_bit = uart_tx_o;
        if (tx_bit != tx_data[bit_cnt]) begin
            $display("Error: TX Bit %0d error, expected %b, got %b", bit_cnt, tx_data[bit_cnt], tx_bit);
            error_count++;
        end
    end
    
    // 验证停止位（下降沿采样）
    @(negedge u_apb_uart.clk_uart);
    if (uart_tx_o != 1'b1) begin
        $display("Error: TX Stop Bit error, expected 1, got %b", uart_tx_o);
        error_count++;
    end
    $display("UART TX Stop Bit Detected");
    @(posedge PCLK);
    // 读取LSR验证发送完成
    apb_read(32'h0000_0014, lsr_data);
    if ((lsr_data[5] != 1'b1) || (lsr_data[6] != 1'b1)) begin
        $display("Error: LSR TX status error, THRE=%b, TEMT=%b", lsr_data[5], lsr_data[6]);
        error_count++;
    end
    
    $display("--- Test 2 Completed ---");
endtask

// 任务7: UART接收测试（调用通用task，无冗余逻辑）
task test_uart_rx(input logic[7:0] rx_data);
    logic[31:0] read_data;
    logic[7:0]  lsr_data;
    
    $display("\n--- Test 3: UART RX Function (Data=0x%02h) ---", rx_data);
    @(posedge PCLK);
    // 确保总线空闲
    uart_rx_i = 1'b1;
    #1;
    
    // 调用通用任务发送完整字节
    send_uart_byte(rx_data);
    // 读取RBR寄存器验证
    apb_read(32'h0000_0000, read_data);
    if (read_data[7:0] != rx_data) begin
        $display("Error: RX Data error, expected 0x%02h, got 0x%02h", rx_data, read_data[7:0]);
        error_count++;
    end
    
    // 读取LSR验证接收完成
    apb_read(32'h0000_0014, read_data);
    if (read_data[0] != 1'b0) begin
        $display("Error: LSR RX DR bit error, expected 1, got %b", read_data[0]);
        error_count++;
    end
    
    $display("--- Test 3 Completed ---");
endtask

// 任务8: 中断功能测试（调用通用task，消除冗余）
task test_uart_irq();
    logic[31:0] read_data;
    
    $display("\n--- Test 4: UART irq_o Function ---");
    @(posedge PCLK);
    // 使能接收数据就绪中断
    apb_write(32'h0000_0004, 32'h0000_0001);  // IER[0]=1
    
    // 确保总线空闲
    @(posedge u_apb_uart.clk_sample);
    uart_rx_i = 1'b1;
    #1;
    // 调用通用任务发送测试字节（替代原有冗余的逐位发送逻辑）
    send_uart_byte(8'h55);
    
    // 验证中断触发（带超时保护）
    fork
        begin : irq_timeout
            wait(irq_o);
        end
        begin : irq_watchdog
            repeat(100000) @(posedge u_apb_uart.clk_uart);
            $display("Error: RX irq_o timeout, irq_o never triggered");
            error_count++;
        end
    join_any
    disable fork;
    if (irq_o != 1'b1) begin
        $display("Error: RX irq_o not triggered, expected 1, got %b", irq_o);
        error_count++;
    end
    @(posedge PCLK);
    // 读取IIR验证中断类型
    apb_read(32'h0000_0008, read_data);
    if (read_data[7:0] != 8'h04) begin
        $display("Error: IIR error, expected 0x04 (RDA), got 0x%02h", read_data[7:0]);
        error_count++;
    end
    
    // 读取RBR清除中断（等一拍让中断清除逻辑生效）
    apb_read(32'h0000_0000, read_data);
    @(posedge PCLK);
    #1;
    if (irq_o != 1'b0) begin
        $display("Error: RX irq_o not cleared, expected 0, got %b", irq_o);
        error_count++;
    end
    
    $display("--- Test 4 Completed ---");
endtask

endmodule