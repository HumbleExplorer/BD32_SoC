# udivdi3_pattern.S
# Test the exact DIV→REM→MUL pattern from __udivdi3
# This pattern appears 8 times in the O3 CoreMark binary
#
# Pattern from __udivdi3 (addresses 15020-15034):
#   divu  a0,a7,a2    # DIV dispatches to OITF
#   slli  a3,a6,0x10  # ALU (independent)
#   srli  a3,a3,0x10  # ALU (independent)
#   srli  a4,a5,0x10  # ALU (independent)
#   remu  a7,a7,a2    # REM stalls on OITF (divider busy)
#   mul   a1,a3,a0    # MUL reads a0 from DIV result
#
# Key timing:
# - DIV takes many cycles (iterative divider)
# - 3 ALU instructions execute while DIV is running
# - REM arrives, stalls because divider is busy
# - DIV completes, REM starts, stall releases
# - MUL enters EX, needs a0 from DIV via OITF retire forwarding
#
# The critical question: does MUL get the correct DIV result?

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ============================================================
  # Test 1: Exact __udivdi3 pattern (15020-15034)
  # a7=0x12345678, a2=100, a6=0xABCD, a5=0xEF01
  # Expected:
  #   a0 = a7 / a2 = 0x12345678 / 100 = 0x1DCD64FF (unsigned div)
  #   Actually: 0x12345678 = 305419896, / 100 = 3054198 (0x2E9A36)
  #   a7 = a7 % a2 = 305419896 % 100 = 96 (0x60)
  #   a1 = a3 * a0, where a3 = (a6 << 16) >> 16 = 0x0000ABCD
  #   a1 = 0xABCD * 0x2E9A36 = ?
  #   Let me compute: 0xABCD = 43981, 0x2E9A36 = 3054198
  #   43981 * 3054198 = 134,326,582,138 = 0x1F5E3C7A3A (64-bit)
  #   Low 32 bits: 0x5E3C7A3A
  # ============================================================
  li   x3, 1
  
  # Setup operands
  li   x17, 0x12345678      # a7 = dividend
  li   x12, 100             # a2 = divisor
  li   x16, 0xABCD          # a6
  li   x15, 0xEF01          # a5
  
  # Execute the exact pattern
  divu x10, x17, x12        # a0 = a7 / a2 = 3054198 (0x2E9A36)
  slli x13, x16, 16         # a3 = a6 << 16
  srli x13, x13, 16         # a3 = a3 >> 16 = 0x0000ABCD
  srli x14, x15, 16         # a4 = a5 >> 16 = 0x0000EF01
  remu x17, x17, x12        # a7 = a7 % a2 = 96 (0x60)
  mul  x11, x13, x10        # a1 = a3 * a0 = 0xABCD * 0x2E9A36
  
  # Wait for completion
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
  
  # Check results
  li   x28, 0x2E9A76
  bne  x10, x28, fail       # a0 should be 0x2E9A76
  
  li   x3, 2
  li   x28, 0x60
  bne  x17, x28, fail       # a7 should be 0x60 (remainder)
  
  li   x3, 3
  li   x28, 0xABCD
  bne  x13, x28, fail       # a3 should be 0xABCD
  
  li   x3, 4
  # a1 = 0xABCD * 0x2E9A76 = 43981 * 3054198 = low32 = 0x467E827E
  li   x28, 0x467E827E
  bne  x11, x28, fail       # a1 should be 0x467E827E

  # ============================================================
  # Test 2: Back-to-back DIV→REM→MUL with register reuse
  # Pattern: DIV writes rd, REM writes rs2 of DIV, MUL reads both
  # This tests WAW and RAW hazards in dense sequence
  # ============================================================
  li   x3, 5
  
  li   x10, 1000            # a0 = dividend
  li   x11, 7               # a1 = divisor
  li   x12, 0x12345         # a2
  
  divu x13, x10, x11        # a3 = 1000 / 7 = 142
  remu x10, x10, x11        # a0 = 1000 % 7 = 6 (reuse a0!)
  mul  x14, x12, x13        # a4 = a2 * a3 = 0x12345 * 142
  
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  
  li   x28, 142
  bne  x13, x28, fail       # a3 should be 142
  
  li   x3, 6
  li   x28, 6
  bne  x10, x28, fail       # a0 should be 6 (remainder)
  
  li   x3, 7
  # a4 = 0x12345 * 142 = 74565 * 142 = 10588230 = 0xA19046
  li   x28, 0xA19046
  bne  x14, x28, fail       # a4 should be 0xA19046

  # ============================================================
  # Test 3: Multiple DIV→MUL chains (stress OITF)
  # Simulates the dense DIV usage in __udivdi3
  # ============================================================
  li   x3, 8
  
  li   x10, 500             # a0
  li   x11, 3               # a1
  li   x12, 7               # a2
  li   x13, 11              # a3
  
  divu x14, x10, x11        # a4 = 500 / 3 = 166
  divu x15, x10, x12        # a5 = 500 / 7 = 71
  mul  x16, x14, x15        # a6 = a4 * a5 = 166 * 71 = 11786
  divu x17, x10, x13        # a7 = 500 / 11 = 45
  mul  x10, x16, x17        # a0 = a6 * a7 = 11786 * 45 = 530370
  
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
  
  li   x28, 166
  bne  x14, x28, fail       # a4 should be 166
  
  li   x3, 9
  li   x28, 71
  bne  x15, x28, fail       # a5 should be 71
  
  li   x3, 10
  li   x28, 11786
  bne  x16, x28, fail       # a6 should be 11786
  
  li   x3, 11
  li   x28, 45
  bne  x17, x28, fail       # a7 should be 45
  
  li   x3, 12
  li   x28, 530370
  bne  x10, x28, fail       # a0 should be 530370

  # ============================================================
  # Test 4: DIV→REM→MUL with immediate use (no gap)
  # Tests the tightest possible dependency
  # ============================================================
  li   x3, 13
  
  li   x10, 999             # a0 = dividend
  li   x11, 10              # a1 = divisor
  
  divu x12, x10, x11        # a2 = 999 / 10 = 99
  remu x13, x10, x11        # a3 = 999 % 10 = 9
  mul  x14, x12, x13        # a4 = a2 * a3 = 99 * 9 = 891
  
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  
  li   x28, 99
  bne  x12, x28, fail       # a2 should be 99
  
  li   x3, 14
  li   x28, 9
  bne  x13, x28, fail       # a3 should be 9
  
  li   x3, 15
  li   x28, 891
  bne  x14, x28, fail       # a4 should be 891

  # ============================================================
  # Test 5: __udivdi3 pattern with larger values (64-bit simulation)
  # Simulates the actual 64-bit division pattern
  # ============================================================
  li   x3, 16
  
  # Simulate 64-bit division: (a7:a6) / (a3:a2)
  # For simplicity, use 32-bit values that exercise the same path
  li   x17, 0xFFFFFFFF      # a7 = max uint32
  li   x16, 0x80000000      # a6 = 2^31
  li   x13, 0x10000         # a3 = 65536 (divisor high)
  li   x12, 0x10000         # a2 = 65536 (divisor low)
  
  # This pattern appears in __udivdi3 for large dividends
  divu x10, x17, x12        # a0 = 0xFFFFFFFF / 0x10000 = 0xFFFF
  slli x14, x16, 16         # a4 = a6 << 16
  srli x14, x14, 16         # a4 = a4 >> 16 = 0x00008000
  remu x17, x17, x12        # a7 = 0xFFFFFFFF % 0x10000 = 0xFFFF
  mul  x11, x14, x10        # a1 = a4 * a0 = 0x8000 * 0xFFFF
  
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
  
  li   x28, 0xFFFF
  bne  x10, x28, fail       # a0 should be 0xFFFF
  
  li   x3, 17
  li   x28, 0xFFFF
  bne  x17, x28, fail       # a7 should be 0xFFFF
  
  li   x3, 18
  li   x28, 0x0
  bne  x14, x28, fail       # a4 should be 0x0 (low 16 bits of 0x80000000)
  
  li   x3, 19
  # a1 = 0x0 * 0xFFFF = 0
  li   x28, 0x0
  bne  x11, x28, fail       # a1 should be 0x0

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
