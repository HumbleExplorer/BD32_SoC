/*
 * PLIC IRQ Demo — KEY0 按键中断（已修 PLIC claim bug）
 * 进 ISR 时翻 LED0 + 打印，3 次后 PASS
 */
#include "bsp.h"

#define PLIC_SRC_GPIO 2
static volatile int btn_cnt = 0;

void ext_irq_handler(void)
{
    uint32_t claim = PLIC_CLAIM;
    if (claim == PLIC_SRC_GPIO) {
        /* Opensoc 方式: 先读状态再清标志 */
        (void)GPIO_TR_STAT;        /* 读状态（确认触发源） */
        GPIO_TR_STAT = 0xFF;       /* 写全 1 清所有 pending */
        btn_cnt++;
    }
    PLIC_CLAIM = claim;
}

int main(void)
{
    uart_init(115200);
    GPIO_DIR |= LED_MASK;
    uart_puts("\r\nBD32 PLIC IRQ - Press KEY0 3 times\r\n");

    /* GPIO: KEY0 input, 下降沿触发 */
    GPIO_DIR &= ~PIN_KEY0;
    GPIO_TR_TYPE |= PIN_KEY0;
    GPIO_TR_LVL0 |= PIN_KEY0;
    GPIO_IRQ_ENA |= PIN_KEY0;

    /* PLIC */
    PLIC_PRIORITY(PLIC_SRC_GPIO) = 3;
    PLIC_ENABLE |= (1 << PLIC_SRC_GPIO);
    PLIC_THRESHOLD = 0;

    core_enable_irq(MIE_MEIE);
    __enable_irq();

    uart_puts("Waiting...\r\n");
    while (btn_cnt < 3) {
        uart_puts(".");               /* 主循环打印点，证明活着 */
        delay_ms(500);
    }

    uart_puts("\r\nPASS!\r\n");
    while (1);
    return 0;
}
