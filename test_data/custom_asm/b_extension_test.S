# b_extension_test.S - Zba/Zbb/Zbs 位操作扩展功能测试 + Zcb 的 Zbb 依赖编码
#
# custom_asm 以 rv32im 汇编（无 B 助记符），因此用 .word 直接嵌入 32 位 B 指令编码；
# 编码用 xpack gcc 15.2.0 (-march=rv32im_zba_zbb_zbs) 汇编 + objdump 得到，寄存器固定：
#   sh1add a0,a1,a2  0x20c5a533    sh2add a3,a4,a5  0x20f746b3
#   sh3add a0,a1,a2  0x20c5e533    andn   a0,a1,a2  0x40c5f533
#   orn    a3,a4,a5  0x40f766b3    xnor   a0,a1,a2  0x40c5c533
#   min    a0,a1,a2  0x0ac5c533    minu   a3,a4,a5  0x0af756b3
#   max    a0,a1,a2  0x0ac5e533    maxu   a3,a4,a5  0x0af776b3
#   rol    a0,a1,a2  0x60c59533    ror    a3,a4,a5  0x60f756b3
#   orc.b  a0,a1     0x2875d513    rev8   a0,a1     0x6985d513
#   clz    a0,a1     0x60059513    ctz    a3,a4     0x60171693
#   cpop   a0,a1     0x60259513    sext.b a0,a1     0x60459513
#   sext.h a3,a4     0x60571693    zext.h a0,a1     0x0805c533
#   bset   a0,a1,a2  0x28c59533    bclr   a3,a4,a5  0x48f716b3
#   binv   a0,a1,a2  0x68c59533    bext   a3,a4,a5  0x48f756b3
#   bseti  a0,a1,5   0x28559513    bclri  a3,a4,17  0x49171693
#   binvi  a0,a1,31  0x69f59513    bexti  a3,a4,9   0x48975693
# Zcb(Zbb 依赖)：c.zext.h a0=0x9d69  c.sext.b a0=0x9d65  c.sext.h a4=0x9f6d
#
# 注意：写 a3(x13) 的指令结果用 t0(x5) 比对，避免"先 li x13 再自比较"。
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0

  # ---- 1) Zba: sh1add/sh2add/sh3add（3<<n + 5）----
  li a1, 3
  li a2, 5
  .word 0x20c5a533            # sh1add a0,a1,a2 -> 11
  li x13, 11
  bne a0, x13, fail
  li x3, 1
  li a4, 3
  li a5, 5
  .word 0x20f746b3            # sh2add a3,a4,a5 -> 17
  li t0, 17
  bne a3, t0, fail
  li x3, 2
  li a1, 3
  li a2, 5
  .word 0x20c5e533            # sh3add a0,a1,a2 -> 29
  li x13, 29
  bne a0, x13, fail

  # ---- 2) Zbb 逻辑：andn/orn/xnor ----
  li x3, 3
  li a1, 0xF0F0F0F0
  li a2, 0xFF00FF00
  .word 0x40c5f533            # andn a0,a1,a2 -> 0x00F000F0
  li x13, 0x00F000F0
  bne a0, x13, fail
  li x3, 4
  li a4, 0xF0F0F0F0
  li a5, 0xFF00FF00
  .word 0x40f766b3            # orn a3,a4,a5 -> 0xF0FFF0FF
  li t0, 0xF0FFF0FF
  bne a3, t0, fail
  li x3, 5
  li a1, 0xF0F0F0F0
  li a2, 0x0F0F0F0F
  .word 0x40c5c533            # xnor a0,a1,a2 -> 0
  li x13, 0
  bne a0, x13, fail

  # ---- 3) Zbb 极值：min/minu/max/maxu ----
  li x3, 6
  li a1, 5
  li a2, -3
  .word 0x0ac5c533            # min a0,a1,a2 -> -3 (0xFFFFFFFD)
  li x13, 0xFFFFFFFD
  bne a0, x13, fail
  li x3, 7
  li a4, 0xFFFFFFFF
  li a5, 5
  .word 0x0af756b3            # minu a3,a4,a5 -> 5
  li t0, 5
  bne a3, t0, fail
  li x3, 8
  li a1, 5
  li a2, -3
  .word 0x0ac5e533            # max a0,a1,a2 -> 5
  li x13, 5
  bne a0, x13, fail
  li x3, 9
  li a4, 0xFFFFFFFF
  li a5, 5
  .word 0x0af776b3            # maxu a3,a4,a5 -> 0xFFFFFFFF
  li t0, 0xFFFFFFFF
  bne a3, t0, fail

  # ---- 4) Zbb 旋转：rol/ror（含 shift=0 边界）----
  li x3, 10
  li a1, 0x80000001
  li a2, 1
  .word 0x60c59533            # rol a0,a1,a2 -> 0x00000003
  li x13, 0x00000003
  bne a0, x13, fail
  li x3, 11
  li a4, 0x80000001
  li a5, 1
  .word 0x60f756b3            # ror a3,a4,a5 -> 0xC0000000
  li t0, 0xC0000000
  bne a3, t0, fail
  li x3, 12
  li a1, 0x12345678
  li a2, 0
  .word 0x60c59533            # rol a0,a1,x0 -> 0x12345678
  li x13, 0x12345678
  bne a0, x13, fail

  # ---- 5) Zbb orc.b / rev8 ----
  li x3, 13
  li a1, 0x00010203
  .word 0x2875d513            # orc.b a0,a1 -> 0x00FFFFFF
  li x13, 0x00FFFFFF
  bne a0, x13, fail
  li x3, 14
  li a1, 0x11223344
  .word 0x6985d513            # rev8 a0,a1 -> 0x44332211
  li x13, 0x44332211
  bne a0, x13, fail

  # ---- 6) Zbb 位计数：clz/ctz/cpop（clz(0)=32 边界）----
  li x3, 15
  li a1, 0x0F000000
  .word 0x60059513            # clz a0,a1 -> 4
  li x13, 4
  bne a0, x13, fail
  li x3, 16
  li a1, 0
  .word 0x60059513            # clz a0,x0 -> 32
  li x13, 32
  bne a0, x13, fail
  li x3, 17
  li a4, 0x00000010
  .word 0x60171693            # ctz a3,a4 -> 4
  li t0, 4
  bne a3, t0, fail
  li x3, 18
  li a1, 0x0F0F0F0F
  .word 0x60259513            # cpop a0,a1 -> 16
  li x13, 16
  bne a0, x13, fail

  # ---- 7) Zbb 符号/零扩展 ----
  li x3, 19
  li a1, 0x00000080
  .word 0x60459513            # sext.b a0,a1 -> 0xFFFFFF80
  li x13, 0xFFFFFF80
  bne a0, x13, fail
  li x3, 20
  li a4, 0x00008000
  .word 0x60571693            # sext.h a3,a4 -> 0xFFFF8000
  li t0, 0xFFFF8000
  bne a3, t0, fail
  li x3, 21
  li a1, 0xFFFF8000
  .word 0x0805c533            # zext.h a0,a1 -> 0x00008000
  li x13, 0x00008000
  bne a0, x13, fail

  # ---- 8) Zbs 单比特：寄存器形式 ----
  li x3, 22
  li a1, 1
  li a2, 5
  .word 0x28c59533            # bset a0,a1,a2 -> 0x21
  li x13, 0x21
  bne a0, x13, fail
  li x3, 23
  li a4, 0x21
  li a5, 5
  .word 0x48f716b3            # bclr a3,a4,a5 -> 1
  li t0, 1
  bne a3, t0, fail
  li x3, 24
  li a1, 0x21
  li a2, 5
  .word 0x68c59533            # binv a0,a1,a2 -> 1
  li x13, 1
  bne a0, x13, fail
  li x3, 25
  li a4, 0x21
  li a5, 5
  .word 0x48f756b3            # bext a3,a4,a5 -> 1
  li t0, 1
  bne a3, t0, fail

  # ---- 9) Zbs 单比特：立即数形式 ----
  li x3, 26
  li a1, 1
  .word 0x28559513            # bseti a0,a1,5 -> 0x21
  li x13, 0x21
  bne a0, x13, fail
  li x3, 27
  li a4, 0x00020001
  .word 0x49171693            # bclri a3,a4,17 -> 1
  li t0, 1
  bne a3, t0, fail
  li x3, 28
  li a1, 1
  .word 0x69f59513            # binvi a0,a1,31 -> 0x80000001
  li x13, 0x80000001
  bne a0, x13, fail
  li x3, 29
  li a4, 0x00000200
  .word 0x48975693            # bexti a3,a4,9 -> 1
  li t0, 1
  bne a3, t0, fail

  # ---- 10) Zcb 的 Zbb 依赖编码（c.zext.h / c.sext.b / c.sext.h）----
  li x3, 30
  li a0, 0x1234FFFF
  .word 0x00019d69            # nop; c.zext.h a0 -> 0x0000FFFF
  li x13, 0x0000FFFF
  bne a0, x13, fail
  li x3, 31
  li a0, 0x12345680
  .word 0x00019d65            # nop; c.sext.b a0 -> 0xFFFFFF80
  li x13, 0xFFFFFF80
  bne a0, x13, fail
  li x3, 32
  li a4, 0x12348000
  .word 0x00019f6d            # nop; c.sext.h a4 -> 0xFFFF8000
  li t0, 0xFFFF8000
  bne a4, t0, fail

  # ---- 11) 依赖链（数据前递）：sh1add -> andn -> min ----
  li x3, 33
  li a1, 3
  li a2, 5
  .word 0x20c5a533            # sh1add a0,a1,a2 -> 11
  mv a1, a0                   # a1 = 11
  li a2, 0x0000000F
  .word 0x40c5f533            # andn a0,a1,a2 -> 11 & ~0xF = 0
  mv a1, a0                   # a1 = 0
  li a2, 7
  .word 0x0ac5c533            # min a0,a1,a2 -> min(0,7) = 0
  li x13, 0
  bne a0, x13, fail

  # ---- 12) 依赖链 2：clz -> cpop -> rol ----
  li x3, 34
  li a1, 0x0FF00000
  .word 0x60059513            # clz a0,a1 -> 4
  mv a1, a0                   # a1 = 4
  .word 0x60259513            # cpop a0,a1 -> cpop(4)=1
  mv a1, a0                   # a1 = 1
  li a2, 3
  .word 0x60c59533            # rol a0,a1,a2 -> 1<<3 = 8
  li x13, 8
  bne a0, x13, fail

  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
