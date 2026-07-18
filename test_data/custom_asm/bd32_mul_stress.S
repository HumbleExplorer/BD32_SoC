# BD32 MUL/OITF stress test.
# x27 = FAIL_CODE on failure (1 = pass). Pure register ops (no memory), so it
# runs directly in tb_core_top with no UART dependency.
#
# Covers patterns riscv-tests 'mul' does NOT:
#   A: WAW  - a younger write to the same reg as an in-flight MUL must win
#   B: RAW  - forwarding of the OITF-retired MUL result to a dependent ADD
#   C: MULTI- four concurrent MULs in OITF, then accumulate (matrix pattern)
#   D: MULH - signed-high product (64-bit emulation)
#   E: MD   - concurrent MUL (unit0) + DIV (unit1), then combine
#   F: 64   - 64-bit accumulate using mul/mulh + carry (matrix acc loop)

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ---- A: WAW (younger write wins) ----
  li   x2, 6
  li   x3, 7
  mul  x1, x2, x3      # x1 = 42 (long, to OITF)
  li   x4, 0xABCDEF01
  addi x1, x4, 0       # WAW: x1 must become 0xABCDEF01 (younger wins)
  li   x5, 0xABCDEF01
  bne  x1, x5, failA

  # ---- B: RAW forwarding from OITF retire ----
  li   x2, 6
  li   x3, 7
  mul  x1, x2, x3      # 42
  li   x6, 100
  add  x7, x1, x6      # x7 = 142 (RAW on x1)
  li   x8, 142
  bne  x7, x8, failB

  # ---- C: four concurrent MULs then accumulate ----
  li   x2, 2;  li   x3, 3;   mul x10, x2, x3    # 6
  li   x4, 4;  li   x5, 5;   mul x11, x4, x5    # 20
  li   x6, 6;  li   x7, 7;   mul x12, x6, x7    # 42
  li   x8, 8;  li   x9, 9;   mul x13, x8, x9    # 72
  add  x14, x10, x11     # 26
  add  x15, x12, x13     # 114
  add  x16, x14, x15     # 140
  li   x17, 140
  bne  x16, x17, failC

  # ---- D: MULH (signed high) ----
  li   x2, 0x10000
  li   x3, 0x10000
  mul  x10, x2, x3      # low  = 0x00000000
  mulh x11, x2, x3      # high = 0x00000001  (0x10000*0x10000 = 0x1_00000000)
  li   x12, 0
  bne  x10, x12, failD1
  li   x13, 1
  bne  x11, x13, failD2

  li   x2, -3
  li   x3, 5
  mul  x10, x2, x3      # -15 = 0xFFFFFFF1
  mulh x11, x2, x3      # 0xFFFFFFFF
  li   x12, -15
  bne  x10, x12, failD3
  li   x13, -1
  bne  x11, x13, failD4

  # ---- E: concurrent MUL + DIV (cross-unit OITF) ----
  li   x2, 20;  li   x6, 6;   mul x10, x2, x6   # 120
  li   x4, 100; li   x5, 7;   div x11, x4, x5   # 14
  li   x13, 120
  bne  x10, x13, failE_mul
  li   x14, 14
  bne  x11, x14, failE_div
  add  x12, x10, x11    # 134
  li   x13, 134
  bne  x12, x13, failE_add

  # ---- F: 64-bit accumulate (matrix acc loop) ----
  li   x20, 0;  li   x21, 0    # acc_hi, acc_lo
  li   x2, 0x10000;  li   x3, 0x10000
  # iter1: prod = 0x1_00000000
  mul  x10, x2, x3
  mulh x11, x2, x3
  add  x21, x21, x10
  sltu x22, x21, x10
  add  x20, x20, x11
  add  x20, x20, x22
  # iter2: prod = 0x1_00000000
  mul  x10, x2, x3
  mulh x11, x2, x3
  add  x21, x21, x10
  sltu x22, x21, x10
  add  x20, x20, x11
  add  x20, x20, x22
  # expect acc_hi = 2, acc_lo = 0
  li   x23, 2
  bne  x20, x23, failF1
  li   x24, 0
  bne  x21, x24, failF2

  # ---- G: branch loop with in-flight MUL (branch+OITF flush interaction) ----
  li   x11, 5
  li   x12, 0
cf_loop:
  mul  x13, x11, x11
  add  x12, x12, x13
  addi x11, x11, -1
  bne  x11, x0, cf_loop
  li   x14, 55
  bne  x12, x14, failG

  # ---- H: jal call + MUL (call+OITF) ----
  li   a0, 7
  jal  ra, cf_mul3
  li   x8, 21
  bne  a0, x8, failH

  # ---- J: jalr function-pointer call + MUL ----
  la   x5, cf_mul3
  li   a0, 9
  jalr ra, x5, 0
  li   x8, 27
  bne  a0, x8, failJ

  # all passed
  li x26, 1
  li x27, 1
pass_loop:
  j pass_loop

failA:  li x26,1; li x27,2; li gp,2;  j fail_loop
failB:  li x26,1; li x27,3; li gp,3;  j fail_loop
failC:  li x26,1; li x27,4; li gp,4;  j fail_loop
failD1: li x26,1; li x27,5; li gp,5;  j fail_loop
failD2: li x26,1; li x27,6; li gp,6;  j fail_loop
failD3: li x26,1; li x27,7; li gp,7;  j fail_loop
failD4: li x26,1; li x27,8; li gp,8;  j fail_loop
failE_mul: li x26,1; li x27,9; li gp,9;  j fail_loop
failE_div: li x26,1; li x27,12; li gp,12; j fail_loop
failE_add: li x26,1; li x27,13; li gp,13; j fail_loop
failF1: li x26,1; li x27,10; li gp,10; j fail_loop
failF2: li x26,1; li x27,11; li gp,11; j fail_loop
failG:  li x26,1; li x27,14; li gp,14; j fail_loop
failH:  li x26,1; li x27,15; li gp,15; j fail_loop
failJ:  li x26,1; li x27,16; li gp,16; j fail_loop
fail_loop:
  j fail_loop

cf_mul3:
  li   a1, 3
  mul  a0, a0, a1
  ret

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
