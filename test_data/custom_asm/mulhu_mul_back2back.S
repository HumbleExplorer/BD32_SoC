# mulhu_mul_back2back.S
# Test the 64-bit multiply split pattern found in CoreMark -O3:
#   mulhu rd1, rs1, rs2   (high word)
#   mul   rd2, rs1, rs2   (low word, back-to-back)
# Also tests triple-MUL, DIVU->SW->MUL, and WAW scenarios.

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # 初始化 sp 到 DTCM 有效地址（复位后 x2=0，sub-test 11 的 sw/lw 需要）
  li   x2, 0x00019000

  # ============================================================
  # Test 1: MULHU -> MUL back-to-back (exact O3 pattern)
  # s2 = 0x00010000, a0 = 0x00010000
  # product = 0x00010000 * 0x00010000 = 0x00000001_00000000
  # mulhu a5, s2, a0 => a5 = 0x00000001 (high)
  # mul   a0, s2, a0 => a0 = 0x00000000 (low)
  # ============================================================
  li   x3, 1
  li   x18, 0x00010000      # s2 = 65536
  li   x10, 0x00010000      # a0 = 65536
  li   x15, 0               # clear a5

  mulhu x15, x18, x10      # a5 = high(s2*a0) = 0x00000001
  mul   x10, x18, x10      # a0 = low(s2*a0)  = 0x00000000

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0x00000001
  bne  x15, x28, fail      # a5 should be 1
  li   x3, 2
  li   x28, 0x00000000
  bne  x10, x28, fail      # a0 should be 0

  # ============================================================
  # Test 2: MULHU -> MUL with larger values
  # s2 = 0xDEADBEEF, a0 = 0x00010000
  # product = 0xDEADBEEF * 0x00010000 = 0xDEAD_BEEF0000
  # mulhu => 0x0000DEAD
  # mul   => 0xBEEF0000
  # ============================================================
  li   x3, 3
  lui  x18, 0xDEADC         # s2 = 0xDEADC000
  addi x18, x18, -273       # s2 = 0xDEADBEEF
  li   x10, 0x00010000      # a0 = 65536
  li   x15, 0

  mulhu x15, x18, x10      # a5 = high(0xDEADBEEF * 0x10000)
  mul   x10, x18, x10      # a0 = low(0xDEADBEEF * 0x10000)

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0x0000DEAD
  bne  x15, x28, fail      # a5 = 0x0000DEAD
  li   x3, 4
  lui  x28, 0xBEEF0         # x28 = 0xBEEF0000
  bne  x10, x28, fail      # a0 = 0xBEEF0000

  # ============================================================
  # Test 3: MULHU -> MUL -> ADD (use high result immediately)
  # Pattern from O3: mulhu a5,s2,a0 / mul a0,s2,a0 / add a1,a1,a5
  # s2=100, a0=1000000(0xF4240)
  # product = 100 * 1000000 = 100000000 = 0x05F5E100
  # mulhu => 0x00000000, mul => 0x05F5E100
  # a1 starts at 42, after add: a1 = 42 + 0 = 42
  # ============================================================
  li   x3, 5
  li   x18, 100             # s2 = 100
  lui  x10, 0xF4            # a0 = 0xF4000
  addi x10, x10, 0x240     # a0 = 0xF4240 = 1000000
  li   x11, 42              # a1 = 42
  li   x15, 0

  mulhu x15, x18, x10      # a5 = high(100*1000000) = 0
  mul   x10, x18, x10      # a0 = low(100*1000000) = 0x05F5E100
  add   x11, x11, x15      # a1 = 42 + 0 = 42

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 42
  bne  x11, x28, fail      # a1 = 42
  li   x3, 6
  li   x28, 0x05F5E100
  bne  x10, x28, fail      # a0 = 0x05F5E100

  # ============================================================
  # Test 4: Triple MUL pattern (O3 117d0-117e0)
  # mulhu a1, a4, a0   (high of a4*a0)
  # mv    a2, s2       (independent ALU)
  # li    a3, 0        (independent ALU)
  # mul   a5, a4, a5   (a4 * a5, different rs2!)
  # mul   a0, a4, a0   (low of a4*a0)
  # add   a1, a5, a1   (combine)
  #
  # a4=0x10000, a0=0x10000, a5=3, s2=99
  # mulhu: high(0x10000*0x10000) = 1
  # mul(a5): 0x10000*3 = 0x30000
  # mul(a0): low(0x10000*0x10000) = 0
  # add: a1 = 0x30000 + 1 = 0x30001
  # ============================================================
  li   x3, 7
  li   x14, 0x00010000      # a4 = 65536
  li   x10, 0x00010000      # a0 = 65536
  li   x15, 3               # a5 = 3
  li   x18, 99              # s2 = 99
  li   x11, 0               # clear a1

  mulhu x11, x14, x10      # a1 = high(a4*a0) = 1
  mv    x12, x18            # a2 = s2 = 99 (independent)
  li    x13, 0              # a3 = 0 (independent)
  mul   x15, x14, x15      # a5 = a4*a5 = 0x30000
  mul   x10, x14, x10      # a0 = low(a4*a0) = 0
  add   x11, x15, x11      # a1 = a5 + a1 = 0x30000 + 1 = 0x30001

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

  li   x28, 0x30001
  bne  x11, x28, fail      # a1 = 0x30001
  li   x3, 8
  li   x28, 0x30000
  bne  x15, x28, fail      # a5 = 0x30000
  li   x3, 9
  li   x28, 0
  bne  x10, x28, fail      # a0 = 0
  li   x3, 10
  li   x28, 99
  bne  x12, x28, fail      # a2 = 99

  # ============================================================
  # Test 5: DIVU -> SW -> MUL (O3 pattern at 1137c-11388)
  # divu a1, a1, a3   => a1 = 2000/3 = 666
  # sw   a1, offset(sp) => store a1
  # mul  a4, a4, a1   => a4 = 7 * 666 = 4662 = 0x1236
  # ============================================================
  li   x3, 11
  li   x11, 2000            # a1 = 2000
  li   x13, 3               # a3 = 3
  li   x14, 7               # a4 = 7

  divu x11, x11, x13       # a1 = 2000/3 = 666
  sw   x11, 0(x2)          # store a1 to stack (uses divu result)
  mul  x14, x14, x11       # a4 = 7 * 666 = 4662

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
  nop
  nop

  li   x28, 666
  bne  x11, x28, fail      # a1 = 666
  li   x3, 12
  li   x28, 4662
  bne  x14, x28, fail      # a4 = 4662
  # verify stored value
  li   x3, 13
  lw   x29, 0(x2)
  li   x28, 666
  bne  x29, x28, fail_x28_666

  # ============================================================
  # Test 6: WAW - two MULs writing same register
  # mul a0, s2, a0  (first)
  # mul a0, s3, a1  (second, same rd=a0)
  # Final a0 should be second result
  # s2=5, a0=10 => first: 50
  # s3=7, a1=20 => second: 140
  # ============================================================
  li   x3, 14
  li   x18, 5               # s2 = 5
  li   x10, 10              # a0 = 10
  li   x19, 7               # s3 = 7
  li   x11, 20              # a1 = 20

  mul  x10, x18, x10       # a0 = 5*10 = 50
  mul  x10, x19, x11       # a0 = 7*20 = 140 (WAW with previous)

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 140
  bne  x10, x28, fail      # a0 = 140 (second mul wins)

  # ============================================================
  # Test 7: MULHU -> MUL where MUL's rd == rs2 (exact O3 pattern)
  # This is the critical pattern: rd of second == rs2 of both
  # a0 = 0x12345678, s2 = 0x1000
  # product = 0x12345678 * 0x1000 = 0x12345678000
  # high = 0x00000123, low = 0x45678000
  # After: a0 should be 0x45678000 (low word)
  # ============================================================
  li   x3, 15
  lui  x10, 0x12345         # a0 = 0x12345000
  addi x10, x10, 0x678     # a0 = 0x12345678
  li   x18, 0x1000          # s2 = 4096
  li   x15, 0               # clear a5

  mulhu x15, x18, x10      # a5 = high(s2*a0) = 0x00000123
  mul   x10, x18, x10      # a0 = low(s2*a0) = 0x45678000

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0x00000123
  bne  x15, x28, fail      # a5 = 0x123
  li   x3, 16
  lui  x28, 0x45678         # x28 = 0x45678000
  bne  x10, x28, fail      # a0 = 0x45678000

  # ============================================================
  # Test 8: Accumulation loop pattern (like O3's multiply-accumulate)
  # Simulates: for i in 1..4: acc += mulhu(s2, a0); s2++
  # s2 starts at 0x10000, a0 = 0x10000
  # Each iteration: high(s2 * 0x10000) = s2 >> 16
  # i=1: s2=0x10000, high=1; i=2: s2=0x10001, high=1
  # i=3: s2=0x10002, high=1; i=4: s2=0x10003, high=1
  # acc = 4
  # ============================================================
  li   x3, 17
  li   x18, 0x00010000      # s2 = 0x10000
  li   x10, 0x00010000      # a0 = 0x10000
  li   x11, 0               # a1 = acc = 0
  li   x16, 4               # s0 = loop count
  li   x17, 0               # s1 = counter

loop8:
  mulhu x15, x18, x10      # a5 = high(s2*a0)
  mul   x10, x18, x10      # a0 = low(s2*a0) -- DESTROYS a0!
  add   x11, x11, x15      # acc += a5
  # restore a0 for next iteration
  li   x10, 0x00010000     # a0 = 0x10000 again
  addi x18, x18, 1         # s2++
  addi x17, x17, 1         # counter++
  bne  x17, x16, loop8

  nop
  nop
  nop
  nop

  li   x28, 4
  bne  x11, x28, fail      # acc = 4

  # ============================================================
  # Test 9: DIVU -> MULHU -> MUL (cross-unit then back-to-back)
  # a1 = 2000/3 = 666
  # mulhu a5, a1, a0 => high(666 * 0x10000) = 0x00000002
  # mul   a0, a1, a0 => low(666 * 0x10000) = 0x9A0000
  # 666 * 65536 = 43646976 = 0x029A0000
  # high = 0x02, low = 0x9A0000... wait let me recalculate
  # 666 = 0x29A, 0x29A * 0x10000 = 0x029A0000
  # high = 0x00000002, low = 0x9A0000
  # Hmm: 0x029A0000 >> 16 = 0x029A... no
  # 666 * 65536 = 43646976
  # 43646976 / 2^32 = 0 (fits in 32 bits!)
  # So high = 0, low = 43646976 = 0x029A0000
  # Let me use bigger values: a1=666, a0=0x100000(1048576)
  # 666 * 1048576 = 698351616 = 0x29A00000
  # Still fits in 32 bits. Use a0=0x10000000(268435456)
  # 666 * 268435456 = 178757959696... too big, let me just use
  # a1=666, a0=0x100000 => 666*1048576 = 698351616 = 0x29A00000
  # high=0, low=0x29A00000. Not great for testing mulhu.
  # Use a0 = 0x00100000, s2=666: 666*0x100000 = 0x29A00000, high=0
  # Need bigger: a1=0x10000(65536), a0=0x10000(65536)
  # 65536*65536 = 0x100000000, high=1, low=0
  # But a1 comes from divu... let's do 200000/3 = 66666
  # 66666 * 65536 = 4369121280... > 2^32? 2^32=4294967296
  # 4369121280 > 4294967296, so high = 1, low = 4369121280-4294967296=74153984=0x046B4000
  # Actually: 66666 = 0x1046A, 0x1046A * 0x10000 = 0x1046A0000
  # high = 0x00000001, low = 0x046A0000
  # ============================================================
  li   x3, 18
  li   x11, 200000          # a1 = 200000
  li   x13, 3               # a3 = 3
  li   x10, 0x00010000      # a0 = 65536

  divu x11, x11, x13       # a1 = 200000/3 = 66666
  mulhu x15, x11, x10      # a5 = high(66666*65536) = 1
  mul   x10, x11, x10      # a0 = low(66666*65536) = 0x046A0000

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
  nop
  nop

  li   x28, 66666
  bne  x11, x28, fail      # a1 = 66666
  li   x3, 19
  li   x28, 1
  bne  x15, x28, fail      # a5 = 1
  li   x3, 20
  li   x28, 0x046A0000
  bne  x10, x28, fail      # a0 = 0x046A0000

  # ============================================================
  # Test 10: Stress - 4 MULs in flight (fill OITF depth=4)
  # All independent, different rd
  # ============================================================
  li   x3, 21
  li   x10, 2               # a0 = 2
  li   x11, 3               # a1 = 3
  li   x12, 4               # a2 = 4
  li   x13, 5               # a3 = 5
  li   x14, 10              # a4 = 10
  li   x15, 10              # a5 = 10
  li   x16, 10              # s0 = 10
  li   x17, 10              # s1 = 10

  mul  x10, x10, x14       # a0 = 2*10 = 20
  mul  x11, x11, x15       # a1 = 3*10 = 30
  mul  x12, x12, x16       # a2 = 4*10 = 40
  mul  x13, x13, x17       # a3 = 5*10 = 50

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 20
  bne  x10, x28, fail
  li   x3, 22
  li   x28, 30
  bne  x11, x28, fail
  li   x3, 23
  li   x28, 40
  bne  x12, x28, fail
  li   x3, 24
  li   x28, 50
  bne  x13, x28, fail

  # ============================================================
  # Test 11: MULHU->MUL back-to-back, then immediate use of BOTH
  # s2=0xFFFF, a0=0xFFFF
  # 0xFFFF * 0xFFFF = 0xFFFE0001
  # mulhu => 0x00000000, mul => 0xFFFE0001
  # Then: add a1, a5, a0 => a1 = 0 + 0xFFFE0001 = 0xFFFE0001
  # ============================================================
  li   x3, 25
  li   x18, 0xFFFF          # s2 = 65535
  li   x10, 0xFFFF          # a0 = 65535
  li   x15, 0
  li   x11, 0

  mulhu x15, x18, x10      # a5 = high(65535*65535) = 0
  mul   x10, x18, x10      # a0 = low(65535*65535) = 0xFFFE0001
  add   x11, x15, x10      # a1 = a5 + a0 = 0xFFFE0001

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0
  bne  x15, x28, fail      # a5 = 0
  li   x3, 26
  lui  x28, 0xFFFE0         # 0xFFFE0000
  addi x28, x28, 1         # 0xFFFE0001
  bne  x10, x28, fail      # a0 = 0xFFFE0001
  li   x3, 27
  bne  x11, x28, fail      # a1 = 0xFFFE0001

  # ============================================================
  # All passed
  # ============================================================
  li   x27, 1
  li   x26, 1
p: j p

fail_x28_666:
  li   x28, 666
  j    fail

fail:
  li   x27, 0
  li   x26, 1
fl: j fl

  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
