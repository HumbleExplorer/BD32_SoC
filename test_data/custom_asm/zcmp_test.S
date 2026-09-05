# zcmp_test.S - Zcmp 压缩堆栈操作功能测试
#
# custom_asm 以 rv32im 汇编（无 zcmp 助记符），用 .word 嵌入 16 位 Zcmp 编码，
# 高半字用 C.NOP(0x0001) 填充。编码用 GCC 15.2 (-march=rv32imc_zcmp) 实测：
#   cm.push  {ra,s0-s1},-32   0xb866   rlist=6  spimm=01
#   cm.push  {ra},-16         0xb842   rlist=4  spimm=00
#   cm.push  {ra,s0-s11},-112 0xb8fe   rlist=15 spimm=11
#   cm.pop   {ra,s0-s1},32    0xba66
#   cm.pop   {ra},16          0xba42
#   cm.popret {ra,s0-s3},48   0xbe86   rlist=8  spimm=01
#   cm.mvsa01 s0,s1           0xac26
#   cm.mva01s s0,s1           0xac66
#
# 栈基 0x1B000（栈向低地址增长）。push 顺序：最高寄存器先存 sp-4，递减；
# pop 顺序：最高寄存器先从 sp+(adj-4) 载入，递减；SP 调整最后。
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0

  # ---- 1) cm.push {ra,s0-s1},-32：寄存器保存 + sp 调整 ----
  li sp, 0x1B000
  li ra, 0xDEADBEEF
  li s0, 0x11112222
  li s1, 0x33334444
  .word 0x0001b866            # nop; cm.push {ra,s0-s1},-32
  li t0, 0x1AFE0              # 0x1B000 - 32
  bne sp, t0, fail
  li x3, 1
  lw t1, 28(sp)               # s1 @ sp'-4 = sp'+28
  li t0, 0x33334444
  bne t1, t0, fail
  li x3, 2
  lw t1, 24(sp)               # s0 @ sp'-8 = sp'+24
  li t0, 0x11112222
  bne t1, t0, fail
  li x3, 3
  lw t1, 20(sp)               # ra @ sp'-12 = sp'+20
  li t0, 0xDEADBEEF
  bne t1, t0, fail

  # ---- 2) cm.pop {ra,s0-s1},32：恢复寄存器 + sp 调整 ----
  li x3, 4
  li ra, 0
  li s0, 0
  li s1, 0
  .word 0x0001ba66            # nop; cm.pop {ra,s0-s1},32
  li t0, 0xDEADBEEF
  bne ra, t0, fail
  li x3, 5
  li t0, 0x11112222
  bne s0, t0, fail
  li x3, 6
  li t0, 0x33334444
  bne s1, t0, fail
  li t0, 0x1B000
  bne sp, t0, fail

  # ---- 3) cm.push {ra},-16 + cm.pop {ra},16（rlist=4 最小寄存器表）----
  li x3, 7
  li sp, 0x1B000
  li ra, 0x12345678
  .word 0x0001b842            # nop; cm.push {ra},-16
  li t0, 0x1AFF0
  bne sp, t0, fail
  lw t1, 12(sp)
  li t0, 0x12345678
  bne t1, t0, fail
  li x3, 8
  li ra, 0
  .word 0x0001ba42            # nop; cm.pop {ra},16
  li t0, 0x12345678
  bne ra, t0, fail
  li t0, 0x1B000
  bne sp, t0, fail

  # ---- 4) 嵌套 push/pop（两级）----
  li x3, 9
  li sp, 0x1B000
  li ra, 0xAABBCCDD
  li s0, 0x11223344
  .word 0x0001b866            # 外层 push {ra,s0-s1},-32
  li ra, 0x11111111
  li s0, 0x22222222
  li s1, 0x33333333
  .word 0x0001b842            # 内层 push {ra},-16
  li t0, 0x1AFD0              # 0x1B000-32-16
  bne sp, t0, fail
  li x3, 10
  .word 0x0001ba42            # 内层 pop {ra},16
  li t0, 0x11111111
  bne ra, t0, fail
  li x3, 11
  .word 0x0001ba66            # 外层 pop {ra,s0-s1},32
  li t0, 0xAABBCCDD
  bne ra, t0, fail
  li x3, 12
  li t0, 0x11223344
  bne s0, t0, fail
  li t0, 0x33334444
  bne s1, t0, fail
  li t0, 0x1B000
  bne sp, t0, fail

  # ---- 5) cm.mvsa01 / cm.mva01s ----
  li x3, 13
  li a0, 0x11110000
  li a1, 0x22220000
  li s0, 0
  li s1, 0
  .word 0x0001ac26            # nop; cm.mvsa01 s0,s1（a0->s0, a1->s1）
  li t0, 0x11110000
  bne s0, t0, fail
  li x3, 14
  li t0, 0x22220000
  bne s1, t0, fail
  li x3, 15
  li s0, 0x33330000
  li s1, 0x44440000
  .word 0x0001ac66            # nop; cm.mva01s s0,s1（s0->a0, s1->a1）
  li t0, 0x33330000
  bne a0, t0, fail
  li x3, 16
  li t0, 0x44440000
  bne a1, t0, fail

  # ---- 6) cm.push/cm.pop {ra,s0-s11}（rlist=15 满寄存器表，13 次存取）----
  # cm.pop {ra,s0-s11},112 = 0xbafe（rlist=15 spimm=11）
  li x3, 17
  li sp, 0x1B000
  li ra, 0x01
  li s0, 0x02
  li s1, 0x03
  li s2, 0x04
  li s3, 0x05
  li s4, 0x06
  li s5, 0x07
  li s6, 0x08
  li s7, 0x09
  li s8, 0x0A
  li s9, 0x0B
  li s10, 0x0C
  li s11, 0x0D
  .word 0x0001b8fe            # nop; cm.push {ra,s0-s11},-112
  li t0, 0x1AF90              # 0x1B000 - 112
  bne sp, t0, fail
  # s11 @ sp'-4 (=sp+108)，ra @ sp'-52 (=sp+60)
  lw t1, 108(sp)
  li t0, 0x0D
  bne t1, t0, fail
  li x3, 18
  lw t1, 60(sp)
  li t0, 0x01
  bne t1, t0, fail
  li x3, 19
  li ra, 0
  li s0, 0
  li s1, 0
  li s2, 0
  li s3, 0
  li s4, 0
  li s5, 0
  li s6, 0
  li s7, 0
  li s8, 0
  li s9, 0
  li s10, 0
  li s11, 0
  .word 0x0001bafe            # nop; cm.pop {ra,s0-s11},112（13 个寄存器全恢复）
  li t0, 0x01
  bne ra, t0, fail
  li x3, 20
  li t0, 0x02
  bne s0, t0, fail
  li x3, 21
  li t0, 0x0D
  bne s11, t0, fail
  li x3, 22
  li t0, 0x1B000
  bne sp, t0, fail

  # ---- 7) cm.push/cm.popret {ra,s0-s3},48：返回地址跳转 ----
  # cm.push {ra,s0-s3},-48 = 0xb886（rlist=8 spimm=01）
  li x3, 23
  li sp, 0x1B000
  la ra, after_popret
  li s0, 0x0F
  li s1, 0x10
  li s2, 0x11
  li s3, 0x12
  .word 0x0001b886            # nop; cm.push {ra,s0-s3},-48
  li ra, 0xDEADBEEF           # 破坏 ra
  .word 0x0001be86            # nop; cm.popret {ra,s0-s3},48 -> 跳回 after_popret
after_popret:
  li t0, 0x0F
  bne s0, t0, fail
  li x3, 24
  li t0, 0x12
  bne s3, t0, fail
  li x3, 25
  li t0, 0x1B000
  bne sp, t0, fail

  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
