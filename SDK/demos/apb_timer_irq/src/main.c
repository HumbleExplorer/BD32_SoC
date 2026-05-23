/*
 * Demo: APB Timer IRQ — 外设定时器中断（经 PLIC Source 3）
 * ISR 中不做 UART 打印，只清标志 + 计数
 */
#include "bsp.h"

#define PLIC_SRC_TIMER 3
static volatile int tim_cnt = 0;

void ext_irq_handler(void)
{
    uint32_t claim = PLIC_CLAIM;
    if (claim == PLIC_SRC_TIMER) {
        TIM_SR = 0x01;           /* 写 1 清 UIF */
        tim_cnt++;
    }
    PLIC_CLAIM = claim;
}

int main(void)
{
    uart_init();
    uart_puts("\r\nBD32 APB Timer IRQ\r\n");

    /* APB Timer: 100MHz / 10000 = 10kHz, ARR=9999 → 1Hz */
    TIM_PSC  = 10000 - 1;
    TIM_ARR  = 10000 - 1;
    TIM_IER  = 0x01;
    TIM_CR   = 0x01;

    PLIC_PRIORITY(PLIC_SRC_TIMER) = 5;
    PLIC_ENABLE |= (1 << PLIC_SRC_TIMER);
    PLIC_THRESHOLD = 0;

    core_enable_irq(MIE_MEIE);
    __enable_irq();

    while (tim_cnt < 3) __asm__ volatile("wfi");

    TIM_CR = 0;
    uart_puts("PASS!\r\n");
    while (1);
    return 0;
}
