# j_over_data.S - isolate: does `j` over data work when preceded by a NON-branch?
# x27=1 pass / x27=0 fail; x3 = 1 if fell into litpool (bad)
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN
  li x3, 0
  li x5, 0xCAFEBABE   # x5 holds expected; ensures a non-branch instr before j
  j skip_lit
litpool:
  .word 0xCAFEBABE
skip_lit:
  li x27, 1
  li x26, 1
p: j p
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
