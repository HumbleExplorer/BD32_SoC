/*
 * picolibc_syscalls.c — picolibc 系统调用桩（无 OS 环境）
 *
 * 与 newlib 的区别：picolibc 的 malloc 使用 POSIX 名 sbrk()
 * （newlib 是 _sbrk），因此这里提供 sbrk 而不是 _sbrk。
 * 栈/堆边界由 link.ld 的 __heap_start / __heap_end 符号提供。
 */
#include <errno.h>
#include <stdint.h>
#include <unistd.h>

extern char __heap_start[];
extern char __heap_end[];

static char *heap_ptr = __heap_start;

void *sbrk(intptr_t incr)
{
    char *prev = heap_ptr;
    if (heap_ptr + incr > __heap_end || heap_ptr + incr < __heap_start) {
        errno = ENOMEM;
        return (void *)-1;
    }
    heap_ptr += incr;
    return prev;
}

void _exit(int status)
{
    (void)status;
    while (1)
        ;
}
