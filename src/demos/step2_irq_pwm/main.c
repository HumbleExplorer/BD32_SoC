/*
 * Step 2 — PWM 呼吸灯 + 定时器中断演示
 *
 * 功能：
 *   - APB Timer 产生 100Hz 溢出中断（PSC=999, ARR=999 @ 100MHz）
 *   - PLIC 响应中断，调用 ext_irq_handler 清除标志
 *   - 主循环通过不断修改 TIM_CCR1 实现呼吸灯 PWM 效果
 *   - 每 500 轮打印一次 mip 和 PLIC 状态
 */

#include "bd32.h"
#include "bd32_core.h"

/* hex 打印辅助 */
static void phex(uint32_t v) {
    for (int i = 28; i >= 0; i -= 4) {
        int d = (v >> i) & 0xF;
        uart_putc(d < 10 ? '0' + d : 'A' + d - 10);
    }
}

/* ===================================================================
 * 外部中断处理函数（由 irq_external_entry 汇编入口调用）
 * BD32 只有 Timer 中断通过 PLIC 上报（INT_TIMER=3）
 * 直接清除标志并 complete 即可
 * =================================================================== */
void ext_irq_handler(void) {
    TIM_SR  = TIM_OF_FLAG;      /* 清定时器溢出标志 */
    PLIC_COMPLETE = 3;          /* PLIC complete (INT_TIMER) */
}

/* ===================================================================
 * 主函数
 * =================================================================== */
int main(void) {
    uart_init();
    uart_puts("BD32 Step2: PWM Breathing LED\n");

    /* ── 初始化 GPIO（板载 LED） ── */
    GPIO_DIR |= PIN_LED0;
    GPIO_CLR(PIN_LED0);

    /* ── 配置 APB Timer: 100Hz 溢出 ── */
    TIM_PSC  = 999;             /* 分频 1000 */
    TIM_ARR  = 999;             /* 周期 1000 计数 → 100Hz */
    TIM_CCMR = 0x01;            /* PWM 模式 1 */
    TIM_CCER = 0x01;            /* 使能通道 1 输出 */
    TIM_CR   = 0x01;            /* 使能定时器 */
    TIM_IER  = 0x03;            /* 使能溢出中断 */

    /* ── 配置 PLIC ── */
    PLIC_PRIORITY(3)  = 1;      /* Timer 中断优先级 */
    PLIC_ENABLE      |= (1 << 3); /* 使能 Timer 中断 */
    PLIC_THRESHOLD    = 0;      /* 门槛=0，接收所有中断 */
    PLIC_COMPLETE     = 3;      /* 初始 complete */

    /* ── 开 CPU 级中断 ── */
    set_csr(mie, MIE_MEIE);     /* 使能外部中断 */
    set_csr(mstatus, MSTATUS_MIE); /* 使能全局中断 */

    /* ── 呼吸灯主循环 ── */
    uint32_t ccr = 0, dir = 0, cnt = 0;
    while (1) {
        clint_delay_ms(2);

        /* 三角波：0 → 999 → 0 循环 */
        if (dir == 0) {
            if (ccr >= 999) { dir = 1; ccr--; }
            else ccr++;
        } else {
            if (ccr == 0) { dir = 0; ccr++; }
            else ccr--;
        }
        TIM_CCR1 = ccr;

        /* 周期打印（约 1000ms 一次） */
        cnt++;
        if (cnt >= 500) {
            cnt = 0;
            uart_putc('M'); phex(read_csr(mip));
            uart_puts(" P3="); phex(PLIC_PRIORITY(3));
            uart_puts(" SR="); phex(TIM_SR);
            uart_puts(" PS="); phex(PLIC_PENDING);
            uart_puts(" EN="); phex(PLIC_ENABLE);
            uart_puts(" TH="); phex(PLIC_THRESHOLD);
            uart_putc('\n');
        }
    }
}
