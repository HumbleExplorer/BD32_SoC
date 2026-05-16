/* BD32 定时器中断 Demo — 自包含启动，不链接 start.o */
/* 
 * 启动流程：
 *   内嵌 _start (设sp+BSS清零) → _init (mtvec=trap_entry) → main
 *   链接 init.o + trap_entry.o + trap_handler.o + syscalls.o
 */
asm(".section .init\n"
    ".global _start\n"
    "_start:\n"
    "    la sp, _estack\n"
    "    la a0, _sbss\n"
    "    la a1, _ebss\n"
    "    beq a0, a1, 2f\n"
    "1:  sw zero, 0(a0)\n"
    "    addi a0, a0, 4\n"
    "    bltu a0, a1, 1b\n"
    "2:\n"
    "    call _init\n"
    "    call main\n"
    "    j .\n");

#include "../lib/bd32_intr.h"

/* CSR 操作 */
#define write_csr(reg, val) ({ \
    unsigned long __v = (unsigned long)(val); \
    __asm__ volatile("csrw " #reg ", %0" : : "r"(__v)); \
})

/* 外设 */
#define UART_THR    (*(volatile uint32_t*)0xE0010000)
#define UART_LSR    (*(volatile uint32_t*)0xE0010014)
#define UART_LCR    (*(volatile uint32_t*)0xE001000C)
#define LSR_THRE    (1UL << 5)
#define GPIO_OUT    (*(volatile uint32_t*)0xE0000008)
#define GPIO_DIR    (*(volatile uint32_t*)0xE0000004)
#define LED_MASK    0x18

#define CLINT_MTIME_LO   (*(volatile uint32_t*)0xF200BFF8)
#define CLINT_MTIME_HI   (*(volatile uint32_t*)0xF200BFFC)
#define CLINT_MTIMECMP_LO (*(volatile uint32_t*)0xF2004000)
#define CLINT_MTIMECMP_HI (*(volatile uint32_t*)0xF2004004)

static uint64_t clint_get_mtime(void) {
    uint32_t lo, hi;
    do { hi = CLINT_MTIME_HI; lo = CLINT_MTIME_LO; } while (hi != CLINT_MTIME_HI);
    return ((uint64_t)hi << 32) | lo;
}

static void clint_set_mtimecmp(uint64_t val) {
    CLINT_MTIMECMP_HI = (uint32_t)(val >> 32);
    CLINT_MTIMECMP_LO = (uint32_t)(val);
}

static void uart_putc(char c) {
    while (!(UART_LSR & LSR_THRE));
    UART_THR = (uint32_t)(uint8_t)c;
}

static void uart_print_dec(uint32_t n) {
    if (n >= 10) uart_print_dec(n / 10);
    uart_putc('0' + (n % 10));
}

volatile uint32_t timer_irq_count = 0;

void tmr_irq_handler(void) {
    timer_irq_count++;
    GPIO_OUT ^= LED_MASK;
    uart_putc('['); uart_print_dec(timer_irq_count); uart_putc(']');
    uart_putc(' '); uart_putc('T'); uart_putc('!'); uart_putc('\n');
    clint_set_mtimecmp(clint_get_mtime() + 50000000ULL);
}

int main(void) {
    /* UART */
    UART_LCR = 0x80;
    *(volatile uint32_t*)0xE0010004 = 0;
    UART_THR = 54;
    UART_LCR = 0x03;

    uart_putc('O'); uart_putc('K'); uart_putc('\n');

    /* GPIO */
    GPIO_DIR = LED_MASK;
    GPIO_OUT = 0;

    /* CLINT */
    clint_set_mtimecmp(clint_get_mtime() + 50000000ULL);

    /* mie + mstatus */
    write_csr(mie, 0x00000080);
    write_csr(mstatus, 0x00001888);

    uart_putc('E'); uart_putc('N'); uart_putc('\n');

    while (1);
}
