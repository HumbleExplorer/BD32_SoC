/* 
 * RISC-V 启动汇编代码
 * 完成功能：
 * 1. 设置栈指针
 * 2. 清零 .bss 段
 * 3. 跳转到 main 函数
 *
 * 注意：本SoC无外部Flash，用户程序应避免使用带初始值的全局变量
 *     （.data段直接运行于DTCM，LMA=VMA，无需复制）
 */

.section .init /* 声明此处段名为.init */
.global _start /* 全局声明_start */
.type _start, @function /* 声明_start为函数 */

_start:
    .option push /* 保存编译设置 */
    .option norelax /* 禁用相对寻址，禁用链接器的 gp 优化，确保 gp 正确设置 */
    
    /* ===== 设置 Global Pointer (gp) ===== */
    /* 设置gp为全局指针，__global_pointer$来源于链接脚本，与data段关联，指向全局变量 */
1:  auipc gp, %pcrel_hi(__global_pointer$) 
    addi  gp, gp, %pcrel_lo(1b)
    .option pop
    
    /* ===== 设置栈指针 ===== */
    /* 栈向下增长，所以设置为栈区域末尾 */
    la   sp, _estack

    /* ===== 初始化中断向量表 mtvec ===== */
    /* mtvec格式：[31:2] = 向量表基地址, [1:0] = 模式（1=Vectored） */
    la   a0, __vector_base       # 向量表基地址
    ori  a0, a0, 1               # 设置为向量模式（Vectored）
    csrw mtvec, a0               # 写入mtvec寄存器
    
    /* ===== 使能机器模式全局中断 ===== */
    /* mstatus.MIE (bit 3) = 1: 使能机器模式中断 */
    csrr t0, mstatus
    ori  t0, t0, 0x8             # 置位MIE位
    csrw mstatus, t0

    /* ===== 清零 .bss 段 ===== */
    /* .bss 段存放未初始化的全局/静态变量，需要清零 */
    
    la   a0, _sbss        /* .bss 起始地址 */
    la   a1, _ebss         /* .bss 结束地址 */
    
    /* 如果 _sbss == _ebss，说明没有 .bss 段，跳过清零 */
    beq  a0, a1, 2f
    
    /* 清零循环 */
1:  sw   zero, 0(a0)     /* 写入 0 */
    addi a0, a0, 4         /* 地址 +4 */
    bltu a0, a1, 1b        /* 未清零完，继续 */
    
2:
    /* ===== 调用C初始化函数（可选，自由发挥） ===== */
    call _init

    /* ===== 跳转到 main 函数 ===== */
    /* 初始化完成，跳转到 C 代码入口 */
    call main
    
    /* ===== main 返回后的处理 ===== */
    /* 如果 main 返回，通常进入无限循环或关机 */
1:  j 1b                  /* 无限循环 */

.size _start, .-_start


/*
 * 以下是一些可选的辅助代码
 */

/* ========== 2. 中断向量表 ========== */
.section .vector_table, "a" // 可分配
.align 4  /* RISC-V要求向量表按4字节对齐 */
/*入口基地址(__vector_base)可以放在程序存储器的任何地方，但必须32bit对齐，初始化阶段需要写入CSR_mtvec。
每个异常和中断都有独立的trap编码，每个trap编码对应中断向量表的一个32bit表项，每个表项必须按照trap编码在内存上连续分布
发生中断后，跳转至中断向量表的对应表项，即PC = 入口基地址 + trap编码*4
每个表项存放了一条跳转指令，可以跳转至相应的中断服务程序。也可以放一条其他指令，但必须是RV32I指令。 */
.global __vector_base
__vector_base:
    /* 向量表格式（Vectored模式）：
     * - 0x000: 机器模式异常入口（所有同步异常）
     * - 0x004: 硬件错误异常
     * - 0x008: 机器模式软件中断 (MSIP)
     * - 0x00C: 机器模式定时器中断 (MTIP)
     * - 0x010: 机器模式外部中断 (MEIP)
     * - 其余：保留/自定义中断(GPIO,UART,IIC,SPI,TIMER)
     */
    j _start                 /* 0x000: 0  软件复位 */
    j Exception_Handler      /* 0x004: 1  机器模式异常 */
    j HardFault_Handler      /* 0x008: 2  硬件错误异常 */
    j MSoft_IRQ_Handler      /* 0x00C: 3  机器软件中断 */
    j MTimer_IRQ_Handler     /* 0x010: 4  机器定时器中断 */
    j MExtern_IRQ_Handler    /* 0x014: 5  机器外部中断 */
    j UART0_TX_IRQ_Handler   /* 0x018: 6  UART0发送中断 */
    j UART0_RX_IRQ_Handler   /* 0x01C: 7  UART0接收中断 */
    j UART1_TX_IRQ_Handler   /* 0x020: 8  UART1发送中断 */
    j UART1_RX_IRQ_Handler   /* 0x024: 9  UART1接收中断 */

    j IIC_IRQ_Handler        /* 0x028: 10 IIC1中断 */
    j SPI_IRQ_Handler        /* 0x02C: 11 SPI中断 */

/* ========== 3. 异常/中断处理核心逻辑 ========== */
.section .trap.handler, "ax" // 可分配可执行
.align 4

/* 全局异常处理入口：保存寄存器 + 分发异常 */
.global Exception_Handler
Exception_Handler:
    /* 保存调用者寄存器（RISC-V ABI 调用者保存寄存器） */
    addi  sp, sp, -64          /* 栈空间：16个寄存器 × 4字节 */
    sw    ra,  0(sp)
    sw    a0,  4(sp)
    sw    a1,  8(sp)
    sw    a2, 12(sp)
    sw    a3, 16(sp)
    sw    a4, 20(sp)
    sw    a5, 24(sp)
    sw    a6, 28(sp)
    sw    a7, 32(sp)
    sw    t0, 36(sp)
    sw    t1, 40(sp)
    sw    t2, 44(sp)
    sw    t3, 48(sp)
    sw    t4, 52(sp)
    sw    t5, 56(sp)
    sw    t6, 60(sp)

    /* 读取mcause寄存器，判断异常类型 */
    csrr  t0, mcause
    li    t1, 0x80000000       /* 最高位：1=中断，0=异常 */
    and   t2, t0, t1
    bnez  t2, IRQ_Dispatch     /* 是中断 → 分发中断 */
    
    /* 是同步异常 → 识别异常类型 */
    /* 0: 指令地址未对齐 */
    li    t1, 0
    beq   t0, t1, Instruction_Address_Misaligned_Handler
    /* 1: 指令访问错误 */
    li    t1, 1
    beq   t0, t1, Instruction_Access_Fault_Handler
    /* 2: 非法指令 */
    li    t1, 2
    beq   t0, t1, Illegal_Instruction_Handler
    /* 3: 环境断点 */
    li    t1, 3
    beq   t0, t1, Breakpoint_Handler
    /* 5: 访存错误 */
    li    t1, 5
    beq   t0, t1, Load_Address_Fault_Handler 
    /* 7: 访存错误 */
    li    t1, 7
    beq   t0, t1, Store_Address_Fault_Handler
    /* 11: 机器模式ECALL环境调用 */ 
    li    t1, 11
    beq   t0, t1, M_Ecall_Handler

    j     HardFault_Handler                 /* 未定义异常 → 死循环 */

/* 中断分发：根据mcause识别中断类型 */
IRQ_Dispatch:
    li    t1, 0x80000003       /* 机器软件中断 (mcause=3 + 中断位) */
    beq   t0, t1, MSoft_IRQ_Handler
    li    t1, 0x80000007       /* 机器定时器中断 (mcause=7 + 中断位) */
    beq   t0, t1, MTimer_IRQ_Handler
    li    t1, 0x8000000B       /* 机器外部中断 (mcause=11 + 中断位) */
    beq   t0, t1, MExtern_IRQ_Handler
    j     HardFault_Handler        /* 未定义中断 → 死循环 */

/* 异常返回：恢复寄存器 + mret */
.global Exception_Exit
Exception_Exit:
    /* 恢复调用者寄存器 */
    lw    ra,  0(sp)
    lw    a0,  4(sp)
    lw    a1,  8(sp)
    lw    a2, 12(sp)
    lw    a3, 16(sp)
    lw    a4, 20(sp)
    lw    a5, 24(sp)
    lw    a6, 28(sp)
    lw    a7, 32(sp)
    lw    t0, 36(sp)
    lw    t1, 40(sp)
    lw    t2, 44(sp)
    lw    t3, 48(sp)
    lw    t4, 52(sp)
    lw    t5, 56(sp)
    lw    t6, 60(sp)
    addi  sp, sp, 64
    
    /* mret: 返回到异常/中断发生前的指令 */
    mret

/* ========== 4. 异常/中断处理函数（弱定义，可被C覆盖） ========== */
.section .trap.handler
.align 4

/* 同步异常处理 */
.weak Instruction_Address_Misaligned_Handler
Instruction_Address_Misaligned_Handler:
    j HardFault_Handler

.weak Instruction_Access_Fault_Handler
Instruction_Access_Fault_Handler:
    j HardFault_Handler

.weak Illegal_Instruction_Handler
Illegal_Instruction_Handler:
    j HardFault_Handler

.weak Breakpoint_Handler
Breakpoint_Handler:
    j HardFault_Handler

.weak Load_Address_Fault_Handler
Load_Address_Fault_Handler:
    j HardFault_Handler

.weak Store_Address_Fault_Handler
Store_Address_Fault_Handler:
    j HardFault_Handler

.weak M_Ecall_Handler
M_Ecall_Handler:

    j Exception_Exit

/* 中断处理 */
.weak MSoft_IRQ_Handler
MSoft_IRQ_Handler:

    j Exception_Exit

.weak MTimer_IRQ_Handler
MTimer_IRQ_Handler:

    j Exception_Exit

.weak MExtern_IRQ_Handler
MExtern_IRQ_Handler:

    j Exception_Exit

.weak UART0_TX_IRQ_Handler
UART_RX_IRQ_Handler:

    j Exception_Exit

.weak UART0_RX_IRQ_Handler
UART_RX_IRQ_Handler:

    j Exception_Exit

.weak UART1_TX_IRQ_Handler
UART_RX_IRQ_Handler:

    j Exception_Exit

.weak UART1_RX_IRQ_Handler
UART_RX_IRQ_Handler:

    j Exception_Exit

.weak IIC_IRQ_Handler
IIC_IRQ_Handler:

    j Exception_Exit

.weak SPI_IRQ_Handler
SPI_IRQ_Handler:

    j Exception_Exit

/* 未处理的异常/中断：死循环 */
.global HardFault_Handler
HardFault_Handler:
1:  j 1b

/* ========== 5. 可选：C初始化函数（弱定义） ========== */
.section .text
.weak _init
_init:
    ret  /* 默认空实现，可在C中重定义 */

/*
 * 链接器会使用的符号声明
 * 这些符号在链接脚本中定义，这里声明为外部引用
 */
.global _sdata
.global _edata
.global _sbss
.global _ebss
.global _sstack
.global _estack
.global __global_pointer$
.global __vector_base