/*
 * Demo: Breathing LED — 呼吸灯（定时器 PWM + 中断闪烁）
 * 呼吸：Timer PWM 输出 → 硬件呼吸灯
 * 闪烁：ISR 计数翻转 GPIO LED（无 UART 诊断，避免总线竞争）
 */
#include "bsp.h"

#define PLIC_SRC_TIMER 3
#define BLINK_INTERVAL 10    /* 仿真观察：10 次中断翻转一次 LED */

static volatile uint32_t blink_cnt;

void ext_irq_handler(void)
{
    uint32_t src = PLIC_CLAIM;
    if (src != PLIC_SRC_TIMER) {
        PLIC_CLAIM = src;
        return;
    }

    TIM_SR = 0x01;              /* 清 UIF */

    blink_cnt++;
    if (blink_cnt >= BLINK_INTERVAL) {
        blink_cnt = 0;
        GPIO_OUT ^= PIN_LED0;   /* 翻转闪烁 LED */
    }

    PLIC_CLAIM = src;
}

int main(void)
{
    uart_init(115200);
    uart_puts("\r\nBD32 Breathing LED (PWM + Timer IRQ)\r\n");

    /* 闪烁 LED 输出 */
    GPIO_DIR |= PIN_LED0;
    GPIO_CLR(PIN_LED0);

    /* 崩溃复现配方（慢）：PSC=80/ARR=1000 → 约 1ms/次中断，第 3 次中断（~16.34ms）触发
     * dtcm_rvalid 陈旧写回 bug。快速观察配置：TIM_PSC=4-1、TIM_ARR=100-1（不触发该 bug） */
    TIM_PSC  = 80 - 1;
    TIM_ARR  = 1000 - 1;
    TIM_CCMR = 0x01;            /* PWM mode 1 */
    TIM_CCER = 0x01;            /* 使能 OC1 输出 */
    TIM_CR   = 0x01;
    TIM_IER  = 0x03;            /* 更新中断 + 溢出中断使能 */

    PLIC_PRIORITY(PLIC_SRC_TIMER) = 1;
    PLIC_ENABLE |= (1 << PLIC_SRC_TIMER);
    PLIC_THRESHOLD = 0;

    core_enable_irq(MIE_MEIE);
    __enable_irq();

    /* 呼吸效果：CCR1 从 0→999 爬升再下降 */
    uint32_t ccr = 0, dir = 0;
    while (1) {
        delay_ms(2);

        if (dir == 0) {
            if (ccr >= 999) { dir = 1; ccr--; }
            else ccr++;
        } else {
            if (ccr == 0) { dir = 0; ccr++; }
            else ccr--;
        }
        TIM_CCR1 = ccr;
    }
    return 0;
}
