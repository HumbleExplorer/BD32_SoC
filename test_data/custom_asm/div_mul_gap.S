# div_mul_gap.S
# Test: does adding enough gap between DIVU and MUL fix the result?
# If yes → RAW stall/forwarding bug. If no → multiplier bug.

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # Test 1: DIVU → 3 NOP → MUL (short gap, likely still in divider)
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

  li   x28, 14
  bne  x10, x28, fail
  li   x3, 2
  li   x28, 0xFED8
  bne  x11, x28, fail

  # Test 2: DIVU → 40 NOP → MUL (long gap, divider definitely done)
  li   x3, 3
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
  li   x3, 4
  li   x28, 0xFED8
  bne  x11, x28, fail

  # All passed
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
