/*
 * BD32 UART 驱动实现
 * 参考 Panda apb_uart / tinyriscv uart
 */

#include "bsp.h"

void uart_init(uint32_t baud) {
    /* NCO FCW = (baud * 16 * 2^32 + Fclk/2) / Fclk，四舍五入 */
    uint32_t fcw = (uint32_t)(((uint64_t)baud * 16 * 0x100000000ULL + CPU_FREQ_HZ/2) / CPU_FREQ_HZ);
    UART_FCW = fcw;

    /* 兼容旧除数写入（NCO 模式下无效，但无害） */
    UART_LCR = 0x80;        /* DLAB = 1 */
    UART_DLL = (uint32_t)(CPU_FREQ_HZ / (16 * baud)) & 0xFF;
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

/* 打印定点小数: val = 整数部分放大 10^precision 倍 */
/* 例: uart_put_fixed(250, 2) → "2.50" */
void uart_put_fixed(int32_t val, int precision)
{
    if (val < 0) { uart_putc('-'); val = -val; }
    int32_t divisor = 1;
    for (int i = 0; i < precision; i++) divisor *= 10;
    uart_putdec((uint32_t)(val / divisor));
    if (precision > 0) {
        uart_putc('.');
        uint32_t frac = (uint32_t)(val % divisor);
        uint32_t d = divisor / 10;
        while (d > 0) {
            uart_putc('0' + (frac / d) % 10);
            d /= 10;
        }
    }
}
