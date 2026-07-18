# auipc_test.S - verify auipc (imm addition) and la (auipc+addi) addressing.
# x27=1 pass / x27=0 fail; x3 = failing sub-test code (1=diff, 2=la).
# NOTE: auipc rd,imm  => rd = PC_of_this_auipc + (imm<<12). Each auipc uses its
# OWN pc, so two adjacent `auipc x,0` differ by exactly 4 (the instruction size).
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0

  # ---- Test 1: two adjacent auipc x,0 must differ by 4 (instruction size) ----
  auipc x10, 0          # x10 = pc of this inst
  auipc x11, 0          # x11 = pc of next inst  = x10 + 4
  sub   x12, x11, x10   # x12 = 4
  li    x13, 4
  bne   x12, x13, f_diff

  # ---- Test 2: la (auipc+addi) to a literal pool in .text ----
  j     skip_lit
litpool:
  .word 0xCAFEBABE
skip_lit:
  la    x14, litpool     # auipc + addi -> &litpool
  lw    x15, 0(x14)
  li    x16, 0xCAFEBABE
  bne   x15, x16, f_la

  li x27, 1
  li x26, 1
p: j p

f_diff: li x3, 1; j rf
f_la:  li x3, 2; j rf
rf: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
