# div_only.S - isolate DIV/DIVU/REM/REMU. x26 armed only at pass/fail.
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0

  # divu: 100/7 = 14
  li x10, 100
  li x11, 7
  divu x12, x10, x11
  li x13, 14
  bne x12, x13, f_divu

  # remu: 100%7 = 2
  remu x12, x10, x11
  li x13, 2
  bne x12, x13, f_remu

  # div (signed): -100/7 = -14
  li x10, -100
  li x11, 7
  div x12, x10, x11
  li x13, -14
  bne x12, x13, f_div

  # rem (signed): -100%7 = -2
  rem x12, x10, x11
  li x13, -2
  bne x12, x13, f_rem

  li x27, 1
  li x26, 1
p: j p

f_divu: li x3, 1; j rf
f_remu: li x3, 2; j rf
f_div:  li x3, 3; j rf
f_rem:  li x3, 4; j rf
rf: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
