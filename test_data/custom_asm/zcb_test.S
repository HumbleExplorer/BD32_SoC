# zcb_test.S - Zcb 压缩字节/半字 load/store + c.zext.b/c.not/c.mul 功能测试
#
# 汇编器以 rv32im 模式构建（无 c 助记符），因此用 .word 直接嵌入 Zcb 的
# 16 位编码，低半字为被测指令、高半字用 C.NOP(0x0001) 填充：
#   c.lbu a0,{0,1,2,3}(a1) : 0x8188/0x81c8/0x81a8/0x81e8
#   c.lhu a0,{0,2}(a1)     : 0x8588/0x85a8
#   c.lh  a0,{0,2}(a1)     : 0x85c8/0x85e8（有符号半字）
#   c.sb  a0,{0,1,2,3}(a1) : 0x8988/0x89c8/0x89a8/0x89e8
#   c.sh  a0,{0,2}(a1)     : 0x8d88/0x8da8
#   c.zext.b a0            : 0x9d61
#   c.not  a0              : 0x9d75
#   c.mul  a0,a1           : 0x9d4d
# 编码位域：C0 [15:13]=100、[12:10] 区分 lbu/lhu/lh/sb/sh、uimm[1:0]={i5,i6}；
#          C1 MISC-ALU {i12,i6:5}=110→c.mul、111 按 i[4:2] 区分 zext.b(000)/not(101)。
#
# 数据区 0x1B000：78 56 34 12 | 0F 5A C3 A5 | 01 00 00 80（0x80000001 小端）
# 判定：x3=失败子测试号，x27=0/x26=1 失败，x27=1/x26=1 通过。
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0

  # ---- 数据区初始化 ----
  li a1, 0x1B000
  li t0, 0x12345678
  sw t0, 0(a1)                # 78 56 34 12
  li t0, 0xA5C35A0F
  sw t0, 4(a1)                # 0F 5A C3 A5
  li t0, 0x80000001
  sw t0, 8(a1)                # 01 00 00 80（供 c.lh 符号扩展）

  # ---- 1) c.lbu 偏移 0/1/2/3 ----
  li x13, 0x78
  .word 0x00018188            # nop; c.lbu a0,0(a1)
  bne a0, x13, fail
  li x3, 1
  li x13, 0x56
  .word 0x000181c8            # nop; c.lbu a0,1(a1)
  bne a0, x13, fail
  li x3, 2
  li x13, 0x34
  .word 0x000181a8            # nop; c.lbu a0,2(a1)
  bne a0, x13, fail
  li x3, 3
  li x13, 0x12
  .word 0x000181e8            # nop; c.lbu a0,3(a1)
  bne a0, x13, fail

  # ---- 2) c.lhu 偏移 0/2（无符号半字）----
  li x3, 4
  li x13, 0x5678
  .word 0x00018588            # nop; c.lhu a0,0(a1)
  bne a0, x13, fail
  li x3, 5
  li x13, 0x1234
  .word 0x000185a8            # nop; c.lhu a0,2(a1)
  bne a0, x13, fail

  # ---- 3) c.lh 偏移 0/2（有符号半字）----
  li x3, 6
  li x13, 0x5678
  .word 0x000185c8            # nop; c.lh a0,0(a1)
  bne a0, x13, fail
  li x3, 7
  li x13, 0x1234
  .word 0x000185e8            # nop; c.lh a0,2(a1)
  bne a0, x13, fail

  # 负半字：base+8 处字节 01 00 00 80，偏移 2 的半字 0x8000 -> 0xFFFF8000
  li x3, 8
  addi a1, a1, 8
  li x13, 0x0001
  .word 0x00018588            # nop; c.lhu a0,0(a1)
  bne a0, x13, fail
  li x3, 9
  li x13, 0xFFFF8000
  .word 0x000185e8            # nop; c.lh a0,2(a1)
  bne a0, x13, fail
  addi a1, a1, -8

  # ---- 4) c.sb 偏移 0/1/2/3，写入后 32 位 lbu 回读 ----
  li x3, 10
  addi a1, a1, 16             # a1 = 0x1B010
  li a0, 0x11
  .word 0x00018988            # nop; c.sb a0,0(a1)
  li a0, 0x22
  .word 0x000189c8            # nop; c.sb a0,1(a1)
  li a0, 0x33
  .word 0x000189a8            # nop; c.sb a0,2(a1)
  li a0, 0x44
  .word 0x000189e8            # nop; c.sb a0,3(a1)
  lbu t0, 0(a1)
  li x13, 0x11
  bne t0, x13, fail
  li x3, 11
  lbu t0, 1(a1)
  li x13, 0x22
  bne t0, x13, fail
  li x3, 12
  lbu t0, 2(a1)
  li x13, 0x33
  bne t0, x13, fail
  li x3, 13
  lbu t0, 3(a1)
  li x13, 0x44
  bne t0, x13, fail

  # ---- 5) c.sh 偏移 0/2，写入后 32 位 lhu 回读 ----
  li x3, 14
  addi a1, a1, 16             # a1 = 0x1B020
  li a0, 0x1122
  .word 0x00018d88            # nop; c.sh a0,0(a1)
  li a0, 0x3344
  .word 0x00018da8            # nop; c.sh a0,2(a1)
  lhu t0, 0(a1)
  li x13, 0x1122
  bne t0, x13, fail
  li x3, 15
  lhu t0, 2(a1)
  li x13, 0x3344
  bne t0, x13, fail

  # ---- 6) c.zext.b / c.not ----
  li x3, 16
  li a0, 0x12345678
  .word 0x00019d61            # nop; c.zext.b a0 -> 0x78
  li x13, 0x78
  bne a0, x13, fail
  li x3, 17
  .word 0x00019d75            # nop; c.not a0 -> 0xFFFFFF87
  li x13, 0xFFFFFF87
  bne a0, x13, fail

  # ---- 7) c.mul（走 M 扩展 3 级流水 + OITF）----
  li x3, 18
  li a0, 7
  li a1, 6
  .word 0x00019d4d            # nop; c.mul a0,a1 -> 42
  li x13, 42
  bne a0, x13, fail
  # 背靠背 c.mul：7*6=42；42*5=210
  li x3, 19
  li a1, 5
  .word 0x00019d4d            # nop; c.mul a0,a1（a0=42, a1=5）
  li x13, 210
  bne a0, x13, fail

  # ---- 8) rd'=rs1' 别名：c.lbu a0,0(a0) ----
  li x3, 20
  li a0, 0x1B000
  .word 0x00018108            # nop; c.lbu a0,0(a0) -> 0x78（rs1'=rd'=a0）
  li x13, 0x78
  bne a0, x13, fail

  # ---- 9) rs2'=rs1' 别名：c.sb a0,0(a0) 写回 a0 低字节 ----
  li x3, 21
  li a0, 0x1B030
  .word 0x00018908            # nop; c.sb a0,0(a0) -> 写 0x30 到 0x1B030
  li t0, 0x1B030
  lbu t1, 0(t0)
  li x13, 0x30
  bne t1, x13, fail

  # ---- 10) 连续 3 条 16 位（跨字装配）：zext.b -> not -> zext.b ----
  li x3, 22
  li a0, 0x12345678
  .word 0x9d759d61            # c.zext.b a0; c.not a0 -> 0x78 -> 0xFFFFFF87
  .word 0x00019d61            # nop; c.zext.b a0 -> 0x87
  li x13, 0x87
  bne a0, x13, fail

  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
