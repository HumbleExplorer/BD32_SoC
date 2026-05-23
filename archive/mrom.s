# MROM Bootloader — 带 LED 诊断的启动引导
#
# GPIO map:
#   [0] MODE_SEL (input,  W15, 跳线帽接3.3V=UART下载, 浮空=正常)
#   [3] LED0     (output, H15, 底板PL_LED0)
#   [4] LED1     (output, J16, 核心板PL_LED)
#
# LED 诊断信号:
#   LED0 亮              → MROM 已启动, GPIO 已配好
#   LED0 灭, LED1 亮     → GPIO[0]=0, 走 normal_mode, 即将跳 ITCM
#   LED0+LED1 都亮       → GPIO[0]=1, 进 UART 下载模式
#   LED1 闪烁            → 等待 UART 下载完成
#   两灯全灭              → CPU 挂了(不太可能) 或 已跳转用户程序

# === Step 1: GPIO init + LED0 亮 = MROM alive ===
lui ra, 0xE0000          # ra = GPIO base (0xE000_0000)

# DIR: bits[4:3]=out, bits[2:0]=in → 0x18
li t1, 0x18
sw t1, 0x04(ra)

# LED0 ON (GPIO[3]=1)
li t1, 0x08
sw t1, 0x08(ra)

# === Step 2: 读 GPIO[0] 判断启动模式 ===
lw t1, 0x0C(ra)          # 读 INPUT 寄存器
andi t1, t1, 0x01        # 提取 bit[0]
bnez t1, download_mode   # t1=1 → UART 下载

# ==================== Normal Mode ====================
# LED0 灭, LED1 亮 → 表示 "进了 normal_mode 分支"
li t1, 0x10
sw t1, 0x08(ra)          # LED0 off, LED1 on

# 短暂延时让人眼能看到
li t2, 0x100000
1: addi t2, t2, -1
bnez t2, 1b

j jump_to_itcm

# ==================== UART Download Mode ====================
download_mode:
# LED0 + LED1 都亮 → 表示 "检测到下载模式"
li t1, 0x18
sw t1, 0x08(ra)          # LED0+LED1 ON

# 初始化 UART (DLL=27 for 50MHz → 115200, but SoC runs at 100MHz → DLL=54)
# 实际上: clk_soc=100MHz, baud=115200, divisor=100M/(16*115200)=54
lui ra, 0xE0010          # ra = UART base (0xE001_0000)
li t3, 0x80
sw t3, 0x0C(ra)          # LCR[DLAB]=1
li t3, 54                # DLL = 54 ← 100MHz / (16 * 115200)
sw t3, 0x00(ra)
sw zero, 0x04(ra)        # DLM = 0
li t3, 0x03
sw t3, 0x0C(ra)          # LCR = 8N1, DLAB=0
sw zero, 0x08(ra)        # FCR reset

# 使能 UART 下载
li t3, 0x01
sw t3, 0x1C(ra)          # DBG_EN = 1 (UART 0x1C write → set download_en)

# ===== 轮询等待下载完成，LED1 闪烁 =====
lui t0, 0xE0000          # t0 = GPIO base (for LED toggle)

download_wait:
# 读下载状态
lw t4, 0x20(ra)          # DBG status (bit0=download_done)
andi t5, t4, 0x01
bnez t5, download_done   # done!

# LED1 toggle (GPIO[4])
lw t3, 0x08(t0)          # 读当前 OUT 值
xori t3, t3, 0x10        # 翻转 bit[4]
sw t3, 0x08(t0)          # 写回

# 简单位循环延时
li t6, 0x40000
1: addi t6, t6, -1
bnez t6, 1b

j download_wait

# ===== 下载完成 =====
download_done:
# LED0+LED1 常亮
li t1, 0x18
sw t1, 0x08(t0)

# ===== 跳转 ITCM =====
jump_to_itcm:
lui t1, 0x10             # t1 = 0x00010000
jr t1                    # jump to user program
