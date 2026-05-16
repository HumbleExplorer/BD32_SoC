/*
 * Step 1: GPIO 闪烁（BOP + CLINT 精确延时）
 */

#include "bd32.h"

int main(void) {
    uart_init();
    uart_puts("Step1: BOP + CLINT delay\n");

    GPIO_DIR |= PIN_LED0;
    GPIO_CLR(PIN_LED0);

    while (1) {
        GPIO_SET(PIN_LED0);
        clint_delay_ms(200);
        GPIO_CLR(PIN_LED0);
        clint_delay_ms(200);
    }
}
