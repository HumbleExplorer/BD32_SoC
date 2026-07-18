# mulh_dbg.S - characterize MULH/MULHU error pattern with distinct cases.
# Each case: if wrong, set x3 to its code and finish (so we know WHICH fails).
# x27=1 only if ALL pass. x26 armed only at pass/fail.
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0

  # 1) mulh(3,3) -> high(9)=0
  li x10, 3
  li x11, 3
  mulh x12, x10, x11
  li x13, 0
  bne x12, x13, c1

  # 2) mulh(-2,3) -> high(-6)=0xFFFFFFFF
  li x10, -2
  li x11, 3
  mulh x12, x10, x11
  li x13, -1
  bne x12, x13, c2

  # 3) mulh(0x80000000,1) -> -2^31 = 0xFFFFFFFF80000000 -> high = 0xFFFFFFFF
  li x10, 0x80000000
  li x11, 1
  mulh x12, x10, x11
  li x13, -1
  bne x12, x13, c3

  # 4) mulh(0x80000000,0x80000000) -> 0x40000000
  li x10, 0x80000000
  li x11, 0x80000000
  mulh x12, x10, x11
  li x13, 0x40000000
  bne x12, x13, c4

  # 5) mulhu(0x80000000,0x80000000) -> 0x40000000 (unsigned high)
  mulhu x12, x10, x11
  bne x12, x13, c5

  # 6) mulhu(3,3) -> 0
  li x10, 3
  li x11, 3
  mulhu x12, x10, x11
  li x13, 0
  bne x12, x13, c6

  # 7) mulhsu(0x80000000,0x80000000) -> (-2^31)*(2^31) = -2^62 = 0xC000000000000000 -> high = 0xC0000000
  li x10, 0x80000000
  li x11, 0x80000000
  mulhsu x12, x10, x11
  li x13, 0xC0000000
  bne x12, x13, c7

  # 8) mulhsu(-2,3) -> high(-6)=0xFFFFFFFF (a signed -2, b unsigned 3)
  li x10, -2
  li x11, 3
  mulhsu x12, x10, x11
  li x13, -1
  bne x12, x13, c8

  li x27, 1
  li x26, 1
p: j p

c1: li x3, 1; j rf
c2: li x3, 2; j rf
c3: li x3, 3; j rf
c4: li x3, 4; j rf
c5: li x3, 5; j rf
c6: li x3, 6; j rf
c7: li x3, 7; j rf
c8: li x3, 8; j rf
rf: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
