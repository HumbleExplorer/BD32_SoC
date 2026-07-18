# arith_ext.S - exercise MUL/DIV ops coremark uses but bd32 never covered.
# x27=1 pass / x27=0 fail; x26 arms tb check ONLY at the end (pass/fail).
# x3 = failing sub-test code (1..8).
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0

  # ---- mul: 6 * 7 = 42 ----
  li x10, 6
  li x11, 7
  mul x12, x10, x11
  li x13, 42
  bne x12, x13, fail_mul

  # ---- mulh (signed high): (-2^31)*(-2^31) high = 0x40000000 ----
  li x10, 0x80000000
  li x11, 0x80000000
  mulh x12, x10, x11
  li x13, 0x40000000
  bne x12, x13, fail_mulh

  # ---- mulhu (unsigned high): same = 0x40000000 ----
  mulhu x12, x10, x11
  bne x12, x13, fail_mulhu

  # ---- mulhsu: a signed(-2^31) * b unsigned(2^31) = -2^62 -> high word = 0xC0000000 ----
  mulhsu x12, x10, x11
  li x13, 0xC0000000
  bne x12, x13, fail_mulhsu

  # ---- divu: 100 / 7 = 14 ----
  li x10, 100
  li x11, 7
  divu x12, x10, x11
  li x13, 14
  bne x12, x13, fail_divu

  # ---- remu: 100 % 7 = 2 ----
  remu x12, x10, x11
  li x13, 2
  bne x12, x13, fail_remu

  # ---- div (signed): -100 / 7 = -14 ----
  li x10, -100
  li x11, 7
  div x12, x10, x11
  li x13, -14
  bne x12, x13, fail_div

  # ---- rem (signed): -100 % 7 = -2 ----
  rem x12, x10, x11
  li x13, -2
  bne x12, x13, fail_rem

  # all passed
  li x27, 1
  li x26, 1
pass_loop:
  j pass_loop

fail_mul:    li x3, 1;  j report_fail
fail_mulh:   li x3, 2;  j report_fail
fail_mulhu:  li x3, 3;  j report_fail
fail_mulhsu: li x3, 4;  j report_fail
fail_divu:   li x3, 5;  j report_fail
fail_remu:   li x3, 6;  j report_fail
fail_div:    li x3, 7;  j report_fail
fail_rem:    li x3, 8;  j report_fail

report_fail:
  li x27, 0
  li x26, 1
fail_loop:
  j fail_loop

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
