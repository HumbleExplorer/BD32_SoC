# BD32 诊断 MROM — 极简版（无 mul/div/CSR/OITF）
# 目的：排除 OITF/CSR 对 GPIO 总线访问的干扰
# 行为：
#   复位后立即检查 GPIO[0]
#   GPIO[0]=1 → LED1 亮，硬编码 UART 初始化，使能下载，等待
#   GPIO[0]=0 → LED0 亮，跳 ITCM
#
# 如果此 MROM 复位后能正常下载 → 问题在 OITF/CSR 路径
# 如果此 MROM 复位后仍失败 → 问题在基本总线访问路径
#
# 硬编码主频 = 75MHz（与 MMCM 输出匹配）
# DLL = 75000000 / 1843200 = 40 (0x28)
# FCW = round(1843200 * 2^32 / 75000000) = 105550758 (0x064A93A6)

.equ GPIO_BASE,     0xE0000000
.equ UART_BASE,     0xE0010000

    .section .text
    .global _start

_start:
# ====================================================================
# Step 1: GPIO 初始化（第一条指令就是总线访问，无 OITF 前置活动）
# ====================================================================
    lui ra, 0xE0000         # ra = GPIO base
    li t1, 0x18
    sw t1, 0x04(ra)        # DIR: bit[4:3]=out (LED1/LED0), [2:0]=in
    sw zero, 0x08(ra)      # 关所有 LED

# ====================================================================
# Step 2: 读 MODE_SEL（紧跟 GPIO 初始化，中间无 mul/div/CSR）
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
# Download Mode — 硬编码 UART 参数（75MHz）
# ====================================================================
download_mode:
    li t1, 0x10             # LED1 ON (bit[4])
    sw t1, 0x08(ra)

    # --- UART 初始化 ---
    lui ra, 0xE0010         # ra = UART base (0xE001_0000)

    # LCR[DLAB]=1, 写 DLL/DLM
    li t1, 0x80
    sw t1, 0x0C(ra)         # LCR[DLAB]=1
    li t2, 40               # DLL = 75MHz / 1843200 ≈ 40
    sw t2, 0x00(ra)         # DLL
    sw zero, 0x04(ra)       # DLM = 0

    # LCR = 8N1, DLAB=0
    li t1, 0x03
    sw t1, 0x0C(ra)         # LCR = 8N1
    sw zero, 0x08(ra)       # FCR reset

    # NCO FCW = 105550758 = 0x064A93A6
    li t2, 0x64A93A6
    sw t2, 0x24(ra)         # FCW

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
