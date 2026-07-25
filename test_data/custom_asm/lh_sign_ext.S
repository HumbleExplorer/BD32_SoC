# lh_sign_ext.S
# 验证: 负数半字/字节 load 的符号扩展（coremark list 的 data16 是 ee_s16 有符号
# 半字，calc_func 对其做 >>/&0xff00 等位操作，对负数极敏感）。
# dtcm_stress 只测了正数半字，未覆盖负数符号扩展。

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  li t0, 0x00019000

  # ---- 用例1: 低半字为 0x8000 (负半字), lh 应符号扩展为 0xFFFF8000 ----
  li t1, 0x00008000
  sw t1, 0(t0)
  lh t2, 0(t0)          # lh(0x8000) 应 = 0xFFFF8000
  li t3, 0xFFFF8000
  bne t2, t3, fail

  # ---- 用例2: 同地址 lhu 应零扩展为 0x00008000 ----
  lhu t4, 0(t0)         # lhu(0x8000) 应 = 0x00008000
  li t5, 0x00008000
  bne t4, t5, fail

  # ---- 用例3: 高半字为 0x8000 (offset 2), lh 符号扩展 ----
  li t1, 0x80001234     # 高半字 0x8000, 低半字 0x1234
  sw t1, 0(t0)
  lh t6, 2(t0)          # lh @offset2 = 高半字 0x8000 -> 0xFFFF8000
  li t3, 0xFFFF8000
  bne t6, t3, fail

  # ---- 用例4: 低半字 0x1234 (正), lh 应为 0x00001234 ----
  lh a0, 0(t0)          # lh @offset0 = 低半字 0x1234 -> 0x00001234
  li t3, 0x00001234
  bne a0, t3, fail

  # ---- 用例5: 负数字节 lb (offset 0 = 0x80) ----
  li t1, 0x00000080
  sw t1, 0(t0)
  lb a1, 0(t0)          # lb(0x80) 应 = 0xFFFFFF80
  li t3, 0xFFFFFF80
  bne a1, t3, fail

  # ---- 用例6: 同地址 lbu 零扩展 ----
  lbu a2, 0(t0)         # lbu(0x80) 应 = 0x00000080
  li t3, 0x00000080
  bne a2, t3, fail

  # ---- 用例7: 负数字节 lb 在 offset 3 (0x80 在最高字节) ----
  li t1, 0x80000000
  sw t1, 0(t0)
  lb a3, 3(t0)          # lb @offset3 = 0x80 -> 0xFFFFFF80
  li t3, 0xFFFFFF80
  bne a3, t3, fail

  # ---- 用例8: 负数半字参与算术右移 (calc_func 的 >>7 模式) ----
  li t1, 0x0000FF80     # data16 = 0xFF80 (负数, bit15=1)
  sw t1, 0(t0)
  lh a4, 0(t0)          # a4 = 0xFFFFFF80
  srai a5, a4, 7        # a5 = 0xFFFFFF80 >> 7 = 0xFFFFFFFF (算术右移)
  li t3, 0xFFFFFFFF
  bne a5, t3, fail

  # PASS
  li x27, 1
  li x26, 1
p: j p

fail:
  li x27, 0
  li x26, 1
fl: j fl

  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
