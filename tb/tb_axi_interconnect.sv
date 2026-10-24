// ============================================================================
// tb_axi_interconnect.sv — AXI 互联链验证（verification_plan §SoC PLANNED 项完成）
//
// BD32 — RV32IM Pipelined RISC-V SoC
// Copyright (c) 2026 BD32 Project
// SPDX-License-Identifier: Apache-2.0
//
// 被测链（与 SoC_top 同构，全真实 DUT）：
//   axi_lite_master_bfm → AXI_Interconnect ┬─ m0 → AXI_APB_Bridge → APB_Interconnect
//                                          │        └─ GPIO 槽位挂 apb_slave_stub
//                                          ├─ m1 → axi_err_slave（0x8/9/A 段）
//                                          └─ m2 → axi_err_slave（0xB/C 段）
//
// 用例：
//   T1 APB 区写读回环（OKAY + 数据一致）
//   T2 从机随机等待态压力（数据完整性，反压经桥回传 AXI）
//   T3 桩从机 PSLVERR → AXI SLVERR 传播
//   T4 MROM/Flash 段 err_slave：读 0 + OKAY、写接受
//   T5 DDR 段 err_slave：同 T4
//   T6 桩从机不响应（PREADY 保持低）→ 桥超时 → SLVERR（有界完成）
//   T7 未路由段（0xD 段）：无从机握手 → BFM 有界超时（验证不挂死）
// ============================================================================
timeunit 1ns;
timeprecision 1ps;

module tb_axi_interconnect;

localparam logic [31:0] STUB_BASE  = 32'hE000_0000;  // APB GPIO 槽位（桩从机）
localparam logic [31:0] STUB_ERR   = 32'hE000_0800;  // addr[11]=1 → 桩从机 PSLVERR
localparam logic [31:0] MROM_ADDR  = 32'h9000_0000;  // m1 err_slave 段
localparam logic [31:0] DDR_ADDR   = 32'hB000_0000;  // m2 err_slave 段
localparam logic [31:0] DEAD_ADDR  = 32'hD000_0000;  // 未路由段

int error_count = 0;
int test_no     = 0;

logic clk;
logic rst_n;

// =================== 时钟与复位 ===================
initial begin
    clk = 1'b0;
    forever #10 clk = ~clk;     // 50MHz
end

initial begin
    rst_n = 1'b0;
    #200;
    rst_n = 1'b1;
end

// =================== AXI 互联信号 ===================

// =================== AXI-Lite Master BFM ===================
axi_if axi_bus ();        // BFM ↔ AXI 互联
axi_if axi_m0  ();        // 互联.m0 ↔ 桥
axi_if axi_m1  ();        // 互联.m1 ↔ err_slave
axi_if axi_m2  ();        // 互联.m2 ↔ err_slave

axi_lite_master_bfm #(
    .ADDR_WIDTH    (32),
    .DATA_WIDTH    (32),
    .STRB_WIDTH    (4),
    .ID_WIDTH      (4),
    .TIMEOUT_CYCLES(4096)
) bfm (
    .clk        (clk),
    .rst_n      (rst_n),
    .m         (axi_bus)
);

// =================== 互联三个从机口的全部信号 ===================
// m0：APB 桥

// m1/m2：err_slave（同一 shapes）


// =================== DUT：AXI_Interconnect ===================
AXI_Interconnect #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .STRB_WIDTH (4),
    .ID_WIDTH   (4)
) u_interconnect (
    .clk        (clk),
    .rst_n      (rst_n),
    .s          (axi_bus),
    .m0         (axi_m0),
    .m1         (axi_m1),
    .m2         (axi_m2)
);

// =================== DUT：axi_err_slave ×2 ===================
axi_err_slave #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .STRB_WIDTH (4),
    .ID_WIDTH   (4)
) u_err_mrom (
    .clk        (clk),
    .rst_n      (rst_n),
    .s          (axi_m1)
);

axi_err_slave #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .STRB_WIDTH (4),
    .ID_WIDTH   (4)
) u_err_ddr (
    .clk        (clk),
    .rst_n      (rst_n),
    .s          (axi_m2)
);

// APB 接口实例（先声明后使用，避免隐式线网）
apb_if apb_bridge ();        // 桥 ↔ APB 互联
apb_if apb_bus [16] ();      // APB 互联 ↔ 从机槽位

// =================== DUT：AXI_APB_Bridge ===================

AXI_APB_Bridge #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .STRB_WIDTH (4),
    .ID_WIDTH   (4),
    .LEN_WIDTH  (8)
) u_bridge (
    .clk       (clk),
    .rst_n     (rst_n),
    .s          (axi_m0),
    .apb       (apb_bridge)
);

// =================== DUT：APB_Interconnect（16 槽，仅 GPIO 槽挂桩从机）====================
logic        stub_hang;
logic        stub_rand_wait;

APB_Interconnect #(
    .PADDR_WIDTH (32),
    .PDATA_WIDTH (32),
    .NUM_SLAVES  (16)
) u_apb_interconnect (
    .m         (apb_bridge),
    .s         (apb_bus)
);

// 非桩槽位与 SoC_top 同构：PREADY=1, PRDATA=0, PSLVERR=0
generate
    for (genvar g = 0; g < 16; g = g + 1) begin : gen_slot
        if (g != 2) begin : gen_idle
            assign apb_bus[g].prdata  = 32'd0;
            assign apb_bus[g].pready  = 1'b1;
            assign apb_bus[g].pslverr = 1'b0;
        end
    end
endgenerate

// =================== TB 本地桩从机：APB 寄存器块（GPIO 槽位）====================
// 特性：16 字寄存器；SETUP 拍按使能载入 0~3 拍随机等待；PADDR[11]=1 时
// ACCESS 完成拍报 PSLVERR；force_hang 拉低 PREADY（测桥超时路径）。
apb_slave_stub u_stub (
    .PCLK        (clk),
    .PRESETn     (rst_n),
    .s           (apb_bus[2]),
    .force_hang  (stub_hang),
    .rand_wait_en(stub_rand_wait)
);

// =================== 主测试流程 ===================
task automatic check(input bit cond, input string msg);
    if (!cond) begin
        error_count++;
        $display("[T%0d] FAIL: %s", test_no, msg);
    end
endtask

task automatic test_apb_region();
    logic [31:0] rdata_q;
    logic [1:0]  resp;
    bit          ok;
    logic [31:0] pat;

    // T1：写读回环
    test_no = 1;
    bfm.write(STUB_BASE + 0, 32'hA5A5_5A5A, 4'hF, resp, ok);
    check(ok && resp == 2'b00, "T1 write resp not OKAY");
    bfm.read(STUB_BASE + 0, rdata_q, resp, ok);
    check(ok && resp == 2'b00 && rdata_q == 32'hA5A5_5A5A,
          $sformatf("T1 readback mismatch: %h", rdata_q));

    // T2：随机等待态压力，走位数据
    test_no = 2;
    stub_rand_wait = 1'b1;
    for (int i = 0; i < 16; i++) begin
        pat = (32'h0000_0001 << i) | (32'hDEAD_0000 + i * 32'h0101);
        bfm.write(STUB_BASE + i * 4, pat, 4'hF, resp, ok);
        check(ok && resp == 2'b00, $sformatf("T2 write[%0d] resp=%b", i, resp));
    end
    for (int i = 0; i < 16; i++) begin
        pat = (32'h0000_0001 << i) | (32'hDEAD_0000 + i * 32'h0101);
        bfm.read(STUB_BASE + i * 4, rdata_q, resp, ok);
        check(ok && resp == 2'b00 && rdata_q == pat,
              $sformatf("T2 read[%0d] mismatch: got %h want %h", i, rdata_q, pat));
    end
    stub_rand_wait = 1'b0;

    // T3：PSLVERR → SLVERR
    test_no = 3;
    bfm.write(STUB_ERR, 32'h0, 4'hF, resp, ok);
    check(ok && resp == 2'b10, $sformatf("T3 write PSLVERR resp=%b", resp));
    bfm.read(STUB_ERR, rdata_q, resp, ok);
    check(ok && resp == 2'b10, $sformatf("T3 read PSLVERR resp=%b", resp));
endtask

task automatic test_err_slave();
    logic [31:0] rdata_q;
    logic [1:0]  resp;
    bit          ok;

    // T4：MROM/Flash 段
    test_no = 4;
    bfm.read(MROM_ADDR, rdata_q, resp, ok);
    check(ok && resp == 2'b00 && rdata_q == 32'd0,
          $sformatf("T4 err read: data=%h resp=%b", rdata_q, resp));
    bfm.write(MROM_ADDR, 32'h1234_5678, 4'hF, resp, ok);
    check(ok && resp == 2'b00, $sformatf("T4 err write resp=%b", resp));

    // T5：DDR 段
    test_no = 5;
    bfm.read(DDR_ADDR, rdata_q, resp, ok);
    check(ok && resp == 2'b00 && rdata_q == 32'd0,
          $sformatf("T5 err read: data=%h resp=%b", rdata_q, resp));
    bfm.write(DDR_ADDR, 32'h8765_4321, 4'hF, resp, ok);
    check(ok && resp == 2'b00, $sformatf("T5 err write resp=%b", resp));
endtask

task automatic test_timeout_paths();
    logic [31:0] rdata_q;
    logic [1:0]  resp;
    bit          ok;
    realtime     t0;

    // T6：桩从机不响应（PREADY 保持低）→ 桥超时（BUS_TIMEOUT=1024 拍）→ SLVERR
    test_no = 6;
    stub_hang = 1'b1;
    t0 = $realtime;
    bfm.read(STUB_BASE, rdata_q, resp, ok);
    check(ok && resp == 2'b10,
          $sformatf("T6 hung-slave read resp=%b ok=%b", resp, ok));
    check(($realtime - t0) < 40.0us,
          "T6 completion not bounded (bridge timeout too long?)");
    bfm.write(STUB_BASE, 32'h0, 4'hF, resp, ok);
    check(ok && resp == 2'b10, $sformatf("T6 hung-slave write resp=%b", resp));
    stub_hang = 1'b0;

    // T7：未路由段 → 无从机握手 → BFM 有界超时（不挂死 TB）
    test_no = 7;
    t0 = $realtime;
    bfm.read(DEAD_ADDR, rdata_q, resp, ok);
    check(!ok, "T7 unrouted read should hit BFM timeout (ok=0)");
    check(($realtime - t0) < 200.0us, "T7 read not bounded");
    t0 = $realtime;
    bfm.write(DEAD_ADDR, 32'h0, 4'hF, resp, ok);
    check(!ok, "T7 unrouted write should hit BFM timeout (ok=0)");
    check(($realtime - t0) < 200.0us, "T7 write not bounded");
endtask

// BFM 复位线程（等 rst_n 释放）
initial begin
    bfm.reset();
end

initial begin
    stub_hang      = 1'b0;
    stub_rand_wait = 1'b0;
    wait (rst_n === 1'b1);
    repeat (4) @(posedge clk);

    $display("============================================================");
    $display("  AXI Interconnect Chain Test Start");
    $display("============================================================");

    test_apb_region();
    test_err_slave();
    test_timeout_paths();

    repeat (10) @(posedge clk);
    $display("============================================================");
    if (error_count == 0)
        $display("  AXI Interconnect Chain Test: ALL PASSED");
    else
        $display("  AXI Interconnect Chain Test: FAILED (%0d errors)", error_count);
    $display("============================================================");
    $finish;
end

// 超时看门狗：整跑 8ms 上限（正常流程远短于此）
initial begin
    #8_000_000;
    $display("[WATCHDOG] global timeout — test hung");
    $finish;
end

endmodule

// ============================================================================
// APB 从机桩（寄存器块 + 等待态/错误/无响应控制）
// ============================================================================
module apb_slave_stub #(
    parameter NUM_REGS = 16
)(
    input  logic        PCLK,
    input  logic        PRESETn,
    apb_if.slave        s,
    input  logic        force_hang,
    input  logic        rand_wait_en
);
    logic [31:0] regs [NUM_REGS];
    logic [3:0]  wait_cnt;
    logic [3:0]  rd_idx;

    // SETUP 拍载入等待拍数（0~3 随机），ACCESS 期递减
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            wait_cnt <= 4'd0;
        else if (s.psel && !s.penable)
            wait_cnt <= rand_wait_en ? 4'($urandom_range(3)) : 4'd0;
        else if (s.psel && s.penable && wait_cnt != 0)
            wait_cnt <= wait_cnt - 4'd1;
    end

    assign s.pready  = force_hang ? 1'b0 : (wait_cnt == 4'd0);
    // s.paddr[11]=1 → 注入 s.pslverr（ACCESS 完成拍有效语义）
    assign s.pslverr = s.psel && s.penable && s.pready && s.paddr[11];

    assign rd_idx = s.paddr[5:2];
    always_comb begin
        if (rd_idx < NUM_REGS)
            s.prdata = regs[rd_idx];
        else
            s.prdata = 32'd0;
    end

    // 写：ACCESS 完成拍按字节使能写入
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            for (int i = 0; i < NUM_REGS; i++) regs[i] <= 32'd0;
        end else if (s.psel && s.penable && s.pwrite && s.pready) begin
            for (int b = 0; b < 4; b++) begin
                if (s.pstrb[b])
                    regs[rd_idx][b*8 +: 8] <= s.pwdata[b*8 +: 8];
            end
        end
    end
endmodule
