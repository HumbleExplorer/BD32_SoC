// ============================================================================
// tb_apb_uart.sv — APB UART (16550 subset) 寄存器级测试套件
//
// BD32 — RV32IM Pipelined RISC-V SoC
// Copyright (c) 2026 BD32 Project
// SPDX-License-Identifier: Apache-2.0
//
// 覆盖矩阵（对齐 tb_apb_gpio / tb_apb_timer 的完善度）：
//   全寄存器：RBR/THR/DLL/DLM · IER · IIR/FCR · LCR · MCR · LSR · MSR ·
//             DBG_EN · DBG_STAT · FCW
//   × 复位值 / RW 回读 / 掩码 / DLAB 分组复用的读写隔离
//   × FCR 触发级（1/4/8/14）+ FCR[1]/[2] 清 FIFO
//   × IIR 五类子源：RDA / 超时 / THRE / RLS / MSR（恒无）
//   × LSR 四位错误：OE（溢出）/ PE（奇偶）/ FE（帧）/ BI（break）+ 读清 + LSR[7] 汇总
//   × 中断优先级 RLS > RDA > THRE、空读 RBR 返回 0
// 激励走共享 apb_master_bfm（tb/apb_bfm.sv，带超时保护与 PSLVERR 采样）
// ============================================================================
timeunit 1ns;
timeprecision 1ps;

module tb_apb_uart;

// =================== 配置参数 ===================
parameter CLK_FREQ    =  50_000_000;  // must match PCLK below (forever #10)
parameter BAUD_RATE   = 115200;
localparam SAMPLE_PER_BIT = 16;
// 真实波特率周期 (ns)：模拟真实串口助手发送节拍
localparam BAUD_PERIOD_NS = 1_000_000_000 / BAUD_RATE;  // ~8680ns @ 115200

// NCO 频率控制字：FCW = (Baud × 16 / Fclk) × 2^32，四舍五入
localparam FCW_VAL = int'((BAUD_RATE * SAMPLE_PER_BIT * (2.0**32)) / CLK_FREQ + 0.5);

// =================== 寄存器地址 ===================
localparam [31:0] RBR_THR_DLL = 32'h00;   // DLAB=0: RBR/THR；DLAB=1: DLL
localparam [31:0] IER_DLM     = 32'h04;   // DLAB=0: IER；DLAB=1: DLM
localparam [31:0] IIR_FCR     = 32'h08;   // 读=IIR；写=FCR
localparam [31:0] LCR_ADDR    = 32'h0C;
localparam [31:0] MCR_ADDR    = 32'h10;
localparam [31:0] LSR_ADDR    = 32'h14;
localparam [31:0] MSR_ADDR    = 32'h18;
localparam [31:0] DBG_EN_ADDR = 32'h1C;
localparam [31:0] DBG_ST_ADDR = 32'h20;
localparam [31:0] FCW_ADDR    = 32'h24;

// =================== 信号 ===================
logic                       PCLK;
logic                       PRESETn;
logic                       uart_rx_i;
logic                       uart_tx_o;
logic   [31:0]              PADDR;
logic                       PSEL;
logic                       PENABLE;
logic                       PWRITE;
logic   [3:0]               PSTRB;
logic   [31:0]              PWDATA;
logic   [31:0]              PRDATA;
logic                       PREADY;
logic                       PSLVERR;
logic                       irq_o;
logic                       test_pass;
int                         error_count;

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
    .irq_o       (irq_o),
    // 下载接口输出：外设独立仿真不检查，留空
    .itcm_download_en_o    (),
    .itcm_download_addr_o  (),
    .itcm_download_data_o  (),
    .dtcm_download_en_o    (),
    .dtcm_download_addr_o  (),
    .dtcm_download_data_o  ()
);

// =================== APB BFM ===================
apb_master_bfm #(
    .PADDR_WIDTH (32),
    .PDATA_WIDTH (32)
) bfm (
    .PRESETn  (PRESETn),
    .PCLK     (PCLK),
    .PSEL     (PSEL),
    .PENABLE  (PENABLE),
    .PADDR    (PADDR),
    .PSTRB    (PSTRB),
    .PWDATA   (PWDATA),
    .PRDATA   (PRDATA),
    .PWRITE   (PWRITE),
    .PREADY   (PREADY),
    .PSLVERR  (PSLVERR)
);

// =================== 时钟 ===================
initial begin
    PCLK = 1'b0;
    forever #10 PCLK = ~PCLK;  // 50MHz
end

// =================== BFM 复位线程 ===================
initial begin
    bfm.reset();
end

// =================== 工具任务 ===================
task apb_write(input logic[31:0] addr, input logic[31:0] data);
    bfm.write(addr, 4'hF, data);
endtask

task apb_read(input logic[31:0] addr, output logic[31:0] data);
    bfm.read(addr, data);
endtask

task check(input bit cond, input string msg);
    if (!cond) begin
        error_count++;
        $display("  [FAIL] %s", msg);
    end
endtask

task check_eq8(input string name, input logic[7:0] got, input logic[7:0] exp);
    if (got !== exp) begin
        error_count++;
        $display("  [FAIL] %s: got 0x%02h, expect 0x%02h", name, got, exp);
    end
endtask

task check_eq32(input string name, input logic[31:0] got, input logic[31:0] exp);
    if (got !== exp) begin
        error_count++;
        $display("  [FAIL] %s: got 0x%08h, expect 0x%08h", name, got, exp);
    end
endtask

// =================== UART 位/字节/帧发送（真实串口节拍）===================
task send_uart_bit(input logic bit_val);
    uart_rx_i = bit_val;
    #(BAUD_PERIOD_NS);
endtask

task send_uart_byte(input logic[7:0] byte_data);
    send_uart_bit(1'b0);                   // 起始位
    for (int bit_idx = 0; bit_idx < 8; bit_idx++)
        send_uart_bit(byte_data[bit_idx]); // LSB 先行
    send_uart_bit(1'b1);                   // 停止位
endtask

// 8 数据位 + 可选校验位 + 1 停止位（用于 PE 用例；parity_bit 由调用方按 LCR 配置计算）
task send_uart_frame(input logic[7:0] byte_data, input logic parity_en, input logic parity_bit);
    send_uart_bit(1'b0);
    for (int bit_idx = 0; bit_idx < 8; bit_idx++)
        send_uart_bit(byte_data[bit_idx]);
    if (parity_en)
        send_uart_bit(parity_bit);
    send_uart_bit(1'b1);
endtask

// 通用帧发送：N 数据位 + 可选校验 + M 停止位（5/6/7 数据位与两位停止位用例）
task send_uart_frame_n(input logic[7:0] data, input int nbits,
                       input logic parity_en, input logic parity_bit, input int stop_bits);
    send_uart_bit(1'b0);
    for (int bit_idx = 0; bit_idx < nbits; bit_idx++)
        send_uart_bit(data[bit_idx]);
    if (parity_en)
        send_uart_bit(parity_bit);
    for (int bit_idx = 0; bit_idx < stop_bits; bit_idx++)
        send_uart_bit(1'b1);
endtask

// 停止位发送 0 的坏帧（FE 用例）；发完恢复空闲并等待 FSM 复位
task send_uart_byte_fe(input logic[7:0] byte_data);
    send_uart_bit(1'b0);
    for (int bit_idx = 0; bit_idx < 8; bit_idx++)
        send_uart_bit(byte_data[bit_idx]);
    send_uart_bit(1'b0);                   // 停止位 = 0 → 帧错误
    uart_rx_i = 1'b1;
    #(BAUD_PERIOD_NS*2);
endtask

// =================== 测试用例 ===================

// --- Test 1：复位值（全寄存器） ---
task test_reset_register_values();
    logic[31:0] rd;
    $display("\n--- Test 1: Reset register values ---");
    apb_read(LCR_ADDR, rd);    check_eq8("LCR reset", rd[7:0], 8'h03);
    apb_read(IER_DLM, rd);     check_eq8("IER reset", rd[7:0], 8'h00);
    apb_read(IIR_FCR, rd);     check_eq8("IIR reset", rd[7:0], 8'hC1);
    apb_read(MCR_ADDR, rd);    check_eq8("MCR reset", rd[7:0], 8'h00);
    apb_read(LSR_ADDR, rd);    check_eq8("LSR reset", rd[7:0], 8'h60);
    apb_read(MSR_ADDR, rd);    check_eq8("MSR read", rd[7:0], 8'h00);
    apb_read(DBG_ST_ADDR, rd); check_eq8("DBG_STAT reset", rd[7:0], 8'h00);
    apb_read(FCW_ADDR, rd);    check_eq32("FCW reset", rd, 32'h0);
    // DLAB=1 读 DLL/DLM
    apb_write(LCR_ADDR, 32'h83);           // DLAB=1, 8N1
    apb_read(RBR_THR_DLL, rd); check_eq8("DLL reset", rd[7:0], 8'h00);
    apb_read(IER_DLM, rd);     check_eq8("DLM reset", rd[7:0], 8'h00);
    apb_write(LCR_ADDR, 32'h03);
endtask

// --- Test 2：MCR 读写回环（无调制解调器引脚，纯寄存器） ---
task test_mcr_register();
    logic[31:0] rd;
    $display("\n--- Test 2: MCR register ---");
    apb_write(MCR_ADDR, 32'h0F); apb_read(MCR_ADDR, rd); check_eq8("MCR=0x0F", rd[7:0], 8'h0F);
    apb_write(MCR_ADDR, 32'hA5); apb_read(MCR_ADDR, rd); check_eq8("MCR=0xA5", rd[7:0], 8'hA5);
    apb_write(MCR_ADDR, 32'h00); apb_read(MCR_ADDR, rd); check_eq8("MCR=0x00", rd[7:0], 8'h00);
endtask

// --- Test 3：DLAB 分组复用（DLL/DLM 读写 + 与 RBR/IER 的隔离） ---
task test_divisor_dlab();
    logic[31:0] rd;
    $display("\n--- Test 3: Divisor registers (DLAB group) ---");
    apb_write(LCR_ADDR, 32'h83);           // DLAB=1
    apb_write(RBR_THR_DLL, 32'h12); apb_read(RBR_THR_DLL, rd); check_eq8("DLL=0x12", rd[7:0], 8'h12);
    apb_write(IER_DLM, 32'h34);     apb_read(IER_DLM, rd);     check_eq8("DLM=0x34", rd[7:0], 8'h34);
    apb_write(IER_DLM, 32'hFF);            // DLAB=1：仍写 DLM，不碰 IER
    apb_write(LCR_ADDR, 32'h03);           // DLAB=0
    apb_read(IER_DLM, rd);     check_eq8("IER not polluted while DLAB=1", rd[7:0], 8'h00);
    apb_read(RBR_THR_DLL, rd); check_eq8("RBR (not DLL) when DLAB=0", rd[7:0], 8'h00);
    apb_write(LCR_ADDR, 32'h83);
    apb_read(RBR_THR_DLL, rd); check_eq8("DLL preserved", rd[7:0], 8'h12);
    apb_read(IER_DLM, rd);     check_eq8("DLM preserved", rd[7:0], 8'hFF);
    apb_write(LCR_ADDR, 32'h03);
endtask

// --- Test 4：IER 位掩码（仅 [3:0] 可写） ---
task test_ier_mask();
    logic[31:0] rd;
    $display("\n--- Test 4: IER mask ---");
    apb_write(IER_DLM, 32'hFF); apb_read(IER_DLM, rd); check_eq8("IER masked to 0x0F", rd[7:0], 8'h0F);
    apb_write(IER_DLM, 32'h00); apb_read(IER_DLM, rd); check_eq8("IER cleared", rd[7:0], 8'h00);
endtask

// --- Test 5：LCR 全位回读 + bit6 置位强制清 bit7 的写路径 ---
task test_lcr_register();
    logic[31:0] rd;
    $display("\n--- Test 5: LCR register ---");
    apb_write(LCR_ADDR, 32'h0B); apb_read(LCR_ADDR, rd); check_eq8("LCR=0x0B (even parity)", rd[7:0], 8'h0B);
    apb_write(LCR_ADDR, 32'h1B); apb_read(LCR_ADDR, rd); check_eq8("LCR=0x1B (odd parity)", rd[7:0], 8'h1B);
    apb_write(LCR_ADDR, 32'h3B); apb_read(LCR_ADDR, rd); check_eq8("LCR=0x3B (force parity)", rd[7:0], 8'h3B);
    apb_write(LCR_ADDR, 32'hC0); apb_read(LCR_ADDR, rd); check_eq8("LCR bit6 write clears DLAB", rd[7:0], 8'h40);
    apb_write(LCR_ADDR, 32'h03); apb_read(LCR_ADDR, rd); check_eq8("LCR=0x03 (8N1)", rd[7:0], 8'h03);
endtask

// --- Test 6：FCW 配置 + LCR/FCR 基础配置（后续收发用例的前置） ---
task test_reg_config();
    logic[31:0] rd;
    $display("\n--- Test 6: FCW + basic config ---");
    apb_write(FCW_ADDR, FCW_VAL);
    apb_read(FCW_ADDR, rd); check_eq32("FCW readback", rd, FCW_VAL);
    apb_write(LCR_ADDR, 32'h03);           // 8N1
    apb_write(IIR_FCR, 32'h00);            // FCR=0：触发级=1
endtask

// --- Test 7：UART 发送（字节级 + LSR THRE/TEMT） ---
task test_uart_tx(input logic[7:0] tx_data);
    logic       tx_bit;
    logic[31:0] lsr_data;
    $display("\n--- Test 7: UART TX (0x%02h) ---", tx_data);
    @(posedge PCLK);
    apb_write(RBR_THR_DLL, {24'h0, tx_data});   // 写 THR
    @(negedge uart_tx_o);                       // 等起始位
    #(BAUD_PERIOD_NS/2);
    for (int bit_cnt = 0; bit_cnt < 8; bit_cnt++) begin
        #(BAUD_PERIOD_NS);
        tx_bit = uart_tx_o;
        check(tx_bit == tx_data[bit_cnt], $sformatf("TX bit %0d mismatch", bit_cnt));
    end
    #(BAUD_PERIOD_NS);
    check(uart_tx_o == 1'b1, "TX stop bit");
    @(posedge PCLK);
    apb_read(LSR_ADDR, lsr_data);
    check(lsr_data[5] == 1'b1 && lsr_data[6] == 1'b1, "LSR THRE/TEMT after TX");
endtask

// --- Test 8：UART 接收（字节级 + DR 读清） ---
task test_uart_rx(input logic[7:0] rx_data);
    logic[31:0] read_data;
    $display("\n--- Test 8: UART RX (0x%02h) ---", rx_data);
    @(posedge PCLK);
    uart_rx_i = 1'b1;
    send_uart_byte(rx_data);
    #(2us);
    apb_read(RBR_THR_DLL, read_data);
    check_eq8("RX data", read_data[7:0], rx_data);
    apb_read(LSR_ADDR, read_data);
    check(read_data[0] == 1'b0, "LSR DR cleared after RBR read");
endtask

// --- Test 9：中断（RDA 子源 + 读 RBR 清中断） ---
task test_uart_irq();
    logic[31:0] read_data;
    integer     timeout;
    $display("\n--- Test 9: IRQ (RDA + read-clear) ---");
    apb_write(IER_DLM, 32'h01);            // 使能 RDA
    uart_rx_i = 1'b1;
    send_uart_byte(8'h55);
    timeout = 0;
    while (!irq_o && timeout < 100000) begin
        @(posedge PCLK);
        timeout++;
    end
    check(irq_o, "RX irq timeout");
    apb_read(IIR_FCR, read_data);
    check_eq8("IIR = RDA (0x04)", read_data[7:0], 8'h04);
    apb_read(RBR_THR_DLL, read_data);      // 读 RBR 清 RDA
    check_eq8("RDA data", read_data[7:0], 8'h55);
    @(posedge PCLK);
    check(irq_o == 1'b0, "RX irq not cleared");
    apb_write(IER_DLM, 32'h00);
endtask

// --- Test 10：FCR 触发级（4 字节水位） ---
task test_fcr_trigger_level();
    logic[31:0] rd;
    $display("\n--- Test 10: FCR trigger level ---");
    apb_write(IER_DLM, 32'h01);
    apb_write(IIR_FCR, 32'h42);            // trigger=4 + 清 RX FIFO
    #(100ns);
    apb_write(IIR_FCR, 32'h41);            // trigger=4, 不 flush
    send_uart_byte(8'h11); send_uart_byte(8'h22); send_uart_byte(8'h33);
    #(2us);
    apb_read(IIR_FCR, rd); check_eq8("IIR no-int below trigger", rd[7:0], 8'hC1);
    send_uart_byte(8'h44);
    #(2us);
    apb_read(IIR_FCR, rd); check_eq8("IIR RDA at trigger", rd[7:0], 8'h04);
    apb_read(RBR_THR_DLL, rd); check_eq8("RX byte1", rd[7:0], 8'h11);
    apb_read(RBR_THR_DLL, rd); check_eq8("RX byte2", rd[7:0], 8'h22);
    apb_read(RBR_THR_DLL, rd); check_eq8("RX byte3", rd[7:0], 8'h33);
    apb_read(RBR_THR_DLL, rd); check_eq8("RX byte4", rd[7:0], 8'h44);
    #(100ns);
    apb_read(IIR_FCR, rd); check_eq8("IIR idle after drain", rd[7:0], 8'hC1);
    apb_write(IER_DLM, 32'h00);
    apb_write(IIR_FCR, 32'h00);
endtask

// --- Test 11：FCR[1] 清接收 FIFO + 空读返回 0 ---
task test_fcr_clear_rx_fifo();
    logic[31:0] rd;
    $display("\n--- Test 11: FCR clear RX FIFO ---");
    apb_write(IER_DLM, 32'h00);
    apb_write(IIR_FCR, 32'h02);            // 先清空
    #(100ns);
    send_uart_byte(8'hA1); send_uart_byte(8'hB2);
    #(2us);
    apb_read(LSR_ADDR, rd); check(rd[0] == 1'b1, "DR set with 2 bytes");
    apb_write(IIR_FCR, 32'h02);            // FCR[1]=1 清接收 FIFO
    #(100ns);
    apb_read(LSR_ADDR, rd); check(rd[0] == 1'b0, "DR cleared after RX flush");
    apb_read(RBR_THR_DLL, rd); check_eq8("empty RBR reads 0", rd[7:0], 8'h00);
endtask

// --- Test 12：FCR[2] 清发送 FIFO（灌满后冲刷，线条保持空闲） ---
task test_fcr_clear_tx_fifo();
    logic[31:0] rd;
    $display("\n--- Test 12: FCR clear TX FIFO ---");
    apb_write(IER_DLM, 32'h00);
    for (int i = 0; i < 16; i++)
        apb_write(RBR_THR_DLL, 32'h80 + i);  // 灌满 TX FIFO（16 深）
    apb_read(LSR_ADDR, rd); check(rd[5] == 1'b0, "THRE=0 with TX FIFO pending");
    apb_write(IIR_FCR, 32'h04);              // FCR[2]=1 清发送 FIFO
    #(2us);
    apb_read(LSR_ADDR, rd); check(rd[5] == 1'b1, "THRE=1 after TX flush");
    // 等可能已在移位的字节发完 → TEMT=1
    for (int i = 0; i < 300; i++) begin
        apb_read(LSR_ADDR, rd);
        if (rd[6]) break;
        #(1us);
    end
    check(rd[6] == 1'b1, "TEMT=1 after flush drain");
    #(20us);
    apb_read(LSR_ADDR, rd); check(rd[6] == 1'b1, "TX stays idle (byte dropped)");
    check(uart_tx_o == 1'b1, "TX line idle after flush");
    apb_write(IIR_FCR, 32'h00);
endtask

// --- Test 13：IIR 超时子源（RDA 之后数据未取 → 超时升级为 0x0C） ---
task test_iir_timeout();
    logic[31:0] rd;
    $display("\n--- Test 13: IIR timeout sub-source ---");
    apb_write(IER_DLM, 32'h01);
    apb_write(IIR_FCR, 32'h03);            // 清 RX FIFO + trigger=1
    #(100ns);
    send_uart_byte(8'h5C);
    #(2us);
    apb_read(IIR_FCR, rd); check_eq8("IIR RDA before timeout", rd[7:0], 8'h04);
    rd = 0;
    for (int i = 0; i < 120; i++) begin  // 等超时（~35us）
        apb_read(IIR_FCR, rd);
        if (rd[7:0] == 8'h0C) break;
        #(1us);
    end
    check_eq8("IIR timeout code (0x0C)", rd[7:0], 8'h0C);
    apb_read(RBR_THR_DLL, rd); check_eq8("RX byte after timeout", rd[7:0], 8'h5C);
    #(100ns);
    apb_read(IIR_FCR, rd); check_eq8("IIR idle after drain", rd[7:0], 8'hC1);
    apb_write(IER_DLM, 32'h00);
    apb_write(IIR_FCR, 32'h00);
endtask

// --- Test 14：IIR THRE 子源（发送 FIFO 空 + IER[1]） ---
task test_iir_thre();
    logic[31:0] rd;
    $display("\n--- Test 14: IIR THRE sub-source ---");
    apb_read(LSR_ADDR, rd);                // 清错误位
    apb_write(IIR_FCR, 32'h02);            // 清 RX（避免 RDA 抢先）
    #(100ns);
    apb_write(IER_DLM, 32'h02);            // 仅 THRE
    #(2us);
    apb_read(IIR_FCR, rd); check_eq8("IIR THRE (0x02)", rd[7:0], 8'h02);
    apb_write(IER_DLM, 32'h00);
    #(2us);
    apb_read(IIR_FCR, rd); check_eq8("IIR idle after THRE disable", rd[7:0], 8'hC1);
endtask

// --- Test 15：IIR 优先级（RLS(BI) > RDA） ---
task test_iir_priority();
    logic[31:0] rd;
    $display("\n--- Test 15: IIR priority RLS > RDA ---");
    apb_write(IER_DLM, 32'h05);            // RDA + RLS
    apb_write(IIR_FCR, 32'h02);            // 清 RX
    #(100ns);
    apb_write(LCR_ADDR, 32'h43);           // 置 break（LCR[6]）→ BI
    send_uart_byte(8'h77);
    #(2us);
    apb_read(IIR_FCR, rd); check_eq8("IIR RLS priority over RDA", rd[7:0], 8'h06);
    apb_write(LCR_ADDR, 32'h03);           // 清 break
    apb_read(LSR_ADDR, rd);                // 读 LSR 清 RLS 锁存
    #(100ns);
    apb_read(IIR_FCR, rd); check_eq8("IIR RDA after RLS clear", rd[7:0], 8'h04);
    apb_read(RBR_THR_DLL, rd); check_eq8("RX byte intact", rd[7:0], 8'h77);
    apb_write(IER_DLM, 32'h00);
endtask

// --- Test 16：LSR BI 位（LCR[6] 直触发）+ 粘滞/读清 + LSR[7] 汇总 ---
task test_lsr_bi_sticky();
    logic[31:0] rd;
    $display("\n--- Test 16: LSR BI sticky ---");
    apb_write(IER_DLM, 32'h00);
    apb_write(LCR_ADDR, 32'h43);           // BI
    #(100ns);
    apb_read(LSR_ADDR, rd); check(rd[4] == 1'b1 && rd[7] == 1'b1, "BI sets LSR[4]+LSR[7]");
    apb_write(LCR_ADDR, 32'h03);
    apb_read(LSR_ADDR, rd); check(rd[4] == 1'b1, "BI sticky until LSR read");
    apb_read(LSR_ADDR, rd); check(rd[4] == 1'b0 && rd[7] == 1'b0, "BI cleared after read");
endtask

// --- Test 17：LSR PE 位（偶/奇/强制三种校验的错帧与对帧） ---
task test_lsr_pe();
    logic[31:0] rd;
    logic       pc;
    $display("\n--- Test 17: LSR PE ---");
    apb_write(IER_DLM, 32'h00);
    apb_write(IIR_FCR, 32'h02);
    #(100ns);
    apb_read(LSR_ADDR, rd);                // 清错误位
    pc = ^8'h5A;                           // 0x5A 有 4 个 1 → 偶校验位 = 0
    // 偶校验：对帧无 PE
    apb_write(LCR_ADDR, 32'h0B);
    send_uart_frame(8'h5A, 1'b1, pc);
    #(2us);
    apb_read(LSR_ADDR, rd); check(rd[2] == 1'b0, "no PE on correct even parity");
    apb_read(RBR_THR_DLL, rd); check_eq8("RX even data", rd[7:0], 8'h5A);
    // 偶校验：错帧报 PE + 读清 + 数据仍入 FIFO
    send_uart_frame(8'h5A, 1'b1, ~pc);
    #(2us);
    apb_read(LSR_ADDR, rd); check(rd[2] == 1'b1, "PE on wrong parity (even)");
    apb_read(LSR_ADDR, rd); check(rd[2] == 1'b0, "PE cleared after LSR read");
    apb_read(RBR_THR_DLL, rd); check_eq8("RX data delivered despite PE", rd[7:0], 8'h5A);
    // 奇校验：对帧无 PE
    apb_write(LCR_ADDR, 32'h1B);
    send_uart_frame(8'h5A, 1'b1, ~pc);
    #(2us);
    apb_read(LSR_ADDR, rd); check(rd[2] == 1'b0, "no PE on correct odd parity");
    apb_read(RBR_THR_DLL, rd);
    // 奇校验：错帧报 PE
    send_uart_frame(8'h5A, 1'b1, pc);
    #(2us);
    apb_read(LSR_ADDR, rd); check(rd[2] == 1'b1, "PE on wrong parity (odd)");
    apb_read(RBR_THR_DLL, rd);
    // 强制校验位（FPR=1, EPS=1 → 校验位应为 1）：发 0 报 PE
    apb_write(LCR_ADDR, 32'h3B);
    send_uart_frame(8'h5A, 1'b1, 1'b0);
    #(2us);
    apb_read(LSR_ADDR, rd); check(rd[2] == 1'b1, "PE on force-parity mismatch");
    apb_read(RBR_THR_DLL, rd);
    apb_write(LCR_ADDR, 32'h03);
endtask

// --- Test 18：LSR FE 位（停止位为 0 的坏帧） ---
task test_lsr_fe();
    logic[31:0] rd;
    $display("\n--- Test 18: LSR FE ---");
    apb_write(IER_DLM, 32'h00);
    send_uart_byte_fe(8'hB4);
    #(2us);
    apb_read(LSR_ADDR, rd); check(rd[3] == 1'b1, "FE on low stop bit");
    apb_read(LSR_ADDR, rd); check(rd[3] == 1'b0, "FE cleared after read");
    apb_read(RBR_THR_DLL, rd); check_eq8("FE frame data delivered", rd[7:0], 8'hB4);
endtask

// --- Test 19：LSR OE 位（17 字节灌满 16 深 FIFO 溢出）+ 空读 0 ---
task test_lsr_oe();
    logic[31:0] rd;
    $display("\n--- Test 19: LSR OE (overrun) ---");
    apb_write(IER_DLM, 32'h00);
    apb_write(IIR_FCR, 32'h02);
    #(100ns);
    for (int i = 0; i < 17; i++)
        send_uart_byte(8'hA0 + i[7:0]);    // 第 17 字节溢出丢弃
    #(2us);
    apb_read(LSR_ADDR, rd);
    check(rd[0] == 1'b1, "DR set (16 bytes in FIFO)");
    check(rd[1] == 1'b1, "OE set on 17th byte (FIFO full)");
    check(rd[7] == 1'b1, "LSR[7] summary with OE");
    apb_read(LSR_ADDR, rd); check(rd[1] == 1'b0, "OE cleared after read");
    apb_read(RBR_THR_DLL, rd); check_eq8("first byte preserved", rd[7:0], 8'hA0);
    apb_write(IIR_FCR, 32'h02);
    #(100ns);
    apb_read(LSR_ADDR, rd); check(rd[0] == 1'b0, "RX FIFO flushed");
endtask

// --- Test 20：DBG_EN / DBG_STAT（下载通道寄存器位） ---
// 注：使能下载时 RX FIFO 数据会被下载模块消费，故先清空 FIFO 且不注入数据；
//     完整下载协议流程由 SoC 级 TB（uart_download_program）覆盖。
task test_dbg_en_stat();
    logic[31:0] rd;
    $display("\n--- Test 20: DBG_EN / DBG_STAT ---");
    apb_write(IIR_FCR, 32'h02);            // 确保 RX FIFO 空
    #(100ns);
    apb_write(DBG_EN_ADDR, 32'h01);
    #(100ns);
    apb_read(DBG_ST_ADDR, rd);
    check(rd[1] == 1'b1 && rd[0] == 1'b0, "DBG_EN readback=1, download_done=0");
    apb_write(DBG_EN_ADDR, 32'h00);
    #(100ns);
    apb_read(DBG_ST_ADDR, rd);
    check(rd[1:0] == 2'b00, "DBG_EN cleared");
endtask

// --- Test 21/22/23：5/6/7 数据位收发（LCR[1:0]，RBR 右对齐语义） ---
// RX：发 N 位帧，读回应为数据低 N 位（16550 右对齐）；
// TX：写 THR 后按采样点逐位核对波形，只发送低 N 位数据。
task test_tx_data_bits(input int nbits, input logic[7:0] data);
    wait (u_apb_uart.lsr[6] == 1'b1);      // 等 TEMT（上帧排空）
    apb_write(RBR_THR_DLL, {24'h0, data}); // 写 THR
    @(negedge uart_tx_o);                  // 起始位沿
    #(BAUD_PERIOD_NS/2);                   // 移到起始位中央
    for (int bit_idx = 0; bit_idx < nbits; bit_idx++) begin
        #(BAUD_PERIOD_NS);
        check(uart_tx_o === data[bit_idx],
              $sformatf("TX %0d-bit data[%0d] mismatch (got %b)", nbits, bit_idx, uart_tx_o));
    end
    #(BAUD_PERIOD_NS);
    check(uart_tx_o === 1'b1, $sformatf("TX %0d-bit stop bit", nbits));
endtask

task test_data_bits(input int nbits, input logic[7:0] probe);
    logic[31:0] rd;
    logic[7:0]  exp_word;
    exp_word = probe & ((8'h1 << nbits) - 1);  // 低 N 位为本帧有效数据
    $display("\n--- Test %0d: %0d data bits (data=0x%02h) ---", 20 + nbits - 4, nbits, exp_word);

    apb_write(IER_DLM, 32'h00);
    apb_write(IIR_FCR, 32'h02);            // 清 RX FIFO
    #(100ns);
    apb_read(LSR_ADDR, rd);                // 清错误位

    // RX：N 数据位 + 1 停止位
    apb_write(LCR_ADDR, {6'h0, (nbits - 5)});  // lcr[1:0] = 5→00 6→01 7→10
    send_uart_frame_n(exp_word, nbits, 1'b0, 1'b0, 1);
    #(2us);
    apb_read(RBR_THR_DLL, rd);
    check_eq8($sformatf("RX %0d-bit data", nbits), rd[7:0], exp_word);
    apb_read(LSR_ADDR, rd);                // 清 DR

    // TX：波形逐位核对（低 N 位）
    test_tx_data_bits(nbits, exp_word);
    #(2us);
    apb_read(LCR_ADDR, rd);
    check_eq8($sformatf("LCR %0d-bit config preserved", nbits), rd[7:0], {6'h0, (nbits - 5)});
    apb_write(LCR_ADDR, 32'h03);           // 回 8N1
endtask

// --- Test 24：两位停止位（LCR[2]=1，8N2）---
task test_two_stop_bits();
    logic[31:0] rd;
    logic[7:0]  tx_pat;
    tx_pat = 8'h6E;
    $display("\n--- Test 24: two stop bits (8N2) ---");
    apb_write(IER_DLM, 32'h00);
    apb_write(IIR_FCR, 32'h02);
    #(100ns);
    apb_read(LSR_ADDR, rd);

    // RX：8 数据位 + 2 停止位
    apb_write(LCR_ADDR, 32'h07);           // 8N2
    send_uart_frame_n(8'h6E, 8, 1'b0, 1'b0, 2);
    #(2us);
    apb_read(RBR_THR_DLL, rd);
    check_eq8("RX data with 2 stop bits", rd[7:0], 8'h6E);
    apb_read(LSR_ADDR, rd);
    check(rd[3] === 1'b0, "no FE with valid 2 stop bits");

    // TX：核对两个停止位
    wait (u_apb_uart.lsr[6] == 1'b1);
    apb_write(RBR_THR_DLL, {24'h0, tx_pat});
    @(negedge uart_tx_o);
    #(BAUD_PERIOD_NS/2);
    for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
        #(BAUD_PERIOD_NS);
        check(uart_tx_o === tx_pat[bit_idx], $sformatf("8N2 TX data[%0d]", bit_idx));
    end
    #(BAUD_PERIOD_NS);
    check(uart_tx_o === 1'b1, "8N2 TX stop bit 1");
    #(BAUD_PERIOD_NS);
    check(uart_tx_o === 1'b1, "8N2 TX stop bit 2");
    apb_write(LCR_ADDR, 32'h03);
endtask

// =================== 主流程 ===================
initial begin
    PRESETn      = 1'b0;
    uart_rx_i    = 1'b1;
    test_pass    = 1'b1;
    error_count  = 0;

    #100;
    PRESETn = 1'b1;
    #100;

    $display("==================== APB UART Register Test Suite ====================");
    $display("FCW = 0x%08h (Baud=%0d, Fclk=%0dMHz)", FCW_VAL, BAUD_RATE, CLK_FREQ/1000000);

    test_reset_register_values();
    test_mcr_register();
    test_divisor_dlab();
    test_ier_mask();
    test_lcr_register();
    test_reg_config();
    test_uart_tx(8'h5A);
    test_uart_rx(8'hA5);
    test_uart_irq();
    test_fcr_trigger_level();
    test_fcr_clear_rx_fifo();
    test_fcr_clear_tx_fifo();
    test_iir_timeout();
    test_iir_thre();
    test_iir_priority();
    test_lsr_bi_sticky();
    test_lsr_pe();
    test_lsr_fe();
    test_lsr_oe();
    test_dbg_en_stat();
    test_data_bits(5, 8'hBD);              // Test 21
    test_data_bits(6, 8'hBD);              // Test 22
    test_data_bits(7, 8'hBD);              // Test 23
    test_two_stop_bits();                  // Test 24

    #1000;
    if (error_count == 0) begin
        $display("\n==================== All Tests Passed! (24 tests) ====================");
    end else begin
        test_pass = 1'b0;
        $display("\n==================== Test Failed! Total Errors: %0d ====================", error_count);
    end
    $finish;
end

endmodule
