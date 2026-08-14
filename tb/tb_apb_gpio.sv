// ============================================================================
// tb_apb_gpio.sv — APB GPIO Testbench
//
// BD32 — RV32IM Pipelined RISC-V SoC
// Copyright (c) 2026 BD32 Project
// SPDX-License-Identifier: Apache-2.0
// ============================================================================
timeunit 1ns;
timeprecision 1ps;
module tb_apb_gpio;
parameter  PADDR_WIDTH  = 32;
parameter  PDATA_WIDTH  = 32;
localparam PSTRB_SIZE   = PDATA_WIDTH/8;

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
logic   [PDATA_WIDTH  -1:0] gpio_o;
logic   [PDATA_WIDTH  -1:0] gpio_oe;
logic   [PDATA_WIDTH  -1:0] gpio_i;
logic                       irq_o;

//////////////////////////////////////////////////////////////////
//
// Constants
//
localparam  MODE_REG      = 0*4,
            DIRECTION_REG = 1*4,
            OUTPUT_REG    = 2*4,
            INPUT_REG     = 3*4,
            TR_TYPE_REG   = 4*4,
            TR_LVL0_REG   = 5*4,
            TR_LVL1_REG   = 6*4,
            TR_STATUS_REG = 7*4,
            IRQ_ENA_REG   = 8*4,
            BOP_SET_REG   = 9*4,
            BOP_CLR_REG   = 10*4;

localparam VERBOSE=0;//调试日志等级控制变量，控制打印日志精细程度

//////////////////////////////////////////////////////////////////
//
// Variables
//
int reset_watchdog,
    got_reset,
    errors;

/////////////////////////////////////////////////////////
//
// Instantiate the APB-Master
//
apb_master_bfm #(
    .PADDR_WIDTH ( PADDR_WIDTH ),
    .PDATA_WIDTH ( PDATA_WIDTH )
) apb_mst_bfm (.*);

apb_gpio #(
    .ADDR_WIDTH     (PADDR_WIDTH),
    .DATA_WIDTH     (PDATA_WIDTH),
    .ALIGN_BYTES    (PSTRB_SIZE )
) dut (.*);

initial begin : reset_watchdog_monitor
    errors         = 0;
    reset_watchdog = 0;
    got_reset      = 0;

    // 复位看门狗：若 1000 拍内未出现 PRESETn 有效脉冲则终止仿真
    forever begin
        reset_watchdog++;
        @(posedge PCLK);
        if (!got_reset && reset_watchdog == 1000)
            $fatal(1, "APB reset never observed; testbench requires an active-low PRESETn");
    end
end

initial begin : gen_PCLK
    PCLK <= 1'b0;
    forever #10 PCLK = ~PCLK;
end : gen_PCLK

initial begin : gen_PRESETn
    PRESETn = 1'b1;
    //ensure falling edge of PRESETn
    #10;
    PRESETn = 1'b0;
    #32;
    PRESETn = 1'b1;
end : gen_PRESETn;


always @(negedge PRESETn) begin : main_test_flow
    // 等待复位释放，随后按顺序执行全部测试用例
    @(posedge PRESETn);
    got_reset = 1;

    repeat (5) @(posedge PCLK);
    #1;

    print_banner();

    test_reset_register_values();   // 复位后寄存器初值
    test_io_basic();                // 基本 IO 读写
    test_bop();                     // BOP_SET / BOP_CLR
    test_io_random();               // 随机 IO
    test_clear_status();            // TR_STATUS 清零
    test_trigger_level_low();       // 电平触发（低有效）
    test_trigger_level_high();      // 电平触发（高有效）
    test_trigger_level_random();    // 电平触发（随机）
    test_trigger_edge_fall();       // 下降沿触发
    test_trigger_edge_rise();       // 上升沿触发
    test_trigger_edge_random();     // 随机边沿触发
    test_irq();                     // 中断输出

    // 收尾：留出余量后打印结果
    repeat (100) @(posedge PCLK);
    #1;
    print_summary();
    $finish;
end


/////////////////////////////////////////////////////////
//
// Tasks
//
task print_banner();
    $display("==================================================");
    $display(" BD32 APB GPIO Testbench");
    $display("==================================================");
endtask : print_banner


task print_summary();
    if (errors > 0) begin
        $display("------------------------------------------------------------");
        $display(" APB GPIO Testbench FAILED: %0d error(s) @%0t", errors, $time);
        $display("------------------------------------------------------------");
    end else begin
        $display("------------------------------------------------------------");
        $display(" APB GPIO Testbench PASSED @%0t", $time);
        $display("------------------------------------------------------------");
    end
endtask : print_summary


task check (
    input   string              name,
    input   [PDATA_WIDTH-1:0]   actual,
    input   [PDATA_WIDTH-1:0]   expected
);
    #1;
    if (VERBOSE > 2) $display("Checking %s for %b==%b", name, actual, expected);
    if (actual !== expected) error_msg(name, actual, expected);
endtask : check


task error_msg(
    input   string              name,
    input   [PDATA_WIDTH-1:0]   actual,
    input   [PDATA_WIDTH-1:0]   expected
);
    errors++;
    $display("ERROR  : %s mismatch. Expected: %b, got: %b @%0t", name, expected, actual, $time);
endtask : error_msg


/*
* Reset Test. Test if all register are zero after reset
*/
task test_reset_register_values;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Checking reset values ...");

    //read register(s) contents
    apb_mst_bfm.read(MODE_REG, readdata);
    check("MODE", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(DIRECTION_REG, readdata);
    check("DIRECTION", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(OUTPUT_REG, readdata);
    check("OUTPUT", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TR_TYPE_REG, readdata);
    check("TriggerType", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TR_LVL0_REG, readdata);
    check("TriggerLevelEdge0", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TR_LVL1_REG, readdata);
    check("TriggerLevelEdge1", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TR_STATUS_REG, readdata);
    check("TR_STATUS", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(IRQ_ENA_REG, readdata);
    check("IRQ", readdata, {PDATA_WIDTH{1'b0}});
endtask : test_reset_register_values


/*
* Basic IO tests
*/
task test_io_basic;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Basic IO test ...");

    //basic output
    for (int mode=0; mode <= 1              ; mode++)
    for (int dir =0; dir  <= 1              ; dir++ )
    for (int d   =0; d    <  1<<PDATA_WIDTH ; d++   )
    begin
        gpio_i = d;

        apb_mst_bfm.write(MODE_REG     , {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{mode[0]}});
        apb_mst_bfm.write(DIRECTION_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{dir [0]}});
        apb_mst_bfm.write(OUTPUT_REG   , {PSTRB_SIZE{1'b1}}, d);
        apb_mst_bfm.read (INPUT_REG    , readdata);

        //check read data
        check("INPUT", readdata, d[PDATA_WIDTH-1:0]);

        //check gpio_o/gpio_oe
        if (mode)
        begin
            //open-drain
            check("GPIO_OE", gpio_oe, {PDATA_WIDTH{dir[0]}} & ~d[PDATA_WIDTH-1:0]);
            check("GPIO_O ", gpio_o , {PDATA_WIDTH{1'b0}});
        end
        else
        begin
            //push-pull
            check("GPIO_OE", gpio_oe, {PDATA_WIDTH{dir[0]}});
            check("GPIO_O ", gpio_o , d[PDATA_WIDTH-1:0]);
        end
    end
endtask : test_io_basic


/*
* Random IO tests
*/
task test_io_random(input int runs=10000);
    logic [PDATA_WIDTH-1:0] mode;
    logic [PDATA_WIDTH-1:0] dir;
    logic [PDATA_WIDTH-1:0] d;
    logic [PDATA_WIDTH-1:0] readdata;
    logic [PDATA_WIDTH-1:0] expected;

    $display ("Random IO test ...");

    //basic output
    for (int run=0; run < runs; run++)
    begin
        if (VERBOSE > 0) $display("Random IO test Run=%0d", run);
        mode=$random;
        dir =$random;
        d   =$random;

        gpio_i = $random;

        apb_mst_bfm.write(MODE_REG     , {PSTRB_SIZE{1'b1}}, mode);
        apb_mst_bfm.write(DIRECTION_REG, {PSTRB_SIZE{1'b1}}, dir );
        apb_mst_bfm.write(OUTPUT_REG   , {PSTRB_SIZE{1'b1}}, d   );
        apb_mst_bfm.read (INPUT_REG    , readdata);

        //check read data
        check($sformatf("INPUT   (%0d %0d %0d %0d)", run, mode, dir, d), readdata, gpio_i);

        //check gpio_o
        for (int b=0; b < PDATA_WIDTH; b++) expected[b] = mode[b] ? 1'b0 : d[b];
        check($sformatf("GPIO_O  (%0d %0d %0d %0d)", run, mode, dir, d), gpio_o, expected);

        //check gpio_oe
        for (int b=0; b < PDATA_WIDTH; b++) expected[b] = mode[b] ? dir[b] & ~d[b] : dir[b];
        check($sformatf("GPIO_OE (%0d %0d %0d %0d)", run, mode, dir, d), gpio_oe, expected);
    end //next run
endtask : test_io_random


/*
* BOP_SET/BOP_CLR test
*/
task test_bop;
    logic [PDATA_WIDTH-1:0] readdata;
    logic [PDATA_WIDTH-1:0] expected;

    $display ("BOP_SET/BOP_CLR test ...");

    // Configure: push-pull mode, all output
    apb_mst_bfm.write(MODE_REG,      {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});
    apb_mst_bfm.write(DIRECTION_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});
    apb_mst_bfm.write(OUTPUT_REG,    {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

    // Verify output starts at 0
    apb_mst_bfm.read(OUTPUT_REG, readdata);
    check("OUTPUT after reset", readdata, {PDATA_WIDTH{1'b0}});

    // BOP_SET: set bits 0, 2, 4 = 5'b10101
    apb_mst_bfm.write(BOP_SET_REG, {PSTRB_SIZE{1'b1}}, 32'h00000015);
    apb_mst_bfm.read(OUTPUT_REG, readdata);
    expected = 32'h00000015;
    check("BOP_SET bits 0,2,4", readdata, expected);

    // BOP_CLR: clear bit 2, set bits 1,3
    apb_mst_bfm.write(BOP_CLR_REG, {PSTRB_SIZE{1'b1}}, 32'h00000004);
    apb_mst_bfm.read(OUTPUT_REG, readdata);
    expected = 32'h00000011;
    check("BOP_CLR bit 2", readdata, expected);

    // BOP_SET is write-only, reads back as 0
    apb_mst_bfm.read(BOP_SET_REG, readdata);
    check("BOP_SET readback", readdata, {PDATA_WIDTH{1'b0}});

    // BOP_CLR is write-only, reads back as 0
    apb_mst_bfm.read(BOP_CLR_REG, readdata);
    check("BOP_CLR readback", readdata, {PDATA_WIDTH{1'b0}});

    $display ("BOP_SET/BOP_CLR test PASS");
endtask : test_bop


/*
* Clear TR_STATUS test
*/
task test_clear_status;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Clear TR_STATUS Register test ...");

    //drive gpio_i low
    gpio_i = {PDATA_WIDTH{1'b0}};

    //set trigger TR_TYPE to level
    apb_mst_bfm.write(TR_TYPE_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

    //enable TR_LVL0
    apb_mst_bfm.write(TR_LVL0_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

    //wait for data to propagate
    @(posedge PCLK);
    #1;

    //read TR_STATUS register
    apb_mst_bfm.read(TR_STATUS_REG, readdata);
    check("TR_STATUS-0", readdata, {PDATA_WIDTH{1'b1}});

    //disable TR_LVL0
    apb_mst_bfm.write(TR_LVL0_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

    //check TR_STATUS register (should not have changed)
    apb_mst_bfm.read(TR_STATUS_REG, readdata);
    check("TR_STATUS-1", readdata, {PDATA_WIDTH{1'b1}});

    //clear TR_STATUS register
    apb_mst_bfm.write(TR_STATUS_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

    //check TR_STATUS register
    apb_mst_bfm.read(TR_STATUS_REG, readdata);
    check("TR_STATUS-2", readdata, {PDATA_WIDTH{1'b0}});
endtask : test_clear_status


/*
* Trigger Level Low test
*/
task test_trigger_level_low(input int runs=1<<PDATA_WIDTH);
    logic [PDATA_WIDTH-1:0] gpio_data;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Trigger Level-Low test ...");

    //drive gpio_i high
    gpio_i = {PDATA_WIDTH{1'b1}};

    //set trigger TR_TYPE to level
    apb_mst_bfm.write(TR_TYPE_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

    //disble TR_LVL1
    apb_mst_bfm.write(TR_LVL1_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

    //enable TR_LVL0
    apb_mst_bfm.write(TR_LVL0_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

    for (int run=0; run < runs; run++)
    begin
        if (VERBOSE > 0) $display("  Trigger Level-Low test run=%0d", run);

        //clear TR_STATUS register
        apb_mst_bfm.write(TR_STATUS_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

        //drive gpio_i
        gpio_data = $random;
        gpio_i    = gpio_data;
        @(posedge PCLK);
        #1;

        //drive gpio_i high
        gpio_i = {PDATA_WIDTH{1'b1}};

        //wait for data to propagate
        repeat(3) @(posedge PCLK);
        #1;

        //read TR_STATUS register
        apb_mst_bfm.read(TR_STATUS_REG, readdata);
        check("TR_STATUS", readdata, ~gpio_data);
    end
endtask : test_trigger_level_low


/*
* Trigger Level High test
*/
task test_trigger_level_high(input int runs=1<<PDATA_WIDTH);
    logic [PDATA_WIDTH-1:0] gpio_data;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Trigger Level-High test ...");

    //drive gpio_i low
    gpio_i = {PDATA_WIDTH{1'b0}};

    //set trigger TR_TYPE to level
    apb_mst_bfm.write(TR_TYPE_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

    //disbale TR_LVL0
    apb_mst_bfm.write(TR_LVL0_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

    //enable TR_LVL1
    apb_mst_bfm.write(TR_LVL1_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

    for (int run=0; run < runs; run++)
    begin
        if (VERBOSE > 0) $display("  Trigger Level-High test run=%0d", run);

        //clear TR_STATUS register
        apb_mst_bfm.write(TR_STATUS_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

        //drive gpio_i
        gpio_data = $random;
        gpio_i    = gpio_data;
        @(posedge PCLK);
        #1;

        //drive gpio_i high
        gpio_i = {PDATA_WIDTH{1'b0}};

        //wait for data to propagate
        repeat(3) @(posedge PCLK);
        #1;

        //read TR_STATUS register
        apb_mst_bfm.read(TR_STATUS_REG, readdata);
        check("TR_STATUS", readdata, gpio_data);
    end
endtask : test_trigger_level_high


/*
* Trigger Level Random test
*/
task test_trigger_level_random(input int runs=10000);
    logic [PDATA_WIDTH-1:0] tr_lvl0;
    logic [PDATA_WIDTH-1:0] tr_lvl1;
    logic [PDATA_WIDTH-1:0] gpio_data;
    logic [PDATA_WIDTH-1:0] readdata;
    logic [PDATA_WIDTH-1:0] expected;

    $display ("Trigger Level-Random test ...");

    //drive gpio_i high
    gpio_i = {PDATA_WIDTH{1'b1}};

    //set trigger TR_TYPE to level
    apb_mst_bfm.write(TR_TYPE_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

    for (int run=0; run < runs; run++)
    begin
        if (VERBOSE > 0) $display("  Trigger Level-Random test run=%0d", run);

        //disable TR_LVL0
        apb_mst_bfm.write(TR_LVL0_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

        //disable TR_LVL1
        apb_mst_bfm.write(TR_LVL1_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

        //clear TR_STATUS register
        apb_mst_bfm.write(TR_STATUS_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

        //drive gpio_i
        gpio_data = $random;
        gpio_i    = gpio_data;

        //wait for data to propagate
        repeat(4) @(posedge PCLK);
        #1;

        //randomize level triggers
        tr_lvl0 = $random;
        tr_lvl1 = $random;
        apb_mst_bfm.write(TR_LVL0_REG, {PSTRB_SIZE{1'b1}}, tr_lvl0);
        apb_mst_bfm.write(TR_LVL1_REG, {PSTRB_SIZE{1'b1}}, tr_lvl1);

        //allow data to propagate
        @(posedge PCLK);
        #1;

        //read TR_STATUS register
        apb_mst_bfm.read(TR_STATUS_REG, readdata);

        for (int b=0; b<PDATA_WIDTH; b++) expected[b] = (tr_lvl0[b] & ~gpio_data[b]) | (tr_lvl1[b] & gpio_data[b]);
        check("TR_STATUS", readdata, expected);
    end
endtask : test_trigger_level_random


/*
* Trigger Falling Edge test
*/
task test_trigger_edge_fall(input int runs=4* 1<<PDATA_WIDTH);
    logic [PDATA_WIDTH-1:0] gpio_data0;
    logic [PDATA_WIDTH-1:0] gpio_data1;
    logic [PDATA_WIDTH-1:0] readdata;
    logic [PDATA_WIDTH-1:0] expected;

    $display ("Trigger Falling-Edge test ...");

    //set trigger TR_TYPE to edge
    apb_mst_bfm.write(TR_TYPE_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

    //disble TR_LVL1 (rising edge)
    apb_mst_bfm.write(TR_LVL1_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

    //enable TR_LVL0 (falling edge)
    apb_mst_bfm.write(TR_LVL0_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

    for (int run=0; run < runs; run++)
    begin
        if (VERBOSE > 0) $display("  Trigger Falling-Edge test run=%0d", run);

        //drive 1st data onto gpio_i
        gpio_data0 = $random;
        gpio_i     = gpio_data0;
        @(posedge PCLK);

        //wait for data to propagate
        repeat(3) @(posedge PCLK);
        #1;

        //clear TR_STATUS register
        apb_mst_bfm.write(TR_STATUS_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

        //drive 2nd data onto gpio_i
        gpio_data1 = $random;
        gpio_i     = gpio_data1;
        @(posedge PCLK);

        //wait for data to propagate (one extra stage for edge detector)
        repeat(4) @(posedge PCLK);
        #1;

        //read TR_STATUS register
        apb_mst_bfm.read(TR_STATUS_REG, readdata);

        for (int b=0; b<PDATA_WIDTH; b++) expected[b] = gpio_data0[b] & ~gpio_data1[b];
        check("TR_STATUS", readdata, expected);
    end
endtask : test_trigger_edge_fall


/*
* Trigger Rising Edge test
*/
task test_trigger_edge_rise(input int runs=4* 1<<PDATA_WIDTH);
    logic [PDATA_WIDTH-1:0] gpio_data0;
    logic [PDATA_WIDTH-1:0] gpio_data1;
    logic [PDATA_WIDTH-1:0] readdata;
    logic [PDATA_WIDTH-1:0] expected;

    $display ("Trigger Rising-Edge test ...");

    //set trigger TR_TYPE to edge
    apb_mst_bfm.write(TR_TYPE_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

    //disble TR_LVL0 (falling edge)
    apb_mst_bfm.write(TR_LVL0_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

    //enable TR_LVL1 (rising edge)
    apb_mst_bfm.write(TR_LVL1_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

    for (int run=0; run < runs; run++)
    begin
        if (VERBOSE > 0) $display("  Trigger Rising-Edge test run=%0d", run);

        //drive 1st data onto gpio_i
        gpio_data0 = $random;
        gpio_i     = gpio_data0;
        @(posedge PCLK);

        //wait for data to propagate
        repeat(3) @(posedge PCLK);
        #1;

        //clear TR_STATUS register
        apb_mst_bfm.write(TR_STATUS_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

        //drive 2nd data onto gpio_i
        gpio_data1 = $random;
        gpio_i     = gpio_data1;
        @(posedge PCLK);

        //wait for data to propagate (one extra stage for edge detector)
        repeat(4) @(posedge PCLK);
        #1;

        //read TR_STATUS register
        apb_mst_bfm.read(TR_STATUS_REG, readdata);

        for (int b=0; b<PDATA_WIDTH; b++) expected[b] = ~gpio_data0[b] & gpio_data1[b];
        check("TR_STATUS", readdata, expected);
    end
endtask : test_trigger_edge_rise


/*
* Trigger Rising Random test
*/
task test_trigger_edge_random(input int runs=40000);
    logic [PDATA_WIDTH-1:0] gpio_data0;
    logic [PDATA_WIDTH-1:0] gpio_data1;
    logic [PDATA_WIDTH-1:0] tr_lvl0;
    logic [PDATA_WIDTH-1:0] tr_lvl1;
    logic [PDATA_WIDTH-1:0] readdata;
    logic [PDATA_WIDTH-1:0] expected;

    $display ("Trigger Random-Edge test ...");

    //set trigger TR_TYPE to edge
    apb_mst_bfm.write(TR_TYPE_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

    for (int run=0; run < runs; run++)
    begin
        if (VERBOSE > 0) $display("  Trigger Random-Edge test run=%0d", run);

        //randomize trigger edge(s)
        tr_lvl0 = $random;
        tr_lvl1 = $random;
        apb_mst_bfm.write(TR_LVL0_REG, {PSTRB_SIZE{1'b1}}, tr_lvl0);
        apb_mst_bfm.write(TR_LVL1_REG, {PSTRB_SIZE{1'b1}}, tr_lvl1);

        //drive 1st data onto gpio_i
        gpio_data0 = $random;
        gpio_i     = gpio_data0;
        @(posedge PCLK);

        //wait for data to propagate
        repeat(3) @(posedge PCLK);
        #1;

        //clear TR_STATUS register
        apb_mst_bfm.write(TR_STATUS_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

        //drive 2nd data onto gpio_i
        gpio_data1 = $random;
        gpio_i     = gpio_data1;
        @(posedge PCLK);

        //wait for data to propagate (one extra stage for edge detector)
        repeat(4) @(posedge PCLK);
        #1;

        //read TR_STATUS register
        apb_mst_bfm.read(TR_STATUS_REG, readdata);

        for (int b=0; b<PDATA_WIDTH; b++) expected[b] = (tr_lvl0[b] &  gpio_data0[b] & ~gpio_data1[b]) |
                                                        (tr_lvl1[b] & ~gpio_data0[b] &  gpio_data1[b]);
        check("TR_STATUS", readdata, expected);
    end
endtask : test_trigger_edge_random


/*
* IRQ test
*/
task test_irq;
    logic [PDATA_WIDTH-1:0] gpio_data0;
    logic [PDATA_WIDTH-1:0] gpio_data1;
    logic [PDATA_WIDTH-1:0] tr_lvl0;
    logic [PDATA_WIDTH-1:0] tr_lvl1;
    logic [PDATA_WIDTH-1:0] readdata;
    logic [PDATA_WIDTH-1:0] expected;

    $display ("IRQ test ...");

    //disable all triggers
    apb_mst_bfm.write(TR_LVL0_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});
    apb_mst_bfm.write(TR_LVL1_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

    //clear TR_STATUS
    apb_mst_bfm.write(TR_STATUS_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

    //IRQ should be low
    check("irq_o-0", irq_o, 1'b0);

    //
    //Test 1, check if trigger propagates to IRQ
    //

    //enable level-high triggers
    gpio_i = {PDATA_WIDTH{1'b0}};
    apb_mst_bfm.write(TR_TYPE_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});
    apb_mst_bfm.write(TR_LVL0_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});
    apb_mst_bfm.write(TR_LVL1_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

    //enable IRQs
    apb_mst_bfm.write(IRQ_ENA_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b1}});

    //trigger all inputs
    gpio_i = {PDATA_WIDTH{1'b1}};
    @(posedge PCLK);
    #1;
    gpio_i = {PDATA_WIDTH{1'b0}};

    //wait for data to propagate (one more for irq_o flipflop)
    repeat(3) @(posedge PCLK);
    #1;

    //check irq_o
    repeat(2) @(posedge PCLK); //it takes 2 cycles for irq_o to propagate and check
    #1;
    check("irq_o-1", irq_o, 1'b1);


    //
    //Test 2, test IRQ_ENA
    //
    //disable IRQs
    apb_mst_bfm.write(IRQ_ENA_REG, {PSTRB_SIZE{1'b1}}, {PDATA_WIDTH{1'b0}});

    //check irq_o
    repeat(2) @(posedge PCLK);
    #1;
    check("irq_o-2", irq_o, 1'b0);


    //
    // Test 3, check STAT/ENA combination
    //

    //Check STAT is all ones
    apb_mst_bfm.read(TR_STATUS_REG, readdata);
    check("TR_STATUS", readdata, {PDATA_WIDTH{1'b1}});

    for (int b=0; b < PDATA_WIDTH; b++)
    begin
        //Enable bitwise IRQs
        apb_mst_bfm.write(IRQ_ENA_REG, {PSTRB_SIZE{1'b1}}, 1<<b);

        //check irq_o
        repeat(2) @(posedge PCLK);
        #1;
        check($sformatf("irq_o-3-%0d",b), irq_o, 1'b1);

        //clear TR_STATUS bit
        apb_mst_bfm.write(TR_STATUS_REG, {PSTRB_SIZE{1'b1}}, 1<<b);

        //check irq_o
        repeat(2) @(posedge PCLK);
        #1;
        check($sformatf("irq_o-3-%0d",b), irq_o, 1'b0);
    end

endtask : test_irq

endmodule
