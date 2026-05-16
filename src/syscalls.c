/*
 * BD32 SoC newlib-nano syscall stubs
 *
 * 提供 newlib 需要的底层系统调用。
 * _write -> UART 输出（printf 可用）
 * _sbrk -> 堆管理（malloc 可用）
 * 其余 stubs 直接返回 -1 或 0。
 */

#include <sys/types.h>
#include <errno.h>

#undef errno
extern int errno;

/* ========== UART 寄存器（与 periph.h 一致） ========== */
#define UART_BASE       0xE0010000UL
#define UART_THR        (*(volatile unsigned int*)(UART_BASE + 0x00))
#define UART_LSR        (*(volatile unsigned int*)(UART_BASE + 0x14))
#define UART_LSR_THRE   (1 << 5)

static void uart_putc(char c) {
    while (!(UART_LSR & UART_LSR_THRE));
    UART_THR = (unsigned int)c;
}

/* ========== 堆管理 ========== */
extern char __heap_start;
extern char __heap_end;

static char *heap_ptr = &__heap_start;

void *_sbrk(int incr) {
    char *prev = heap_ptr;
    char *next = heap_ptr + incr;

    /* 检查是否超出堆边界 */
    if (next > &__heap_end && incr > 0) {
        errno = ENOMEM;
        return (void*)-1;
    }
    if (next < &__heap_start && incr < 0) {
        errno = ENOMEM;
        return (void*)-1;
    }

    heap_ptr = next;
    return prev;
}

/* ========== 标准输出 ========== */
int _write(int file, char *ptr, int len) {
    for (int i = 0; i < len; i++) {
        if (ptr[i] == '\n') uart_putc('\r');
        uart_putc(ptr[i]);
    }
    return len;
}

/* ========== 标准输入 ========== */
int _read(int file, char *ptr, int len) {
    /* 本 SoC 当前未实现 UART 接收中断轮询 */
    return 0;  /* 无数据可读 */
}

/* ========== 文件操作 stubs ========== */
int _close(int file) {
    return -1;
}

int _fstat(int file, void *st) {
    return 0;
}

int _isatty(int file) {
    return 1;
}

int _lseek(int file, int ptr, int dir) {
    return 0;
}

/* ========== 进程控制 ========== */
void _exit(int status) {
    while (1);
}

int _kill(int pid, int sig) {
    errno = EINVAL;
    return -1;
}

int _getpid(void) {
    return 1;
}
