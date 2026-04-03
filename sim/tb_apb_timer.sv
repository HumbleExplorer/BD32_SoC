`timescale 1ns/1ps
/*
 * tb_apb_timer.sv - APB Timer Testbench
 *
 * 测试内容：
 *   - 寄存器读写测试.
0. *   - 定时器基本计数功能测试
 *   - 预分频功能测试
 *   - 自动重载功能测试
 *   - 递增/递减计数模式测试
 *   - 溢出中断测试
 *   - 输入捕获/输出比较功能测试 (可选)
 *
 * 作者：基于参考代码改编
 * 日期：2026/03/31
 */

module tb_apb_timer;

parameter  PADDR_WIDTH  = 32;
parameter  PDATA_WIDTH  = 32;
parameter  TIMER_WIDTH = 16;
parameter  CHANNEL_NUM = 4;
localparam PSTRB_SIZE   = PDATA_WIDTH/8;

// APB信号
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
logic                       irq_o;

// 通道信号
logic   [CHANNEL_NUM-1:0]    channel_i;
logic   [CHANNEL_NUM-1:0]    channel_o;
logic   [CHANNEL_NUM-1:0]    channel_oe;

// 寄存器地址定义
localparam  
    TIMx_PSC    = 0*4,  // 0x00
    TIMx_CNT    = 1*4,  // 0x04
    TIMx_ARR    = 2*4,  // 0x08
    TIMx_CR     = 3*4,  // 0x0c
    TIMx_IER    = 4*4,  // 0x10
    TIMx_SR     = 5*4,  // 0x14
    TIMx_CCMR   = 6*4,  // 0x18
    TIMx_CCER   = 7*4,  // 0x1c
    TIMx_CCR1   = 8*4,  // 0x20
    TIMx_CCR2   = 9*4,  // 0x24
    TIMx_CCR3   = 10*4,  // 0x28
    TIMx_CCR4   = 11*4;  // 0x2c

// 控制寄存器位
localparam CR_EN_BIT       = 0;
localparam CR_CLR_BIT     = 1;
localparam CR_DIR_BIT     = 2;

// 中断使能寄存器位
localparam IER_INT_EN_BIT     = 0;
localparam IER_OF_INT_EN_BIT  = 1;
localparam IER_IC_OC_EN_BIT   = 2;

// 状态寄存器位
localparam SR_OF_PEND_BIT     = 0;
localparam SR_TRIGGER_PEND_BIT = 1;

localparam VERBOSE = 1;  // 调试日志等级控制

////////////////////////////////////////////////////////////////
//
// Variables
//
int reset_watchdog,
    got_reset,
    errors;

////////////////////////////////////////////////////////////////
//
// Instantiate the APB-Master BFM
//
apb_master_bfm #(
    .PADDR_WIDTH ( PADDR_WIDTH ),
    .PDATA_WIDTH ( PDATA_WIDTH )
) apb_mst_bfm (.*);

// DUT
apb_timer #(
    .ADDR_WIDTH     (PADDR_WIDTH),
    .DATA_WIDTH     (PDATA_WIDTH),
    .TIMER_WIDTH    (TIMER_WIDTH),
    .CHANNEL_NUM    (CHANNEL_NUM)
) dut (.*);

initial
begin
    errors         = 0;
    reset_watchdog = 0;
    got_reset      = 0;

    forever
    begin
        reset_watchdog++;
        @(posedge PCLK);
        if (!got_reset && reset_watchdog == 1000)
            $fatal(-1,"PRESETn not asserted\nTestbench requires an APB reset");
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
end : gen_PRESETn


always @(negedge PRESETn) begin
    //wait for reset to negate
    @(posedge PRESETn);
    got_reset = 1;

    repeat(5) @(posedge PCLK);
    #1;

    welcome_text();

    //check reset values
    test_reset_register_values();

    // basic timer function tests
    test_timer_basic_count();
    test_timer_prescaler();
    test_timer_autoload();
    test_timer_direction();
    test_timer_overflow_interrupt();
    test_timer_clear();

    // channel tests
    test_channel_output_compare();
    test_channel_input_capture();

    //Finish simulation
    repeat (100) @(posedge PCLK);
    #1;
    finish_text();
    $finish();
end


////////////////////////////////////////////////////////////////
//
// Tasks
//
           
task welcome_text();
    $display("      _____                                                                   _____      ");
    $display("     ( ___ )-----------------------------------------------------------------( ___ )     ");
    $display("      |   |                                                                   |   |      ");
    $display("      |   |                                                                   |   |      ");
    $display("      |   |      ____  __    __  ________   ____  ____  _________    __  ___  |   |      ");
    $display("      |   |     / __ )/ /   / / / / ____/  / __ \/ __ \/ ____/   |  /  |/  /  |   |      ");
    $display("      |   |    / __  / /   / / / / __/    / / / / /_/ / __/ / /| | / /|_/ /   |   |      ");
    $display("      |   |   / /_/ / /___/ /_/ / /___   / /_/ / _, _/ /___/ ___ |/ /  / /    |   |      ");
    $display("      |   |  /_____/_____/\____/_____/  /_____/_/ |_/_____/_/  |_/_/  /_/     |   |      ");
    $display("      |   |                                                                   |   |      ");
    $display("      |___|                                                                   |___|      ");
    $display("     (_____)-----------------------------------------------------------------(_____)     ");
    $display("                                                                                         ");
    $display("                                    ..                                                   ");
    $display("                                   .++.                                                  ");
    $display("                                   .++.                                                  ");
    $display("                                   .++.                                                  ");
    $display("                                   .++.                                                  ");
    $display("                                   .--.    ..                                            ");
    $display("                                    -.     .+-                                           ");
    $display("                                    -.     .+#-.       .++.                              ");
    $display("                                    -.     .+##+..      ..                               ");
    $display("                                    -.     .+###+.      ..               .++.            ");
    $display("                            -+++.   -.     .+####+-.    -.               -##.            ");
    $display("                            -+++.   -.     .+####++-    -.                .-             ");
    $display("                                    -.    ..#####+++.   -.                .-             ");
    $display("                                   .-+. ..#-+####++++.  -.                .-             ");
    $display("                                    .. .-##-+####++++.  -.      .-.       .-             ");
    $display("                              ....   .-####-+####++++...-.      .+....    .-             ");
    $display("                ..---..            .+######-#####++++-#+..      .+..+-    .-             ");
    $display("        .----..-++++###+--++-.  .-#########-####+++++-####-.    .-.       .-  .-.        ");
    $display("      ......+#########-.........###########-####+++++-#####+..  .-.       .-  .+-..      ");
    $display("                              .+###########-####+++++-########+..-.       .-  .++-.      ");
    $display("                  ..        .--+##########+-####+++++-#########..-.       .- .+++--.     ");
    $display("    .--.          ..       .+#-+#######--###++##++++--#########.-#-       .- -+++--.     ");
    $display("   .-#-           .-      .###-+###+-+###+------------#########.-##.  .-. .++++++--.     ");
    $display("  .-+#.      .-++..-   ...-###-++-++##+------------.--#########.+##.   .-+####+++--.     ");
    $display(" .--+#-      ..+-..-   -#--###-+##+---------------------+##+###.+##.   .++####+++--.     ");
    $display(" .--+#+.     ..   .-  .##--###-+#+--+++----------------++--++##.+##.  .-++####+++--.     ");
    $display(" .--###.     ...  .-  .##--###-+##+++------------------+--+++##.+##..-++++####++--..     ");
    $display(" .-+###+.    ...  .-.++##--###-+#++++++--------------.-+#++-+##-###-++++#####+++--.      ");
    $display(" .-++##++-.  .-. .-++++##--####+-+##++++++--------.-+++-###++##-###++########++--.       ");
    $display(" .-++#+++++-.-.  .+++++##-.+#######+++++--+-----+++-+######++#+-###+########+++-.        ");
    $display(" .--++++++++-+. ..+++++##-+--##########++++--+++-+#########+++--###+#######++++..        ");
    $display("  .--+++++++-+-.-##++++##-+++--############+--+############--++-###########++-.          ");
    $display("   .--++++++---.-###+++##-++++--.-##########.+##########+----++-##########+-.            ");
    $display("   ..--+++++----#####+++#-++++----..+#######.+########--+++--++-######++..               ");
    $display("    ..---++#+-----++#++++-++++---------+####.+#####---++###+-++-####-..-.  .             ");
    $display("      .---++##+-------+++-++++----------.-++.+#+-.---++####+-++-###. .++-.               ");
    $display("       ..--++###+-.-----+-++++-------------...-------+#####+-++-###. ...                 ");
    $display("         ..-+++####+------+###--------------..------++#####++##-#-.  ..       -+..       ");
    $display("             .-+###+++----+###--------------..------++#####++##-     ..  ...             ");
    $display("                 ..-++++--..----------------..-----+++#####++#+.     .-....              ");
    $display("                   .++++++-----.------------..----++++#####++#+.....----..               ");
    $display("          ..        .++++##++----.----------..---+++++#####+++...------.                 ");
    $display("        ...+....      ..-++++++--...--------..--++++++#----...----++++..                 ");
    $display("       ..-+#+...          .--+++----.-------..-++++++-.--------+++++..                   ");
    $display("           ..              .---++-----........-++++-.-----++++++++.                      ");
    $display("                            .---++++-----..-----------+####+++-..                        ");
    $display("  .+........................  .-+++##++++++---...--++####+-.    ........................ ");
    $display("  .-........................    .--++###++++++++++++#+++..               ............... ");
    $display("                                    .-+++#########+--..                                  ");
    $display("                                         ........                                        ");
    $display("                                                                                         ");
    $display("APB Timer Testbench Initialized");
endtask : welcome_text


task finish_text();
    if (errors>0)
    begin
        $display ("------------------------------------------------------------");
        $display (" APB Timer Testbench failed with (%0d) errors @%0t", errors, $time);
        $display ("------------------------------------------------------------");
    end
    else
    begin
        $display ("------------------------------------------------------------");
        $display (" APB Timer Testbench finished successfully @%0t", $time);
        $display ("------------------------------------------------------------");
    end
endtask : finish_text


task check (
    input   string              name,
    input   [PDATA_WIDTH-1:0]   actual,
    input   [PDATA_WIDTH-1:0]   expected
);
    #1;
    if (VERBOSE > 2) $display("Checking %s for %h==%h", name, actual, expected);
    if (actual !== expected) error_msg(name, actual, expected);
endtask : check


task check_bit (
    input   string              name,
    input   logic               actual,
    input   logic               expected
);
    #1;
    if (VERBOSE > 2) $display("Checking %s for %b==%b", name, actual, expected);
    if (actual !== expected) error_msg_bit(name, actual, expected);
endtask : check_bit


task error_msg(
    input   string              name,
    input   [PDATA_WIDTH-1:0]   actual,
    input   [PDATA_WIDTH-1:0]   expected
);
    errors++;
    $display("ERROR  : Incorrect %s value. Expected: %h, received: %h @%0t", name, expected, actual, $time);
endtask : error_msg


task error_msg_bit(
    input   string              name,
    input   logic               actual,
    input   logic               expected
);
    errors++;
    $display("ERROR  : Incorrect %s value. Expected: %b, received: %b @%0t", name, expected, actual, $time);
endtask : error_msg_bit


/*
* Reset Test. Test if all register are zero after reset
*/
task test_reset_register_values;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Checking reset values ...");

    // Read all registers and verify they are zero
    apb_mst_bfm.read(TIMx_PSC, readdata);
    check("TIMx_PSC", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TIMx_CNT, readdata);
    check("TIMx_CNT", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TIMx_ARR, readdata);
    check("TIMx_ARR", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TIMx_CR, readdata);
    check("TIMx_CR", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TIMx_IER, readdata);
    check("TIMx_IER", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TIMx_SR, readdata);
    check("TIMx_SR", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TIMx_CCMR, readdata);
    check("TIMx_CCMR", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TIMx_CCER, readdata);
    check("TIMx_CCER", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TIMx_CCR1, readdata);
    check("TIMx_CCR1", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TIMx_CCR2, readdata);
    check("TIMx_CCR2", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TIMx_CCR3, readdata);
    check("TIMx_CCR3", readdata, {PDATA_WIDTH{1'b0}});

    apb_mst_bfm.read(TIMx_CCR4, readdata);
    check("TIMx_CCR4", readdata, {PDATA_WIDTH{1'b0}});
endtask : test_reset_register_values


/*
* Basic Timer Count Test
* 配置定时器并验证计数功能
*/
task test_timer_basic_count;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Basic Timer Count test ...");

    // 配置预分频为2-1=1
    apb_mst_bfm.write(TIMx_PSC, {PSTRB_SIZE{1'b1}}, 16'h0001);

    // 配置自动重载值为10-1
    apb_mst_bfm.write(TIMx_ARR, {PSTRB_SIZE{1'b1}}, 16'h0009);

    // 配置计数器初值为0
    apb_mst_bfm.write(TIMx_CNT, {PSTRB_SIZE{1'b1}}, 16'h0000);

    // 使能定时器 (递减模式)
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, (1 << CR_EN_BIT)+(1 << CR_DIR_BIT));

    // 等待几个时钟周期
    repeat(5) @(posedge PCLK);
    #1;

    // 读取计数器值
    apb_mst_bfm.read(TIMx_CNT, readdata);
    // check("TIMx_CNT", readdata, 16'h000);
    if (VERBOSE > 0) $display("  Timer count after 5 cycles: %h", readdata);

    // 禁用定时器
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, 16'h0000);
endtask : test_timer_basic_count


/*
* Prescaler Test
* 测试预分频功能
*/
task test_timer_prescaler;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Timer Prescaler test ...");

    // 配置预分频为10-1 (每10个时钟周期计数一次)
    apb_mst_bfm.write(TIMx_PSC, {PSTRB_SIZE{1'b1}}, 16'h0009);

    // 配置自动重载值为20-1
    apb_mst_bfm.write(TIMx_ARR, {PSTRB_SIZE{1'b1}}, 16'h0013);

    // 使能定时器
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, (1 << CR_EN_BIT));

    // 等待20个时钟周期 (2次计数)
    repeat(20) @(posedge PCLK);
    #1;

    // 读取计数器值
    apb_mst_bfm.read(TIMx_CNT, readdata);
    // check("TIMx_CNT with prescaler=9", readdata, 16'h0002);
    if (VERBOSE > 0) $display("  Timer count with prescaler=9 after 20 cycles: %h", readdata);

    // 禁用定时器
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, 16'h0000);

    // 重置预分频
    apb_mst_bfm.write(TIMx_PSC, {PSTRB_SIZE{1'b1}}, 16'h0000);
endtask : test_timer_prescaler


/*
* Autoload Test
* 测试自动重载功能
*/
task test_timer_autoload;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Timer Autoload test ...");

    // 配置预分频为2-1
    apb_mst_bfm.write(TIMx_PSC, {PSTRB_SIZE{1'b1}}, 16'h0001);
    // 配置自动重载值为5-1
    apb_mst_bfm.write(TIMx_ARR, {PSTRB_SIZE{1'b1}}, 16'h0004);

    // 使能定时器 (递增模式)
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, (1 << CR_EN_BIT));

    // 等待溢出 (5个时钟周期)
    repeat(10) @(posedge PCLK);
    #1;

    // 读取计数器值和状态
    apb_mst_bfm.read(TIMx_CNT, readdata);
    if (VERBOSE > 0) $display("  Timer count after overflow: %h", readdata);

    // 读取状态寄存器检查溢出标志
    apb_mst_bfm.read(TIMx_SR, readdata);
    if (VERBOSE > 0) $display("  Timer SR after overflow: %h (bit %d should be 1)", readdata, SR_OF_PEND_BIT);

    // 清除溢出标志
    apb_mst_bfm.write(TIMx_SR, {PSTRB_SIZE{1'b1}}, (1 << SR_OF_PEND_BIT));

    // 禁用定时器
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, 16'h0000);
endtask : test_timer_autoload


/*
* Direction Test
* 测试递增/递减计数模式
*/
task test_timer_direction;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Timer Direction test ...");

    // 配置预分频为2-1
    apb_mst_bfm.write(TIMx_PSC, {PSTRB_SIZE{1'b1}}, 16'h0001);

    // 配置自动重载值为5-1
    apb_mst_bfm.write(TIMx_ARR, {PSTRB_SIZE{1'b1}}, 16'h0004);

    // 配置计数器初值为4
    apb_mst_bfm.write(TIMx_CNT, {PSTRB_SIZE{1'b1}}, 16'h0004);

    // 使能定时器 (递减模式: DIR bit = 1)
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, (1 << CR_EN_BIT) | (1 << CR_DIR_BIT));

    // 等待3个时钟周期
    repeat(3) @(posedge PCLK);
    #1;

    // 读取计数器值
    apb_mst_bfm.read(TIMx_CNT, readdata);
    if (VERBOSE > 0) $display("  Timer count in decrement mode after 3 cycles: %h", readdata);

    // 禁用定时器
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, 16'h0000);
endtask : test_timer_direction


/*
* Overflow Interrupt Test
* 测试溢出中断功能
*/
task test_timer_overflow_interrupt;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Timer Overflow Interrupt test ...");

    // 配置预分频为2-1
    apb_mst_bfm.write(TIMx_PSC, {PSTRB_SIZE{1'b1}}, 16'h0001);

    // 配置自动重载值为3-1
    apb_mst_bfm.write(TIMx_ARR, {PSTRB_SIZE{1'b1}}, 16'h0002);

    // 配置计数器初值为0
    apb_mst_bfm.write(TIMx_CNT, {PSTRB_SIZE{1'b1}}, 16'h0000);

    // 使能溢出中断
    apb_mst_bfm.write(TIMx_IER, {PSTRB_SIZE{1'b1}}, (1 << IER_INT_EN_BIT) | (1 << IER_OF_INT_EN_BIT));

    // 使能定时器
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, (1 << CR_EN_BIT));

    // 等待溢出发生
    repeat(10) @(posedge PCLK);
    #1;

    // 检查中断标志
    apb_mst_bfm.read(TIMx_SR, readdata);
    if (VERBOSE > 0) $display("  SR after overflow interrupt: %h", readdata);

    // 检查irq_o信号
    if (VERBOSE > 0) $display("  irq_o signal: %b", irq_o);

    // 清除中断标志
    apb_mst_bfm.write(TIMx_SR, {PSTRB_SIZE{1'b1}}, (1 << SR_OF_PEND_BIT));

    // 禁用定时器和中断
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, 16'h0000);
    apb_mst_bfm.write(TIMx_IER, {PSTRB_SIZE{1'b1}}, 16'h0000);
endtask : test_timer_overflow_interrupt


/*
* Timer Clear Test
* 测试定时器清零功能
*/
task test_timer_clear;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Timer Clear test ...");

    // 配置预分频为2-1
    apb_mst_bfm.write(TIMx_PSC, {PSTRB_SIZE{1'b1}}, 16'h0001);

    // 配置自动重载值为10-1
    apb_mst_bfm.write(TIMx_ARR, {PSTRB_SIZE{1'b1}}, 16'h0009);

    // 使能定时器
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, (1 << CR_EN_BIT));

    // 等待几个时钟周期
    repeat(5) @(posedge PCLK);
    #1;

    // 读取计数器值
    apb_mst_bfm.read(TIMx_CNT, readdata);
    if (VERBOSE > 0) $display("  Timer count before clear: %h", readdata);

    // 发送清零信号
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, (1 << CR_EN_BIT) | (1 << CR_CLR_BIT));

    // 等待清零完成
    // repeat(2) @(posedge PCLK);
    #1;

    // 读取计数器值
    apb_mst_bfm.read(TIMx_CNT, readdata);
    if (VERBOSE > 0) $display("  Timer count after clear: %h", readdata);
    check("CNT after clear", readdata, 16'h0000);

    // 禁用定时器
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, 16'h0000);
endtask : test_timer_clear


/*
* Channel Output Compare Test
* 测试输出比较功能
*/
task test_channel_output_compare;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Channel Output Compare test ...");

    // 配置通道1为输出比较模式
    apb_mst_bfm.write(TIMx_CCMR, {PSTRB_SIZE{1'b1}}, 16'h0001);  // CH1为比较模式

    // 配置通道1使能
    apb_mst_bfm.write(TIMx_CCER, {PSTRB_SIZE{1'b1}}, 16'h0001);  // CH1使能

    // 配置比较值为10
    apb_mst_bfm.write(TIMx_CCR1, {PSTRB_SIZE{1'b1}}, 16'h000A);

    // 配置预分频为2-1
    apb_mst_bfm.write(TIMx_PSC, {PSTRB_SIZE{1'b1}}, 16'h0001);

    // 配置自动重载值为20-1
    apb_mst_bfm.write(TIMx_ARR, {PSTRB_SIZE{1'b1}}, 16'h0019);

    // 使能定时器
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, (1 << CR_EN_BIT));

    // 等待比较匹配
    repeat(15) @(posedge PCLK);
    #1;

    if (VERBOSE > 0) begin
        $display("  Channel 1 output after compare match: %b", channel_o[0]);
        $display("  Channel 1 output enable: %b", channel_oe[0]);
    end

    // 禁用定时器
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, 16'h0000);

    // 关闭通道
    apb_mst_bfm.write(TIMx_CCER, {PSTRB_SIZE{1'b1}}, 16'h0000);
endtask : test_channel_output_compare


/*
* Channel Input Capture Test
* 测试输入捕获功能
*/
task test_channel_input_capture;
    logic [PDATA_WIDTH-1:0] readdata;

    $display ("Channel Input Capture test ...");
    channel_i[0] = 1'b0;

    // 配置通道1为输入捕获模式
    apb_mst_bfm.write(TIMx_CCMR, {PSTRB_SIZE{1'b1}}, 16'h0000);  // CH1为捕获模式

    // 配置通道1使能,上升沿触发
    apb_mst_bfm.write(TIMx_CCER, {PSTRB_SIZE{1'b1}}, 16'h0001);  // CH1使能

    // 配置预分频为2-1
    apb_mst_bfm.write(TIMx_PSC, {PSTRB_SIZE{1'b1}}, 16'h0001);

    // 配置自动重载值为100-1
    apb_mst_bfm.write(TIMx_ARR, {PSTRB_SIZE{1'b1}}, 16'h0063);

    // 使能捕获中断
    apb_mst_bfm.write(TIMx_IER, {PSTRB_SIZE{1'b1}}, 16'h0005);

    // 使能定时器
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, (1 << CR_EN_BIT));

    // 等待定时器运行
    repeat(10) @(posedge PCLK);
    #1;

    // 模拟输入信号变化 (上升沿)
    channel_i[0] = 1'b1;
    repeat(6) @(posedge PCLK);
    #1;

    // 读取捕获值
    apb_mst_bfm.read(TIMx_CCR1, readdata);
    if (VERBOSE > 0) $display("  Captured value on channel 1: %h", readdata);

    // 检查触发中断标志
    apb_mst_bfm.read(TIMx_SR, readdata);
    if (VERBOSE > 0) $display("  SR after capture: %h", readdata);

    // 清除标志
    apb_mst_bfm.write(TIMx_SR, {PSTRB_SIZE{1'b1}}, (1 << SR_TRIGGER_PEND_BIT));

    // 禁用定时器
    apb_mst_bfm.write(TIMx_CR, {PSTRB_SIZE{1'b1}}, 16'h0000);

    // 关闭通道
    apb_mst_bfm.write(TIMx_CCER, {PSTRB_SIZE{1'b1}}, 16'h0000);

    // 重置输入
    channel_i[0] = 1'b0;
endtask : test_channel_input_capture

endmodule