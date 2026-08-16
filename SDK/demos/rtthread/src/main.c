/*
 * BD32 RT-Thread v3.1.5 (lts-v3.1.x) 双线程 demo
 *
 * 验证目标（与 demos/rtthread 的 v5.1.0 demo 保持一致）：
 *   1. rtthread_startup 启动序列（board init → 调度器启动）
 *   2. 轻量入口 + SW_handler（PendSV 模式）下的延迟调度
 *   3. 两个同优先级线程按时间片轮转（t1/t2 交替打印）
 *
 * 构建：python tools/build.py demos/rtthread --rtthread（默认 lts-v3.1.x）
 */
#include <rtthread.h>

/* 线程参数：每个线程独立配置（本 demo 两线程故意相同，以演示同优先级时间片轮转） */
#define T1_STACK_SIZE   4096
#define T1_PRIORITY     5
#define T1_TIMESLICE    20
#define T1_MDELAY_MS    10
#define T2_STACK_SIZE   4096
#define T2_PRIORITY     5
#define T2_TIMESLICE    20
#define T2_MDELAY_MS    10

static struct rt_thread t1;
static rt_uint8_t t1_stack[T1_STACK_SIZE];
static struct rt_thread t2;
static rt_uint8_t t2_stack[T2_STACK_SIZE];

static void t1_entry(void *parameter)
{
    (void)parameter;
    rt_kprintf("t1: start\n");
    while (1) {
        rt_kprintf("t1\n");
        rt_thread_mdelay(T1_MDELAY_MS);
    }
}

static void t2_entry(void *parameter)
{
    (void)parameter;
    rt_kprintf("t2: start\n");
    while (1) {
        rt_kprintf("t2\n");
        rt_thread_mdelay(T2_MDELAY_MS);
    }
}

int main(void)
{
    rt_thread_init(&t1, "t1", t1_entry, RT_NULL,
                   t1_stack, sizeof(t1_stack), T1_PRIORITY, T1_TIMESLICE);
    rt_thread_init(&t2, "t2", t2_entry, RT_NULL,
                   t2_stack, sizeof(t2_stack), T2_PRIORITY, T2_TIMESLICE);
    rt_thread_startup(&t1);
    rt_thread_startup(&t2);

    while (1) {
        rt_thread_mdelay(1000);
    }
}
