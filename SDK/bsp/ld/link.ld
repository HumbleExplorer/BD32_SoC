/* BD32 RISC-V SoC 链接脚本
 *
 * 内存布局：
 *   ITCM: 0x0001_0000 ~ 0x0001_FFFF (64KB，代码段)
 *   DTCM: 0x0002_0000 ~ 0x0002_FFFF (64KB，数据段)
 *   启动地址：0x0001_0000 (ITCM 首地址)
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    itcm (rwx) : ORIGIN = 0x00010000, LENGTH = 64K
    dtcm (rwx) : ORIGIN = 0x00020000, LENGTH = 64K
}

/* 栈/堆大小，可被链接命令行覆盖 */
PROVIDE(__STACK_SIZE = 4K);
PROVIDE(__HEAP_SIZE = 8K);

SECTIONS
{
    .text : {
        . = ALIGN(4);
        _stext = .;
        /* 硬件复位向量固定为 0x00010000 */
        KEEP(*(.reset))
        /* 中断向量表 — vectored 模式要求 128B 对齐 */
        . = ALIGN(128);
        __vector_table_org = .;
        KEEP(*(.trap.vector))
        . = ALIGN(4);
        KEEP (*(SORT_NONE(.init)))
        /* ITCM 仅存代码 */
        *(.text)
        *(.text.*)
        _etext = .;
    } >itcm

    .data : ALIGN(4) {
        _sdata = .;
        *(.data)
        *(.data.*)
        . = ALIGN(8);
        __global_pointer$ = . + 0x800;
        *(.sdata)
        *(.sdata.*)
        *(.gnu.linkonce.s.*)
        /* 只读数据在 DTCM 中 */
        *(.rodata)
        *(.rodata.*)
        *(.srodata.*)
        . = ALIGN(4);
        _edata = .;
    } >dtcm

    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start = .;
        _sbss = .;
        *(.sbss)
        *(.sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
        __bss_end = .;
    } >dtcm

    .heap (NOLOAD) : {
        . = ALIGN(4);
        __heap_start = .;
        . = . + __HEAP_SIZE;
        . = ALIGN(4);
        __heap_end = .;
    } >dtcm

    /* RT-Thread 独立中断栈（SW_handler 用 mscratch 切换） */
    .rt_irq_stack (NOLOAD) : {
        . = ALIGN(16);
        __rt_irq_stack_start = .;
        . = . + 1K;
        __rt_irq_stack_end = .;
        PROVIDE(__rt_rvstack = .);
    } >dtcm

    .stack ORIGIN(dtcm) + LENGTH(dtcm) - __STACK_SIZE (NOLOAD) : {
        . = ALIGN(16);
        _sstack = .;
        __stack_start__ = .;
        . = . + __STACK_SIZE;
        . = ALIGN(16);
        __stack_top__ = .;
        _estack = .;
    } >dtcm

    /DISCARD/ : {
        *(.debug*)
        *(.comment)
        *(.note*)
    }
}
