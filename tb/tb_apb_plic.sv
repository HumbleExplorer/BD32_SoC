timeunit 1ns;
timeprecision 1ps;
/*
 * tb_apb_plic.sv - APB PLIC Testbench
 *
 * 测试内容:
 *   - 复位后寄存器默认值检查
 *   - Priority 寄存器读写 (含 source 0 保留、WARL 裁剪)
 *   - Pending 寄存器只读
 *   - Enable 寄存器读写
 *   - Threshold 寄存器读写 (含 WARL 裁剪)
 *   - 中断优先级仲裁
 *   - Claim/Complete 完整流程
 *   - 阈值过滤
 *   - 最低优先级(0)中断不应被响应
 */

module tb_apb_plic;

parameter  PADDR_WIDTH  = 32;
parameter  PDATA_WIDTH  = 32;
parameter  NUM_SOURCES  = 16;   // 含 source 0
parameter  MAX_PRIORITY = 7;
parameter  NUM_TARGETS  = 1;
localparam PSTRB_SIZE   = PDATA_WIDTH/8;

// APB 信号
logic                       PRESETn;
logic                       PCLK;
logic                       PSEL;
logic                       PENABLE;
logic   [PADDR_WIDTH  -1:0] PADDR;
logic   [PSTRB_SIZE   -1:0] PSTRB;
logic   [PDATA_WIDTH  -1:0] PWDATA;
logic   [PDATA_WIDTH  -1:0] PRDATA;
logic                       PWRITE;
logic                       PREADY;
logic                       PSLVERR;

// PLIC 中断信号 (声明时赋初值, 避免复位前不定态传播)
logic   [NUM_SOURCES-1:0]   irq_i = '0;
logic   [NUM_TARGETS-1:0]   irq_o;

// ================================================================
// 地址定义 (byte 地址, 与 PLIC 地址映射一致)
// ================================================================
// Priority: 0x0000 + src*4 (source 0 = 0x0000, source 1 = 0x0004, ...)
localparam PRIO_BASE     = 32'h0000;
// Pending:  0x1000 + word*4 (每 word 32 个源)
localparam PEND_BASE     = 32'h1000;
// Target:   0x2000 + tgt*0x100
localparam TGT_BASE      = 32'h2000;
//   Enable:    +0x00 + word*4
localparam TGT_EN_OFF    = 32'h0000;
//   Threshold: +0x80
localparam TGT_THRESH_OFF= 32'h0080;
//   Claim:     +0x84 (读=claim, 写=complete)
localparam TGT_CLAIM_OFF= 32'h0084;

localparam VERBOSE = 1;

////////////////////////////////////////////////////////////////
//
// Variables
//
int errors;
int test_count;

////////////////////////////////////////////////////////////////
//
// Instantiate the APB Master BFM
//
apb_master_bfm #(
    .PADDR_WIDTH ( PADDR_WIDTH ),
    .PDATA_WIDTH ( PDATA_WIDTH )
) apb_mst_bfm (.*);

// DUT
PLIC #(
    .ADDR_WIDTH     (PADDR_WIDTH),
    .DATA_WIDTH     (PDATA_WIDTH),
    .ALIGN_BYTES    (4),
    .NUM_SOURCES    (NUM_SOURCES),
    .MAX_PRIORITY (MAX_PRIORITY),
    .NUM_TARGETS    (NUM_TARGETS),
    .SYNC_STAGES    (0)         // 测试中旁路同步, 减少延迟
) dut (.*);

////////////////////////////////////////////////////////////////
//
// Clock & Reset
//
initial begin : gen_PCLK
    PCLK <= 1'b0;
    forever #10 PCLK = ~PCLK;
end : gen_PCLK

initial begin : gen_PRESETn
    PRESETn = 1'b1;
    #10;
    PRESETn = 1'b0;
    #32;
    PRESETn = 1'b1;
end : gen_PRESETn

////////////////////////////////////////////////////////////////
//
// Watchdog & Main Stimulus
//
int reset_watchdog, got_reset;

initial
begin
    errors         = 0;
    test_count     = 0;
    reset_watchdog = 0;
    got_reset      = 0;

    forever begin
        reset_watchdog++;
        @(posedge PCLK);
        if (!got_reset && reset_watchdog == 1000)
            $fatal(-1, "PRESETn not asserted\nTestbench requires an APB reset");
    end
end

always @(negedge PRESETn) begin
    @(posedge PRESETn);
    got_reset = 1;

    repeat(5) @(posedge PCLK);
    #1;

    // 复位值检查
    test_reset_values();

    // Priority 寄存器测试
    test_priority_rw();
    test_priority_source0();

    // Enable 寄存器测试
    test_enable_rw();

    // Pending 寄存器只读测试
    test_pending_readonly();

    // Threshold 寄存器测试
    test_threshold_rw();

    // 中断仲裁与 Claim/Complete 流程测试
    test_single_irq_claim_complete();
    test_priority_arbitration();
    test_threshold_filter();
    test_prio0_disabled();
    test_claim_no_irq();

    // 多源并发中断测试
    test_multiple_irq_sources();

    // 结束
    repeat(100) @(posedge PCLK);
    #1;
    finish_text();
    $finish();
end

////////////////////////////////////////////////////////////////
//
// 辅助 task: 寄存器地址计算
//
function automatic [PADDR_WIDTH-1:0] prio_addr(input int src);
    return PRIO_BASE + src * 4;
endfunction

function automatic [PADDR_WIDTH-1:0] pend_addr(input int word_idx);
    return PEND_BASE + word_idx * 4;
endfunction

function automatic [PADDR_WIDTH-1:0] enable_addr(input int tgt, input int word_idx);
    return TGT_BASE + tgt * 'h100 + TGT_EN_OFF + word_idx * 4;
endfunction

function automatic [PADDR_WIDTH-1:0] threshold_addr(input int tgt);
    return TGT_BASE + tgt * 'h100 + TGT_THRESH_OFF;
endfunction

function automatic [PADDR_WIDTH-1:0] claim_addr(input int tgt);
    return TGT_BASE + tgt * 'h100 + TGT_CLAIM_OFF;
endfunction

////////////////////////////////////////////////////////////////
//
// Check / Error Tasks
//
task check(
    input string              name,
    input [PDATA_WIDTH-1:0]   actual,
    input [PDATA_WIDTH-1:0]   expected
);
    #1;
    test_count++;
    if (actual !== expected) error_msg(name, actual, expected);
    else if (VERBOSE > 1) $display("  PASS: %s = %h", name, actual);
endtask : check

task error_msg(
    input string              name,
    input [PDATA_WIDTH-1:0]   actual,
    input [PDATA_WIDTH-1:0]   expected
);
    errors++;
    $display("  FAIL: %s - Expected: %h, Got: %h @%0t", name, expected, actual, $time);
endtask : error_msg

////////////////////////////////////////////////////////////////
//
// Finish Text
//
task finish_text();
    $display("------------------------------------------------------------");
    if (errors > 0)
        $display(" PLIC Testbench: FAIL  (%0d errors, %0d tests) @%0t", errors, test_count, $time);
    else
        $display(" PLIC Testbench: PASS  (%0d tests) @%0t", test_count, $time);
    $display("------------------------------------------------------------");
endtask : finish_text

////////////////////////////////////////////////////////////////
//
// Test: 复位后寄存器默认值
//
task test_reset_values;
    logic [PDATA_WIDTH-1:0] rdata;

    $display("[TEST] Reset values ...");

    // Priority: 所有源复位为 0
    for (int i = 0; i < NUM_SOURCES; i++) begin
        apb_mst_bfm.read(prio_addr(i), rdata);
        check($sformatf("prio[%0d]", i), rdata, 32'h0);
    end

    // Pending word 0
    apb_mst_bfm.read(pend_addr(0), rdata);
    check("pending[0]", rdata, 32'h0);

    // Enable word 0, target 0
    apb_mst_bfm.read(enable_addr(0, 0), rdata);
    check("enable[t0][0]", rdata, 32'h0);

    // Threshold target 0
    apb_mst_bfm.read(threshold_addr(0), rdata);
    check("threshold[0]", rdata, 32'h0);

    // Claim target 0 (读 = claim, 无中断应返回 0)
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("claim[0] (no irq)", rdata, 32'h0);
endtask : test_reset_values

////////////////////////////////////////////////////////////////
//
// Test: Priority 读写
//
task test_priority_rw;
    logic [PDATA_WIDTH-1:0] rdata;

    $display("[TEST] Priority R/W ...");

    // 写 source 1 优先级 = 3
    apb_mst_bfm.write(prio_addr(1), {PSTRB_SIZE{1'b1}}, 32'h3);
    apb_mst_bfm.read(prio_addr(1), rdata);
    check("prio[1]=3", rdata, 32'h3);

    // 写 source 5 优先级 = 7
    apb_mst_bfm.write(prio_addr(5), {PSTRB_SIZE{1'b1}}, 32'h7);
    apb_mst_bfm.read(prio_addr(5), rdata);
    check("prio[5]=7", rdata, 32'h7);

    // 改写 source 1 优先级 = 5
    apb_mst_bfm.write(prio_addr(1), {PSTRB_SIZE{1'b1}}, 32'h5);
    apb_mst_bfm.read(prio_addr(1), rdata);
    check("prio[1]=5", rdata, 32'h5);

    // 清除
    apb_mst_bfm.write(prio_addr(1), {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(prio_addr(5), {PSTRB_SIZE{1'b1}}, 32'h0);
endtask : test_priority_rw

////////////////////////////////////////////////////////////////
//
// Test: Source 0 Priority 始终为 0 (保留)
//
task test_priority_source0;
    logic [PDATA_WIDTH-1:0] rdata;

    $display("[TEST] Priority source 0 reserved ...");

    // 尝试写 source 0 优先级 = 5
    apb_mst_bfm.write(prio_addr(0), {PSTRB_SIZE{1'b1}}, 32'h5);
    apb_mst_bfm.read(prio_addr(0), rdata);
    check("prio[0] always 0", rdata, 32'h0);
endtask : test_priority_source0

////////////////////////////////////////////////////////////////
//
// Test: Enable 读写
//
task test_enable_rw;
    logic [PDATA_WIDTH-1:0] rdata;

    $display("[TEST] Enable R/W ...");

    // 写 enable word 0 = 0x000C (source 2,3)
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h000C);
    apb_mst_bfm.read(enable_addr(0, 0), rdata);
    check("enable[t0][0]=0xC", rdata, 32'h000C);

    // 清除
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.read(enable_addr(0, 0), rdata);
    check("enable[t0][0] clear", rdata, 32'h0);
endtask : test_enable_rw

////////////////////////////////////////////////////////////////
//
// Test: Pending 只读
//
task test_pending_readonly;
    logic [PDATA_WIDTH-1:0] rdata;

    $display("[TEST] Pending readonly ...");

    // 无中断时 pending 应为 0
    apb_mst_bfm.read(pend_addr(0), rdata);
    check("pending[0] no irq", rdata, 32'h0);

    // 写 pending 应无效
    apb_mst_bfm.write(pend_addr(0), {PSTRB_SIZE{1'b1}}, 32'hFFFF);
    apb_mst_bfm.read(pend_addr(0), rdata);
    check("pending[0] after write", rdata, 32'h0);
endtask : test_pending_readonly

////////////////////////////////////////////////////////////////
//
// Test: Threshold 读写
//
task test_threshold_rw;
    logic [PDATA_WIDTH-1:0] rdata;

    $display("[TEST] Threshold R/W ...");

    // 写 threshold = 3
    apb_mst_bfm.write(threshold_addr(0), {PSTRB_SIZE{1'b1}}, 32'h3);
    apb_mst_bfm.read(threshold_addr(0), rdata);
    check("threshold[0]=3", rdata, 32'h3);

    // 清除
    apb_mst_bfm.write(threshold_addr(0), {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.read(threshold_addr(0), rdata);
    check("threshold[0] clear", rdata, 32'h0);
endtask : test_threshold_rw

////////////////////////////////////////////////////////////////
//
// Test: 单源中断 Claim/Complete 完整流程
//
task test_single_irq_claim_complete;
    logic [PDATA_WIDTH-1:0] rdata;

    $display("[TEST] Single IRQ Claim/Complete ...");

    // 配置: source 3 优先级=5, enable source 3, threshold=0
    irq_i = '0;
    apb_mst_bfm.write(prio_addr(3), {PSTRB_SIZE{1'b1}}, 32'h5);
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h8); // bit 3
    apb_mst_bfm.write(threshold_addr(0), {PSTRB_SIZE{1'b1}}, 32'h0);

    // 触发中断: source 3 拉高
    irq_i[3] = 1'b1;
    repeat(3) @(posedge PCLK);  // 等待 gateway 传播
    #1;

    // 检查 irq_o 拉高
    check("irq_o asserted", irq_o[0], 1'b1);

    // 检查 pending bit
    apb_mst_bfm.read(pend_addr(0), rdata);
    check("pending[0] has bit3", rdata[3], 1'b1);

    // Claim: 读取 claim 寄存器, 应返回 source 3
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("claim returns src3", rdata, 32'h3);

    // Claim 后 pending 应被清除 (gateway 关闭)
    apb_mst_bfm.read(pend_addr(0), rdata);
    check("pending[0] after claim", rdata, 32'h0);

    // 撤销中断源 (电平模式: claim 后拉低 irq_i, complete 后 pending 才不会恢复)
    irq_i[3] = 1'b0;
    repeat(3) @(posedge PCLK);
    #1;

    // Complete: 写 source ID = 3
    apb_mst_bfm.write(claim_addr(0), {PSTRB_SIZE{1'b1}}, 32'h3);

    // Complete 后 gateway 重新开放, irq_i 已拉低, pending 应保持 0
    repeat(3) @(posedge PCLK);
    #1;
    apb_mst_bfm.read(pend_addr(0), rdata);
    check("pending[0] after complete", rdata, 32'h0);

    // 清理: 清除配置
    apb_mst_bfm.write(prio_addr(3), {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(threshold_addr(0), {PSTRB_SIZE{1'b1}}, 32'h0);
endtask : test_single_irq_claim_complete

////////////////////////////////////////////////////////////////
//
// Test: 优先级仲裁 - 多源时选出最高优先级
//
task test_priority_arbitration;
    logic [PDATA_WIDTH-1:0] rdata;

    $display("[TEST] Priority arbitration ...");

    // 配置: source 2 优先级=3, source 5 优先级=6, source 8 优先级=4
    // 都 enable, threshold=0
    irq_i = '0;
    apb_mst_bfm.write(prio_addr(2), {PSTRB_SIZE{1'b1}}, 32'h3);
    apb_mst_bfm.write(prio_addr(5), {PSTRB_SIZE{1'b1}}, 32'h6);
    apb_mst_bfm.write(prio_addr(8), {PSTRB_SIZE{1'b1}}, 32'h4);
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h124); // bit 2,5,8
    apb_mst_bfm.write(threshold_addr(0), {PSTRB_SIZE{1'b1}}, 32'h0);

    // 触发三个中断
    irq_i[2] = 1'b1;
    irq_i[5] = 1'b1;
    irq_i[8] = 1'b1;
    repeat(3) @(posedge PCLK);
    #1;

    // Claim 应返回优先级最高的 source 5 (prio=6)
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("arbiter picks src5 (prio=6)", rdata, 32'h5);
    irq_i[5] = 1'b0;  // 拉低已 claim 的中断源

    // Complete source 5
    apb_mst_bfm.write(claim_addr(0), {PSTRB_SIZE{1'b1}}, 32'h5);
    repeat(3) @(posedge PCLK);
    #1;

    // 下一个最高应为 source 8 (prio=4)
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("arbiter picks src8 (prio=4)", rdata, 32'h8);
    irq_i[8] = 1'b0;  // 拉低已 claim 的中断源

    // Complete source 8
    apb_mst_bfm.write(claim_addr(0), {PSTRB_SIZE{1'b1}}, 32'h8);
    repeat(3) @(posedge PCLK);
    #1;

    // 最后应为 source 2 (prio=3)
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("arbiter picks src2 (prio=3)", rdata, 32'h2);
    irq_i[2] = 1'b0;  // 拉低已 claim 的中断源

    // Complete source 2
    apb_mst_bfm.write(claim_addr(0), {PSTRB_SIZE{1'b1}}, 32'h2);

    // 清理
    irq_i = '0;
    repeat(3) @(posedge PCLK);
    #1;
    apb_mst_bfm.write(prio_addr(2), {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(prio_addr(5), {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(prio_addr(8), {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h0);
endtask : test_priority_arbitration

////////////////////////////////////////////////////////////////
//
// Test: 阈值过滤 - 优先级不大于阈值的中断不应触发
//
task test_threshold_filter;
    logic [PDATA_WIDTH-1:0] rdata;

    $display("[TEST] Threshold filter ...");

    // 配置: source 4 优先级=2, threshold=3
    irq_i = '0;
    apb_mst_bfm.write(prio_addr(4), {PSTRB_SIZE{1'b1}}, 32'h2);
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h10); // bit 4
    apb_mst_bfm.write(threshold_addr(0), {PSTRB_SIZE{1'b1}}, 32'h3);

    // 触发中断
    irq_i[4] = 1'b1;
    repeat(3) @(posedge PCLK);
    #1;

    // irq_o 不应拉高 (prio=2 <= threshold=3)
    check("irq_o filtered by threshold", irq_o[0], 1'b0);

    // Claim 应返回 0 (无有效中断)
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("claim filtered", rdata, 32'h0);

    // 降低阈值为 1, 此时 prio=2 > threshold=1, 应触发
    apb_mst_bfm.write(threshold_addr(0), {PSTRB_SIZE{1'b1}}, 32'h1);
    repeat(3) @(posedge PCLK);
    #1;

    check("irq_o after threshold lower", irq_o[0], 1'b1);
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("claim src4 after threshold lower", rdata, 32'h4);
    irq_i[4] = 1'b0;  // 拉低已 claim 的中断源
    apb_mst_bfm.write(claim_addr(0), {PSTRB_SIZE{1'b1}}, 32'h4);
    repeat(3) @(posedge PCLK);
    #1;
    apb_mst_bfm.write(prio_addr(4), {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(threshold_addr(0), {PSTRB_SIZE{1'b1}}, 32'h0);
endtask : test_threshold_filter

////////////////////////////////////////////////////////////////
//
// Test: 优先级 0 的中断不应被响应 (spec: priority=0 禁用)
//
task test_prio0_disabled;
    logic [PDATA_WIDTH-1:0] rdata;

    $display("[TEST] Priority 0 disabled ...");

    // source 6 优先级=0 (默认), enable=1, threshold=0
    irq_i = '0;
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h40); // bit 6
    apb_mst_bfm.write(threshold_addr(0), {PSTRB_SIZE{1'b1}}, 32'h0);

    // 触发中断
    irq_i[6] = 1'b1;
    repeat(3) @(posedge PCLK);
    #1;

    // prio=0 不满足 > threshold(0), irq_o 不应拉高
    check("irq_o prio=0 disabled", irq_o[0], 1'b0);

    // Claim 返回 0
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("claim prio=0", rdata, 32'h0);

    // 清理
    irq_i[6] = 1'b0;
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h0);
endtask : test_prio0_disabled

////////////////////////////////////////////////////////////////
//
// Test: 无中断时 Claim 返回 0
//
task test_claim_no_irq;
    logic [PDATA_WIDTH-1:0] rdata;

    $display("[TEST] Claim no IRQ ...");

    irq_i = '0;
    apb_mst_bfm.write(threshold_addr(0), {PSTRB_SIZE{1'b1}}, 32'h0);

    repeat(3) @(posedge PCLK);
    #1;

    // 无中断, irq_o 应为 0
    check("irq_o no irq", irq_o[0], 1'b0);

    // Claim 应返回 0
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("claim no irq", rdata, 32'h0);
endtask : test_claim_no_irq

////////////////////////////////////////////////////////////////
//
// Test: 多源并发中断 - 验证 pending 位图和仲裁
//
task test_multiple_irq_sources;
    logic [PDATA_WIDTH-1:0] rdata;

    $display("[TEST] Multiple IRQ sources ...");

    // 配置: source 1,3,7,10,13 各有不同优先级
    irq_i = '0;
    apb_mst_bfm.write(prio_addr(1),  {PSTRB_SIZE{1'b1}}, 32'h2);
    apb_mst_bfm.write(prio_addr(3),  {PSTRB_SIZE{1'b1}}, 32'h5);
    apb_mst_bfm.write(prio_addr(7),  {PSTRB_SIZE{1'b1}}, 32'h1);
    apb_mst_bfm.write(prio_addr(10), {PSTRB_SIZE{1'b1}}, 32'h7);
    apb_mst_bfm.write(prio_addr(13), {PSTRB_SIZE{1'b1}}, 32'h3);
    // enable bit 1,3,7,10,13
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h200A); // bit 1,3,5,13
    // bit 10 在 word 0 的 bit 10: 0x400 + bit 1,3 = 0x40A
    // 实际: bit1=0x2, bit3=0x8, bit7=0x80, bit13=0x2000 => 0x208A
    // bit 10 也在 word 0 (NUM_SOURCES=16, 全在 word 0): 0x400
    // 合计: 0x208A | 0x400 = 0x248A
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h248A);
    apb_mst_bfm.write(threshold_addr(0), {PSTRB_SIZE{1'b1}}, 32'h0);

    // 同时触发所有中断
    irq_i[1]  = 1'b1;
    irq_i[3]  = 1'b1;
    irq_i[7]  = 1'b1;
    irq_i[10] = 1'b1;
    irq_i[13] = 1'b1;
    repeat(3) @(posedge PCLK);
    #1;

    // 检查 pending 位图
    apb_mst_bfm.read(pend_addr(0), rdata);
    check("pending bitmap", rdata & 32'h248A, 32'h248A);

    // 最高优先级应为 source 10 (prio=7)
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("arbiter picks src10 (prio=7)", rdata, 32'hA); // 10 decimal
    irq_i[10] = 1'b0;  // 拉低已 claim 的中断源
    apb_mst_bfm.write(claim_addr(0), {PSTRB_SIZE{1'b1}}, 32'hA);

    // 等待 gateway 重新 open
    repeat(3) @(posedge PCLK);
    #1;

    // 下一个最高: source 3 (prio=5)
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("arbiter picks src3 (prio=5)", rdata, 32'h3);
    irq_i[3] = 1'b0;  // 拉低已 claim 的中断源
    apb_mst_bfm.write(claim_addr(0), {PSTRB_SIZE{1'b1}}, 32'h3);

    repeat(3) @(posedge PCLK);
    #1;

    // 下一个: source 13 (prio=3)
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("arbiter picks src13 (prio=3)", rdata, 32'hD); // 13 decimal
    irq_i[13] = 1'b0;  // 拉低已 claim 的中断源
    apb_mst_bfm.write(claim_addr(0), {PSTRB_SIZE{1'b1}}, 32'hD);

    repeat(3) @(posedge PCLK);
    #1;

    // 下一个: source 1 (prio=2)
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("arbiter picks src1 (prio=2)", rdata, 32'h1);
    irq_i[1] = 1'b0;  // 拉低已 claim 的中断源
    apb_mst_bfm.write(claim_addr(0), {PSTRB_SIZE{1'b1}}, 32'h1);

    repeat(3) @(posedge PCLK);
    #1;

    // 最后: source 7 (prio=1)
    apb_mst_bfm.read(claim_addr(0), rdata);
    check("arbiter picks src7 (prio=1)", rdata, 32'h7);
    irq_i[7] = 1'b0;  // 拉低已 claim 的中断源
    apb_mst_bfm.write(claim_addr(0), {PSTRB_SIZE{1'b1}}, 32'h7);

    // 清理
    irq_i = '0;
    repeat(3) @(posedge PCLK);
    #1;
    apb_mst_bfm.write(prio_addr(1),  {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(prio_addr(3),  {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(prio_addr(7),  {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(prio_addr(10), {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(prio_addr(13), {PSTRB_SIZE{1'b1}}, 32'h0);
    apb_mst_bfm.write(enable_addr(0, 0), {PSTRB_SIZE{1'b1}}, 32'h0);
endtask : test_multiple_irq_sources

endmodule
