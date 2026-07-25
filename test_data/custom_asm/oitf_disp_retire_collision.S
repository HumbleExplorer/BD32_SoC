# oitf_disp_retire_collision.S
#
# Trigger: OITF single-entry dispatch/retire same-slot collision.
#
# When the OITF has exactly 1 entry (cnt=1, wr_ptr==rd_ptr) and that entry
# is ready (about to retire), a new MUL dispatching in the SAME cycle writes
# to slot wr_ptr.  But the retire logic then clears slot rd_ptr (= wr_ptr),
# overwriting the freshly dispatched entry.  The new MUL's OITF entry is lost:
#   - multiplier still computes the result (3-cycle pipeline)
#   - but unit_wbck_valid finds no valid entry -> result discarded
#   - register file is never written for that MUL
#
# Timing requirement: second MUL must enter EX exactly 3 cycles after the
# first (MUL latency = 3).  This needs exactly 3 independent instructions
# between the two MULs (they pass through EX in 3 cycles while MUL1 matures).
#
# Expected (correct): x6 = 6 * 7 = 42
# Buggy behaviour:    x6 stays 0 (MUL2 result lost, regfile never written)

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  li x1, 3
  li x2, 4
  li x3, 5
  li x6, 6
  li x7, 7

  # ---- critical sequence: 3 independent insns between two MULs ----
  mul  x5, x1, x2       # MUL1: x5 = 12  (dispatched to OITF, 3-cycle)
  add  x10, x1, x3      # independent ALU (EX cycle +1)
  add  x11, x2, x3      # independent ALU (EX cycle +2)
  add  x12, x1, x2      # independent ALU (EX cycle +3)
  mul  x6, x6, x7       # MUL2: x6 = 42  (enters EX when MUL1 ready -> BUG)

  # ---- let MUL2 pipeline finish (3+ cycles) ----
  add  x13, x3, x1
  add  x14, x3, x2
  add  x15, x1, x3
  add  x16, x2, x3
  add  x17, x1, x2
  add  x18, x3, x3

  # ---- check MUL2 result ----
  li   x28, 42
  bne  x6, x28, fail

  # ---- also verify MUL1 result is correct ----
  li   x29, 12
  bne  x5, x29, fail

  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl

  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
