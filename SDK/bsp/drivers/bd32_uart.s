	.file	"bd32_uart.c"
	.option nopic
	.attribute arch, "rv32i2p0_m2p0_zmmul1p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	2
	.type	uart_putc, @function
uart_putc:
	li	a4,-536805376
	addi	a4,a4,20
.L2:
	lw	a5,0(a4)
	andi	a5,a5,32
	beq	a5,zero,.L2
	li	a5,-536805376
	sw	a0,0(a5)
	ret
	.size	uart_putc, .-uart_putc
	.align	2
	.globl	uart_init
	.type	uart_init, @function
uart_init:
	addi	sp,sp,-16
	lui	a5,%hi(g_cpu_freq_hz)
	sw	s0,8(sp)
	lw	s0,%lo(g_cpu_freq_hz)(a5)
	sw	s1,4(sp)
	slli	s1,a0,4
	mv	a2,s0
	srli	a0,s0,1
	divu	s0,s0,s1
	mv	a1,s1
	li	a3,0
	sw	ra,12(sp)
	call	__udivdi3
	li	a5,-536805376
	sw	a0,36(a5)
	li	a4,128
	sw	a4,12(a5)
	lw	ra,12(sp)
	li	a4,3
	lw	s1,4(sp)
	andi	s0,s0,255
	sw	s0,0(a5)
	lw	s0,8(sp)
	sw	zero,4(a5)
	sw	a4,12(a5)
	addi	sp,sp,16
	jr	ra
	.size	uart_init, .-uart_init
	.align	2
	.globl	uart_puts
	.type	uart_puts, @function
uart_puts:
	addi	sp,sp,-16
	sw	s0,8(sp)
	sw	s1,4(sp)
	sw	ra,12(sp)
	mv	s0,a0
	li	s1,10
.L8:
	lbu	a5,0(s0)
	bne	a5,zero,.L10
	lw	ra,12(sp)
	lw	s0,8(sp)
	lw	s1,4(sp)
	addi	sp,sp,16
	jr	ra
.L10:
	bne	a5,s1,.L9
	li	a0,13
	call	uart_putc
.L9:
	lbu	a0,0(s0)
	addi	s0,s0,1
	call	uart_putc
	j	.L8
	.size	uart_puts, .-uart_puts
	.align	2
	.globl	uart_puthex
	.type	uart_puthex, @function
uart_puthex:
	addi	sp,sp,-32
	sw	s1,20(sp)
	mv	s1,a0
	li	a0,48
	sw	ra,28(sp)
	sw	s0,24(sp)
	sw	s2,16(sp)
	sw	s3,12(sp)
	call	uart_putc
	li	a0,120
	call	uart_putc
	li	s0,28
	lui	s3,%hi(.LANCHOR0)
	li	s2,-4
.L13:
	srl	a4,s1,s0
	andi	a4,a4,15
	addi	a5,s3,%lo(.LANCHOR0)
	add	a5,a5,a4
	lbu	a0,0(a5)
	addi	s0,s0,-4
	call	uart_putc
	bne	s0,s2,.L13
	lw	ra,28(sp)
	lw	s0,24(sp)
	lw	s1,20(sp)
	lw	s2,16(sp)
	lw	s3,12(sp)
	addi	sp,sp,32
	jr	ra
	.size	uart_puthex, .-uart_puthex
	.align	2
	.globl	uart_putdec
	.type	uart_putdec, @function
uart_putdec:
	addi	sp,sp,-16
	sw	s0,8(sp)
	sw	ra,12(sp)
	li	a5,9
	mv	s0,a0
	bleu	a0,a5,.L17
	li	a0,10
	divu	a0,s0,a0
	call	uart_putdec
.L17:
	li	a5,10
	remu	a0,s0,a5
	lw	s0,8(sp)
	lw	ra,12(sp)
	addi	sp,sp,16
	addi	a0,a0,48
	tail	uart_putc
	.size	uart_putdec, .-uart_putdec
	.align	2
	.globl	uart_put_fixed
	.type	uart_put_fixed, @function
uart_put_fixed:
	addi	sp,sp,-16
	sw	s1,4(sp)
	sw	s2,0(sp)
	sw	ra,12(sp)
	sw	s0,8(sp)
	mv	s1,a0
	mv	s2,a1
	bge	a0,zero,.L20
	li	a0,45
	call	uart_putc
	neg	s1,s1
.L20:
	li	a5,0
	li	s0,1
	li	a4,10
.L21:
	blt	a5,s2,.L22
	div	a0,s1,s0
	call	uart_putdec
	ble	s2,zero,.L19
	li	a0,46
	li	s2,10
	call	uart_putc
	rem	s1,s1,s0
	div	s0,s0,s2
.L24:
	bne	s0,zero,.L25
.L19:
	lw	ra,12(sp)
	lw	s0,8(sp)
	lw	s1,4(sp)
	lw	s2,0(sp)
	addi	sp,sp,16
	jr	ra
.L22:
	mul	s0,s0,a4
	addi	a5,a5,1
	j	.L21
.L25:
	divu	a0,s1,s0
	remu	a0,a0,s2
	addi	a0,a0,48
	call	uart_putc
	divu	s0,s0,s2
	j	.L24
	.size	uart_put_fixed, .-uart_put_fixed
	.section	.rodata
	.align	2
	.set	.LANCHOR0,. + 0
	.type	hex.0, @object
	.size	hex.0, 17
hex.0:
	.string	"0123456789ABCDEF"
	.globl	__udivdi3
	.ident	"GCC: (g47ade337c) 14.2.1 20240816"
	.section	.note.GNU-stack,"",@progbits
