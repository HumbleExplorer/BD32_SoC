/*
 * PLIC IRQ Demo — KEY0 按键中断
 * 每次按下 KEY0 打印一次信息（仿 gpio_input），3 次后 PASS
 * 消抖：ISR 只置标志；主循环延时 10ms 后复检电平，确认仍按下才计数
 */
#include "bsp.h"

#define PLIC_SRC_GPIO 2
#define KEY_DEBOUNCE_MS   10       /* 消抖延时：等机械抖动稳定 */
static volatile int btn_cnt = 0;
static volatile int key_pressed = 0;   /* 中断标志：ISR 置位，主循环消抖确认 */

void ext_irq_handler(void)
{
    uint32_t claim = PLIC_CLAIM;
    if (claim == PLIC_SRC_GPIO) {
        /* Opensoc 方式: 先读状态再清标志 */
        (void)GPIO_TR_STAT;        /* 读状态（确认触发源） */
        GPIO_TR_STAT = 0xFF;       /* 写全 1 清所有 pending */
        key_pressed = 1;           /* 置按键标志，主循环做消抖确认 */
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
        if (key_pressed) {
            key_pressed = 0;
            delay_ms(KEY_DEBOUNCE_MS);          /* 等抖动稳定 */
            if ((GPIO_IN & PIN_KEY0) == 0) {    /* 复检：仍按住才算一次 */
                btn_cnt++;
                uart_puts("KEY0 #"); uart_putdec(btn_cnt); uart_puts("\r\n");
            }
        }
        delay_ms(10);
    }

    uart_puts("\r\nPASS!\r\n");
    while (1);
    return 0;
}
