# oitf_dual_reader.S - Test OITF retire forwarding to two consecutive readers
# of the same register.
#
# Bug: When a MUL/DIV retires from OITF, Port2 writes the register file at
# posedge. The instruction in EX (first reader) gets the OITF forward correctly.
# But the instruction in ID (second reader) reads the register file BEFORE the
# Port2 write takes effect, getting the stale value. In the next cycle (EX),
# the OITF retire pulse is gone, so no forwarding corrects it.
#
# Pattern: mul a5 → srai a6,a5 → srai a7,a5 (two consecutive readers of a5)
# Expected: a6 = 20000>>4 = 1250, a7 = 20000>>8 = 78
# Bug:      a7 = OLD_a5 >> 8 = 0x7FFFF000 >> 8 = 8388607
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0

  # Setup: a5 = old value (should NOT appear in results)
  lui a5, 0x7FFFF        # a5 = 0x7FFFF000 (stale value)
  li a1, 100
  li a2, 200

  # MUL writes a5 = 100*200 = 20000 via OITF (3-cycle latency)
  mul a5, a1, a2         # a5 = 20000 (0x4E20)

  # Two CONSECUTIVE readers of a5:
  # First reader (in EX when MUL retires): gets OITF forward → correct
  # Second reader (in ID when MUL retires): reads stale register file → BUG
  srai a6, a5, 4         # a6 = 20000 >> 4 = 1250
  srai a7, a5, 8         # a7 = 20000 >> 8 = 78 (bug gives 8388607)

  # Verify first reader (should always be correct)
  li x13, 1250
  bne a6, x13, fail

  # Verify second reader (fails if bug exists)
  li x14, 78
  bne a7, x14, fail

  # === Test 2: same pattern with different shift amounts ===
  lui a5, 0x12345        # stale a5 = 0x12345000
  li a1, 7
  li a2, 9
  mul a5, a1, a2         # a5 = 63
  srai a6, a5, 1         # a6 = 63 >> 1 = 31
  srai a7, a5, 3         # a7 = 63 >> 3 = 7 (bug: 0x12345000>>3 = 0x02468A00)

  li x13, 31
  bne a6, x13, fail
  li x14, 7
  bne a7, x14, fail

  # === Test 3: three consecutive readers ===
  lui a5, 0xABCDE        # stale a5 = 0xABCDE000
  li a1, 11
  li a2, 13
  mul a5, a1, a2         # a5 = 143
  srai a6, a5, 0         # a6 = 143 (srai by 0 = mv)
  srai a7, a5, 1         # a7 = 143 >> 1 = 71
  srai t0, a5, 2         # t0 = 143 >> 2 = 35

  li x13, 143
  bne a6, x13, fail
  li x14, 71
  bne a7, x14, fail
  li x15, 35
  bne t0, x15, fail

  # === Test 4: reader pair with rs2 usage ===
  lui a5, 0x55555        # stale
  li a1, 50
  li a2, 3
  mul a5, a1, a2         # a5 = 150
  add a6, a5, a5         # a6 = 150 + 150 = 300 (reads a5 as BOTH rs1 and rs2)
  sub a7, a5, a1         # a7 = 150 - 50 = 100 (reads a5 as rs1)

  li x13, 300
  bne a6, x13, fail
  li x14, 100
  bne a7, x14, fail

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
