/*
 * syscalls.c — Newlib-nano 系统调用桩（无 OS 环境）
 * 为 printf/scanf/malloc 等标准库函数提供底层支持
 */
#include <sys/stat.h>
#include <sys/times.h>
#include <sys/unistd.h>
#include <errno.h>
#include "bsp.h"

#undef errno
extern int errno;

/* 链接脚本提供的堆边界 */
extern char __heap_start[];
extern char __heap_end[];

static char *heap_ptr = __heap_start;

void _exit(int status)
{
    while (1);
}

int _close(int fd)
{
    return -1;
}

int _fstat(int fd, struct stat *st)
{
    st->st_mode = S_IFCHR;
    return 0;
}

int _isatty(int fd)
{
    return 1;
}

int _lseek(int fd, off_t offset, int whence)
{
    return 0;
}

int _open(const char *path, int flags, int mode)
{
    return -1;
}

ssize_t _read(int fd, void *buf, size_t count)
{
    return 0;  /* 暂不支持 UART 输入 */
}

void *_sbrk(ptrdiff_t incr)
{
    char *prev = heap_ptr;
    if (heap_ptr + incr > __heap_end || heap_ptr + incr < __heap_start) {
        errno = ENOMEM;
        return (void *)-1;
    }
    heap_ptr += incr;
    return prev;
}

ssize_t _write(int fd, const void *buf, size_t count)
{
    if (fd != 1 && fd != 2) return -1;
    const char *p = (const char *)buf;
    for (size_t i = 0; i < count; i++)
        uart_putc(p[i]);
    return count;
}
