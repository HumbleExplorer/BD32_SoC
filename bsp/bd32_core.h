/*
 * BD32 核心驱动 — 中断控制 + 辅助
 * 参考 Panda RISC-V / nuclei-sdk / SparrowRV
 */

#ifndef BD32_CORE_H
#define BD32_CORE_H

#include "bd32.h"

/* ── 全局中断 ── */
static inline void core_global_irq_enable(void)  { set_csr(mstatus, MSTATUS_MIE); }
static inline void core_global_irq_disable(void) { clear_csr(mstatus, MSTATUS_MIE); }

/* ── 分类中断使能 ── */
static inline void core_enable_irq(uint32_t mask)  { set_csr(mie, mask); }
static inline void core_disable_irq(uint32_t mask) { clear_csr(mie, mask); }

static inline void core_enable_timer_irq(void)     { set_csr(mie, MIE_MTIE); }
static inline void core_enable_soft_irq(void)      { set_csr(mie, MIE_MSIE); }
static inline void core_enable_extern_irq(void)    { set_csr(mie, MIE_MEIE); }

/* ── 诊断 ── */
static inline uint32_t core_get_mcause(void)  { return read_csr(mcause); }
static inline uint32_t core_get_mepc(void)    { return read_csr(mepc); }
static inline uint32_t core_get_mtval(void)   { return read_csr(mtval); }

/* ── 进入 M-mode 并开中断的标准序列 ── */
static inline void core_start_interrupts(void) {
    write_csr(mstatus, MSTATUS_MPP_M | MSTATUS_MPIE | MSTATUS_MIE);
}

#endif /* BD32_CORE_H */
