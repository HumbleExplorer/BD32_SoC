# div_rem_mul_oitf.S
#
# Replicate the exact __udivdi3 DIV→REM→MUL cross-unit OITF pattern
# that appears in CoreMark -O3's 64-bit division helper.
#
# Pattern from __udivdi3:
#   divu  a0, a7, a2      # DIV (unit_id=1)
#   slli  a3, a6, 16      # independent ALU
#   srli  a3, a3, 16      # independent ALU
#   srli  a4, a5, 16      # independent ALU
#   remu  a7, a7, a2      # REM (unit_id=1, same rs1/rs2 as DIV)
#   mul   a1, a3, a0      # MUL (unit_id=0, reads DIV result a0)
#
# The OITF must correctly:
#   1. Dispatch DIV, stall REM until divider free
#   2. Retire DIV (write a0), then dispatch REM
#   3. Forward DIV result (a0) to MUL
#   4. Eventually retire REM (write a7) and MUL (write a1)
#
# Test with multiple value sets to stress different timing.

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ============================================================
  # Test 1: Basic DIV→REM→MUL pattern (3 independent insns between)
  # ============================================================
  # a7=100, a2=7 → divu a0=14, remu a7=2
  # a6=0xABCD1234 → slli+srli → a3=0x1234
  # mul a1 = a3 * a0 = 0x1234 * 14 = 0xFE18
  li   x3, 1             # test number
  li   x17, 100          # a7 = dividend
  li   x12, 7            # a2 = divisor
  li   x16, 0xABCD1234   # a6 = source for a3
  li   x15, 0x56780000   # a5 = source for a4

  # --- critical sequence (mirrors __udivdi3 lines 26-31) ---
  divu x10, x17, x12    # a0 = 100/7 = 14
  slli x13, x16, 16     # independent
  srli x13, x13, 16     # a3 = 0x1234
  srli x14, x15, 16     # a4 = 0x5678
  remu x17, x17, x12    # a7 = 100%7 = 2
  mul  x11, x13, x10    # a1 = 0x1234 * 14 = 0xFE18

  # let pipeline settle
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

  # check a0 = 14
  li   x28, 14
  bne  x10, x28, fail

  # check a7 = 2 (remu result)
  li   x3, 2
  li   x28, 2
  bne  x17, x28, fail

  # check a1 = 0xFE18 (mul result = DIV_result * a3)
  li   x3, 3
  li   x28, 0xFE18
  bne  x11, x28, fail

  # check a3 = 0x1234
  li   x3, 4
  li   x28, 0x1234
  bne  x13, x28, fail

  # ============================================================
  # Test 2: Pattern with 1 independent insn (like __udivdi3 line 41-45)
  #   divu a1, a4, a2
  #   slli a5, a5, 16
  #   srli a5, a5, 16
  #   remu a4, a4, a2
  #   mul  a3, a3, a1
  # ============================================================
  li   x14, 200          # a4 = dividend
  li   x12, 13           # a2 = divisor
  li   x15, 0xDEAD5678   # a5
  li   x13, 0x00000005   # a3 = multiplier

  # a4/a2 = 200/13 = 15, a4%a2 = 200%13 = 5
  # mul a3 = 5 * 15 = 75
  divu x11, x14, x12    # a1 = 200/13 = 15
  slli x15, x15, 16     # independent
  srli x15, x15, 16     # a5 = 0x5678
  remu x14, x14, x12    # a4 = 200%13 = 5
  mul  x13, x13, x11    # a3 = 5 * 15 = 75

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

  li   x28, 15
  bne  x11, x28, fail

  li   x28, 5
  bne  x14, x28, fail

  li   x28, 75
  bne  x13, x28, fail

  # ============================================================
  # Test 3: Back-to-back DIV→REM→MUL with larger values
  # Stress the divider with a multi-cycle division
  # ============================================================
  li   x17, 0xFFFF0000   # large dividend
  li   x12, 0x00010001   # divisor
  li   x16, 0x00000003   # for a3

  # 0xFFFF0000 / 0x00010001 = 0xFFFE (65534)
  # 0xFFFF0000 % 0x00010001 = 0x00010002 - wait let me compute
  # Actually: 0xFFFF0000 = 4294901760, 0x00010001 = 65537
  # 4294901760 / 65537 = 65534 (0xFFFE), remainder = 4294901760 - 65534*65537
  # 65534*65537 = 65534*65536 + 65534 = 4294770688 + 65534 = 4294836222
  # Hmm let me just use simpler values

  li   x17, 1000000      # dividend
  li   x12, 337          # divisor
  li   x16, 7            # multiplier for a3

  # 1000000 / 337 = 2967, remainder = 1000000 - 2967*337 = 1000000 - 999879 = 121
  # mul = 7 * 2967 = 20769

  divu x10, x17, x12    # a0 = 2967
  addi x13, x16, 0      # a3 = 7 (1 independent insn)
  remu x17, x17, x12    # a7 = 121
  mul  x11, x13, x10    # a1 = 7 * 2967 = 20769

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

  li   x28, 2967
  bne  x10, x28, fail

  li   x28, 121
  bne  x17, x28, fail

  li   x28, 20769
  bne  x11, x28, fail

  # ============================================================
  # Test 4: Two consecutive DIV→REM→MUL sequences (like full __udivdi3)
  # ============================================================
  li   x17, 999          # first dividend
  li   x14, 888          # second dividend
  li   x12, 17           # shared divisor
  li   x16, 0x0000ABCD   # for a3
  li   x15, 0x12340000   # for a5

  # First: 999/17=58, 999%17=13, mul=0xABCD*58
  # 0xABCD = 43981, 43981*58 = 2550898 = 0x26EEF2
  divu x10, x17, x12    # a0 = 58
  slli x13, x16, 16     # independent
  srli x13, x13, 16     # a3 = 0xABCD
  srli x14, x15, 16     # a4 = 0x1234 (overwrites second dividend!)
  remu x17, x17, x12    # a7 = 13
  mul  x11, x13, x10    # a1 = 0xABCD * 58 = 0x26EEF2

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 58
  bne  x10, x28, fail

  li   x28, 13
  bne  x17, x28, fail

  li   x28, 0x26EEF2
  bne  x11, x28, fail

  # Second: use a4=0x1234 (from srli above), divisor=17
  # 0x1234 = 4660, 4660/17=274, 4660%17=2
  # mul: a3(=0xABCD) * a1(=274)... wait a3 was overwritten
  # Let me just check div/rem results
  divu x11, x14, x12    # a1 = 4660/17 = 274
  slli x15, x15, 16     # independent
  srli x15, x15, 16     # a5 = 0x0000 (was 0x12340000, slli→0, srli→0)
  remu x14, x14, x12    # a4 = 4660%17 = 2
  mul  x13, x13, x11    # a3 = 0xABCD * 274

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 274
  bne  x11, x28, fail

  li   x28, 2
  bne  x14, x28, fail

  # 0xABCD * 274 = 43981 * 274 = 12050794 = 0xB7E57A
  li   x28, 0xB7E57A
  bne  x13, x28, fail

  # ============================================================
  # Test 5: MULHU variant (used in CoreMark CRC)
  # DIV→MULHU cross-unit dependency
  # ============================================================
  li   x17, 0x80000000   # dividend (large unsigned)
  li   x12, 3            # divisor
  li   x16, 0xFFFFFFFF   # multiplier operand

  # 0x80000000 / 3 = 0x2AAAAAAA
  # mulhu x11, x16, x10 = (0xFFFFFFFF * 0x2AAAAAAA) >> 32
  # = 0x2AAAAAA9 (high word of product)
  divu x10, x17, x12    # a0 = 0x2AAAAAAA
  nop
  nop
  nop
  remu x17, x17, x12    # a7 = 0x80000000 % 3 = 2
  mulhu x11, x16, x10   # a1 = high(0xFFFFFFFF * 0x2AAAAAAA)

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0x2AAAAAAA
  bne  x10, x28, fail

  li   x28, 2
  bne  x17, x28, fail

  # 0xFFFFFFFF * 0x2AAAAAAA = 0x2AAAAAA9_D5555556
  li   x28, 0x2AAAAAA9
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
