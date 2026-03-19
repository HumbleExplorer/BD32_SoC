li	s10,0
li	s11,0


li	ra,0
li	sp,0
sub	t5,ra,sp
li	t4,0
li	gp,2
bne	t5,t4,0x4c8 # <fail>


li	ra,1
li	sp,1
sub	t5,ra,sp
li	t4,0
li	gp,3
bne	t5,t4,0x4c8 # <fail>


li	ra,3
li	sp,7
sub	t5,ra,sp
li	t4,-4
li	gp,4
bne	t5,t4,0x4c8 # <fail>


li	ra,0
lui	sp,0xffff8
sub	t5,ra,sp
lui	t4,0x8
li	gp,5
bne	t5,t4,0x4c8 # <fail>


lui	ra,0x80000
li	sp,0
sub	t5,ra,sp
lui	t4,0x80000
li	gp,6
bne	t5,t4,0x4c8 # <fail>


lui	ra,0x80000
lui	sp,0xffff8
sub	t5,ra,sp
lui	t4,0x80008
li	gp,7
bne	t5,t4,0x4c8 # <fail>


li	ra,0
lui	sp,0x8
addi	sp,sp,-1 # 7fff # <begin_signature+0x6fff>
sub	t5,ra,sp
lui	t4,0xffff8
addi	t4,t4,1 # ffff8001 # <begin_signature+0xffff7001>
li	gp,8
bne	t5,t4,0x4c8 # <fail>


lui	ra,0x80000
addi	ra,ra,-1 # 7fffffff # <begin_signature+0x7fffefff>
li	sp,0
sub	t5,ra,sp
lui	t4,0x80000
addi	t4,t4,-1 # 7fffffff # <begin_signature+0x7fffefff>
li	gp,9
bne	t5,t4,0x4c8 # <fail>


lui	ra,0x80000
addi	ra,ra,-1 # 7fffffff # <begin_signature+0x7fffefff>
lui	sp,0x8
addi	sp,sp,-1 # 7fff # <begin_signature+0x6fff>
sub	t5,ra,sp
lui	t4,0x7fff8
li	gp,10
bne	t5,t4,0x4c8 # <fail>


lui	ra,0x80000
lui	sp,0x8
addi	sp,sp,-1 # 7fff # <begin_signature+0x6fff>
sub	t5,ra,sp
lui	t4,0x7fff8
addi	t4,t4,1 # 7fff8001 # <begin_signature+0x7fff7001>
li	gp,11
bne	t5,t4,0x4c8 # <fail>


lui	ra,0x80000
addi	ra,ra,-1 # 7fffffff # <begin_signature+0x7fffefff>
lui	sp,0xffff8
sub	t5,ra,sp
lui	t4,0x80008
addi	t4,t4,-1 # 80007fff # <begin_signature+0x80006fff>
li	gp,12
bne	t5,t4,0x4c8 # <fail>


li	ra,0
li	sp,-1
sub	t5,ra,sp
li	t4,1
li	gp,13
bne	t5,t4,0x4c8 # <fail>


li	ra,-1
li	sp,1
sub	t5,ra,sp
li	t4,-2
li	gp,14
bne	t5,t4,0x4c8 # <fail>


li	ra,-1
li	sp,-1
sub	t5,ra,sp
li	t4,0
li	gp,15
bne	t5,t4,0x4c8 # <fail>


li	ra,13
li	sp,11
sub	ra,ra,sp
li	t4,2
li	gp,16
bne	ra,t4,0x4c8 # <fail>


li	ra,14
li	sp,11
sub	sp,ra,sp
li	t4,3
li	gp,17
bne	sp,t4,0x4c8 # <fail>


li	ra,13
sub	ra,ra,ra
li	t4,0
li	gp,18
bne	ra,t4,0x4c8 # <fail>


li	tp,0
li	ra,13
li	sp,11
sub	t5,ra,sp
mv	t1,t5
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x1c8 # <test_19+0x4>
li	t4,2
li	gp,19
bne	t1,t4,0x4c8 # <fail>


li	tp,0
li	ra,14
li	sp,11
sub	t5,ra,sp
nop
mv	t1,t5
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x1f4 # <test_20+0x4>
li	t4,3
li	gp,20
bne	t1,t4,0x4c8 # <fail>


li	tp,0
li	ra,15
li	sp,11
sub	t5,ra,sp
nop
nop
mv	t1,t5
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x224 # <test_21+0x4>
li	t4,4
li	gp,21
bne	t1,t4,0x4c8 # <fail>


li	tp,0
li	ra,13
li	sp,11
sub	t5,ra,sp
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x258 # <test_22+0x4>
li	t4,2
li	gp,22
bne	t5,t4,0x4c8 # <fail>


li	tp,0
li	ra,14
li	sp,11
nop
sub	t5,ra,sp
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x280 # <test_23+0x4>
li	t4,3
li	gp,23
bne	t5,t4,0x4c8 # <fail>


li	tp,0
li	ra,15
li	sp,11
nop
nop
sub	t5,ra,sp
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x2ac # <test_24+0x4>
li	t4,4
li	gp,24
bne	t5,t4,0x4c8 # <fail>


li	tp,0
li	ra,13
nop
li	sp,11
sub	t5,ra,sp
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x2dc # <test_25+0x4>
li	t4,2
li	gp,25
bne	t5,t4,0x4c8 # <fail>


li	tp,0
li	ra,14
nop
li	sp,11
nop
sub	t5,ra,sp
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x308 # <test_26+0x4>
li	t4,3
li	gp,26
bne	t5,t4,0x4c8 # <fail>


li	tp,0
li	ra,15
nop
nop
li	sp,11
sub	t5,ra,sp
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x338 # <test_27+0x4>
li	t4,4
li	gp,27
bne	t5,t4,0x4c8 # <fail>


li	tp,0
li	sp,11
li	ra,13
sub	t5,ra,sp
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x368 # <test_28+0x4>
li	t4,2
li	gp,28
bne	t5,t4,0x4c8 # <fail>


li	tp,0
li	sp,11
li	ra,14
nop
sub	t5,ra,sp
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x390 # <test_29+0x4>
li	t4,3
li	gp,29
bne	t5,t4,0x4c8 # <fail>


li	tp,0
li	sp,11
li	ra,15
nop
nop
sub	t5,ra,sp
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x3bc # <test_30+0x4>
li	t4,4
li	gp,30
bne	t5,t4,0x4c8 # <fail>


li	tp,0
li	sp,11
nop
li	ra,13
sub	t5,ra,sp
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x3ec # <test_31+0x4>
li	t4,2
li	gp,31
bne	t5,t4,0x4c8 # <fail>


li	tp,0
li	sp,11
nop
li	ra,14
nop
sub	t5,ra,sp
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x418 # <test_32+0x4>
li	t4,3
li	gp,32
bne	t5,t4,0x4c8 # <fail>


li	tp,0
li	sp,11
nop
nop
li	ra,15
sub	t5,ra,sp
addi	tp,tp,1 # 1 # <_start+0x1>
li	t0,2
bne	tp,t0,0x448 # <test_33+0x4>
li	t4,4
li	gp,33
bne	t5,t4,0x4c8 # <fail>


li	ra,-15
neg	sp,ra
li	t4,15
li	gp,34
bne	sp,t4,0x4c8 # <fail>


li	ra,32
sub	sp,ra,zero
li	t4,32
li	gp,35
bne	sp,t4,0x4c8 # <fail>


neg	ra,zero
li	t4,0
li	gp,36
bne	ra,t4,0x4c8 # <fail>


li	ra,16
li	sp,30
sub	zero,ra,sp
li	t4,0
li	gp,37
bne	zero,t4,0x4c8 # <fail>
bne	zero,gp,0x4d4 # <pass>


li	s10,1
li	s11,0


j	0x4d0 # <loop_fail>


li	s10,1
li	s11,1


j	0x4dc # <loop_pass>
