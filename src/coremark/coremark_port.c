/* BD32 CoreMark — 多文件 CoreMark 合并为单翻译单元
 *
 * 策略：所有 .c 文件通过 #include 合并为一个编译单元，
 *       避免跨编译单元链接到 64 位 libc.a 的问题。
 *       -fno-lto 防止 GCC 把 printf 当成内置函数优化掉。
 *
 * 编译（从 Working 目录运行）：
 *   riscv64-unknown-elf-gcc -c -Os -march=rv32im -mabi=ilp32 \
 *     -fno-lto -fno-builtin -fno-function-sections \
 *     -I. -Isrc -Isrc/coremark \
 *     src/coremark/coremark_port.c -o coremark.o
 *
 * 链接：
 *   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
 *     -nostartfiles -T lib/link.ld \
 *     coremark.o lib/bd32_printf.o lib/syscalls.o lib/start.o \
 *     -o coremark.elf
 */

#ifndef COREMARK_PORT_C
#define COREMARK_PORT_C

#include <stdint.h>
#include <stdarg.h>
#include <stdlib.h>

/* ===== BD32 平台层 ===== */
void _putchar(char c);

/* rdcycle — BD32 支持 mcycle 读取 */
static inline uint64_t read_cycles(void) {
    uint32_t lo, hi;
    do {
        __asm__ volatile("csrr %0, mcycleh" : "=r"(hi));
        __asm__ volatile("csrr %0, mcycle"  : "=r"(lo));
    } while (hi != ({ uint32_t h2; __asm__ volatile("csrr %0, mcycleh" : "=r"(h2)); h2; }));
    return ((uint64_t)hi << 32) | lo;
}

static uint64_t t0, t1;
void start_time(void) { t0 = read_cycles(); }
void stop_time(void)  { t1 = read_cycles(); }
uint64_t get_time(void) { return t1 - t0; }
typedef uint64_t CORE_TICKS;
typedef uint64_t secs_ret;
secs_ret time_in_secs(CORE_TICKS ticks) {
    return (secs_ret)(ticks / 100000000);  /* 100MHz */
}

void portable_init(void *p, int *a, char **v) { (void)p; (void)a; (void)v; }

/* ===== CoreMark 多文件 include（按依赖顺序） ===== */
#include "core_list_join.c"
#include "core_matrix.c"
#include "core_state.c"
#include "core_util.c"
#include "core_main.c"
/* core_portme.c 仅保留种子变量和 portable_init（已在上方重写） */
#include "core_portme.c"

/* ===== printf 实现（内联，不引用外部） ===== */
/* 注意：bd32_printf.c 定义了 void printf(...) 会和下方冲突，
 *       链接时去掉 bd32_printf.o，改用此内联版 */

#define is_digit(c) ((c) >= '0' && (c) <= '9')
#define PAD_RIGHT 1
#define PAD_ZERO  2

static void prints(const char *s) { while (*s) _putchar(*s++); }

static int prints_width(const char *s, int width, int pad) {
    int len = 0; const char *p = s;
    while (*p++) len++;
    if (len >= width) { while (*s) _putchar(*s++); return len; }
    if (pad & PAD_ZERO) { while (width-- > len) _putchar('0'), len++; }
    else { while (width-- > len) _putchar(' '), len++; }
    while (*s) _putchar(*s++), len++;
    return len;
}

static int printi(unsigned val, int sign, int width, int pad, int base) {
    char buf[12], *p = buf + sizeof(buf);
    int len = 0;
    unsigned v = val;
    if (sign && (int)val < 0) { _putchar('-'); v = (unsigned)(-(int)val); len++; }
    do { *--p = (v % base < 10) ? (v % base) + '0' : (v % base) + 'A' - 10; v /= base; len++; } while (v);
    return len + prints_width(p, width - len, pad);
}

/* 必须避免重名：bd32_printf.c 已有 printf，改名 */
int bd32_printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int width, pad, printed = 0;
    char scr[2];
    scr[1] = '\0';
    for (; *fmt; fmt++) {
        if (*fmt != '%') { _putchar(*fmt); printed++; continue; }
        fmt++; width = pad = 0;
        if (*fmt == '-') { fmt++; pad |= PAD_RIGHT; }
        while (*fmt == '0') { fmt++; pad |= PAD_ZERO; }
        while (*fmt >= '0' && *fmt <= '9') { width = width * 10 + (*fmt - '0'); fmt++; }
        if (*fmt == 'l') fmt++;
        switch (*fmt) {
            case 's': { const char *s = va_arg(ap, const char*); printed += prints_width(s ? s : "(null)", width, pad); break; }
            case 'c': { scr[0] = (char)va_arg(ap, int); printed += prints_width(scr, width, pad); break; }
            case 'd': case 'i': printed += printi((unsigned)va_arg(ap, unsigned), 1, width, pad, 10); break;
            case 'u': printed += printi(va_arg(ap, unsigned), 0, width, pad, 10); break;
            case 'x': case 'X': printed += printi(va_arg(ap, unsigned), 0, width, pad, 16); break;
            case 'p': { unsigned v = (unsigned)(uintptr_t)va_arg(ap, void*); _putchar('0'); _putchar('x'); printed += 2 + printi(v, 0, 8, PAD_ZERO, 16); break; }
            case '%': _putchar('%'); printed++; break;
            default: break;
        }
    }
    va_end(ap);
    return printed;
}

/* CoreMark 用 ee_printf，需要映射 */
#define printf bd32_printf

#endif /* COREMARK_PORT_C */
