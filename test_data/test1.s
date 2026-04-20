# UART Print Loop Test - Output memory content via UART
# Base addresses:
#   0x80010000 - UART register base

# Initialize registers
li ra, 0x80010000   # UART base address
li a0, 0            # Initial value to print (clear a0)
li a1, 0x00026000   # End address of memory region to print
li a2, 0x00020000   # DTCM base address

# Main print loop
print_loop:
    lb a0, 0(a2)     # Load byte from DTCM at address a2
    sw a0, 0(ra)     # Write to UART THR register
    addi a2, a2, 4   # Increment address by 4 (word-aligned)
    bne a1, a2, print_loop  # If not at end address, continue
    nop              # Delay slot
    nop
