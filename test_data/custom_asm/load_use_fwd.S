# load_use_fwd.S
# Test load-use forwarding with 1-instruction gap.
# Hypothesis: when a load is in MEM and a dependent instruction is in EX
# (with 1 instruction between them), the MEM forwarding provides
# reg_rd_wdata_mem (0 for loads) instead of the actual load data.
#
# Pattern:
#   sw  known_val, offset(sp)   # store known value to DTCM
#   lw  a0, offset(sp)          # load a0 from DTCM
#   addi a1, a1, 0              # gap instruction (independent)
#   add   a2, a0, a3            # uses a0 (should get load result)
#
# If MEM forwarding is broken, a2 gets 0 + a3 instead of load_val + a3.

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ============================================================
  # Test 1: Load → 1 gap → Use (MEM forwarding)
  # Store 0xDEAD to stack, load it back, use with 1 gap
  # ============================================================
  li   x3, 1
  li   x10, 0xDEAD           # value to store
  sw   x10, 0(x2)            # store to stack (DTCM)
  li   x11, 0                # clear a1
  li   x13, 0x100            # a3 = 0x100 (addend)

  lw   x10, 0(x2)            # a0 = load from DTCM (should be 0xDEAD)
  addi x11, x11, 0           # gap: independent instruction
  add  x12, x10, x13         # a2 = a0 + a3 = 0xDEAD + 0x100 = 0xDEAD + 0x100

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0xDEAD + 0x100   # expected: 0xDFAD
  bne  x12, x28, fail        # a2 should be 0xDFAD

  # ============================================================
  # Test 2: Load → 1 gap → Use (rs2 instead of rs1)
  # Same pattern but load value goes to rs2 of dependent inst
  # ============================================================
  li   x3, 2
  li   x10, 0xBEEF
  sw   x10, 4(x2)
  li   x13, 0x200

  lw   x11, 4(x2)            # a1 = load (should be 0xBEEF)
  addi x14, x14, 0           # gap
  sub  x12, x13, x11         # a2 = a3 - a1 = 0x200 - 0xBEEF

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0x200 - 0xBEEF   # expected: 0xFFFF4311 (with underflow)
  bne  x12, x28, fail

  # ============================================================
  # Test 3: Load → 1 gap → Load (chained loads)
  # Second load address depends on first load result
  # ============================================================
  li   x3, 3
  li   x10, 0x12345678
  sw   x10, 8(x2)            # store value at offset 8
  li   x11, 8                # a1 = 8 (offset)
  add  x11, x11, x2          # a1 = sp + 8 (address of stored value)
  sw   x11, 16(x2)           # store address at offset 16

  lw   x10, 16(x2)           # a0 = load address (should be sp+8)
  nop                         # gap
  lw   x12, 0(x10)           # a2 = load from loaded address (should be 0x12345678)

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0x12345678
  bne  x12, x28, fail

  # ============================================================
  # Test 4: Load → 2 gaps → Use (should work via WB forwarding)
  # This is the control test — 2 gaps should always work
  # ============================================================
  li   x3, 4
  li   x10, 0xCAFE
  sw   x10, 20(x2)
  li   x13, 0x300

  lw   x10, 20(x2)           # a0 = load (should be 0xCAFE)
  addi x11, x11, 0           # gap 1
  addi x14, x14, 0           # gap 2
  add  x12, x10, x13         # a2 = a0 + a3 = 0xCAFE + 0x300

  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0xCAFE + 0x300   # expected: 0xCDFE
  bne  x12, x28, fail

  # ============================================================
  # Test 5: Load → 0 gaps → Use (load-use stall, should work)
  # Adjacent load and use — load_use_flag should stall
  # ============================================================
  li   x3, 5
  li   x10, 0xF00D
  sw   x10, 24(x2)
  li   x13, 0x400

  lw   x10, 24(x2)           # a0 = load
  add  x12, x10, x13         # a2 = a0 + a3 (immediately!)

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0xF00D + 0x400   # expected: 0xF40D
  bne  x12, x28, fail

  # ============================================================
  # Test 6: Load → 1 gap → ALU using both loaded and computed values
  # More complex pattern from O3 code
  # ============================================================
  li   x3, 6
  li   x10, 0xAAAA
  sw   x10, 28(x2)
  li   x11, 0x5555
  li   x13, 0x1111

  lw   x10, 28(x2)           # a0 = 0xAAAA (load)
  addi x14, x11, 0           # gap: a4 = a1 = 0x5555
  xor  x12, x10, x13         # a2 = a0 ^ a3 = 0xAAAA ^ 0x1111 = 0xBBBB

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0xBBBB
  bne  x12, x28, fail

  # ============================================================
  # Test 7: Halfword load → 1 gap → Use
  # Tests lh (signed halfword load) forwarding
  # ============================================================
  li   x3, 7
  li   x10, 0xFFFF8765       # value with sign bit in halfword
  sw   x10, 32(x2)

  lh   x10, 32(x2)           # a0 = sign-extended halfword = 0xFFFF8765
  addi x11, x11, 0           # gap
  add  x12, x10, x0          # a2 = a0 + 0 = 0xFFFF8765

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0xFFFF8765
  bne  x12, x28, fail

  # ============================================================
  # Test 8: Byte load → 1 gap → Use
  # Tests lb (signed byte load) forwarding
  # ============================================================
  li   x3, 8
  li   x10, 0xFFFFFF80       # value with sign bit in byte
  sw   x10, 36(x2)

  lb   x10, 36(x2)           # a0 = sign-extended byte = 0xFFFFFF80
  addi x11, x11, 0           # gap
  add  x12, x10, x0          # a2 = a0 + 0 = 0xFFFFFF80

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0xFFFFFF80
  bne  x12, x28, fail

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
