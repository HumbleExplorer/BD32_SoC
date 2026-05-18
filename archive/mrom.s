# MROM Bootloader - RISC-V Bootloader
# GPIO map（5路）:
#   [0] MODE_SEL (input, W15, 跳线帽接3.3V=UART下载, 浮空=正常跳ITCM)
#   [1] KEY1     (input, K16)
#   [2] KEY0     (input, L14)
#   [3] LED0     (output, H15, 底板PL_LED0)
#   [4] LED2     (output, J16, 核心板PL_LED)

# === Step 1: Configure GPIO ===
lui ra, 0xE0000         # ra = 0xE000_0000 (GPIO base)
sw zero, 0x00(ra)        # MODE = push-pull for all

# DIRECTION: bits[2:0]=input, bits[4:3]=output → 0b11000 = 0x18
li t1, 0x18
sw t1, 0x04(ra)

# Light LED0 (GPIO[3]) → 0x08: CPU alive
li t1, 0x08
sw t1, 0x08(ra)

# === Step 2: Read MODE_SEL (GPIO[0]) to choose boot mode ===
lw t1, 0x0C(ra)         # Read GPIO input value
andi t1, t1, 0x01       # MODE_SEL = bit[0]
beqz t1, normal_mode    # 0 = floating -> jump to ITCM; 1 (3.3V) = UART download

# === UART Download Mode ===
# Configure UART
lui ra, 0xE0010         # ra = 0xE001_0000 (UART base)
li t3, 0x80
sw t3, 0x0C(ra)         # LCR[DLAB]=1
li t3, 27
sw t3, 0x00(ra)         # DLL = 27
sw zero, 0x04(ra)       # DLM = 0
li t3, 0x03
sw t3, 0x0C(ra)         # LCR = 8N1 (DLAB=0)
sw zero, 0x08(ra)       # FCR reset
li t3, 0x01
sw t3, 0x1C(ra)         # DBG_EN = 1 (start download)

# Wait for download complete
download_loop:
lw t4, 0x20(ra)         # Read DBG status (bit[0]=download_done)
andi t5, t4, 0x01
beqz t5, download_loop

# Download done: light LED0+LED2 (bits 3+4 = 0x18)
lui ra, 0xE0000
li t1, 0x18
sw t1, 0x08(ra)
j jump_to_itcm

# === Normal Boot Mode ===
normal_mode:
lui ra, 0xE0000
li t1, 0x18             # LED0+LED2 = 0x18
sw t1, 0x08(ra)

# === Jump to user program at ITCM (0x00010000) ===
jump_to_itcm:
lui t1, 0x10
jr t1
