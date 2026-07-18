# mulh_only.S - isolate MULH / MULHU / MULHSU. x26 armed only at pass/fail.
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0

  # mulh (signed high): (-2^31)*(-2^31) high = 0x40000000
  li x10, 0x80000000
  li x11, 0x80000000
  mulh x12, x10, x11
  li x13, 0x40000000
  bne x12, x13, f_mulh

  # mulhu: same = 0x40000000
  mulhu x12, x10, x11
  bne x12, x13, f_mulhu

  # mulhsu: a signed(-2^31) * b unsigned(2^31) = -2^62 -> high word = 0xC0000000
  mulhsu x12, x10, x11
  li x14, 0xC0000000
  bne x12, x14, f_mulhsu

  li x27, 1
  li x26, 1
p: j p

f_mulh:   li x3, 1; j rf
f_mulhu:  li x3, 2; j rf
f_mulhsu: li x3, 3; j rf
rf: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
