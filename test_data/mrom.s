# BD32 MROM Bootloader v2 — 主频测量 + UART 自适应初始化
#
# 测频方法：
#   CLINT mtime 由独立 1MHz 定时器时钟驱动（timer_clk_i，16MHz 分频）
#   通过 csr mcycle 统计 10ms 内的 CPU 时钟周期数
#   freq_hz = mcycle_delta / 10ms = mcycle_delta * 100
#
# NCO FCW 计算（115200 baud）：
#   FCW = (1843200 * 2^32 + freq/2) / freq      (四舍五入)
#   DLL = freq / 1843200
#
# LED 诊断:
#   全灭           → 未启动 / 挂死
#   LED0 亮        → normal mode (GPIO[0]=0), 即将跳 ITCM
#   LED1 亮        → download mode (GPIO[0]=1), 等待下载
#   LED0+LED1 都亮 → 下载完成, 跳 ITCM
#
# 地址常量
.equ GPIO_BASE,     0xE0000000
.equ UART_BASE,     0xE0010000
.equ MTIME_LO,      0xF200BFF8    # CLINT mtime 低 32 位
# 主频存 DTCM 高段（0x0002FFF0），避开栈初始压栈位置
# DTCM: 0x00020000~0x0002FFFF，_estack=0x00030000, stack=顶部 4K
# 初始 SP=0x00030000, 前 4 次 call 用 [0x0002FFFC:0x0002FFF0]
.equ FREQ_STORE,    0x0002FFF0    # DTCM 高段预留 16 bytes
.equ MEASURE_TICKS, 10000         # 测量窗口: 10000 ticks = 10ms @ 1MHz

# UART FCW 分子常量
# baud×16×2^32 = 115200×16×2^32 = 1843200×2^32 = 0x001C2000_00000000
.equ FCW_NUM_HI,    0x001C2000    # 分子高 32 位（勿写成 0x1C20，差 256 倍）
.equ FCW_NUM_LO,    0x00000000    # 分子低 32 位

    .section .text
    .global _start

_start:
# ====================================================================
# Step 1: 使能 mcycle 计数器
# mcounteren[0] = 1, CSR 0x306
# ====================================================================
    li t0, 1
    csrw 0x306, t0

# ====================================================================
# Step 2: 测 CPU 主频
# 基准时钟: CLINT mtime @ 1MHz (1 tick = 1µs)
# 方法: 记录 10ms 内 CPU 经过的周期数 → freq = cycles * 100
# ====================================================================
    li t0, 0xF200BFF8     # t0 = &mtime_lo

    # 等待 mtime 变化（确保不从转换沿开始）
    lw t1, 0(t0)
1:  lw t2, 0(t0)
    beq t2, t1, 1b

    # 读测量起点: mtime_start, mcycle_start
    lw t1, 0(t0)          # t1 = mtime_lo
    csrr t2, 0xB00        # t2 = mcycle (CSR 0xB00)

    # 等待 MEASURE_TICKS 个 mtime ticks
    li t3, MEASURE_TICKS
    add t3, t1, t3         # t3 = mtime_start + 10000
2:  lw t4, 0(t0)
    blt t4, t3, 2b

    # 读测量终点: mcycle_end
    csrr t5, 0xB00        # t5 = mcycle

    # freq_hz = (t5 - t2) * 100
    sub t2, t5, t2        # t2 = cycles elapsed in 10ms
    li t3, 100
    mul a0, t2, t3        # a0 = freq_hz (低32位, <4GHz 足够)
    mulhu a1, t2, t3      # a1 = freq_hz (高32位, 通常为0)

# ====================================================================
# Step 3: 存主频到 DTCM 尾端 (0x0002FFFC)
# 避开 .data(低地址)/.bss/.heap/.stack(顶部4K)
# BSP 启动时从此处读取实测主频
# ====================================================================
    li t0, 0x0002FFF0       # DTCM 高段，避开初始栈压弹
    sw a0, 0(t0)            # [0x0002FFF0] = freq_hz

# ====================================================================
# Step 4: GPIO 初始化
# ====================================================================
    lui ra, 0xE0000        # ra = GPIO base (0xE000_0000)
    li t1, 0x18
    sw t1, 0x04(ra)        # DIR: bit[4:3]=out (LED1/LED0), [2:0]=in
    sw zero, 0x08(ra)      # 关所有 LED

# ====================================================================
# Step 5: 读 MODE_SEL
# ====================================================================
    lw t1, 0x0C(ra)        # INPUT register
    andi t1, t1, 0x01      # GPIO[0]
    bnez t1, download_mode

# ============= Normal Mode =============
normal_mode:
    li t1, 0x08             # LED0 ON (bit[3])
    sw t1, 0x08(ra)
    j jump_to_itcm

# ====================================================================
# Download Mode — 基于实测主频初始化 UART
# ====================================================================
download_mode:
    li t1, 0x10             # LED1 ON (bit[4])
    sw t1, 0x08(ra)

    # --- 计算 DLL = freq / (16 * 115200) = freq / 1843200 ---
    li t2, 1843200
    divu t3, a0, t2         # t3 = DLL (整数除数)

    # --- 计算 UART NCO FCW ---
    # 公式: FCW = (1843200 * 2^32 + freq/2) / freq  (四舍五入)
    # 分子: 0x00001C20_00000000, 分母: a0 = freq_hz
    # 64位/32位 除法, 商存 a2

    # 准备分子 (a3:a2) = 0x1C20 : 0x00000000
    li a2, FCW_NUM_LO       # a2 = 分子低 32 位 = 0
    li a3, FCW_NUM_HI       # a3 = 分子高 32 位 = 0x1C20

    # 四舍五入: 分子 += freq/2
    srli t4, a0, 1          # t4 = freq / 2
    add a2, a2, t4          # a2 += t4
    sltu t5, a2, t4         # 进位?
    add a3, a3, t5          # a3 += carry

    # 执行 64/32 除法: (a3:a2) / a0 → a2 (商)
    mv a4, a0               # a4 = 分母
    call div64_32            # a2 = FCW (商), a3 = 余数

    # --- UART 初始化 ---
    lui ra, 0xE0010         # ra = UART base (0xE001_0000)

    # LCR[DLAB]=1, 写 DLL/DLM
    li t1, 0x80
    sw t1, 0x0C(ra)         # LCR[DLAB]=1
    sw t3, 0x00(ra)         # DLL = freq / 1843200
    sw zero, 0x04(ra)       # DLM = 0

    # LCR = 8N1, DLAB=0
    li t1, 0x03
    sw t1, 0x0C(ra)         # LCR = 8N1
    sw zero, 0x08(ra)       # FCR reset

    # NCO FCW
    sw a2, 0x24(ra)         # FCW = 64/32 除法结果

    # 使能下载
    li t1, 0x01
    sw t1, 0x1C(ra)         # DBG_EN = 1

    # 等下载完成 (轮询 DBG_STAT[0])
download_wait:
    lw t4, 0x20(ra)         # DBG_STAT
    andi t5, t4, 0x01
    beqz t5, download_wait

    # 下载完成 — 全 LED 亮
    lui t0, 0xE0000
    li t1, 0x18             # LED0+LED1 ON
    sw t1, 0x08(t0)

# ====================================================================
# 跳转 ITCM (0x00010000)
# ====================================================================
jump_to_itcm:
    lui t1, 0x10             # t1 = 0x00010000
    jr t1

# ====================================================================
# 子程序: 64位 / 32位 无符号除法 (恢复余数法)
# 输入:
#   a3:a2  — 64位被除数 (a3=高32位, a2=低32位)
#   a4     — 32位除数
# 输出:
#   a2     — 32位商
#   a3     — 32位余数
# 破坏: t0, t1, a5 (临时变量)
# 假设: 商 ≤ 2^32-1 (不溢出), 除数 > 0
# 原理: 标准移位-试商算法, 从 MSB 到 LSB 逐位处理
# ====================================================================
div64_32:
    li t0, 64              # 循环 64 次
    li a5, 0               # a5 = 余数 = 0

div_loop:
    # --- 64位被除数+余数整体左移 1 位 ---
    # 余数 = (余数 << 1) | a3[31]
    slli a5, a5, 1
    srli t1, a3, 31
    or a5, a5, t1

    # a3 = (a3 << 1) | a2[31]
    slli a3, a3, 1
    srli t1, a2, 31
    or a3, a3, t1

    # a2 = a2 << 1 (商位也在低位移入)
    slli a2, a2, 1

    # --- 试商: 余数 >= 除数? ---
    bltu a5, a4, div_next  # 余数 < 除数 → 商位 0
    sub a5, a5, a4         # 余数 -= 除数
    ori a2, a2, 1          # 商[0] = 1

div_next:
    addi t0, t0, -1
    bnez t0, div_loop

    mv a3, a5              # a3 = 余数
    ret
