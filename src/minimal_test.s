# BD32 极简汇编测试
# 不依赖任何 C 代码、栈、DTCM
# 直接从 ITCM 操作 GPIO 灭灯 + UART 发字符
#
# 编译：
#   riscv64-unknown-elf-gcc -c -march=rv32im -mabi=ilp32 \
#     src/minimal_test.s -o minimal_test.o
#
# 链接：
#   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
#     -nostartfiles -nodefaultlibs -T lib/link.ld \
#     minimal_test.o lib/syscalls.o lib/start.o \
#     -o minimal_test.elf
#   riscv64-unknown-elf-objcopy -O binary minimal_test.elf minimal_test.bin

.section .init
.global _start

.equ GPIO_BASE,  0xE0000000
.equ GPIO_MODE,  0x00   # offset 0
.equ GPIO_DIR,   0x04
.equ GPIO_OUT,   0x08
.equ LED_MASK,   0x18   # bit3|bit4

.equ UART_BASE,  0xE0010000
.equ UART_THR,   0x00
.equ UART_LSR,   0x14
.equ UART_LCR,   0x0C
.equ LSR_THRE,   0x20

_start:
    # ===== 1. GPIO 配置：设方向为输出，输出 0 = 灭 LED =====
    li   t0, GPIO_BASE
    li   t1, LED_MASK
    sw   t1, GPIO_DIR(t0)    # GPIO_DIR = 0x18
    sw   zero, GPIO_OUT(t0)  # GPIO_OUT = 0
    
    # ===== 2. 重复写 GPIO_OUT=0 确保时序 =====
    sw   zero, GPIO_OUT(t0)
    sw   zero, GPIO_OUT(t0)
    sw   zero, GPIO_OUT(t0)
    
    # ===== 3. UART 配置：DLAB=1, DLL=54 =====
    li   t2, UART_BASE
    
    li   t1, 0x80
    sw   t1, UART_LCR(t2)    # DLAB=1
    li   t1, 54
    sw   t1, UART_THR(t2)    # DLL=54
    sw   zero, 4(t2)         # DLM=0 (UART_BASE+4)
    li   t1, 0x03
    sw   t1, UART_LCR(t2)    # 8N1, DLAB=0
    
    # ===== 4. 发字符 'A' =====
    li   t3, LSR_THRE
1:  lw   t1, UART_LSR(t2)
    and  t1, t1, t3
    beqz t1, 1b
    li   t1, 0x41   # 'A'
    sw   t1, UART_THR(t2)
    
    # ===== 5. 发字符 'B' =====
2:  lw   t1, UART_LSR(t2)
    and  t1, t1, t3
    beqz t1, 2b
    li   t1, 0x42   # 'B'
    sw   t1, UART_THR(t2)
    
    # ===== 6. 发 '\n' =====
3:  lw   t1, UART_LSR(t2)
    and  t1, t1, t3
    beqz t1, 3b
    li   t1, 0x0A   # '\n'
    sw   t1, UART_THR(t2)
    
    # ===== 7. 无限循环，闪烁 LED =====
loop:
    # 点亮
    li   t1, LED_MASK
    sw   t1, GPIO_OUT(t0)
    # 延时
    li   t4, 200000
4:  addi t4, t4, -1
    bnez t4, 4b
    # 熄灭
    sw   zero, GPIO_OUT(t0)
    # 延时
    li   t4, 200000
5:  addi t4, t4, -1
    bnez t4, 5b
    
    j loop
