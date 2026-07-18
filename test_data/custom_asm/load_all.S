# load_all.S - cover lw/lh/lhu/lb/lbu with sign/zero extension.
# Data pattern stored into ITCM RAM region (0x1D000) then read back.
# x27=1 pass / x27=0 fail; x3 = failing sub-test code (1..6).
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0
  li a0, 0x1D000           # data base (ITCM RAM, writable in core_test)

  # ---- word store/load ----
  li t0, 0x12345678
  sw t0, 0(a0)
  lw t1, 0(a0)
  li t2, 0x12345678
  bne t1, t2, f_lw

  # ---- byte stores (0x9A,0xBC,0xDE,0xF0 at +4..+7) ----
  li t0, 0x9A ; sb t0, 4(a0)
  li t0, 0xBC ; sb t0, 5(a0)
  li t0, 0xDE ; sb t0, 6(a0)
  li t0, 0xF0 ; sb t0, 7(a0)

  # lb sign extension: 0x9A -> 0xFFFFFF9A
  lb t1, 4(a0)
  li t2, 0xFFFFFF9A
  bne t1, t2, f_lb

  # lbu zero extension: 0x9A -> 0x0000009A
  lbu t1, 4(a0)
  li t2, 0x0000009A
  bne t1, t2, f_lbu

  # ---- halfword stores ----
  li t0, 0x7890 ; sh t0, 8(a0)
  li t0, 0xABCD ; sh t0, 10(a0)

  # lh positive: 0x7890
  lh t1, 8(a0)
  li t2, 0x7890
  bne t1, t2, f_lh

  # lh sign extension: 0xABCD -> 0xFFFFABCD
  lh t1, 10(a0)
  li t2, 0xFFFFABCD
  bne t1, t2, f_lh_sx

  # lhu zero extension: 0xABCD
  lhu t1, 10(a0)
  li t2, 0xABCD
  bne t1, t2, f_lhu

  # all passed
  li x27, 1
  li x26, 1
p: j p

f_lw:    li x3, 1; j rf
f_lb:    li x3, 2; j rf
f_lbu:   li x3, 3; j rf
f_lh:    li x3, 4; j rf
f_lh_sx: li x3, 5; j rf
f_lhu:   li x3, 6; j rf
rf: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
