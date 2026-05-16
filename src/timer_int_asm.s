# 汇编级定时器中断测试（CLINT mtime → MTI）
#
# 流程：
#   配UART → 配CLINT(mtimecmp=mtime+100M) → 开mie[7]+mstatus.MIE
#   → 等待中断 → Exception_Handler 保存寄存器
#   → IRQ_Dispatch → call trap_handler → 翻转LED + 打印 → mret
#
# 注意：trap_handler 需要 C 代码提供，但这里保留 start.o 的弱定义

.equ UART_BASE,  0xE0010000
.equ UART_THR,   0x00
.equ UART_LSR,   0x14
.equ LSR_THRE,   0x20

.equ GPIO_BASE,  0xE0000000
.equ GPIO_DIR,   0x04
.equ GPIO_OUT,   0x08
.equ LED_MASK,   0x18

.equ CLINT_BASE,   0xF2000000
.equ MTIME_LO,     0xBFF8
.equ MTIME_HI,     0xBFFC
.equ MTIMECMP_LO,  0x4000
.equ MTIMECMP_HI,  0x4004

.section .init
.global _start

_start:
    # ===== 1. 配 UART =====
    li   s0, UART_BASE
    li   t1, 0x80
    sw   t1, 0x0C(s0)      # LCR = DLAB=1
    li   t1, 54
    sw   t1, 0x00(s0)      # DLL = 54
    sw   zero, 0x04(s0)    # DLM = 0
    li   t1, 0x03
    sw   t1, 0x0C(s0)      # LCR = 8N1

    # ===== 2. 配 GPIO =====
    li   s1, GPIO_BASE
    li   t1, LED_MASK
    sw   t1, GPIO_DIR(s1)  # 方向输出
    sw   zero, GPIO_OUT(s1) # 初始灭

    # ===== 3. 打印 'S' =====
    li   a0, 0x53          # 'S'
    call uart_putc
    li   a0, 0x0A          # '\n'
    call uart_putc

    # ===== 4. 配 CLINT mtimecmp = mtime + 100000000 (1秒@100MHz) =====
    li   s2, CLINT_BASE

    # 读 mtime
    li   t1, MTIME_LO
    add  t0, s2, t1
    lw   t2, 0(t0)         # mtime lo
    li   t1, MTIME_HI
    add  t0, s2, t1
    lw   t3, 0(t0)         # mtime hi

    # target = mtime + 100000000 (0x5F5E100)
    li   t4, 0x5F5         # 0x5F5E100 >> 16
    slli t4, t4, 16
    li   t5, 0xE100
    add  t4, t4, t5        # t4 = 0x5F5E100
    add  t2, t2, t4        # lo += 100M
    sltu t5, t2, t4        # 进位检测
    add  t3, t3, t5        # hi += carry

    # 写 mtimecmp（RISC-V 标准：先写 hi，再写 lo）
    li   t1, MTIMECMP_HI
    add  t0, s2, t1
    sw   t3, 0(t0)         # mtimecmp hi
    li   t1, MTIMECMP_LO
    add  t0, s2, t1
    sw   t2, 0(t0)         # mtimecmp lo

    # ===== 5. 打印 'C' =====
    li   a0, 0x43          # 'C'
    call uart_putc
    li   a0, 0x0A
    call uart_putc

    # ===== 6. 开中断 =====
    li   t1, 0x80           # mie[7] = MTIE
    csrw mie, t1
    li   t1, 0x1808         # mstatus: MIE=1, MPIE=1, MPP=11
    csrw mstatus, t1

    # ===== 7. 打印 'E' =====
    li   a0, 0x45          # 'E'
    call uart_putc
    li   a0, 0x0A
    call uart_putc

loop:
    # 循环等待中断，每次循环开中断确保后续中断响应
    csrsi mstatus, 8
    j loop

# ===== UART putc =====
uart_putc:
    li   t2, LSR_THRE
    li   t6, UART_LSR
1:  lw   t5, UART_LSR(s0)
    and  t5, t5, t2
    beqz t5, 1b
    sw   a0, UART_THR(s0)
    ret
