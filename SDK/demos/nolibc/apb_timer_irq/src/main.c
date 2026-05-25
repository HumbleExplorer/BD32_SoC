/*
 * Demo: APB Timer IRQ — 外设定时器中断，每 0.5s 翻转 LED
 * Timer IRQ (Source 3) 驱动，ISR 中只清标志 + 翻灯 + 计数
 */
#include "bsp.h"

#define PLIC_SRC_TIMER 3
static volatile int tim_cnt = 0;

void ext_irq_handler(void)
{
    uint32_t claim = PLIC_CLAIM;
    if (claim == PLIC_SRC_TIMER) {
        TIM_SR = 0x01;                  /* 写 1 清 UIF */
        GPIO_OUT ^= PIN_LED0;           /* 异或翻转 LED0 */
        tim_cnt++;
    }
    PLIC_CLAIM = claim;
}

int main(void)
{
    uart_init();
    uart_puts("\r\nBD32 APB Timer IRQ - LED toggles every 0.5s\r\n");

    /* 配置 LED0 为推挽输出 */
    GPIO_DIR |= PIN_LED0;               /* bit=1 → 输出模式 */

    /* APB Timer: 100MHz / 50000 = 2000Hz, ARR=999 → 2Hz (0.5s) */
    TIM_PSC  = 50000 - 1;
    TIM_ARR  = 1000 - 1;
    TIM_IER  = 0x03;                    /* bit0=timer_int_en, bit1=timer_of_int_en */
    TIM_CR   = 0x01;                    /* 启动定时器 */

    PLIC_PRIORITY(PLIC_SRC_TIMER) = 5;
    PLIC_ENABLE |= (1 << PLIC_SRC_TIMER);
    PLIC_THRESHOLD = 0;

    core_enable_irq(MIE_MEIE);
    __enable_irq();

    /* 等待 10 次中断 = 5 秒 */
    while (tim_cnt < 10)
        __asm__ volatile("wfi");

    TIM_CR = 0;                         /* 停定时器 */
    GPIO_CLR(PIN_LED0);                 /* 关 LED */
    uart_puts("PASS!\r\n");
    while (1);
    return 0;
}
