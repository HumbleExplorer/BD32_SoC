/*
 * BD32 Core — BD32 处理器核心抽象
 * CSR 操作宏 + 异常/中断定义，不依赖任何外设
 */
#ifndef CORE_H
#define CORE_H

#include <stdint.h>

/* ===================================================================
 * CSR 读写宏
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

/* ===================================================================
 * mstatus 位域
 * =================================================================== */
#define MSTATUS_MIE      (1 << 3)
#define MSTATUS_MPIE     (1 << 7)
#define MSTATUS_MPP      0x1800
#define MSTATUS_MPP_M    (3 << 11)

/* ===================================================================
 * mie / mip 位域
 * =================================================================== */
#define MIE_MSIE         (1 << 3)
#define MIE_MTIE         (1 << 7)
#define MIE_MEIE         (1 << 11)

/* ===================================================================
 * mcause 编码
 * =================================================================== */
#define MCAUSE_INTR      (1u << 31)

#define INTR_CAUSE_M_SW  0x80000003UL
#define INTR_CAUSE_M_TMR 0x80000007UL
#define INTR_CAUSE_M_EXT 0x8000000BUL

/* ===================================================================
 * mtvec 模式
 * =================================================================== */
#define MTVEC_MODE_VECT  1

/* ===================================================================
 * 全局中断控制
 * =================================================================== */
static inline void __enable_irq(void)        { set_csr(mstatus, MSTATUS_MIE); }
static inline void __disable_irq(void)       { clear_csr(mstatus, MSTATUS_MIE); }
static inline void core_enable_irq(uint32_t m)  { set_csr(mie, m); }
static inline void core_disable_irq(uint32_t m) { clear_csr(mie, m); }

static inline uint32_t core_get_mcause(void) { return read_csr(mcause); }
static inline uint32_t core_get_mepc(void)   { return read_csr(mepc); }
static inline uint32_t core_get_mtval(void)  { return read_csr(mtval); }
static inline uint32_t core_get_mcycle(void) { return read_csr(mcycle); }
/* 注：misa CSR (0x301) 当前 RTL 未实现，读返回 0，暂不暴露 */

static inline void core_start_interrupts(void) {
    write_csr(mstatus, MSTATUS_MPP_M | MSTATUS_MPIE | MSTATUS_MIE);
}

#endif /* CORE_H */
