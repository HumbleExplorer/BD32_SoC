/* 多文件 Demo — main，_start 由 bsp/start.S 提供 */

#include "demo.h"

int main(void) {
    uart_init();

    uart_putc('H'); uart_putc('e'); uart_putc('l'); uart_putc('l'); uart_putc('o');
    uart_putc('\n');

    gpio_off();

    uart_putc('W'); uart_putc('o'); uart_putc('r'); uart_putc('l'); uart_putc('d');
    uart_putc('\n');

    while (1);
}
