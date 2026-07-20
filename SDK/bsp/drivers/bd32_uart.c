/*
 * BD32 UART 驱动实现
 * 参考 Panda apb_uart / tinyriscv uart
 *
 * v2: uart_init() 使用运行时主频 g_cpu_freq_hz 计算 NCO FCW
 *     调用前需确保 soc_init() 已完成
 */
#include "bsp.h"

void uart_init(uint32_t baud) {
    uint32_t freq = CPU_FREQ_HZ;

    /* NCO FCW = (baud × 16 × 2^32 + Fclk/2) / Fclk，四舍五入
     * 例：115200 @ 100MHz → FCW = 0x04B7F5A5 (79164837)
     *     115200 @ 90MHz  → FCW = 0x053E2D62 (87960930)
     * 注意：分子是 baud×16×2^32，不是 baud×16×2^24（差 256 倍）
     */
    uint32_t fcw = (uint32_t)(((uint64_t)baud * 16ULL * 0x100000000ULL + (uint64_t)freq / 2) / (uint64_t)freq);
    UART_FCW = fcw;

    /* 兼容旧除数写入（NCO 模式下无效，但无害） */
    UART_LCR = 0x80;        /* DLAB = 1 */
    UART_DLL = (uint32_t)(freq / (16 * baud)) & 0xFF;
    UART_DLM = 0;
    UART_LCR = 0x03;        /* 8N1, DLAB = 0 */
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
