# MROM Bootloader - Boot from flash or download mode
# Base addresses:
#   0x80000000 - GPIO
#   0x80010000 - UART 

# Step 1: Check boot mode by reading SPI status
# SET GPIO mode = push-pull
li ra, 0x80000000           # GPIO base address
sw zero, 0x00(ra)           
# SET GPIO[1] output ,GPIO[0] input
li t1, 0x00000002           
sw t1, 0x04(ra)             
# GET GPIO input val
lw t1, 0x0c(ra)             # GET GPIO[0] input val
andi t1, t1, 0x1            # Extract bit[0]: boot_mode
beqz t1, normal_mode        # If bit[0]=0, boot from ITCM/Flash, otherwise UART

# Download mode: Load program from UART to ITCM/Flash
download_cfg:
# SET UART Divisor Register
    li ra, 0x80010000       # UART base address
    li t3, 0x00000080        
    sw t3, 0x0C(ra)         # SET LCR[DLAB_BIT]
    li t3, 27                # Baud rate 115200(50MHz)
    sw t3, 0(ra)             # SET DLL
    sw zero, 0x04(ra)        # SET DLM
    li t3, 0x00000003        
# SET UART Control Register
    sw t3, 0x0C(ra)          # RESET LCR[DLAB_BIT]
    sw zero, 0x08(ra)        # RESET FCR
    sw t1, 0x1c(ra)          # SET download mode

# Wait for download to complete
download_mode:
    lw t4, 0x20(ra)          # Read UART download status
    andi t5, t4, 0x1         # Check download done flag
    beqz t5, download_mode   # Loop until done

# Normal boot mode: Jump to user program in ITCM/Flash
normal_mode:
    li ra, 0x80000000        # GPIO base address
    # SET GPIO[1] output to indicate normal mode
    li t1, 0x2               
    sw t1, 0x08(ra)          
    li t1, 0x00010000        # User program entry address
    jr t1                    # Jump to user program
    nop
    nop
