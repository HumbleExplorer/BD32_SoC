/* RISC-V Linker Script for BD32_SoC
 * 硬件布局：
 *   BootROM: 0x0000_0000 ~ 0x0000_0FFF（CPU上电入口，由mrom.s管理）
 *   ITCM:    0x0001_0000 ~ 0x0001_FFFF（用户程序代码+只读数据）
 *   DTCM:    0x0002_0000 ~ 0x0002_FFFF（用户数据段+堆栈）
 * 用户程序由BootROM跳转到ITCM首地址(0x00010000)执行
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    itcm (rwx) : ORIGIN = 0x00010000, LENGTH = 60K
    dtcm (rwx) : ORIGIN = 0x00020000, LENGTH = 64K
}

__stack_size = DEFINED(__stack_size) ? __stack_size : 4K;

SECTIONS
{
    .text : {
        . = ALIGN(4);
        _stext = .;
        *(.init)
        *(.text)
        *(.text.*)
        _etext = .;
    } >itcm

    .rodata : {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata.*)
    } >itcm

    .data : {
        . = ALIGN(4);
        _sdata = .;
        *(.data)
        *(.data.*)
        _edata = .;
    } >dtcm

    .sdata : {
        __global_pointer$ = . + 0x800;
        *(.sdata)
        *(.sdata.*)
        *(.gnu.linkonce.s.*)
    } >dtcm

    .bss : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } >dtcm

    .stack : {
        . = ALIGN(16);
        _sstack = .;
        . = . + __stack_size;
        . = ALIGN(16);
        _estack = .;
    } >dtcm

    /DISCARD/ : {
        *(.debug*)
        *(.comment)
        *(.note*)
    }
}
