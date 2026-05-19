/*
 * BD32 BSP — 统一头文件
 * 所有外设寄存器定义 + 驱动 API 集中在此。
 *
 * 参考 Panda RISC-V / tinyriscv / nuclei-sdk / XT_RISC-V
 *
 * 外设基址摘要：
 *   GPIO:  0xE000_0000    APB Timer:  0xE002_0000
 *   UART:  0xE001_0000    CLINT:      0xF200_0000
 *   PLIC:  0xFC00_0000
 *
 * CPU 时钟: 100MHz
 */

#ifndef BD32_H
#define BD32_H

#include <stdint.h>

/* ===================================================================
 * 1. CSR 操作宏（参考 Panda/tinyriscv/nuclei-sdk）
 *    write/set/clear 对编译时常量 < 32 使用立即数约束，省一条 li
 * =================================================================== */
#define read_csr(reg)  ({ unsigned long __tmp; \
    __asm__ volatile("csrr %0, " #reg : "=r"(__tmp)); __tmp; })

#define write_csr(reg, val) ({ \
    if (__builtin_constant_p(val) && (unsigned long)(val) < 32) \
        __asm__ volatile("csrw " #reg ", %0" : : "i"(val)); \
    else { \
        unsigned long __v = (unsigned long)(val); \
        __asm__ volatile("csrw " #reg ", %0" : : "r"(__v)); \
    } })

#define set_csr(reg, mask) ({ \
    if (__builtin_constant_p(mask) && (unsigned long)(mask) < 32) \
        __asm__ volatile("csrrs x0, " #reg ", %0" : : "i"(mask)); \
    else { \
        unsigned long __v = (unsigned long)(mask); \
        __asm__ volatile("csrrs x0, " #reg ", %0" : : "r"(__v)); \
    } })

#define clear_csr(reg, mask) ({ \
    if (__builtin_constant_p(mask) && (unsigned long)(mask) < 32) \
        __asm__ volatile("csrrc x0, " #reg ", %0" : : "i"(mask)); \
    else { \
        unsigned long __v = (unsigned long)(mask); \
        __asm__ volatile("csrrc x0, " #reg ", %0" : : "r"(__v)); \
    } })

/* ── CSR 位掩码（参考 nuclei-sdk riscv_encoding.h） ── */
/* mstatus */
#define MSTATUS_MIE      (1 << 3)   /* Machine Interrupt Enable */
#define MSTATUS_MPIE     (1 << 7)   /* Machine Previous IE */
#define MSTATUS_MPP      0x1800     /* Machine Previous Privilege [12:11] */
#define MSTATUS_MPP_M    (3 << 11)  /* M-mode */

/* mie / mip */
#define MIE_MSIE         (1 << 3)   /* Machine Software Interrupt */
#define MIE_MTIE         (1 << 7)   /* Machine Timer Interrupt */
#define MIE_MEIE         (1 << 11)  /* Machine External Interrupt */

/* mcause */
#define MCAUSE_INTR      (1u << 31) /* Interrupt flag (bit 31) */

/* mtvec */
#define MTVEC_MODE_VECT  1          /* Vectored mode */

/* ===================================================================
 * 2. 系统时钟
 * =================================================================== */
#define CPU_FREQ_HZ      100000000UL
#define CPU_FREQ_KHZ     (CPU_FREQ_HZ / 1000UL)

/* ===================================================================
 * 3. GPIO (0xE000_0000)
 *    BOP_SET (0x24): bit[i]=1 → GPIO[i] 置高（一条 sw，原子）
 *    BOP_CLR (0x28): bit[i]=1 → GPIO[i] 清零（一条 sw，原子）
 * =================================================================== */
#define GPIO_BASE        0xE0000000UL
#define GPIO_DATA        (*(volatile uint32_t*)(GPIO_BASE + 0x00))
#define GPIO_DIR         (*(volatile uint32_t*)(GPIO_BASE + 0x04))
#define GPIO_OUT         (*(volatile uint32_t*)(GPIO_BASE + 0x08))
#define GPIO_IN          (*(volatile uint32_t*)(GPIO_BASE + 0x0C))
#define GPIO_BOP_SET     (*(volatile uint32_t*)(GPIO_BASE + 0x24))
#define GPIO_BOP_CLR     (*(volatile uint32_t*)(GPIO_BASE + 0x28))

/* GPIO 中断寄存器 */
#define GPIO_TR_TYPE     (*(volatile uint32_t*)(GPIO_BASE + 0x10))
#define GPIO_TR_LVL0     (*(volatile uint32_t*)(GPIO_BASE + 0x14))
#define GPIO_TR_LVL1     (*(volatile uint32_t*)(GPIO_BASE + 0x18))
#define GPIO_TR_STAT     (*(volatile uint32_t*)(GPIO_BASE + 0x1C))
#define GPIO_IRQ_ENA     (*(volatile uint32_t*)(GPIO_BASE + 0x20))

/* 原子 GPIO 操作（ISR 安全，无 RMW 竞争） */
#define GPIO_SET(bits)   (GPIO_BOP_SET = (uint32_t)(bits))
#define GPIO_CLR(bits)   (GPIO_BOP_CLR = (uint32_t)(bits))

/* 板载 LED */
#define PIN_LED0         (1 << 3)
#define PIN_LED1         (1 << 4)
#define LED_MASK         (PIN_LED0 | PIN_LED1)

/* ===================================================================
 * 4. UART 16550 (0xE001_0000, 115200bps @ 100MHz)
 * =================================================================== */
#define UART_BASE        0xE0010000UL
#define UART_RBR_THR     (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_DLL         (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_DLM         (*(volatile uint32_t*)(UART_BASE + 0x04))
#define UART_IER         (*(volatile uint32_t*)(UART_BASE + 0x04))
#define UART_IIR         (*(volatile uint32_t*)(UART_BASE + 0x08))
#define UART_FCR         (*(volatile uint32_t*)(UART_BASE + 0x08))
#define UART_LCR         (*(volatile uint32_t*)(UART_BASE + 0x0C))
#define UART_MCR         (*(volatile uint32_t*)(UART_BASE + 0x10))
#define UART_LSR         (*(volatile uint32_t*)(UART_BASE + 0x14))
#define UART_MSR         (*(volatile uint32_t*)(UART_BASE + 0x18))

#define LSR_DR           (1 << 0)
#define LSR_THRE         (1 << 5)

/* UART 驱动函数（实现在 bd32_uart.c） */
void uart_init(void);
void uart_putc(char c);
void uart_puts(const char *s);
void uart_puthex(uint32_t val);
void uart_putdec(uint32_t val);

/* ===================================================================
 * 5. APB Timer (0xE002_0000)
 *    时钟 = PCLK / (PSC+1), 周期 = (ARR+1) / 时钟
 *    CR[0]=EN, CR[1]=CLR, CR[2]=DIR(0=up)
 *    SR[0]=溢出标志（写1清除）
 * =================================================================== */
#define TIMER_BASE       0xE0020000UL
#define TIM_PSC          (*(volatile uint32_t*)(TIMER_BASE + 0x00))
#define TIM_CNT          (*(volatile uint32_t*)(TIMER_BASE + 0x04))
#define TIM_ARR          (*(volatile uint32_t*)(TIMER_BASE + 0x08))
#define TIM_CR           (*(volatile uint32_t*)(TIMER_BASE + 0x0C))
#define TIM_IER          (*(volatile uint32_t*)(TIMER_BASE + 0x10))
#define TIM_SR           (*(volatile uint32_t*)(TIMER_BASE + 0x14))

#define TIM_EN           (1 << 0)
#define TIM_CLR          (1 << 1)
#define TIM_DIR          (1 << 2)
#define TIM_OF_EN        (1 << 1)   /* IER 溢出中断使能 */
#define TIM_OF_FLAG      (1 << 0)   /* SR 溢出标志 */

/* 通道寄存器 */
#define TIM_CCMR         (*(volatile uint32_t*)(TIMER_BASE + 0x18))
#define TIM_CCER         (*(volatile uint32_t*)(TIMER_BASE + 0x1C))
#define TIM_CCR1         (*(volatile uint32_t*)(TIMER_BASE + 0x20))
#define TIM_CCR2         (*(volatile uint32_t*)(TIMER_BASE + 0x24))
#define TIM_CCR3         (*(volatile uint32_t*)(TIMER_BASE + 0x28))
#define TIM_CCR4         (*(volatile uint32_t*)(TIMER_BASE + 0x2C))

/* ===================================================================
 * 6. CLINT (0xF200_0000) — 系统时基 + 精确延时
 *    BD32 CLINT 寄存器偏移非 RISC-V 标准：
 *      MSIP:      0x0000
 *      MTIMECMP:  0x4000 (64bit, lo+0x4000, hi+0x4004)
 *      MTIME:     0xBFF8 (64bit, lo+0xBFF8, hi+0xBFFC, 只读)
 * =================================================================== */
#define CLINT_BASE       0xF2000000UL
#define CLINT_MSIP       (*(volatile uint32_t*)(CLINT_BASE + 0x0000))
#define CLINT_MTIME_LO   (*(volatile uint32_t*)(CLINT_BASE + 0xBFF8))
#define CLINT_MTIME_HI   (*(volatile uint32_t*)(CLINT_BASE + 0xBFFC))
#define CLINT_MTIMECMP_LO (*(volatile uint32_t*)(CLINT_BASE + 0x4000))
#define CLINT_MTIMECMP_HI (*(volatile uint32_t*)(CLINT_BASE + 0x4004))

/* 低层汇编接口（bd32_clint_asm.S） */
uint32_t clint_asm_get_mtime_lo(void);
uint64_t clint_asm_get_mtime(void);
void     clint_asm_set_mtimecmp(uint64_t val);
void     clint_asm_set_timeout_ticks(uint32_t ticks);

/* CLINT 驱动 API（内联） */
static inline uint32_t clint_mtime(void) {
    return clint_asm_get_mtime_lo();
}
static inline void clint_set_timer(uint32_t ticks) {
    clint_asm_set_timeout_ticks(ticks);
}
static inline void clint_enable_timer_int(void)  { set_csr(mie, MIE_MTIE); }
static inline void clint_disable_timer_int(void) { clear_csr(mie, MIE_MTIE); }

/* 精确延时（基于 mtime APB 读，ISR 不走 CLINT，无冲突） */
static inline void clint_delay_us(uint32_t us) {
    uint32_t start = clint_mtime();
    uint32_t ticks = us * (CPU_FREQ_KHZ / 1000UL);
    while ((uint32_t)(clint_mtime() - start) < ticks);
}
static inline void clint_delay_ms(uint32_t ms) {
    uint32_t start = clint_mtime();
    uint32_t ticks = ms * CPU_FREQ_KHZ;
    while ((uint32_t)(clint_mtime() - start) < ticks);
}

/* ===================================================================
 * 7. PLIC (0xFC00_0000) — 平台级中断控制器
 *    NUM_SOURCES=16, 中断源: 1=UART, 2=GPIO, 3=Timer
 *
 *    BD32 PLIC 使用 PADDR[15:12] 做区域译码（直接字节地址）：
 *      PADDR[15:12]=0 → Priority (0x0000~0x0FFF), [11:2]=src_id
 *      PADDR[15:12]=1 → Pending  (0x1000~0x1FFF), [6:2]=word
 *      PADDR[15:12]≥2 → Target  (0x2000~0x2FFF)
 *        [11:8]=tgt_id, [7:2]=offset
 *
 *      Enable:     0x2000   (直接字节地址)
 *      Threshold:  0x2080
 *      Claim:      0x2084
 * =================================================================== */
#define PLIC_BASE        0xFC000000UL
#define PLIC_PRIORITY(id) (*(volatile uint32_t*)(PLIC_BASE + 4*(id)))
#define PLIC_PENDING      (*(volatile uint32_t*)(PLIC_BASE + 0x1000))
#define PLIC_ENABLE       (*(volatile uint32_t*)(PLIC_BASE + 0x2000))
#define PLIC_THRESHOLD    (*(volatile uint32_t*)(PLIC_BASE + 0x2080))
#define PLIC_CLAIM        (*(volatile uint32_t*)(PLIC_BASE + 0x2084))
#define PLIC_COMPLETE     PLIC_CLAIM

/* ===================================================================
 * 8. 中断原因码
 * =================================================================== */
#define INTR_CAUSE_M_SW  0x80000003UL
#define INTR_CAUSE_M_TMR 0x80000007UL
#define INTR_CAUSE_M_EXT 0x8000000BUL

/* ===================================================================
 * 9. 工具函数
 * =================================================================== */
static inline void delay_loop(volatile uint32_t n) {
    while (n--) __asm__ volatile("");
}

#endif /* BD32_H */
