// ============================================================================
// tb_uart_dl_mini.sv — UART RX → 下载 FSM 路径最小直连测试
//
// 目的：绕过 BootROM/CPU/总线，直接驱动 apb_uart 的 UART RX 引脚发送一个
//       20 字节的最小 uartbin（START + ITCM_COUNT=2 + 2 字 + DTCM_COUNT=0），
//       检查 RX 字节流、ITCM 写口与 download_done 是否正确——用于快速定位
//       下载流程停滞是否出在 RX/下载 FSM 串行链路上。
// 用法: 与 uart_test 同 filelist 编译，vsim tb_uart_dl_mini
// ============================================================================
timeunit 1ns;
timeprecision 1ps;

module tb_uart_dl_mini;

localparam BAUD_PERIOD_NS = 1_000_000_000 / 115200;  // ~8680ns
localparam FCW_VAL = int'((115200 * 16 * (2.0**32)) / 50_000_000 + 0.5);

logic        PCLK, PRESETn;
logic        uart_rx_i, uart_tx_o;
apb_if apb();               // APB 总线（BFM ↔ DUT）

// 下载接口
logic        itcm_en, dtcm_en;
logic [31:0] itcm_addr, itcm_data, dtcm_addr, dtcm_data;

int error_count = 0;
int rx_byte_count = 0;
int itcm_wr_count = 0;
logic [31:0] itcm_words [0:7];
logic [31:0] dtcm_words [0:7];
int dtcm_wr_count = 0;

apb_uart #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) dut (
    .PCLK      (PCLK),
    .PRESETn   (PRESETn),
    .uart_rx_i (uart_rx_i),
    .uart_tx_o (uart_tx_o),
    .s      (apb),
    .irq_o     (),
    .itcm_download_en_o    (itcm_en),
    .itcm_download_addr_o  (itcm_addr),
    .itcm_download_data_o  (itcm_data),
    .dtcm_download_en_o    (dtcm_en),
    .dtcm_download_addr_o  (dtcm_addr),
    .dtcm_download_data_o  (dtcm_data)
);

apb_master_bfm #(.PADDR_WIDTH(32), .PDATA_WIDTH(32)) bfm (
    .PRESETn (PRESETn), .PCLK (PCLK),
    .m      (apb)
);

initial begin
    PCLK = 1'b0;
    forever #10 PCLK = ~PCLK;
end

initial bfm.reset();

// RX 字节监视：进 FIFO 的每个字节
always @(posedge PCLK) begin
    if (dut.rx_data_valid) begin
        $display("[RXBYTE %0d] 0x%02h @%0t", rx_byte_count, dut.rx_data_out, $time);
        rx_byte_count <= rx_byte_count + 1;
    end
    if (itcm_en) begin
        $display("[ITCMW] addr=0x%08h data=0x%08h", itcm_addr, itcm_data);
        itcm_words[itcm_wr_count] = itcm_data;
        itcm_wr_count <= itcm_wr_count + 1;
    end
    if (dtcm_en) begin
        $display("[DTCMW] addr=0x%08h data=0x%08h", dtcm_addr, dtcm_data);
        dtcm_words[dtcm_wr_count] = dtcm_data;
        dtcm_wr_count <= dtcm_wr_count + 1;
    end
end

task automatic send_bit(input logic b);
    uart_rx_i = b;
    #(BAUD_PERIOD_NS);
endtask

task automatic send_byte(input logic [7:0] b);
    send_bit(1'b0);
    for (int i = 0; i < 8; i++) send_bit(b[i]);
    send_bit(1'b1);
endtask

task automatic check(input bit cond, input string msg);
    if (!cond) begin
        error_count++;
        $display("  [FAIL] %s", msg);
    end else begin
        $display("  [ok] %s", msg);
    end
endtask

initial begin
    PRESETn   = 1'b0;
    uart_rx_i = 1'b1;
    #100;
    PRESETn = 1'b1;
    #200;

    // 配置：FCW + DBG_EN=1
    bfm.write(32'h24, 4'hF, FCW_VAL);     // FCW
    bfm.write(32'h1C, 4'hF, 32'h0001);    // DBG_EN=1
    #1us;

    // 最小 uartbin：START(AA BB AA BB) + ITCM_COUNT=2 + 2 字 + DTCM_COUNT=0
    send_byte(8'hAA); send_byte(8'hBB); send_byte(8'hAA); send_byte(8'hBB);
    send_byte(8'h02); send_byte(8'h00); send_byte(8'h00); send_byte(8'h00);
    send_byte(8'h11); send_byte(8'h11); send_byte(8'h11); send_byte(8'h11);
    send_byte(8'h22); send_byte(8'h22); send_byte(8'h22); send_byte(8'h22);
    send_byte(8'h00); send_byte(8'h00); send_byte(8'h00); send_byte(8'h00);

    #20us;

    $display("---------------------------------------------");
    $display("RX bytes = %0d (expect 20)", rx_byte_count);
    $display("ITCM writes = %0d (expect 2)", itcm_wr_count);
    $display("DTCM writes = %0d (expect 0)", dtcm_wr_count);
    $display("download_done = %b (expect 1)", dut.download_done);

    check(rx_byte_count == 20, "20 bytes received through RX->FIFO");
    check(rx_byte_count == 20 && itcm_wr_count == 2, "2 ITCM words written");
    check(dtcm_wr_count == 0, "0 DTCM words (count=0)");
    check(dut.download_done === 1'b1, "download_done asserts");
    check(itcm_wr_count >= 1 && itcm_words[0] === 32'h11111111, "ITCM word0 = 0x11111111");
    check(itcm_wr_count >= 2 && itcm_words[1] === 32'h22222222, "ITCM word1 = 0x22222222");

    if (error_count == 0)
        $display("=== MINI DL TEST PASSED ===");
    else
        $display("=== MINI DL TEST FAILED (%0d) ===", error_count);
    $finish;
end

endmodule
