// BD32 SoC CoreMark port layer
#include <stdio.h>
#include <stdarg.h>
#include "coremark.h"
#include "bsp.h"
#include "soc/soc.h"

#if VALIDATION_RUN
	volatile ee_s32 seed1_volatile=0x3415;
	volatile ee_s32 seed2_volatile=0x3415;
	volatile ee_s32 seed3_volatile=0x66;
#endif
#if PERFORMANCE_RUN
	volatile ee_s32 seed1_volatile=0x0;
	volatile ee_s32 seed2_volatile=0x0;
	volatile ee_s32 seed3_volatile=0x66;
#endif
#if PROFILE_RUN
	volatile ee_s32 seed1_volatile=0x8;
	volatile ee_s32 seed2_volatile=0x8;
	volatile ee_s32 seed3_volatile=0x8;
#endif

volatile ee_s32 seed4_volatile=ITERATIONS;
volatile ee_s32 seed5_volatile=0;

static CORE_TICKS t0, t1;

/* mcycle / mcycleh (CSR 0xB00 / 0xB80)，你的 CPU 只实现了这两个 */
static inline uint64_t read_cycles(void) {
    uint32_t lo, hi;
    do {
        asm volatile("csrr %0, mcycleh" : "=r"(hi));
        asm volatile("csrr %0, mcycle"  : "=r"(lo));
    } while (hi != ({
        uint32_t h2;
        asm volatile("csrr %0, mcycleh" : "=r"(h2));
        h2;
    }));
    return ((uint64_t)hi << 32) | lo;
}

void start_time(void) { t0 = read_cycles(); }
void stop_time(void)  { t1 = read_cycles(); }
CORE_TICKS get_time(void) { return t1 - t0; }

/* CPU_FREQ_HZ 为编译期常量，不依赖全局变量 */
secs_ret time_in_secs(CORE_TICKS ticks) {
    return (secs_ret)(ticks / CPU_FREQ_HZ);
}

void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)p; (void)argc; (void)argv;
    uart_puts("CoreMark running...\r\n");
}
