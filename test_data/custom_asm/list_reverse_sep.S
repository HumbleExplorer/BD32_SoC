# list_reverse_sep.S - SAME as list_reverse BUT list placed at 0x2B000 (DTCM tag 0x0002),
# i.e. the SEPARATED ITCM/DTCM mapping that coremark (soc_test) actually uses.
# Run with SoC_Config CORE_TEST DTCM_BASE_TAG temporarily = 0x0002.
# If this FAILS while list_reverse (0x1B000, tag 0x0001) passes, the separated
# DTCM mapping has a hidden store/load bug.

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  li x2, 0x2B000
  li x3, 0x2B008
  sw x3, 0(x2)
  li x4, 1
  sw x4, 4(x2)
  li x5, 0x2B010
  sw x5, 0(x3)
  li x6, 2
  sw x6, 4(x3)
  li x7, 0x2B018
  sw x7, 0(x5)
  li x8, 3
  sw x8, 4(x5)
  sw x0, 0(x7)
  li x9, 4
  sw x9, 4(x7)

  li x10, 0
  li x11, 0x2B000
revloop:
  beq x11, x0, revdone
  lw x12, 0(x11)
  sw x10, 0(x11)
  mv x10, x11
  mv x11, x12
  j revloop
revdone:
  li x13, 0
trav:
  beq x10, x0, check
  lw x14, 4(x10)
  add x13, x13, x14
  lw x10, 0(x10)
  j trav
check:
  li x15, 10
  bne x13, x15, failREV

  li x26, 1
  li x27, 1
pass_loop:
  j pass_loop

failREV:
  li x26, 1
  li x27, 0
  li gp, 32
fail_loop:
  j fail_loop

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
