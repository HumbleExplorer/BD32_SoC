# MROM Bootloader
#
# LED 诊断:
#   全灭              → 未启动 / 挂死
#   LED0 亮 (GPIO[3])  → normal mode (GPIO[0]=0), 即将跳 ITCM
#   LED1 亮 (GPIO[4])  → download mode (GPIO[0]=1), 等待下载
#   LED0+LED1 都亮     → 下载完成, 跳 ITCM

# === GPIO init ===
lui ra, 0xE0000          # ra = GPIO base (0xE000_0000)
li t1, 0x18
sw t1, 0x04(ra)          # DIR: bits[4:3]=out, [2:0]=in

# 关所有 LED
sw zero, 0x08(ra)

# === 读 MODE_SEL ===
lw t1, 0x0C(ra)          # 读 INPUT
andi t1, t1, 0x01        # bit[0]
bnez t1, download_mode

# ==================== Normal Mode ====================
normal_mode:
li t1, 0x08               # LED0 ON
sw t1, 0x08(ra)
j jump_to_itcm

# ==================== Download Mode ====================
download_mode:
li t1, 0x10               # LED1 ON
sw t1, 0x08(ra)

# 初始化 UART
lui ra, 0xE0010          # UART base
li t3, 0x80
sw t3, 0x0C(ra)          # LCR[DLAB]=1
li t3, 54
sw t3, 0x00(ra)          # DLL = 54
sw zero, 0x04(ra)        # DLM = 0
li t3, 0x03
sw t3, 0x0C(ra)          # LCR = 8N1, DLAB=0
sw zero, 0x08(ra)        # FCR reset

# NCO FCW 初始化（115200 baud @ 100MHz）
li t3, 0x04B76893
sw t3, 0x24(ra)          # FCW = 0x04B76893

# 使能下载
li t3, 0x01
sw t3, 0x1C(ra)          # DBG_EN = 1

# 等下载完成
download_wait:
lw t4, 0x20(ra)
andi t5, t4, 0x01
beqz t5, download_wait

# 下载完成
download_done:
lui t0, 0xE0000
li t1, 0x18               # LED0+LED1 ON
sw t1, 0x08(t0)

# ===== 跳 ITCM =====
jump_to_itcm:
lui t1, 0x10             # t1 = 0x00010000
jr t1
