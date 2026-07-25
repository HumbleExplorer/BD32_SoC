# div_mul_fwd.S
# Isolate the DIV→MUL forwarding issue.
# Test A: DIVU then MUL (no REMU) - does MUL read DIV result correctly?
# Test B: DIVU then REMU then MUL - does REMU presence break MUL?

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ============================================================
  # Test A: DIVU → 3 NOPs → MUL (no REMU)
  # x10 = 100/7 = 14, x11 = 0x1234 * 14 = 0xFED8
  # ============================================================
  li   x3, 1
  li   x17, 100
  li   x12, 7
  li   x13, 0x1234

  divu x10, x17, x12    # x10 = 14
  nop
  nop
  nop
  mul  x11, x13, x10    # x11 = 0x1234 * 14 = 0xFED8

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

  # ============================================================
  # Test B: DIVU → 3 ALU → REMU → MUL (exact __udivdi3 pattern)
  # ============================================================
  li   x3, 3
  li   x17, 100
  li   x12, 7
  li   x16, 0xABCD1234
  li   x15, 0x56780000
  li   x10, 0            # clear x10
  li   x11, 0            # clear x11
  li   x13, 0            # clear x13

  divu x10, x17, x12    # x10 = 14
  slli x13, x16, 16     # independent
  srli x13, x13, 16     # x13 = 0x1234
  srli x14, x15, 16     # x14 = 0x5678
  remu x17, x17, x12    # x17 = 2
  mul  x11, x13, x10    # x11 = 0x1234 * 14 = 0xFED8

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
  li   x28, 2
  bne  x17, x28, fail
  li   x3, 5
  li   x28, 0x1234
  bne  x13, x28, fail
  li   x3, 6
  li   x28, 0xFED8
  bne  x11, x28, fail

  # ============================================================
  # Test C: DIVU → REMU → MUL (no independent insns between)
  # ============================================================
  li   x3, 7
  li   x17, 100
  li   x12, 7
  li   x13, 0x1234
  li   x10, 0
  li   x11, 0

  divu x10, x17, x12    # x10 = 14
  remu x17, x17, x12    # x17 = 2 (immediately after DIVU)
  mul  x11, x13, x10    # x11 = 0x1234 * 14

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
  li   x3, 8
  li   x28, 2
  bne  x17, x28, fail
  li   x3, 9
  li   x28, 0xFED8
  bne  x11, x28, fail

  # ============================================================
  # Test D: DIVU → MUL immediately (no REMU, no NOP)
  # ============================================================
  li   x3, 10
  li   x17, 100
  li   x12, 7
  li   x13, 0x1234
  li   x10, 0
  li   x11, 0

  divu x10, x17, x12    # x10 = 14
  mul  x11, x13, x10    # x11 = 0x1234 * 14 (immediately reads DIV result)

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
  li   x3, 11
  li   x28, 0xFED8
  bne  x11, x28, fail

  # ============================================================
  # All passed
  # ============================================================
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
