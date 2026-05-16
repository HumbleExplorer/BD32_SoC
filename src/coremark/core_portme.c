/* BD32 SoC CoreMark port layer */
#include <stdlib.h>
#include "coremark.h"
#include "../../lib/periph.h"

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

/* tinyprintf needs _putchar */
void _putchar(char c) { uart_putc(c); }

/* rdcycle */
static inline uint64_t read_cycles(void) {
    uint32_t lo, hi;
    do {
        asm volatile("rdcycleh %0" : "=r"(hi));
        asm volatile("rdcycle %0"  : "=r"(lo));
    } while (hi != ({
        uint32_t h2;
        asm volatile("rdcycleh %0" : "=r"(h2));
        h2;
    }));
    return ((uint64_t)hi << 32) | lo;
}

void start_time(void) { t0 = read_cycles(); }
void stop_time(void)  { t1 = read_cycles(); }
CORE_TICKS get_time(void) { return t1 - t0; }

/* Return time in seconds as integer (floor). 100MHz = 100,000,000 ticks/s */
secs_ret time_in_secs(CORE_TICKS ticks) {
    return (secs_ret)((uint32_t)ticks / 100000000);
}

void portable_init(core_portable *p, int *argc, char *argv[]) {
    uart_init();
}
