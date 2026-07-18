# jalr_test.S - test jalr whose target is loaded from memory (coremark jump-table pattern)
#
# coremark's big switch in core_state_transition typically compiles to a jump
# table:  lw t, table[idx];  jalr ra, t
# The jalr target (rs1) comes from a freshly-loaded memory entry and MUST be
# forwarded to the EX-stage target computation. If load->jalr-target forwarding
# or the load-use stall is broken, jalr jumps to a stale/wrong address and the
# program can hang or mis-execute -- a failure mode bd32_mul_stress does NOT hit
# (it only uses direct calls + branches).
#
# We build a tiny "jump table" at runtime in DTCM, load an entry, and jalr to it.
# Each callee writes a known value to x8 and returns via jalr ra.

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # scratch region for the jump table (DTCM, CORE_TEST tag 0x0001 -> 0x10000 base)
  li x2, 0x1D000

  # ---- store func addresses into the table ----
  la x3, func0
  sw x3, 0(x2)        # jt[0]
  la x4, func1
  sw x4, 4(x2)        # jt[1]
  la x5, func2
  sw x5, 8(x2)        # jt[2]

  # ---- call func1 via load->jalr (key hazard) ----
  lw x7, 4(x2)        # x7 = jt[1] = func1   (LOAD, result needed by next jalr)
  jalr x1, x7, 0      # call func1; target must equal x7 (LOAD->JALR fwd)
  li x9, 0x1111
  bne x8, x9, failJALR

  # ---- call func2 via load->jalr ----
  lw x7, 8(x2)
  jalr x1, x7, 0
  li x9, 0x2222
  bne x8, x9, failJALR

  # ---- call func0 via load->jalr ----
  lw x7, 0(x2)
  jalr x1, x7, 0
  li x9, 0x0000
  bne x8, x9, failJALR

  # all passed
  li x26, 1
  li x27, 1
pass_loop:
  j pass_loop

failJALR:
  li x26, 1
  li x27, 0
  li gp, 40
fail_loop:
  j fail_loop

  # ---- callees (return via jalr ra) ----
func0:
  li x8, 0x0000
  jalr x0, x1, 0
func1:
  li x8, 0x1111
  jalr x0, x1, 0
func2:
  li x8, 0x2222
  jalr x0, x1, 0

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
