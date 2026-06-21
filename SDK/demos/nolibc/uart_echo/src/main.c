/*
 * Demo: UART Echo — 回显收到的每个字符
 * 验证：UART TX/RX 全双工
 */
#include "bsp.h"

static int uart_getc(void)
{
    if (UART_LSR & LSR_DR) return (int)(UART_RBR_THR & 0xFF);
    return -1;
}

int main(void)
{
    uart_init(115200);
    UART_FCR = 0x01;

    uart_puts("\r\nBD32 UART Echo (ESC to quit)\r\n");

    while (1) {
        int c = uart_getc();
        if (c < 0) continue;
        if (c == 0x1B) break;
        uart_putc((char)c);
    }

    uart_puts("\r\nDone!\r\n");
    while (1);
    return 0;
}
