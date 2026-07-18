/*
 * BD32 SOC — BD32 SoC 统一头文件
 * 包含所有外设定义和系统参数
 *
 * CPU 主频机制：
 *   MROM 上电后通过 CLINT mtime (1MHz 基准) + mcycle 自动测量，
 *   直接用实测值计算 UART NCO FCW。
 *   C 代码侧调用 soc_init() 独立测量并更新 g_cpu_freq_hz，
 *   与 MROM 解耦，正常/下载模式均适用。
 */
#ifndef SOC_H
#define SOC_H

#include "core.h"
#include "gpio.h"
#include "uart.h"
#include "timer.h"
#include "clint.h"
#include "plic.h"

#define CPU_FREQ_DEFINED
/* ===================================================================
 * CSR 读写宏（机器模式）
 * 两级宏：外层展开符号 → 内层字符串化
 * =================================================================== */
#define CSR_MCYCLE        0xB00     /* mcycle    低 32 位 */
#define CSR_MCYCLEH       0xB80     /* mcycle    高 32 位 */
#define CSR_MCOUNTEREN    0x306     /* mcounteren       */
#define CSR_TIME          0xC01     /* time (mtime 低32位，只读影子) */
#define CSR_TIMEH         0xC81     /* timeh (mtime 高32位，只读影子) */

#define _csr_read(csr) ({                        \
    uint32_t __tmp;                             \
    __asm__ volatile ("csrr %0, " #csr : "=r"(__tmp)); \
    __tmp;                                      \
})
#define csr_read(csr)  _csr_read(csr)

#define _csr_write(csr, val)                    \
    __asm__ volatile ("csrw " #csr ", %0" :: "rK"(val))
#define csr_write(csr, val)  _csr_write(csr, val)

/* ===================================================================
 * 运行时 CPU 频率（Hz）
 * 启动后由 MROM 或 BSP 测量填充，默认为保守值
 * =================================================================== */
extern uint32_t g_cpu_freq_hz;

/* 编译期默认值（用于 fallback / 旧代码兼容） */
#define CPU_FREQ_HZ_DEFAULT  80000000UL

/* 兼容宏：指向运行时变量，确保延迟/波特率始终用最新值 */
#define CPU_FREQ_HZ          g_cpu_freq_hz
#define CPU_FREQ_KHZ         (CPU_FREQ_HZ / 1000UL)

/* ===================================================================
 * 频率测量常数
 * =================================================================== */
#define SOC_TIMER_FREQ          1000000UL   /* mtime 频率：1MHz（1 tick = 1µs）*/
#define MEASURE_MTIME_TICKS     10000       /* 测量窗口：10000 ticks = 10ms */

/* ===================================================================
 * measure_cpu_freq — 通过 mcycle vs mtime 测量 CPU 主频
 *
 * 原理（参考 Nuclei E203 SDK）：
 *   同步读取 mtime 和 mcycle，等待 n 个 mtime tick 后重读，
 *   通过 delta_mcycle / delta_mtime 的比例推导主频。
 *
 *   freq = (delta_mcycle × SOC_TIMER_FREQ) / delta_mtime
 *         = delta_mcycle × 1M / delta_mtime
 *
 *   当 delta_mtime = 10000 (10ms) 时可简化为 freq = delta_mcycle × 100
 *   此处使用通用公式，不限测量窗口。
 *
 * 参数 n：测量窗口（mtime ticks 数）
 *   - n=1：预热（约 1µs）
 *   - n=10000：标准测量（10ms，误差 < 0.01%）
 *
 * 返回：CPU 主频（Hz），0 表示失败
 * =================================================================== */
static inline uint32_t measure_cpu_freq(uint32_t n)
{
    uint32_t start_mtime, delta_mtime;
    uint32_t start_mcycle, delta_mcycle;

    if (n == 0) return 0;

    /* Step 1：同步到 mtime tick 边界
     * 等 mtime 跳变一次后记录起点，避免测量跨过 tick 边界的部分周期 */
    uint32_t tmp = csr_read(CSR_TIME);
    do {
        start_mcycle = csr_read(CSR_MCYCLE);
        start_mtime  = csr_read(CSR_TIME);
    } while (start_mtime == tmp);

    /* Step 2：测量 n 个 mtime tick */
    do {
        delta_mtime  = csr_read(CSR_TIME) - start_mtime;
        delta_mcycle = csr_read(CSR_MCYCLE) - start_mcycle;
    } while (delta_mtime < n);

    /* Step 3：计算频率
     *   公式：freq = (delta_mcycle / delta_mtime) × SOC_TIMER_FREQ
     *   等效：freq = delta_mcycle × SOC_TIMER_FREQ / delta_mtime
     *   用 64-bit 保精度，+ delta_mtime/2 做四舍五入 */
    if (delta_mtime == 0) return 0;
    return (uint32_t)(((uint64_t)delta_mcycle * SOC_TIMER_FREQ + (delta_mtime >> 1)) / delta_mtime);
}

/* ===================================================================
 * soc_init — 系统初始化（测主频）
 *
 * 调用时机：_init() 最开头，早于任何 UART/定时器使用
 *
 * 流程：
 *   1. 使能 mcycle CSR 读取
 *   2. 预热一次（去掉第一次 tick 的不稳定边界）
 *   3. 标准测量 10000 ticks (10ms)
 *   4. 合理性检查后写入 g_cpu_freq_hz
 * =================================================================== */
static inline void soc_init(void)
{
    /* 使能 mcycle 计数器 */
    csr_write(CSR_MCOUNTEREN, 1);
#ifdef CPU_FREQ_DEFINED
    /* 读取已定义的 CPU 频率 */
    g_cpu_freq_hz = CPU_FREQ_HZ_DEFAULT;
#else
    /* 预热：丢弃第一次测量（CSR 管线尚未稳定）*/
    measure_cpu_freq(1);

    /* 正式测量：10ms 窗口 */
    uint32_t freq = measure_cpu_freq(MEASURE_MTIME_TICKS);

    /* 合理性检查：<1MHz 或 >1GHz 视为无效，回退默认值 */
    if (freq > 1000000UL && freq < 1000000000UL)
        g_cpu_freq_hz = freq;
    else
        g_cpu_freq_hz = CPU_FREQ_HZ_DEFAULT;
#endif
}
#endif
