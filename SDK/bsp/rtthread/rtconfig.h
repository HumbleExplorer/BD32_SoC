/*
 * BD32 RT-Thread v3.1.5 (lts-v3.1.x) 配置
 *
 * 面向 RV32IM 单核、标准 CLINT/PLIC 中断架构的裁剪配置。
 * 与 bsp/rtthread51（v5.1.0）配置保持同一套裁剪思路，仅保留 3.1.5
 * 内核实际支持的宏。
 */
#ifndef __RTTHREAD_CFG_H__
#define __RTTHREAD_CFG_H__

/* ============ 基础配置 ============ */
#define RT_NAME_MAX               8
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
/* 3.1.5 无 RT_USING_SMALL_MEM_AS_HEAP：RT_USING_SMALL_MEM + RT_USING_HEAP
 * 即由 mem.c 提供 rt_system_heap_init 作为系统堆 */
#define RT_USING_SMALL_MEM
#define RT_USING_HEAP

/* ============ 控制台 ============ */
#define RT_USING_CONSOLE
#define RT_CONSOLEBUF_SIZE        128

/* ============ 用户 main 线程 ============ */
#define RT_USING_USER_MAIN
#define RT_MAIN_THREAD_STACK_SIZE 4096
#define RT_MAIN_THREAD_PRIORITY   5

/* 内核版本号（RT-Thread v3.1.5） */
#define RT_VER_NUM                0x30105

#endif /* __RTTHREAD_CFG_H__ */
