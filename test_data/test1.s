li ra,0x80010000
li a0,0
li a1,0x00028000
li a2,0x00020000
story_loop:
	lb a0,0(a2)
	sw a0,0(ra)
	addi a2,a2,4
	bne a1,a2,story_loop
	nop
	nop
