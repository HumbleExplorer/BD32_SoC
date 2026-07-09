/*
 * BSP — BD32 板级支持包统一头文件
 * 应用只需 #include "bsp.h"
 *
 * v2: CPU_FREQ_HZ 改为运行时变量 g_cpu_freq_hz
 *     delay_us/delay_ms 自动适配任意主频
 */
#ifndef BSP_H
#define BSP_H

#include "soc/soc.h"
#include "board/bd32_board.h"

/* ===================================================================
 * UART 驱动（uart_init 为常规函数，uart_putc/uart_getc 高频调用故内联）
 * =================================================================== */
void uart_init(uint32_t baud);
void uart_puts(const char *s);
void uart_puthex(uint32_t val);
void uart_putdec(uint32_t val);
void uart_put_fixed(int32_t val, int precision);

static inline void uart_putc(char c) {
    while (!(UART_LSR & LSR_THRE));
    UART_RBR_THR = (uint32_t)(uint8_t)c;
}

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

/* 读 mtime 低 32 位（1 tick = 1µs，32 位绕回周期 ~4295s）*/
static inline uint32_t clint_mtime_lo(void) {
    uint32_t val;
    __asm__ volatile("csrr %0, 0xC01" : "=r"(val));
    return val;
}
/* 读完整 64 位 mtime（带双读校验）*/
static inline uint64_t clint_mtime(void) {
    return clint_asm_get_mtime();
}
static inline void clint_set_timer(uint32_t ticks) {
    clint_asm_set_timeout_ticks(ticks);
}

/* ===================================================================
 * 精确延时（基于 CLINT mtime — 独立 1MHz 定时器时钟）
 *
 * CLINT mtime 由 timer_clk_i 驱动，频率固定为 1MHz
 * 1 tick = 1µs，延迟函数直接用 mtime tick 计数
 * 与 CPU 主频解耦，不受 g_cpu_freq_hz 影响
 *
 * 最大延迟：~4295 秒（mtime_lo 32-bit 回绕时间 @1MHz）
 * =================================================================== */
static inline void delay_us(uint32_t us) {
    uint32_t start = clint_mtime_lo();
    while ((uint32_t)(clint_mtime_lo() - start) < us);
}
static inline void delay_ms(uint32_t ms) {
    uint32_t start = clint_mtime_lo();
    uint32_t ticks = ms * 1000UL;   /* 1 tick = 1µs → ms 需 1000× 的 tick */
    while ((uint32_t)(clint_mtime_lo() - start) < ticks);
}
/* 粗糙延时（仅 CPU 循环，用于极短脉冲等特殊场景）*/
static inline void delay_loop(volatile uint32_t n) {
    while (n--) __asm__ volatile("");
}

#endif
