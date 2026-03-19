li ra,0x80000000
sw zero,0x00(ra)
li t1,0x00000002
sw t1,0x04(ra)
lw t1,0x0c(ra)
andi t1,t1,0x1
beqz t1,normal_mode

download_cfg:
    li ra,0x80010000
    li t3,0x00000080
    sw t3,0x0C(ra)
    li t3,27
    sw t3,0(ra)
    sw zero,0x04(ra)
    li t3,0x00000003
    sw t3,0x0C(ra)
    sw zero,0x08(ra)
    sw t1,0x1c(ra)
    
download_mode:
    lw t4,0x20(ra)
    andi t5,t4,0x1
    beqz t5,download_mode

normal_mode:
    li ra,0x80000000
    li t1,0x2
    sw t1,0x08(ra)
    li t1,0x00010000
    jr t1
    nop
    nop
