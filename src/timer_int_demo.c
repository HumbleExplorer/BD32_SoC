/* BD32 定时器中断 Demo (使用新框架 trap_entry + trap_handler)
 *
 * 验证链路:
 *   _start → _init(mtvec=trap_entry, mstatus=0x1888)
 *   → main: 配置CLINT + mie → while(1) 轮询标志
 *   → CLINT mtime≥mtimecmp → timer_int → mip[7] → trap_entry
 *   → trap_handler(0x80000007, mepc) → tmr_irq_handler()
 *
 * 编译:
 *   riscv64-unknown-elf-gcc -c -Os -march=rv32im -mabi=ilp32 -fno-lto \
 *     -fno-builtin src/timer_int_demo.c -o /tmp/timer_int_demo.o
 *
 * 链接:
 *   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
 *     -nostartfiles -nodefaultlibs -T lib/link.ld \
 *     /tmp/timer_int_demo.o \
 *     /tmp/trap_entry.o /tmp/trap_handler.o /tmp/init.o \
 *     /tmp/start.o /tmp/syscalls.o \
 *     -o /tmp/timer_int_demo.elf
 *
 * 打包:
 *   python script/elf2uartbin.py /tmp/timer_int_demo.elf \
 *     test_data/custom/timer_int_demo.uartbin
 */

#include "../lib/bd32_intr.h"

/* ===== CSR 操作 ===== */
#define write_csr(reg, val) ({ \
    unsigned long __v = (unsigned long)(val); \
    __asm__ volatile("csrw " #reg ", %0" : : "r"(__v)); \
})

/* ===== UART (0xE0010000) ===== */
#define UART_THR    (*(volatile uint32_t*)0xE0010000)
#define UART_LSR    (*(volatile uint32_t*)0xE0010014)
#define UART_LCR    (*(volatile uint32_t*)0xE001000C)
#define LSR_THRE    (1UL << 5)

static void uart_putc(char c) {
    while (!(UART_LSR & LSR_THRE));
    UART_THR = (uint32_t)(uint8_t)c;
}

static void uart_print_dec(uint32_t n) {
    if (n >= 10) uart_print_dec(n / 10);
    uart_putc('0' + (n % 10));
}

/* ===== GPIO (0xE0000000) ===== */
#define GPIO_OUT    (*(volatile uint32_t*)0xE0000008)
#define GPIO_DIR    (*(volatile uint32_t*)0xE0000004)
#define LED_MASK    0x18

/* ===== CLINT (0xF2000000) ===== */
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

/* ===== 全局变量 ===== */
volatile uint32_t timer_irq_count = 0;

/* ===== 定时器中断处理函数 ===== */
void tmr_irq_handler(void) {
    timer_irq_count++;

    /* 翻转 LED */
    GPIO_OUT ^= LED_MASK;

    /* 打印计数 */
    uart_putc('[');
    uart_print_dec(timer_irq_count);
    uart_putc(']');
    uart_putc(' ');
    uart_putc('T');
    uart_putc('i');
    uart_putc('m');
    uart_putc('e');
    uart_putc('r');
    uart_putc('!');
    uart_putc('\n');

    /* 重新设 mtimecmp = 当前 mtime + 1秒 */
    clint_set_mtimecmp(clint_get_mtime() + 100000000ULL);
}

/* ===== main ===== */
int main(void) {
    /* UART 初始化 */
    UART_LCR = 0x80;
    *(volatile uint32_t*)0xE0010004 = 0;  /* DLM */
    UART_THR = 54;                         /* DLL */
    UART_LCR = 0x03;                       /* 8N1 */

    uart_putc('T');
    uart_putc('M');
    uart_putc('R');
    uart_putc('\n');

    /* GPIO 初始化 */
    GPIO_DIR = LED_MASK;
    GPIO_OUT = 0;

    /* 配置 CLINT mtimecmp = mtime + 500ms (100MHz = 50,000,000 cycles) */
    clint_set_mtimecmp(clint_get_mtime() + 50000000ULL);

    /* 使能定时器中断 mie[7] = MTIE */
    write_csr(mie, 0x00000080);

    /* 开启全局中断 mstatus[3] = MIE */
    write_csr(mstatus, 0x00001888);

    uart_putc('E');
    uart_putc('N');
    uart_putc('\n');

    /* 主循环: 轮询标志位 (不使用 wfi) */
    uint32_t last_count = 0;
    while (1) {
        if (timer_irq_count != last_count) {
            last_count = timer_irq_count;
        }
    }

    // return 0;
}
