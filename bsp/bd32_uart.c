/*
 * BD32 UART 驱动实现
 * 参考 Panda apb_uart / tinyriscv uart
 */

#include "bd32.h"

void uart_init(void) {
    /* DLL = 100MHz / (16 * 115200) ≈ 54 */
    UART_LCR = 0x80;        /* DLAB = 1 */
    UART_DLL = 54;
    UART_DLM = 0;
    UART_LCR = 0x03;        /* 8N1, DLAB = 0 */
}

void uart_putc(char c) {
    while (!(UART_LSR & LSR_THRE));
    UART_RBR_THR = (uint32_t)(uint8_t)c;
}

void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

void uart_puthex(uint32_t val) {
    static const char hex[] = "0123456789ABCDEF";
    uart_putc('0');
    uart_putc('x');
    for (int i = 28; i >= 0; i -= 4) {
        uart_putc(hex[(val >> i) & 0xF]);
    }
}

void uart_putdec(uint32_t val) {
    if (val >= 10) uart_putdec(val / 10);
    uart_putc('0' + (val % 10));
}
