# div_mul_long_gap.S
# Only test: DIVU → 40 NOP → MUL. If this passes, bug is in RAW forwarding.

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  li   x3, 1
  li   x17, 100
  li   x12, 7
  li   x13, 0x1234
  li   x10, 0
  li   x11, 0

  divu x10, x17, x12
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  mul  x11, x13, x10

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 14
  bne  x10, x28, fail
  li   x3, 2
  li   x28, 0xFED8
  bne  x11, x28, fail

  li   x27, 1
  li   x26, 1
p: j p
fail:
  li   x27, 0
  li   x26, 1
fl: j fl

  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
