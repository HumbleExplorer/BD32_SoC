/*
 * Demo: GPIO Blink — 板载 LED 闪烁（无 C 标准库）
 * 验证：GPIO 输出 / CLINT mtime 延时
 */
#include "bsp.h"

int main(void)
{
    uart_init(115200);
    uart_puts("\r\nBD32 LED Blink\r\n");

    GPIO_DIR |= LED_MASK;

    while (1) {
        GPIO_SET(LED_MASK);
        delay_ms(200);
        GPIO_CLR(LED_MASK);
        delay_ms(200);
    }
    return 0;
}
