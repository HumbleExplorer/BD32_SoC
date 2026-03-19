/* RISC-V Linker Script for Embedded System */
/* 基于 SoC_Config.sv 的内存布局 */

OUTPUT_ARCH("riscv")
/*定义程序入口，_start来自启动文件*/
ENTRY(_start)

/* 内存区域定义 - 基于 SoC_Config.sv */
MEMORY
{
    /* ITCM: Instruction Tightly Coupled Memory - 64KB @ 0x00000000 */
    itcm (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
    
    /* DTCM: Data Tightly Coupled Memory - 64KB @ 0x00010000 (物理分离) */
    dtcm (rwx) : ORIGIN = 0x00010000, LENGTH = 64K
    
    /* FLASH: 外部Flash - 16MB @ 0x82000000 */
    flash (rx) : ORIGIN = 0x82000000, LENGTH = 16M
    
    /* DDR: 外部DDR内存 - 512MB @ 0x84000000 */
    ddr (rwx) : ORIGIN = 0x84000000, LENGTH = 512M
}

/* 堆栈大小定义 */
__stack_size = DEFINED(__stack_size) ? __stack_size : 4K;
__heap_size = DEFINED(__heap_size) ? __heap_size : 4K;

/* SECTIONS 定义 */
SECTIONS
{
    /* KEEP防止被编译器优化，SORT_NONE禁用段排序，防止编译器打乱符号顺序 */
    /* >itcm 即段的运行地址VMA在 ITCM，AT>flash即段的加载地址LMA在 Flash
    /* ===== 代码段 - 放在 ITCM ===== */
    .init 0x00000000 : {
        KEEP(*(.init))
    } >itcm AT>flash
    
    .text : {
        . = ALIGN(4);
        _stext = .;
        *(.text)
        *(.text.*)
        *(.gnu.linkonce.t.*)
        _etext = .;
    } >itcm AT>flash
    
    /* 只读数据段 */
    .rodata : {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata.*)
        *(.gnu.linkonce.r.*)
    } >itcm AT>flash
    
    /* ===== 数据段 - 放在 DTCM ===== */
    /* .data 的加载地址在 flash，运行地址在 dtcm */
    .data : {
        . = ALIGN(4);
        _sdata = .;
        *(.data)
        *(.data.*)
        *(.gnu.linkonce.d.*)
        _edata = .;
    } >dtcm AT>flash
    /* Flash中加载地址起始 */
    _sidata = LOADADDR(.data);
    
    /* .sdata - 小数据段（用于小变量快速访问） */
    .sdata : {
        __global_pointer$ = . + 0x800;
        *(.sdata)
        *(.sdata.*)
        *(.gnu.linkonce.s.*)
    } >dtcm AT>flash
    
    /* ===== BSS 段 - 放在 DTCM ===== */
    .bss : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss)
        *(.bss.*)
        *(.gnu.linkonce.b.*)
        *(.sbss)
        *(.sbss.*)
        *(.gnu.linkonce.sb.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } >dtcm
    
    /* ===== 堆和栈 - 放在 DTCM 末尾 ===== */
    .stack : {
        . = ALIGN(16);
        _sstack = .;
        . = . + __stack_size;
        . = ALIGN(16);
        _estack = .;
    } >dtcm
    
    /* ===== 堆 - 放在 DDR ===== */
    .heap : {
        . = ALIGN(8);
        _heap_start = .;
        . = . + __heap_size;
        _heap_end = .;
    } >ddr
    
    /* ===== 调试信息（如果需要） ===== */
    /DISCARD/ : {
        *(.debug*)
        *(.comment)
        *(.note*)
    }
}
