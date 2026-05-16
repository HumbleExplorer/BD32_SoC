# CLINT 诊断：直接读 4 个关键 CLINT 地址并打印 hex
# 不依赖任何 C 代码
#
# 编译：
#   riscv64-unknown-elf-gcc -c -march=rv32im -mabi=ilp32 \
#     src/clint_diag.s -o /tmp/clint_diag.o
#   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
#     -nostartfiles -nodefaultlibs -T lib/link.ld \
#     /tmp/clint_diag.o /tmp/syscalls.o \
#     -o /tmp/clint_diag.elf
#   python script/elf2uartbin.py /tmp/clint_diag.elf test_data/custom/clint_diag.uartbin

.equ UART_BASE,  0xE0010000
.equ UART_THR,   0
.equ UART_LSR,   0x14
.equ LSR_THRE,   0x20

.equ F2000000,   0xF2000000
.equ F2004000,   0xF2004000
.equ F200BFF8,   0xF200BFF8
.equ F200BFFC,   0xF200BFFC

.section .init
.global _start

_start:
    # 设栈指针（_estack 来自链接脚本）
    la   sp, _estack

    # 配 UART (直接写立即数偏移)
    li   t0, UART_BASE
    li   t1, 0x80
    sw   t1, 0x0C(t0)       # UART_LCR = 0x80 (DLAB=1)
    li   t1, 54
    sw   t1, 0x00(t0)       # UART_THR = DLL = 54
    sw   zero, 0x04(t0)     # DLM = 0
    li   t1, 0x03
    sw   t1, 0x0C(t0)       # UART_LCR = 0x03 (8N1)

    # 初始化指针
    li   s0, UART_BASE

    # ===== 读 0xF2000000 (MSIP) =====
    li   a0, 0x46           # 'F'
    call uart_putc
    li   a0, 0x3D           # '='
    call uart_putc
    li   t1, F2000000
    lw   a0, 0(t1)
    call uart_print_hex
    li   a0, 0x0A           # '\n'
    call uart_putc

    # ===== 读 0xF2004000 (mtimecmp lo) =====
    li   a0, 0x34           # '4'
    call uart_putc
    li   a0, 0x3D           # '='
    call uart_putc
    li   t1, F2004000
    lw   a0, 0(t1)
    call uart_print_hex
    li   a0, 0x0A
    call uart_putc

    # ===== 读 0xF200BFF8 (mtime lo) =====
    li   a0, 0x4C           # 'L'
    call uart_putc
    li   a0, 0x3D           # '='
    call uart_putc
    li   t1, F200BFF8
    lw   a0, 0(t1)
    call uart_print_hex
    li   a0, 0x0A
    call uart_putc

    # ===== 读 0xF200BFFC (mtime hi) =====
    li   a0, 0x48           # 'H'
    call uart_putc
    li   a0, 0x3D           # '='
    call uart_putc
    li   t1, F200BFFC
    lw   a0, 0(t1)
    call uart_print_hex
    li   a0, 0x0A
    call uart_putc

    # ===== 再读一次 mtime lo 看是否变化 =====
    li   a0, 0x4C           # 'L'
    call uart_putc
    li   a0, 0x32           # '2'
    call uart_putc
    li   a0, 0x3D
    call uart_putc
    li   t1, F200BFF8
    lw   a0, 0(t1)
    call uart_print_hex
    li   a0, 0x0A
    call uart_putc

loop:
    j loop

# ===== UART 输出 =====
uart_putc:
    li   t2, LSR_THRE
1:  lw   t3, UART_LSR(s0)
    and  t3, t3, t2
    beqz t3, 1b
    sw   a0, UART_THR(s0)
    ret

# ===== 打印 8 位 hex =====
uart_print_hex:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s1, 4(sp)
    mv   s1, a0
    li   s2, 8
1:  slli a0, s1, 28
    srli a0, a0, 28
    li   t2, 10
    blt  a0, t2, 2f
    addi a0, a0, 55     # 'A' - 10
    j    3f
2:  addi a0, a0, 48     # '0'
3:  call uart_putc
    srli s1, s1, 4
    addi s2, s2, -1
    bnez s2, 1b
    lw   s1, 4(sp)
    lw   ra, 0(sp)
    addi sp, sp, 8
    ret
