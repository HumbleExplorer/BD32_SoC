/*
 * picolibc_rtthread_syscall.c — RT-Thread lts-v3.1.x + picolibc 系统调用适配
 *
 * 与 v5.1.0 官方适配层（components/libc/compilers/picolibc/syscall.c）等价：
 *   - errno 通过 __PICOLIBC_ERRNO_FUNCTION 钩子映射到当前线程的 error 字段
 *     （中断上下文退回全局），不依赖 TLS；
 *   - malloc 族重定向到 RT-Thread 堆（RT_USING_HEAP）。
 * 3.1.x 无 posix/sys 头文件，故只依赖 <rtthread.h> 与 <stddef.h>。
 */
#include <rtthread.h>
#include <stddef.h>

/* global errno */
static volatile int __pico_errno;

int *pico_get_errno(void)
{
    rt_thread_t tid = RT_NULL;

    if (rt_interrupt_get_nest() != 0)
    {
        /* it's in interrupt context */
        return (int *)&__pico_errno;
    }

    tid = rt_thread_self();
    if (tid == RT_NULL)
    {
        return (int *)&__pico_errno;
    }

    return (int *)&tid->error;
}

#ifdef RT_USING_HEAP
void *malloc(size_t n)
{
    return rt_malloc(n);
}

void *realloc(void *rmem, size_t newsize)
{
    return rt_realloc(rmem, newsize);
}

void *calloc(size_t nelem, size_t elsize)
{
    return rt_calloc(nelem, elsize);
}

void free(void *rmem)
{
    rt_free(rmem);
}
#endif /* RT_USING_HEAP */
