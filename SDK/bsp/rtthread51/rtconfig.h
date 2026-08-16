/*
 * BD32 RT-Thread v5.1.0 配置
 *
 * 面向 RV32IM 单核、标准 CLINT/PLIC 中断架构的裁剪配置。
 * 参考 RT-Thread 官方 RISC-V BSP（k210/gd32）与 yuheng 移植。
 */
#ifndef __RTTHREAD_CFG_H__
#define __RTTHREAD_CFG_H__

/* ============ 基础配置 ============ */
#define RT_NAME_MAX               8
#define RT_CPUS_NR                1
#define RT_ALIGN_SIZE             4
#define RT_THREAD_PRIORITY_MAX    8
#define RT_TICK_PER_SECOND        1000

#define RT_USING_OVERFLOW_CHECK
#define IDLE_THREAD_STACK_SIZE    4096

/* ============ IPC ============ */
#define RT_USING_SEMAPHORE
#define RT_USING_MUTEX
#define RT_USING_EVENT
#define RT_USING_MAILBOX

/* ============ 内存管理 ============ */
#define RT_USING_SMALL_MEM
#define RT_USING_SMALL_MEM_AS_HEAP
#define RT_USING_HEAP

/* ============ 控制台 ============ */
#define RT_USING_CONSOLE
#define RT_CONSOLEBUF_SIZE        128
#define RT_BACKTRACE_LEVEL_MAX_NR 32

/* 内核格式化：用 RT-Thread 自带标准 vsnprintf（自包含，不依赖 newlib 行为） */
#define RT_KLIBC_USING_VSNPRINTF_STANDARD

/* ============ 用户 main 线程 ============ */
#define RT_USING_USER_MAIN
#define RT_MAIN_THREAD_STACK_SIZE 4096
#define RT_MAIN_THREAD_PRIORITY   5

/* 内核版本号（RT-Thread v5.1.0） */
#define RT_VER_NUM                0x50100

#endif /* __RTTHREAD_CFG_H__ */
