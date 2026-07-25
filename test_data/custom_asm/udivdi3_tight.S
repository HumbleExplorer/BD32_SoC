# udivdi3_tight.S
# Test the EXACT tight DIV->REM->MUL pattern from __udivdi3
# Key: NO NOPs between operations, remu stalls on divider, mul follows immediately

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ============================================================
  # Test 1: Exact __udivdi3 pattern (15020-15034)
  # divu a0, a7, a2     # a0 = a7 / a2
  # slli a3, a6, 0x10   # a3 = a6 << 16
  # srli a3, a3, 0x10   # a3 = a3 >> 16 (extract low 16 bits)
  # srli a4, a5, 0x10   # a4 = a5 >> 16
  # remu a7, a7, a2     # a7 = a7 % a2 (stalls on divider)
  # mul  a1, a3, a0     # a1 = a3 * a0 (needs a0 from divu!)
  # ============================================================
  li   x3, 1
  
  # Setup: a7=0x12345678, a2=100, a6=0xABCD1234, a5=0xEF012345
  li   x17, 0x12345678      # a7 = dividend
  li   x12, 100             # a2 = divisor
  li   x16, 0xABCD1234      # a6
  li   x15, 0xEF012345      # a5
  
  # Execute the EXACT pattern
  divu x10, x17, x12        # a0 = a7 / a2
  slli x13, x16, 16         # a3 = a6 << 16
  srli x13, x13, 16         # a3 = a3 >> 16
  srli x14, x15, 16         # a4 = a5 >> 16
  remu x17, x17, x12        # a7 = a7 % a2 (stalls!)
  mul  x11, x13, x10        # a1 = a3 * a0 (CRITICAL: needs a0 from divu)
  
  # Wait for completion
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  
  # Check results
  # a0 = 0x12345678 / 100 = 305419896 / 100 = 3054198 = 0x2E9A76
  li   x28, 0x2E9A76
  bne  x10, x28, fail       # a0 should be 0x2E9A76
  
  li   x3, 2
  # a7 = 0x12345678 % 100 = 305419896 % 100 = 96 = 0x60
  li   x28, 0x60
  bne  x17, x28, fail       # a7 should be 0x60
  
  li   x3, 3
  # a3 = (0xABCD1234 << 16) >> 16 = 0x1234
  li   x28, 0x1234
  bne  x13, x28, fail       # a3 should be 0x1234
  
  li   x3, 4
  # a4 = 0xEF012345 >> 16 = 0xEF01
  li   x28, 0xEF01
  bne  x14, x28, fail       # a4 should be 0xEF01
  
  li   x3, 5
  # a1 = a3 * a0 = 0x1234 * 0x2E9A76 = 4660 * 3054198 = 14232562680 = 0x34F3C7A38
  # Low 32 bits: 0x5053ABF8
  li   x28, 0x5053ABF8
  bne  x11, x28, fail       # a1 should be 0x5053ABF8

  # ============================================================
  # Test 2: Even tighter - DIV immediately followed by MUL
  # No instructions between them
  # ============================================================
  li   x3, 6
  
  li   x10, 1000            # a0 = dividend
  li   x11, 7               # a1 = divisor
  li   x12, 0x12345         # a2
  
  divu x13, x10, x11        # a3 = 1000 / 7 = 142
  mul  x14, x12, x13        # a4 = a2 * a3 (immediately after divu!)
  
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
  
  li   x3, 7
  # a4 = 0x12345 * 142 = 74565 * 142 = 10588230 = 0xA19046
  li   x28, 0xA19046
  bne  x14, x28, fail       # a4 should be 0xA19046

  # ============================================================
  # Test 3: DIV->REM->MUL with register reuse (WAW-like)
  # divu writes a0, remu writes a7, mul reads both
  # ============================================================
  li   x3, 8
  
  li   x10, 500             # a0 = dividend
  li   x11, 3               # a1 = divisor
  
  divu x12, x10, x11        # a2 = 500 / 3 = 166
  remu x10, x10, x11        # a0 = 500 % 3 = 2 (reuse a0!)
  mul  x13, x12, x10        # a3 = a2 * a0 = 166 * 2 = 332
  
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  
  li   x28, 166
  bne  x12, x28, fail       # a2 should be 166
  
  li   x3, 9
  li   x28, 2
  bne  x10, x28, fail       # a0 should be 2
  
  li   x3, 10
  li   x28, 332
  bne  x13, x28, fail       # a3 should be 332

  # ============================================================
  # Test 4: Multiple DIV->MUL chains (stress OITF)
  # ============================================================
  li   x3, 11
  
  li   x10, 1000            # a0
  li   x11, 7               # a1
  li   x12, 11              # a2
  li   x13, 13              # a3
  
  divu x14, x10, x11        # a4 = 1000 / 7 = 142
  divu x15, x10, x12        # a5 = 1000 / 11 = 90
  mul  x16, x14, x15        # a6 = a4 * a5 = 142 * 90 = 12780
  divu x17, x10, x13        # a7 = 1000 / 13 = 76
  mul  x10, x16, x17        # a0 = a6 * a7 = 12780 * 76 = 971280
  
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
  
  li   x28, 142
  bne  x14, x28, fail       # a4 should be 142
  
  li   x3, 12
  li   x28, 90
  bne  x15, x28, fail       # a5 should be 90
  
  li   x3, 13
  li   x28, 12780
  bne  x16, x28, fail       # a6 should be 12780
  
  li   x3, 14
  li   x28, 76
  bne  x17, x28, fail       # a7 should be 76
  
  li   x3, 15
  li   x28, 971280
  bne  x10, x28, fail       # a0 should be 971280

  # ============================================================
  # Test 5: DIV->ALU->ALU->REM->MUL (exact __udivdi3 spacing)
  # ============================================================
  li   x3, 16
  
  li   x17, 0xFFFFFFFF      # a7 = max uint32
  li   x12, 0x10000         # a2 = 65536
  li   x16, 0x12345678      # a6
  li   x15, 0xABCDEF01      # a5
  
  divu x10, x17, x12        # a0 = 0xFFFFFFFF / 0x10000 = 0xFFFF
  slli x13, x16, 16         # a3 = a6 << 16
  srli x13, x13, 16         # a3 = a3 >> 16
  srli x14, x15, 16         # a4 = a5 >> 16
  remu x17, x17, x12        # a7 = 0xFFFFFFFF % 0x10000 = 0xFFFF
  mul  x11, x13, x10        # a1 = a3 * a0
  
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
  # a3 = (0x12345678 << 16) >> 16 = 0x5678
  li   x28, 0x5678
  bne  x13, x28, fail       # a3 should be 0x5678
  
  li   x3, 19
  # a4 = 0xABCDEF01 >> 16 = 0xABCD
  li   x28, 0xABCD
  bne  x14, x28, fail       # a4 should be 0xABCD
  
  li   x3, 20
  # a1 = 0x5678 * 0xFFFF = 22136 * 65535 = 1450687560 = 0x5677A988
  li   x28, 0x5677A988
  bne  x11, x28, fail       # a1 should be 0x5677A988

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
