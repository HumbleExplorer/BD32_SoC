# zcmp_r15_80.S - 聚焦测试：cm.push/cm.popret {ra,s0-s11}, ±80（rlist=15, spimm=01）
#
# 复现 rt_vsnprintf 的帧模式（0xb8f6 / 0xbef6）：13 个寄存器 + 80 字节帧 +
# sp 相对局部变量。验证 push 后寄存器保存、sp 局部读写、popret 全恢复 + 跳转。
# 编码：cm.push {ra,s0-s11},-80 = 0xb8f6；cm.popret {ra,s0-s11},80 = 0xbef6
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0

  # ---- 1) push 后逐项验证内存布局与 sp ----
  li sp, 0x1B000
  la ra, after_popret          # ra 保存跳回地址
  li s0, 0x22
  li s1, 0x33
  li s2, 0x44
  li s3, 0x55
  li s4, 0x66
  li s5, 0x77
  li s6, 0x88
  li s7, 0x99
  li s8, 0xAA
  li s9, 0xBB
  li s10, 0xCC
  li s11, 0xDD
  .word 0x0001b8f6            # nop; cm.push {ra,s0-s11},-80
  li t0, 0x1AFB0              # 0x1B000 - 80
  bne sp, t0, fail
  # 布局：s11@sp'-4(=sp+76)，s10@sp+72，...，s0@sp+32，ra@sp+28
  li x3, 1
  lw t1, 76(sp); li t0, 0xDD; bne t1, t0, fail   # s11
  li x3, 2
  lw t1, 32(sp); li t0, 0x22; bne t1, t0, fail   # s0
  li x3, 3
  lw t1, 28(sp)                # ra 在 sp+28（内容为代码地址，仅验证非 0）
  beqz t1, fail

  # ---- 2) 破坏寄存器后 cm.popret 恢复 + 跳转 ----
  li x3, 4
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
  .word 0x0001bef6            # nop; cm.popret {ra,s0-s11},80
after_popret:
  # ra 已恢复为 after_popret（跳转成功即证明）
  li x3, 5
  li t0, 0x22; bne s0, t0, fail
  li x3, 6
  li t0, 0x33; bne s1, t0, fail
  li x3, 7
  li t0, 0x44; bne s2, t0, fail
  li x3, 8
  li t0, 0x55; bne s3, t0, fail
  li x3, 9
  li t0, 0x66; bne s4, t0, fail
  li x3, 10
  li t0, 0x77; bne s5, t0, fail
  li x3, 11
  li t0, 0x88; bne s6, t0, fail
  li x3, 12
  li t0, 0x99; bne s7, t0, fail
  li x3, 13
  li t0, 0xAA; bne s8, t0, fail
  li x3, 14
  li t0, 0xBB; bne s9, t0, fail
  li x3, 15
  li t0, 0xCC; bne s10, t0, fail
  li x3, 16
  li t0, 0xDD; bne s11, t0, fail
  li x3, 17
  li t0, 0x1B000; bne sp, t0, fail   # sp 恢复

  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
