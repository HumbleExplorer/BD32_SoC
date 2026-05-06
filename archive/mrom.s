# MROM Bootloader - RISC-V Bootloader
# GPIO 5路:
#   [0] MODE_SEL (input, W15, 跳线帽接3.3V=UART下载, 浮空=正常跳ITCM)
#   [1] KEY1     (input, K16)
#   [2] KEY0     (input, L14)
#   [3] LED0     (output, H15)
#   [4] LED2     (output, J16)

# === Step 1: Configure GPIO ===
lui ra, 0xE0000
sw zero, 0x00(ra)        # MODE = push-pull
li t1, 0x18
sw t1, 0x04(ra)          # DIR: [3:4]=output
li t1, 0x08
sw t1, 0x08(ra)          # LED0 on: CPU alive

# === Step 2: Read MODE_SEL ===
lw t1, 0x0C(ra)          # Read GPIO input
andi t1, t1, 0x01        # MODE_SEL = bit[0]
beqz t1, normal_mode     # 0 = floating -> jump to ITCM; 1 (3.3V) = UART download

# === UART Download Mode ===
lui ra, 0xE0010
li t3, 0x80
sw t3, 0x0C(ra)          # LCR[DLAB]=1
li t3, 27
sw t3, 0x00(ra)          # DLL = 27
sw zero, 0x04(ra)        # DLM = 0
li t3, 0x03
sw t3, 0x0C(ra)          # LCR = 8N1
sw zero, 0x08(ra)        # FCR reset
li t3, 0x01
sw t3, 0x1C(ra)          # DBG_EN = 1

download_loop:
lw t4, 0x20(ra)
andi t5, t4, 0x01
beqz t5, download_loop

lui ra, 0xE0000
li t1, 0x18
sw t1, 0x08(ra)
lui t1, 0x10
jr t1

normal_mode:
lui ra, 0xE0000
li t1, 0x18
sw t1, 0x08(ra)
lui t1, 0x10
jr t1
