/*
 * picolibc_rtthread_exit.c — RT-Thread lts-v3.1.x + picolibc 退出适配
 *
 * v5.1.0 官方适配层的 exit.c 依赖 posix/stdlib.h 与 __rt_libc_exit
 * （均在 3.1.x 中不存在），这里给出等价实现：_exit 关闭当前线程。
 */
#include <rtthread.h>

void __rt_libc_exit(int status)
{
    rt_thread_t self = rt_thread_self();

    (void)status;
    if (self != RT_NULL)
    {
        rt_thread_control(self, RT_THREAD_CTRL_CLOSE, RT_NULL);
    }
}

void _exit(int status)
{
    __rt_libc_exit(status);
    while (1)
        ;
}
