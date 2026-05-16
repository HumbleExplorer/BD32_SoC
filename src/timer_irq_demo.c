/* BD32 定时器中断 Demo
 *
 * 验证链路：
 *   CLINT mtime ≥ mtimecmp → timer_int → CSR识别MTI → trap_entry
 *   → Exception_Handler → IRQ_Dispatch → call trap_handler(mcause, mepc)
 *
 * 效果：
 *   - 每隔 ~1 秒打印 "T" 并通过 UART 输出计数
 *   - LED(GPIO[3:4]) 每次中断翻转
 *
 * 编译（从 Working 目录运行）：
 *   riscv64-unknown-elf-gcc -c -Os -march=rv32im -mabi=ilp32 \
 *     -fno-lto -fno-builtin src/timer_irq_demo.c -o timer_irq_demo.o
 *
 * 链接：
 *   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
 *     -nostartfiles -nodefaultlibs -T lib/link.ld \
 *     timer_irq_demo.o lib/syscalls.o lib/start.o \
 *     -o timer_irq_demo.elf
 *
 * 生成 bin：
 *   riscv64-unknown-elf-objcopy -O binary timer_irq_demo.elf timer_irq_demo.bin
 */

#include <stdint.h>

/* ===== CSR 操作（参考 Panda RISC-V utils.h） ===== */
#define read_csr(reg) ({ unsigned long __tmp; \
    __asm__ volatile("csrr %0, " #reg : "=r"(__tmp)); \
    __tmp; })

#define write_csr(reg, val) ({ \
    unsigned long __v = (unsigned long)(val); \
    __asm__ volatile("csrw " #reg ", %0" : : "r"(__v)); \
})

/* ===== 宏：NOP 延迟 ===== */
#define DELAY(n) do { volatile int __d; for (__d = (n); __d > 0; __d--) __asm__ volatile("nop"); } while(0)

/* ===== GPIO (0xE0000000) ===== */
#define GPIO_BASE   0xE0000000UL
#define GPIO_DATA   (*(volatile uint32_t*)(GPIO_BASE + 0x00))
#define GPIO_DIR    (*(volatile uint32_t*)(GPIO_BASE + 0x04))
#define GPIO_OUT    (*(volatile uint32_t*)(GPIO_BASE + 0x08))
#define GPIO_IN     (*(volatile uint32_t*)(GPIO_BASE + 0x0C))
#define LED_MASK    0x18   /* GPIO[3:4] */

/* ===== UART (0xE0010000) ===== */
#define UART_BASE   0xE0010000UL
#define UART_THR    (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_LSR    (*(volatile uint32_t*)(UART_BASE + 0x14))
#define UART_LCR    (*(volatile uint32_t*)(UART_BASE + 0x0C))
#define LSR_THRE    (1 << 5)

/* 写单个字符（非 .rodata 依赖） */
static void uart_putc(char c) {
    while (!(UART_LSR & LSR_THRE));
    UART_THR = (uint32_t)(uint8_t)c;
}

/* 写十进制数（无 .rodata 依赖） */
static void uart_print_dec(uint32_t n) {
    if (n >= 10) uart_print_dec(n / 10);
    uart_putc('0' + (n % 10));
}

/* ===== CLINT (0xF2000000) ===== */
#define CLINT_BASE  0xF2000000UL
/* MTIME 在 CLINT 内部偏移 0xBFF8，但注意 CLINT 内部只有 [15:0] 地址有效 */
/* CLINT 模块的 PADDR[15:2] 解码: MTIME=18'h3FFE? 读 CLINT 的代码 */
/* 实际 CLINT 使用 PADDR[15:2] 做 case: 
 *   0xBFF8>>2 = 0x2FFE → mtime[31:0]
 *   0xBFFC>>2 = 0x2FFF → mtime[63:32]  
 *   0x4000>>2 = 0x1000 → mtimecmp[31:0]
 *   0x4004>>2 = 0x1001 → mtimecmp[63:32]
 *   0x0000>>2 = 0x0000 → msip
 * 所以 CLINT 的 APB 地址就是 0xF200_0000 + 偏移
 */
#define CLINT_MTIME_LO   (*(volatile uint32_t*)(CLINT_BASE + 0xBFF8))
#define CLINT_MTIME_HI   (*(volatile uint32_t*)(CLINT_BASE + 0xBFFC))
#define CLINT_MTIMECMP_LO (*(volatile uint32_t*)(CLINT_BASE + 0x4000))
#define CLINT_MTIMECMP_HI (*(volatile uint32_t*)(CLINT_BASE + 0x4004))
#define CLINT_MSIP       (*(volatile uint32_t*)(CLINT_BASE + 0x0000))

/* 读取 64 位 mtime */
static uint64_t clint_get_mtime(void) {
    uint32_t lo, hi;
    do {
        hi = CLINT_MTIME_HI;
        lo = CLINT_MTIME_LO;
    } while (hi != CLINT_MTIME_HI);
    return ((uint64_t)hi << 32) | lo;
}

/* 设置 64 位 mtimecmp（先写高 32 位，再写低 32 位触发比较） */
static void clint_set_mtimecmp(uint64_t val) {
    CLINT_MTIMECMP_HI = (uint32_t)(val >> 32);
    CLINT_MTIMECMP_LO = (uint32_t)(val & 0xFFFFFFFF);
}

/* ===== 全局变量 ===== */
static volatile uint32_t timer_count = 0;

/* ===== C 中断处理函数 ===== */
/* 由 start.s 的 IRQ_Dispatch 在保存上下文后调用 */
/* a0 = mcause, a1 = mepc */
void trap_handler(uint32_t mcause, uint32_t mepc) {
    (void)mepc;

    /* 只有定时器中断 */
    if (mcause == (0x80000000 | 7)) {
        /* 翻转 LED */
        GPIO_OUT ^= LED_MASK;

        timer_count++;

        /* 打印计数器 */
        uart_putc('[');
        uart_print_dec(timer_count);
        uart_putc(']');
        uart_putc(' ');
        uart_putc('T');
        uart_putc('i');
        uart_putc('m');
        uart_putc('e');
        uart_putc('r');
        uart_putc('!');
        uart_putc('\n');

        /* 重新设置 mtimecmp：当前 mtime + 100000000 (1秒 @ 100MHz) */
        clint_set_mtimecmp(clint_get_mtime() + 100000000ULL);

    } else {
        /* 未识别的中断/异常 → HardFault */
        uart_putc('?');
        uart_putc('\n');
        while (1);
    }
}

/* ===== main ===== */
int main(void) {
    /* 初始化 UART */
    UART_LCR = 0x80;           /* DLAB=1 */
    DELAY(200);
    UART_THR = 54;             /* DLL */
    /* UART_BASE+0x04 = DLM */
    *(volatile uint32_t*)(UART_BASE + 0x04) = 0;
    UART_LCR = 0x03;           /* 8N1, DLAB=0 */
    DELAY(200);

    uart_putc('\n');
    uart_putc('T');
    uart_putc('M');
    uart_putc('R');
    uart_putc(' ');
    uart_putc('D');
    uart_putc('E');
    uart_putc('M');
    uart_putc('O');
    uart_putc('\n');

    /* 初始化 GPIO */
    GPIO_DIR = LED_MASK;
    GPIO_OUT = 0;

    /* ===== 配置定时器中断 ===== */

    /* 1. 设置 CLINT mtimecmp = 当前 mtime + 1秒 */
    /*    先将 mtimecmp 设得很大（全 1），然后设置确切值 */
    CLINT_MTIMECMP_HI = 0xFFFFFFFF;
    CLINT_MTIMECMP_LO = 0xFFFFFFFF;
    clint_set_mtimecmp(clint_get_mtime() + 100000000ULL);

    /* 2. 使能机器定时器中断 mie[7] = MTIE */
    write_csr(mie, 0x00000080);

    /* 3. 使能机器模式全局中断 mstatus[3] = MIE */
    write_csr(mstatus, 0x00001808);

    uart_putc('I');
    uart_putc('R');
    uart_putc('Q');
    uart_putc(' ');
    uart_putc('E');
    uart_putc('N');
    uart_putc('!');
    uart_putc('\n');

    /* ===== 打印 mtime 低16位 ===== */
    uart_putc('M');
    uart_putc('=');
    uart_print_dec((uint32_t)clint_get_mtime());
    uart_putc('\n');

    /* ===== 读多个 APB 外设地址，定位哪个段通 ===== */
    #define READ_DEC(label, addr) do { \
        uint32_t __v = *(volatile uint32_t*)(addr); \
        uart_putc(label); uart_putc('='); uart_print_dec(__v); uart_putc('\n'); \
    } while(0)

    READ_DEC('G', 0xE0000000);   /* GPIO Mode （应该大数）  */
    READ_DEC('U', 0xE0010000);   /* UART DLL （应该是54）  */
    READ_DEC('F', 0xF2000000);   /* CLINT MSIP */
    READ_DEC('4', 0xF2004000);   /* CLINT mtimecmp lo */
    READ_DEC('8', 0xF200BFF8);   /* CLINT mtime lo */
    READ_DEC('C', 0xF200BFFC);   /* CLINT mtime hi */
    READ_DEC('P', 0xFC000000);   /* PLIC base */
    READ_DEC('Z', 0x00020000);   /* DTCM 0x20000 */

    /* ===== 主循环：不用 wfi，轮询等待中断触发 ===== */
    {
        uint32_t last_count = 0;
        uint32_t mtime_prev = 0;
        uint32_t stall_count = 0;

        while (1) {
            /* 主动开中断（解决 wfi/中断响应时序问题） */
            __asm__ volatile("csrsi mstatus, 8");

            if (timer_count != last_count) {
                last_count = timer_count;
                stall_count = 0;
            } else {
                stall_count++;
                /* 每大约 100 万轮打印一次 mtime */
                if (stall_count == 100000) {
                    uint32_t mt = (uint32_t)clint_get_mtime();
                    /* 检查 mtime 是否和上次不同（验证在递增） */
                    if (mt != mtime_prev) {
                        uart_putc('m');
                        uart_print_dec(mt);
                        uart_putc('\n');
                        mtime_prev = mt;
                    } else {
                        uart_putc('!');
                        uart_putc('\n');
                    }
                    stall_count = 0;
                }
            }
        }
    }

    // return 0;
}
