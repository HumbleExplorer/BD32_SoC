/*
 * BSP — BD32 板级支持包统一头文件
 * 应用只需 #include "bsp.h"
 */
#ifndef BSP_H
#define BSP_H

#include "soc/soc.h"
#include "board/bd32_board.h"

/* ===================================================================
 * UART 驱动
 * =================================================================== */
void uart_init(uint32_t baud);
void uart_putc(char c);
void uart_puts(const char *s);
void uart_puthex(uint32_t val);
void uart_putdec(uint32_t val);
void uart_put_fixed(int32_t val, int precision);

/* printf 定点小数（需 newlib-nano）*/
void print_fixed(int32_t val, int precision);
void print_fixed_scaled(int32_t val, int32_t scale);

/* ===================================================================
 * CLINT 接口（低层汇编 + 内联包装）
 * =================================================================== */
uint32_t clint_asm_get_mtime_lo(void);
uint64_t clint_asm_get_mtime(void);
void     clint_asm_set_mtimecmp(uint64_t val);
void     clint_asm_set_timeout_ticks(uint32_t ticks);

static inline uint32_t clint_mtime(void) {
    return clint_asm_get_mtime_lo();
}
static inline void clint_set_timer(uint32_t ticks) {
    clint_asm_set_timeout_ticks(ticks);
}

/* 精确延时 */
static inline void delay_us(uint32_t us) {
    uint32_t start = clint_mtime();
    uint32_t ticks = us * (CPU_FREQ_KHZ / 1000UL);
    while ((uint32_t)(clint_mtime() - start) < ticks);
}
static inline void delay_ms(uint32_t ms) {
    uint32_t start = clint_mtime();
    uint32_t ticks = ms * CPU_FREQ_KHZ;
    while ((uint32_t)(clint_mtime() - start) < ticks);
}
static inline void delay_loop(volatile uint32_t n) {
    while (n--) __asm__ volatile("");
}

#endif
