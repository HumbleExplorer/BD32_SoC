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

/* ---- tidle 栈健康探针 ----
 * 主线程每秒采样一次 tidle TCB：
 *   1) TCB 保存的 sp 相对栈底偏移——递减 = 中断帧泄漏（sp 本身被侵蚀）
 *   2) 栈底 +4/+8 的 '#' 水印字——被改写 = 杂散 store 越界（内存腐蚀）
 * 仅在数值变化时打印。 */
static struct rt_thread *tidle_cb;
static rt_uint32_t last_off;
static rt_uint32_t last_wm;

static void tidle_probe(void)
{
    rt_uint32_t base, off, wm4, wm8;
    if (tidle_cb == RT_NULL) return;
    base = (rt_uint32_t)tidle_cb->stack_addr;
    off = (rt_uint32_t)tidle_cb->sp - base;
    wm4 = *(volatile rt_uint32_t *)(base + 4);
    wm8 = *(volatile rt_uint32_t *)(base + 8);
    if (wm4 != 0x23232323 || wm8 != 0x23232323)
        rt_kprintf("[SPW] WATERMARK broken: base+4=%08x base+8=%08x\n", wm4, wm8);
    if (off != last_off || wm4 != last_wm)
    {
        rt_kprintf("[SPW] tcb_sp=%08x base=%08x off=%d wm4=%08x\n",
                   (rt_uint32_t)tidle_cb->sp, base, off, wm4);
        last_off = off;
        last_wm = wm4;
    }
}

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

    /* tidle 诊断：定位 TCB，主线程每秒采样（sp 爬移 + 水印探针） */
    tidle_cb = rt_thread_find("tidle");

    while (1) {
        rt_thread_mdelay(1000);
        tidle_probe();
    }
}
