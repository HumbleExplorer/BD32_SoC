# oitf_waw_port_collision.S
#
# Root cause: RegFile Port1/Port2 write priority bug during oitf_stall.
#
# When oitf_stall holds MEM_WB, a preceding short instruction (li) that writes
# the same register as a retiring OITF entry (divu) remains in WB. On the
# retire cycle, Port1 (li, stale) overwrites Port2 (divu, correct) because
# Port1 has higher priority in RegFile.sv.
#
# Trigger sequence (must be exactly this pipeline alignment):
#   li   rd, IMM       # reaches WB when stall starts
#   divu rd, rd, rs    # dispatches to OITF, 32-cycle division
#   sw   rd, off(sp)   # reads rd -> RAW hazard -> oitf_stall -> holds li in WB
#   ...                # 32 cycles later, divu retires via Port2
#                      # BUT Port1 (li still held) overwrites with stale value!
#   mul  rx, ry, rd   # reads rd -> gets IMM instead of divu result
#
# Expected (correct): x13 = 666 * 3 = 1998
# Buggy behaviour:    x13 = 2000 * 3 = 6000

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ============================================================
  # Test 1: li -> divu -> sw(RAW) -> mul reads divu result
  # This is the exact CoreMark -O3 bug pattern.
  # ============================================================

  li   x2, 0x11000        # sp = data area base (link.ld puts data at 0x11000)
  li   x10, 3             # x10 = divisor
  li   x11, 2000          # x11 = 2000 (will be overwritten by divu)
  divu x11, x11, x10     # x11 = 2000/3 = 666 (OITF, 32 cycles)
  sw   x11, 0(x2)        # reads x11 -> RAW stall -> holds li x11 in WB
  # After divu retires, x11 should be 666
  # Bug: x11 = 2000 (Port1 overwrites Port2)

  # Wait for pipeline to settle (a few NOPs)
  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0

  # Now read x11 via mul (no forwarding source active)
  li   x14, 3
  mul  x13, x11, x14     # x13 = x11 * 3; correct=666*3=1998, bug=2000*3=6000

  # Wait for mul to complete (3-cycle pipeline)
  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0

  li   x28, 1998
  bne  x13, x28, fail1

  # ============================================================
  # Test 2: Same pattern with different values (rem instead of divu)
  # li -> rem -> sw(RAW) -> later read
  # ============================================================

  li   x10, 7             # divisor
  li   x15, 100           # x15 = 100
  rem  x15, x15, x10     # x15 = 100 % 7 = 2 (OITF, 32 cycles)
  sw   x15, 4(x2)        # reads x15 -> RAW stall

  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0

  # Read x15 directly
  li   x28, 2
  bne  x15, x28, fail2

  # ============================================================
  # Test 3: li -> mul(fast 3-cycle) -> sw(RAW) -> later read
  # MUL is faster (3 cycles), tests same mechanism with shorter stall
  # ============================================================

  li   x10, 5
  li   x16, 10            # x16 = 10
  mul  x16, x16, x10     # x16 = 50 (OITF, 3 cycles)
  sw   x16, 8(x2)        # reads x16 -> RAW stall (shorter)

  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0

  li   x28, 50
  bne  x16, x28, fail3

  # ============================================================
  # Test 4: Verify store got correct value (forwarding path)
  # The sw in Test 1 should have stored 666 via OITF forwarding
  # ============================================================

  lw   x17, 0(x2)        # load back what sw stored
  addi x12, x0, 0
  addi x12, x0, 0
  addi x12, x0, 0

  li   x28, 666
  bne  x17, x28, fail4

  # ============================================================
  # All tests passed
  # ============================================================
  li x27, 1
  li x26, 1
pass: j pass

fail1: li x3, 1; li x27, 0; li x26, 1
f1: j f1
fail2: li x3, 2; li x27, 0; li x26, 1
f2: j f2
fail3: li x3, 3; li x27, 0; li x26, 1
f3: j f3
fail4: li x3, 4; li x27, 0; li x26, 1
f4: j f4

  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  .word 0
  .word 0
  .word 0
  RVTEST_DATA_END
