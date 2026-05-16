# 汇编级定时器中断测试 — 完全自包含，不依赖 start.o
#
# 编译：
#   riscv64-unknown-elf-gcc -c -march=rv32im -mabi=ilp32 \
#     src/timer_int_standalone.s -o /tmp/cio
#   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
#     -nostartfiles -nodefaultlibs -T lib/link.ld \
#     /tmp/cio /tmp/coremark_build/syscalls.o -o /tmp/cie
#   python script/elf2uartbin.py /tmp/cie test_data/custom/ti_standalone.uartbin

.equ UART_BASE,     0xE0010000
.equ UART_LSR,      0x14
.equ LSR_THRE,      0x20

.equ GPIO_BASE,     0xE0000000
.equ GPIO_DIR,      0x04
.equ GPIO_OUT,      0x08
.equ LED_MASK,      0x18

.equ CLINT_BASE,    0xF2000000
.equ MTIME_LO,      0xBFF8
.equ MTIME_HI,      0xBFFC
.equ MTIMECMP_LO,   0x4000
.equ MTIMECMP_HI,   0x4004

.equ ONE_SEC,       0x5F5E100     # 100,000,000

.section .init
.global _start

_start:
    la   sp, _estack

    # ==== UART ====
    li   s0, UART_BASE
    li   t1, 0x80
    sw   t1, 0x0C(s0)      # DLAB=1
    li   t1, 54
    sw   t1, 0x00(s0)      # DLL
    sw   zero, 0x04(s0)    # DLM
    li   t1, 0x03
    sw   t1, 0x0C(s0)      # 8N1

    # ==== GPIO ====
    li   s1, GPIO_BASE
    li   t1, LED_MASK
    sw   t1, GPIO_DIR(s1)
    sw   zero, GPIO_OUT(s1)

    # 打印 "TMR\n"
    li   a0, 0x54; call uart_putc
    li   a0, 0x4D; call uart_putc
    li   a0, 0x52; call uart_putc
    li   a0, 0x0A; call uart_putc

    # ==== mtvec = Exception_Handler (Direct模式) ====
    la   a0, Exception_Handler
    csrw mtvec, a0

    # ==== mtimecmp = mtime + 1秒 ====
    li   s2, CLINT_BASE

    # 读 mtime
    li   t0, MTIME_LO
    add  t0, s2, t0
    lw   t2, 0(t0)           # lo
    li   t0, MTIME_HI
    add  t0, s2, t0
    lw   t3, 0(t0)           # hi

    # lo += 100000000; hi += carry
    li   t4, ONE_SEC
    add  t2, t2, t4
    sltu t5, t2, t4
    add  t3, t3, t5

    # 写 mtimecmp (先 hi 再 lo)
    li   t0, MTIMECMP_HI
    add  t0, s2, t0
    sw   t3, 0(t0)
    li   t0, MTIMECMP_LO
    add  t0, s2, t0
    sw   t2, 0(t0)

    # ==== 开中断 ====
    li   t1, 0x80            # mie[7] = MTIE
    csrw mie, t1
    li   t1, 0x1808          # mstatus: MIE=1
    csrw mstatus, t1

    # 打印 "EN\n"
    li   a0, 0x45; call uart_putc
    li   a0, 0x4E; call uart_putc
    li   a0, 0x0A; call uart_putc

    # ==== 主循环（带 mtime 轮询打印）====
    li   s3, CLINT_BASE
    li   s4, 0   # 轮询计数

1:  csrsi mstatus, 8

    # 每约 100 万轮读 mtime 打印
    addi s4, s4, 1
    li   t0, 100000
    blt  s4, t0, 1b
    li   s4, 0

    # 读 mtime lo
    li   t0, MTIME_LO
    add  t0, s3, t0
    lw   a0, 0(t0)
    call uart_print_hex
    li   a0, 0x2F              # '/'
    call uart_putc
    # 读 mtimecmp lo
    li   t0, MTIMECMP_LO
    add  t0, s3, t0
    lw   a0, 0(t0)
    call uart_print_hex
    li   a0, 0x0A
    call uart_putc
    j 1b

# ================================================================
# Exception_Handler: 保存上下文 → 调 C 风格 dispatch → mret
# 保存全部 16 个 caller 寄存器到栈
# ================================================================
.align 4
Exception_Handler:
    addi sp, sp, -64
    sw   ra,  0(sp)
    sw   a0,  4(sp)
    sw   a1,  8(sp)
    sw   a2, 12(sp)
    sw   a3, 16(sp)
    sw   a4, 20(sp)
    sw   a5, 24(sp)
    sw   a6, 28(sp)
    sw   a7, 32(sp)
    sw   t0, 36(sp)
    sw   t1, 40(sp)
    sw   t2, 44(sp)
    sw   t3, 48(sp)
    sw   t4, 52(sp)
    sw   t5, 56(sp)
    sw   t6, 60(sp)

    csrr t0, mcause
    li   t1, 0x80000000
    and  t2, t0, t1
    bnez t2, handle_interrupt

    # 同步异常 → 死循环
    j hardfault

handle_interrupt:
    # mcause & 0x7FF == 7 → MTI
    li   t1, 0x7FF
    and  t2, t0, t1
    li   t1, 7
    bne  t2, t1, hardfault

    # === MTI handler ===
    # 翻转 LED
    li   t0, GPIO_BASE
    lw   t1, GPIO_OUT(t0)
    xori t1, t1, LED_MASK
    sw   t1, GPIO_OUT(t0)

    # 打印 "T"
    li   a0, 0x54
    call uart_putc
    li   a0, 0x0A
    call uart_putc

    # 重新设 mtimecmp = mtime + 1秒
    li   t0, CLINT_BASE
    li   t1, MTIME_LO
    add  t1, t0, t1
    lw   t2, 0(t1)
    li   t1, MTIME_HI
    add  t1, t0, t1
    lw   t3, 0(t1)

    li   t4, ONE_SEC
    add  t2, t2, t4
    sltu t5, t2, t4
    add  t3, t3, t5

    li   t1, MTIMECMP_HI
    add  t1, t0, t1
    sw   t3, 0(t1)
    li   t1, MTIMECMP_LO
    add  t1, t0, t1
    sw   t2, 0(t1)

    # === 恢复并 mret ===
Exception_Exit:
    lw   ra,  0(sp)
    lw   a0,  4(sp)
    lw   a1,  8(sp)
    lw   a2, 12(sp)
    lw   a3, 16(sp)
    lw   a4, 20(sp)
    lw   a5, 24(sp)
    lw   a6, 28(sp)
    lw   a7, 32(sp)
    lw   t0, 36(sp)
    lw   t1, 40(sp)
    lw   t2, 44(sp)
    lw   t3, 48(sp)
    lw   t4, 52(sp)
    lw   t5, 56(sp)
    lw   t6, 60(sp)
    addi sp, sp, 64
    mret

hardfault:
    j hardfault

# ===== UART putc =====
uart_putc:
    li   t6, LSR_THRE
1:  lw   t5, UART_LSR(s0)
    and  t5, t5, t6
    beqz t5, 1b
    sw   a0, 0x00(s0)
    ret
