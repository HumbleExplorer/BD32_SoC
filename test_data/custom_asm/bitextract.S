# bitextract.S - replicate coremark matrix_mul_matrix_bitextract inner body:
#   lh t1,0(a7); lh a5,0(t2); mul a5,a5,t1; srai t1,a5,2; andi t1,t1,15;
#   andi a5,a5,127; mul a5,t1,a5
# Tests the mul->shift/andi->mul RAW chain on the same rd (a5).
# With A[0]=3, B[0]=7: a5 = (7*3)=21; t1=21>>2=5; t1&=15=5; a5&=127=21;
#   a5 = 5*21 = 105.
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0
  li a7, 0x1B000
  li t2, 0x1C000
  li s0, 2
  li t3, 3; sh t3, 0(a7)
  li t3, 7; sh t3, 0(t2)

  lh t1, 0(a7)
  lh a5, 0(t2)
  mul a5, a5, t1        # a5 = 21
  add a7, a7, s0
  srai t1, a5, 2         # t1 = 5
  andi t1, t1, 15        # t1 = 5
  andi a5, a5, 127       # a5 = 21
  mul a5, t1, a5         # a5 = 105

  li x13, 105
  bne a5, x13, fail
  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
