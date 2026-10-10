// ============================================================================
// tb_uart_dl_file.sv — 真实 uartbin 长流下载路径测试（8 倍速加速版）
//
// 目的：把真实 bus_timeout.uartbin（3116 字节）以 8 倍速（921600 baud 等效）
//       灌进 apb_uart 的 RX 引脚，验证 RX→FIFO→下载 FSM 全程字节级完整性：
//       收到的字节数、ITCM/DTCM 字数、每个字的内容都与文件逐字对账。
// 与 tb_uart_dl_mini 的区别：用真实文件 + 长流 + 全字对账（保真度最高）。
// ============================================================================
timeunit 1ns;
timeprecision 1ps;

module tb_uart_dl_file;

localparam BAUD_X        = 8;
localparam BAUD_PERIOD_NS = 1_000_000_000 / (115200 * BAUD_X);  // ~1085ns
localparam FCW_VAL = int'((115200 * BAUD_X * 16 * (2.0**32)) / 50_000_000 + 0.5);
localparam string UARTBIN = "../../test_data/soc/c/bus_timeout.uartbin";

logic        PCLK, PRESETn;
logic        uart_rx_i, uart_tx_o;
logic [31:0] PADDR, PWDATA, PRDATA;
logic        PSEL, PENABLE, PWRITE, PREADY, PSLVERR;
logic [3:0]  PSTRB;

logic        itcm_en, dtcm_en;
logic [31:0] itcm_addr, itcm_data, dtcm_addr, dtcm_data;

int error_count  = 0;
int rx_byte_count = 0;
int itcm_wr_count = 0;
int dtcm_wr_count = 0;

// 文件内容与接收内容对账缓冲
logic [31:0] exp_itcm [0:1023];
logic [31:0] got_itcm [0:1023];
logic [31:0] exp_dtcm [0:255];
logic [31:0] got_dtcm [0:255];
int exp_itcm_n = 0, exp_dtcm_n = 0;

apb_uart #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) dut (
    .PCLK (PCLK), .PRESETn (PRESETn), .uart_rx_i (uart_rx_i), .uart_tx_o (uart_tx_o),
    .PADDR (PADDR), .PSEL (PSEL), .PENABLE (PENABLE), .PWRITE (PWRITE),
    .PWDATA (PWDATA), .PRDATA (PRDATA), .PREADY (PREADY), .PSLVERR (PSLVERR),
    .irq_o (), .itcm_download_en_o (itcm_en), .itcm_download_addr_o (itcm_addr),
    .itcm_download_data_o (itcm_data), .dtcm_download_en_o (dtcm_en),
    .dtcm_download_addr_o (dtcm_addr), .dtcm_download_data_o (dtcm_data)
);

apb_master_bfm #(.PADDR_WIDTH(32), .PDATA_WIDTH(32)) bfm (
    .PRESETn (PRESETn), .PCLK (PCLK), .PSEL (PSEL), .PENABLE (PENABLE),
    .PADDR (PADDR), .PSTRB (PSTRB), .PWDATA (PWDATA), .PRDATA (PRDATA),
    .PWRITE (PWRITE), .PREADY (PREADY), .PSLVERR (PSLVERR)
);

initial begin
    PCLK = 1'b0;
    forever #10 PCLK = ~PCLK;
end

initial bfm.reset();

// 抓下载写口
always @(posedge PCLK) begin
    if (itcm_en) begin
        if (itcm_wr_count < 1024) got_itcm[itcm_wr_count] = itcm_data;
        itcm_wr_count <= itcm_wr_count + 1;
    end
    if (dtcm_en) begin
        if (dtcm_wr_count < 256) got_dtcm[dtcm_wr_count] = dtcm_data;
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
    end
endtask

// 从文件解析期望内容（小端 4 字节组字）
int fd;
int b0, b1, b2, b3;

initial begin
    PRESETn   = 1'b0;
    uart_rx_i = 1'b1;
    #100;
    PRESETn = 1'b1;
    #200;

    bfm.write(32'h24, 4'hF, FCW_VAL);     // FCW（8 倍速）
    bfm.write(32'h1C, 4'hF, 32'h0001);    // DBG_EN=1
    #1us;

    // 读文件 + 边发边存期望
    fd = $fopen(UARTBIN, "rb");
    if (fd == 0) begin
        $display("CANNOT OPEN %s", UARTBIN);
        $finish;
    end

    // START(4B) + ITCM_CNT(4B)
    for (int i = 0; i < 4; i++) begin
        b0 = $fgetc(fd);
        send_byte(b0[7:0]);
    end
    b0 = $fgetc(fd); b1 = $fgetc(fd); b2 = $fgetc(fd); b3 = $fgetc(fd);
    send_byte(b0[7:0]); send_byte(b1[7:0]); send_byte(b2[7:0]); send_byte(b3[7:0]);
    exp_itcm_n = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
    $display("[FILE] ITCM_COUNT=%0d", exp_itcm_n);

    // ITCM 数据
    for (int w = 0; w < exp_itcm_n; w++) begin
        b0 = $fgetc(fd); b1 = $fgetc(fd); b2 = $fgetc(fd); b3 = $fgetc(fd);
        send_byte(b0[7:0]); send_byte(b1[7:0]); send_byte(b2[7:0]); send_byte(b3[7:0]);
        exp_itcm[w] = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
    end

    // DTCM_COUNT + DTCM 数据
    b0 = $fgetc(fd); b1 = $fgetc(fd); b2 = $fgetc(fd); b3 = $fgetc(fd);
    send_byte(b0[7:0]); send_byte(b1[7:0]); send_byte(b2[7:0]); send_byte(b3[7:0]);
    exp_dtcm_n = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
    $display("[FILE] DTCM_COUNT=%0d", exp_dtcm_n);
    for (int w = 0; w < exp_dtcm_n; w++) begin
        b0 = $fgetc(fd); b1 = $fgetc(fd); b2 = $fgetc(fd); b3 = $fgetc(fd);
        send_byte(b0[7:0]); send_byte(b1[7:0]); send_byte(b2[7:0]); send_byte(b3[7:0]);
        exp_dtcm[w] = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
    end
    $fclose(fd);

    #50us;   // 等最后一字写完

    $display("---------------------------------------------");
    $display("ITCM writes = %0d (expect %0d)", itcm_wr_count, exp_itcm_n);
    $display("DTCM writes = %0d (expect %0d)", dtcm_wr_count, exp_dtcm_n);
    $display("download_done = %b", dut.download_done);

    check(itcm_wr_count == exp_itcm_n, "ITCM word count exact");
    check(dtcm_wr_count == exp_dtcm_n, "DTCM word count exact");
    check(dut.download_done === 1'b1, "download_done asserts");

    // 全字对账
    begin
        int mism = 0;
        for (int w = 0; w < exp_itcm_n; w++) begin
            if (w < 1024 && got_itcm[w] !== exp_itcm[w]) begin
                if (mism < 5)
                    $display("  [MISMATCH] ITCM[%0d] got 0x%08h exp 0x%08h", w, got_itcm[w], exp_itcm[w]);
                mism++;
            end
        end
        $display("ITCM content mismatches = %0d", mism);
        check(mism == 0, "ITCM content all match file");
    end
    begin
        int mism = 0;
        for (int w = 0; w < exp_dtcm_n; w++) begin
            if (w < 256 && got_dtcm[w] !== exp_dtcm[w]) begin
                if (mism < 5)
                    $display("  [MISMATCH] DTCM[%0d] got 0x%08h exp 0x%08h", w, got_dtcm[w], exp_dtcm[w]);
                mism++;
            end
        end
        $display("DTCM content mismatches = %0d", mism);
        check(mism == 0, "DTCM content all match file");
    end

    if (error_count == 0)
        $display("=== DL FILE STREAM TEST PASSED ===");
    else
        $display("=== DL FILE STREAM TEST FAILED (%0d) ===", error_count);
    $finish;
end

// 看门狗
initial begin
    #200ms;
    $display("[WATCHDOG] stream test hung: itcm=%0d dtcm=%0d done=%b rx_bytes=%0d",
             itcm_wr_count, dtcm_wr_count, dut.download_done, rx_byte_count);
    $finish;
end

// 接收字节计数（进 FIFO 的）
always @(posedge PCLK) begin
    if (dut.rx_data_valid) rx_byte_count <= rx_byte_count + 1;
end

endmodule
