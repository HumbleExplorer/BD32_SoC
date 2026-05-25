/*
 * Demo: GPIO Input — 按键轮询（STM32 风格消抖）
 * KEY0 = gpio_io[1] = L14, 按下低电平
 */
#include "bsp.h"

static int key_scan(void)
{
    if ((GPIO_IN & PIN_KEY0) == 0) {
        delay_ms(10);
        if ((GPIO_IN & PIN_KEY0) == 0) {
            while ((GPIO_IN & PIN_KEY0) == 0);
            return 1;
        }
    }
    return 0;
}

int main(void)
{
    uart_init();
    uart_puts("\r\nBD32 GPIO Input - Press KEY0 5 times\r\n");

    GPIO_DIR &= ~PIN_KEY0;

    int count = 0;
    while (count < 5) {
        if (key_scan()) {
            count++;
            uart_puts("KEY0 #"); uart_putdec(count); uart_puts("\r\n");
        }
        delay_ms(10);
    }

    uart_puts("Done!\r\n");
    while (1);
    return 0;
}
