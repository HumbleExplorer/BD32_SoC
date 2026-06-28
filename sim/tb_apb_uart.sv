timeunit 1ns;
timeprecision 1ps;

module tb_apb_uart;

// =================== 配置参数 ===================
parameter CLK_FREQ    = 100_000_000;
parameter BAUD_RATE   = 115200;
localparam SAMPLE_PER_BIT = 16;
// 真实波特率周期 (ns)：模拟真实串口助手发送节拍
localparam BAUD_PERIOD_NS = 1_000_000_000 / BAUD_RATE;  // ~8680ns @ 115200

// NCO 频率控制字：FCW = (Baud × 16 / Fclk) × 2^32，四舍五入
localparam FCW_VAL = int'((BAUD_RATE * SAMPLE_PER_BIT * (2.0**32)) / CLK_FREQ + 0.5);

// =================== 信号 ===================
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

// =================== DUT ===================
apb_uart #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32)
) u_apb_uart (
    .PCLK        (PCLK),
    .PRESETn     (PRESETn),
    .uart_rx_i   (uart_rx_i),
    .uart_tx_o   (uart_tx_o),
    .PADDR       (PADDR),
    .PSEL        (PSEL),
    .PENABLE     (PENABLE),
    .PWRITE      (PWRITE),
    .PWDATA      (PWDATA),
    .PRDATA      (PRDATA),
    .PREADY      (PREADY),
    .PSLVERR     (PSLVERR),
    .irq_o       (irq_o)
);

// =================== 时钟 ===================
initial begin
    PCLK = 1'b0;
    forever #10 PCLK = ~PCLK;  // 50MHz
end

// =================== 测试流程 ===================
initial begin
    PRESETn      = 1'b0;
    PADDR      = 32'h0000_0000;
    PSEL       = 1'b0;
    PENABLE    = 1'b0;
    PWRITE     = 1'b0;
    PWDATA     = 32'h0000_0000;
    uart_rx_i    = 1'b1;
    test_pass  = 1'b1;
    error_count = 0;

    #100;
    PRESETn = 1'b1;
    #100;

    $display("==================== UART NCO Module Test Start ====================");
    $display("FCW = 0x%08h (Baud=%0d, Fclk=%0dMHz)", FCW_VAL, BAUD_RATE, CLK_FREQ/1000000);

    test_reg_config();
    
    tx_test_data = 8'h5A;
    test_uart_tx(tx_test_data);
    
    rx_test_data = 8'hA5;
    test_uart_rx(rx_test_data);
    
    test_uart_irq();

    #1000;
    if (error_count == 0) begin
        $display("==================== All Tests Passed! ====================");
    end else begin
        test_pass = 1'b0;
        $display("==================== Test Failed! Total Errors: %0d ====================", error_count);
    end
    $finish;
end

task send_uart_bit(input logic bit_val);
    uart_rx_i = bit_val;
    #(BAUD_PERIOD_NS);                          // 真实 bit 时间
endtask
// =================== UART 发送（真实串口行为）= 不依赖 sample_pulse ===================
task send_uart_byte(input logic[7:0] byte_data);
    int bit_idx;
    $display("Sending UART Byte: 0x%02h", byte_data);
    send_uart_bit(1'b0);                   // 起始位
    for (bit_idx = 0; bit_idx < 8; bit_idx++) begin 
        send_uart_bit(byte_data[bit_idx]);// LSB先行
    end
    send_uart_bit(1'b1);                   // 停止位
endtask
// =================== APB 写（PREADY 恒为 1）===================
task apb_write(input logic[31:0] addr, input logic[31:0] data);
    PSEL    = 1'b1;
    PENABLE = 1'b0;
    PADDR   = addr;
    PWRITE  = 1'b1;
    PWDATA  = data;
    @(posedge PCLK);
    PENABLE = 1'b1;
    @(posedge PCLK);
    PSEL    = 1'b0;
    PENABLE = 1'b0;
    $display("APB Write: Addr=0x%08h, Data=0x%08h", addr, data);
endtask

// =================== APB 读 ===================
task apb_read(input logic[31:0] addr, output logic[31:0] data);
    PSEL    = 1'b1;
    PENABLE = 1'b0;
    PADDR   = addr;
    PWRITE  = 1'b0;
    @(posedge PCLK);
    PENABLE = 1'b1;
    @(posedge PCLK);
    data    = PRDATA;
    PSEL    = 1'b0;
    PENABLE = 1'b0;
    $display("APB Read:  Addr=0x%08h, Data=0x%08h", addr, data);
endtask

// =================== 测试 1：寄存器配置 ===================
task test_reg_config();
    logic[31:0] read_data;
    $display("\n--- Test 1: Register Configuration ---");
    @(posedge PCLK);

    // 写 FCW
    apb_write(32'h0000_0024, FCW_VAL);

    // 配置 8N1
    apb_write(32'h0000_000C, 32'h0000_0003);  // LCR=0x03

    // 使能 FIFO
    apb_write(32'h0000_0008, 32'h0000_0000);  // FCR

    // 验证 LCR
    apb_read(32'h0000_000C, read_data);
    if (read_data[7:0] != 8'h03) begin
        $display("Error: LCR read error, expected 0x03, got 0x%02h", read_data[7:0]);
        error_count++;
    end

    // 验证 FCW 回读
    apb_read(32'h0000_0024, read_data);
    if (read_data != FCW_VAL) begin
        $display("Error: FCW read error, expected 0x%08h, got 0x%08h", FCW_VAL, read_data);
        error_count++;
    end else begin
        $display("FCW readback OK: 0x%08h", read_data);
    end

    $display("--- Test 1 Completed ---");
endtask

// =================== 测试 2：UART 发送（采样基于 NCO sample_pulse）===================
task test_uart_tx(input logic[7:0] tx_data);
    logic       tx_bit;
    logic[31:0] lsr_data;
    int         bit_cnt;

    $display("\n--- Test 2: UART TX Function (Data=0x%02h) ---", tx_data);
    @(posedge PCLK);

    // 写 THR
    apb_write(32'h0000_0000, {24'h000000, tx_data});

    // 等待起始位（下降沿）
    @(negedge uart_tx_o);
    $display("UART TX Start Bit Detected");

    // 半 bit 到起始位中央，然后每 bit 采样
    #(BAUD_PERIOD_NS/2);
    for (bit_cnt = 0; bit_cnt < 8; bit_cnt++) begin
        #(BAUD_PERIOD_NS);
        tx_bit = uart_tx_o;
        if (tx_bit != tx_data[bit_cnt]) begin
            $display("Error: TX Bit %0d error, expected %b, got %b", bit_cnt, tx_data[bit_cnt], tx_bit);
            error_count++;
        end
    end
    // 停止位
    #(BAUD_PERIOD_NS);
    if (uart_tx_o != 1'b1) begin
        $display("Error: TX Stop Bit error, expected 1, got %b", uart_tx_o);
        error_count++;
    end else begin
        $display("UART TX Stop Bit Detected");
    end

    // 验证 LSR
    @(posedge PCLK);
    apb_read(32'h0000_0014, lsr_data);
    if ((lsr_data[5] != 1'b1) || (lsr_data[6] != 1'b1)) begin
        $display("Error: LSR TX status, THRE=%b, TEMT=%b", lsr_data[5], lsr_data[6]);
        error_count++;
    end
    $display("--- Test 2 Completed ---");
endtask

// =================== 测试 3：UART 接收 ===================
task test_uart_rx(input logic[7:0] rx_data);
    logic[31:0] read_data;
    $display("\n--- Test 3: UART RX Function (Data=0x%02h) ---", rx_data);
    @(posedge PCLK);
    uart_rx_i = 1'b1;

    send_uart_byte(rx_data);

    // 读 RBR
    apb_read(32'h0000_0000, read_data);
    if (read_data[7:0] != rx_data) begin
        $display("Error: RX Data error, expected 0x%02h, got 0x%02h", rx_data, read_data[7:0]);
        error_count++;
    end

    // LSR[0] DR bit
    apb_read(32'h0000_0014, read_data);
    if (read_data[0] != 1'b0) begin
        $display("Error: LSR RX DR bit, expected 0, got %b", read_data[0]);
        error_count++;
    end
    $display("--- Test 3 Completed ---");
endtask

// =================== 测试 4：中断 ===================
task test_uart_irq();
    logic[31:0] read_data;
    integer     timeout;
    $display("\n--- Test 4: UART irq_o Function ---");
    @(posedge PCLK);

    // 使能 RX 中断
    apb_write(32'h0000_0004, 32'h0000_0001);

    uart_rx_i = 1'b1;
    send_uart_byte(8'h55);

    // 等待中断
    timeout = 0;
    while (!irq_o && timeout < 100000) begin
        @(posedge PCLK);
        timeout++;
    end
    if (!irq_o) begin
        $display("Error: RX irq timeout");
        error_count++;
    end

    // 读 IIR
    @(posedge PCLK);
    apb_read(32'h0000_0008, read_data);
    if (read_data[7:0] != 8'h04) begin
        $display("Error: IIR error, expected 0x04 (RDA), got 0x%02h", read_data[7:0]);
        error_count++;
    end

    // 读 RBR 清中断
    apb_read(32'h0000_0000, read_data);
    @(posedge PCLK);
    if (irq_o != 1'b0) begin
        $display("Error: RX irq not cleared, got %b", irq_o);
        error_count++;
    end
    $display("--- Test 4 Completed ---");
endtask

endmodule
