# BD32 M-extension (MUL/DIV/REM) + OITF stress test.
# x27 = FAIL_CODE on failure (1 = pass). Pure register ops (no memory), so it
# runs directly in tb_core_top with no UART dependency.
#
# Convention: gp(x3) is RESERVED for fail-code display — test body uses x28(t3)
# instead, so gp in waveform unambiguously identifies the failing sub-test.
#
# Covers patterns riscv-tests 'mul'/'div' do NOT:
#   A: WAW  - a younger write to the same reg as an in-flight MUL must win
#   B: RAW  - forwarding of the OITF-retired MUL result to a dependent ADD
#   C: MULTI- four concurrent MULs in OITF, then accumulate (matrix pattern)
#   D: MULH - signed-high product (64-bit emulation)
#   E: MD   - concurrent MUL (unit0) + DIV (unit1), then combine
#   F: 64   - 64-bit accumulate using mul/mulh + carry (matrix acc loop)
#   G: branch loop with in-flight MUL (branch+OITF flush interaction)
#   H: jal call + MUL (call+OITF)
#   J: jalr function-pointer call + MUL
#   K: decimal conversion loop — divu/remu by 10 in a loop (printf %u pattern)
#   L: back-to-back div/rem pairs — OITF forwarding stress (divu→remu, remu→divu,
#      signed div→rem, loop with alternating div/rem)
#   M: O3-specific patterns from CoreMark -O3 disassembly (divu→mul RAW, divu→remu→mul
#      triple, mulhu→mul pair, unrolled mul×4, 0xFFFFFFFF decimal loop, div→mul→div
#      chain, mul→div→rem→mul ping-pong)

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ---- A: WAW (younger write wins) ----
  li   x2, 6
  li   x28, 7
  mul  x1, x2, x28     # x1 = 42 (long, to OITF)
  li   x4, 0xABCDEF01
  addi x1, x4, 0       # WAW: x1 must become 0xABCDEF01 (younger wins)
  li   x5, 0xABCDEF01
  bne  x1, x5, failA

  # ---- B: RAW forwarding from OITF retire ----
  li   x2, 6
  li   x28, 7
  mul  x1, x2, x28     # 42
  li   x6, 100
  add  x7, x1, x6      # x7 = 142 (RAW on x1)
  li   x8, 142
  bne  x7, x8, failB

  # ---- C: four concurrent MULs then accumulate ----
  li   x2, 2;  li   x28, 3;  mul x10, x2, x28   # 6
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
  li   x28, 0x10000
  mul  x10, x2, x28     # low  = 0x00000000
  mulh x11, x2, x28     # high = 0x00000001  (0x10000*0x10000 = 0x1_00000000)
  li   x12, 0
  bne  x10, x12, failD1
  li   x13, 1
  bne  x11, x13, failD2

  li   x2, -3
  li   x28, 5
  mul  x10, x2, x28     # -15 = 0xFFFFFFF1
  mulh x11, x2, x28     # 0xFFFFFFFF
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
  li   x20, 0;  li x21, 0    # acc_hi, acc_lo
  li   x2, 0x10000;  li   x28, 0x10000
  # iter1: prod = 0x1_00000000
  mul  x10, x2, x28
  mulh x11, x2, x28
  add  x21, x21, x10
  sltu x22, x21, x10
  add  x20, x20, x11
  add  x20, x20, x22
  # iter2: prod = 0x1_00000000
  mul  x10, x2, x28
  mulh x11, x2, x28
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

  # ================================================================
  # K: Decimal conversion loop (mimics printf %u: divu/remu by 10)
  #    This is the EXACT pattern that exposed the OITF div/rem
  #    forwarding bug — back-to-back remu then divu in a loop,
  #    where divu's result feeds the next iteration's remu.
  # ================================================================
  # Test K1: value = 80000000
  #   digits: 8, 0, 0, 0, 0, 0, 0, 0  →  8 digits, remainder sum = 8
  li   x10, 80000000
  li   x11, 10
  li   x12, 0           # digit count
  li   x13, 0           # sum of remainders
dec_loop1:
  remu x14, x10, x11   # digit = value % 10
  add  x13, x13, x14   # accumulate
  divu x10, x10, x11   # value = value / 10   ← feeds next remu
  addi x12, x12, 1
  bnez x10, dec_loop1
  li   x15, 8
  bne  x12, x15, failK1_cnt
  li   x15, 8
  bne  x13, x15, failK1_sum

  # Test K2: value = 123456789
  #   digits: 1,2,3,4,5,6,7,8,9  →  9 digits, remainder sum = 45
  li   x10, 123456789
  li   x11, 10
  li   x12, 0
  li   x13, 0
dec_loop2:
  remu x14, x10, x11
  add  x13, x13, x14
  divu x10, x10, x11
  addi x12, x12, 1
  bnez x10, dec_loop2
  li   x15, 9
  bne  x12, x15, failK2_cnt
  li   x15, 45
  bne  x13, x15, failK2_sum

  # Test K3: value = 1  (edge case: single digit)
  li   x10, 1
  li   x11, 10
  li   x12, 0
  li   x13, 0
dec_loop3:
  remu x14, x10, x11
  add  x13, x13, x14
  divu x10, x10, x11
  addi x12, x12, 1
  bnez x10, dec_loop3
  li   x15, 1
  bne  x12, x15, failK3_cnt
  li   x15, 1
  bne  x13, x15, failK3_sum

  # ================================================================
  # L: Back-to-back div/rem pairs — OITF forwarding stress
  #    The bug: when div/rem finishes, the NEXT div/rem immediately
  #    forwards the previous result, but data has 1-cycle OITF delay.
  # ================================================================

  # L1: divu immediately followed by remu (same operands)
  li   x2, 100
  li   x28, 7
  divu x10, x2, x28    # 14
  remu x11, x2, x28    # 2  ← must NOT get divu's 14
  li   x12, 14
  bne  x10, x12, failL1_div
  li   x13, 2
  bne  x11, x13, failL1_rem

  # L2: remu immediately followed by divu (same operands)
  li   x2, 100
  li   x28, 7
  remu x10, x2, x28    # 2
  divu x11, x2, x28    # 14 ← must NOT get remu's 2
  li   x12, 2
  bne  x10, x12, failL2_rem
  li   x13, 14
  bne  x11, x13, failL2_div

  # L3: signed div immediately followed by rem
  li   x2, -100
  li   x28, 7
  div  x10, x2, x28    # -14 (truncated toward zero)
  rem  x11, x2, x28    # -2  (sign follows dividend)
  li   x12, -14
  bne  x10, x12, failL3_div
  li   x13, -2
  bne  x11, x13, failL3_rem

  # L4: signed rem immediately followed by div
  li   x2, -100
  li   x28, 7
  rem  x10, x2, x28    # -2
  div  x11, x2, x28    # -14
  li   x12, -2
  bne  x10, x12, failL4_rem
  li   x13, -14
  bne  x11, x13, failL4_div

  # L5: loop with back-to-back divu/remu (OITF forwarding in loop context)
  #     value = 999, divisor = 10, iterate until 0
  #     quotients: 99, 9, 0 → sum = 108
  #     remainders: 9, 9, 9 → sum = 27
  li   x20, 999
  li   x21, 10
  li   x22, 0          # sum of quotients
  li   x23, 0          # sum of remainders
  li   x24, 0          # iteration count
divrem_loop:
  divu x10, x20, x21   # quotient
  remu x11, x20, x21   # remainder  ← back-to-back with divu
  add  x22, x22, x10
  add  x23, x23, x11
  addi x24, x24, 1
  mv   x20, x10        # next value = quotient
  bnez x20, divrem_loop
  li   x25, 108
  bne  x22, x25, failL5_qsum
  li   x25, 27
  bne  x23, x25, failL5_rsum
  li   x25, 3
  bne  x24, x25, failL5_cnt

  # L6: mixed MUL + DIV/REM back-to-back (cross-unit OITF forwarding)
  li   x2, 6
  li   x28, 7
  mul  x10, x2, x28    # 42
  divu x11, x10, x28   # 42 / 7 = 6  ← RAW on MUL result + div
  remu x12, x10, x28   # 42 % 7 = 0  ← back-to-back div→rem
  li   x13, 6
  bne  x11, x13, failL6_div
  li   x14, 0
  bne  x12, x14, failL6_rem

  # ================================================================
  # M: O3-specific patterns — extracted from CoreMark -O3 disassembly
  #    These replicate the exact instruction sequences that O3
  #    generates but O2 does not (loop unroll, aggressive mul, etc.)
  # ================================================================

  # M1: divu→mul immediate RAW (main @ 0x1137C: divu a1,a1,a3 → mul a4,a4,a1)
  #     div result is the VERY NEXT mul's operand — OITF cross-unit forwarding
  li   x2, 200
  li   x28, 7
  li   x4, 5
  divu x10, x2, x28    # 200/7 = 28
  mul  x11, x10, x4    # 28*5 = 140  ← RAW on divu result
  li   x12, 28
  bne  x10, x12, failM1_div
  li   x13, 140
  bne  x11, x13, failM1_mul

  # M2: divu→remu→mul triple (__udivdi3 @ 0x15020 pattern)
  #     Three M-ext instructions in a row, mul uses divu's result
  li   x2, 1000
  li   x28, 7
  divu x10, x2, x28    # 1000/7 = 142
  remu x11, x2, x28    # 1000%7 = 6   ← back-to-back with divu
  mul  x12, x10, x11   # 142*6 = 852  ← uses both divu and remu results
  li   x13, 142
  bne  x10, x13, failM2_div
  li   x14, 6
  bne  x11, x14, failM2_rem
  li   x15, 852
  bne  x12, x15, failM2_mul

  # M3: mulhu→mul back-to-back, same operands (main @ 0x11794 pattern)
  #     64-bit multiply: both go to MUL unit, OITF must track two entries
  li   x2, 0x10001
  li   x28, 0x10001
  mulhu x10, x2, x28   # high = 0x00000001
  mul   x11, x2, x28   # low  = 0x00020001  ← back-to-back mulhu→mul
  li   x12, 1
  bne  x10, x12, failM3_hi
  li   x13, 0x00020001
  bne  x11, x13, failM3_lo

  # M4: unrolled mul×4 with ZERO intervening instructions (O3 unroll)
  #     O2 inserts li/addi between muls; O3 unrolls them back-to-back
  li   x2, 2;  li x4, 4;  li x6, 6;  li x8, 8
  li   x28, 3; li x5, 5;  li x7, 7;  li x9, 9
  mul  x10, x2, x28    # 6   ─┐
  mul  x11, x4, x5     # 20   │ 4 consecutive MUL, no gaps
  mul  x12, x6, x7     # 42   │
  mul  x13, x8, x9     # 72  ─┘
  add  x14, x10, x11   # 26
  add  x15, x12, x13   # 114
  add  x16, x14, x15   # 140
  li   x17, 140
  bne  x16, x17, failM4

  # M5: printf %u with 0xFFFFFFFF (max 10-digit value, longest remu/divu loop)
  #     4294967295 → digits: 4,2,9,4,9,6,7,2,9,5 → sum=57, count=10
  li   x10, 0xFFFFFFFF
  li   x11, 10
  li   x12, 0           # digit count
  li   x13, 0           # digit sum
dec_loop_max:
  remu x14, x10, x11   # digit = value % 10
  add  x13, x13, x14
  divu x10, x10, x11   # value = value / 10
  addi x12, x12, 1
  bnez x10, dec_loop_max
  li   x15, 10
  bne  x12, x15, failM5_cnt
  li   x15, 57
  bne  x13, x15, failM5_sum

  # M6: divu→mul→divu chain (each result feeds the next)
  #     1000/3=333, 333*2=666, 666/7=95
  li   x2, 1000
  li   x28, 3
  li   x4, 2
  li   x5, 7
  divu x10, x2, x28    # 333
  mul  x11, x10, x4    # 666  ← RAW on divu
  divu x12, x11, x5    # 95   ← RAW on mul, cross-unit again
  li   x13, 333
  bne  x10, x13, failM6_d1
  li   x14, 666
  bne  x11, x14, failM6_m
  li   x15, 95
  bne  x12, x15, failM6_d2

  # M7: mul→divu→remu→mul cross-unit ping-pong
  #     6*7=42, 42/5=8, 42%5=2, 8*2=16
  li   x2, 6
  li   x28, 7
  li   x4, 5
  mul  x10, x2, x28    # 42
  divu x11, x10, x4    # 8   ← RAW on mul result
  remu x12, x10, x4    # 2   ← back-to-back divu→remu, same src
  mul  x13, x11, x12   # 16  ← uses both divu and remu results
  li   x14, 8
  bne  x11, x14, failM7_div
  li   x15, 2
  bne  x12, x15, failM7_rem
  li   x16, 16
  bne  x13, x16, failM7_mul

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
failK1_cnt: li x26,1; li x27,17; li gp,17; j fail_loop
failK1_sum: li x26,1; li x27,18; li gp,18; j fail_loop
failK2_cnt: li x26,1; li x27,19; li gp,19; j fail_loop
failK2_sum: li x26,1; li x27,20; li gp,20; j fail_loop
failK3_cnt: li x26,1; li x27,21; li gp,21; j fail_loop
failK3_sum: li x26,1; li x27,22; li gp,22; j fail_loop
failL1_div: li x26,1; li x27,23; li gp,23; j fail_loop
failL1_rem: li x26,1; li x27,24; li gp,24; j fail_loop
failL2_rem: li x26,1; li x27,25; li gp,25; j fail_loop
failL2_div: li x26,1; li x27,26; li gp,26; j fail_loop
failL3_div: li x26,1; li x27,27; li gp,27; j fail_loop
failL3_rem: li x26,1; li x27,28; li gp,28; j fail_loop
failL4_rem: li x26,1; li x27,29; li gp,29; j fail_loop
failL4_div: li x26,1; li x27,30; li gp,30; j fail_loop
failL5_qsum: li x26,1; li x27,31; li gp,31; j fail_loop
failL5_rsum: li x26,1; li x27,32; li gp,32; j fail_loop
failL5_cnt:  li x26,1; li x27,33; li gp,33; j fail_loop
failL6_div:  li x26,1; li x27,34; li gp,34; j fail_loop
failL6_rem:  li x26,1; li x27,35; li gp,35; j fail_loop
failM1_div:  li x26,1; li x27,36; li gp,36; j fail_loop
failM1_mul:  li x26,1; li x27,37; li gp,37; j fail_loop
failM2_div:  li x26,1; li x27,38; li gp,38; j fail_loop
failM2_rem:  li x26,1; li x27,39; li gp,39; j fail_loop
failM2_mul:  li x26,1; li x27,40; li gp,40; j fail_loop
failM3_hi:   li x26,1; li x27,41; li gp,41; j fail_loop
failM3_lo:   li x26,1; li x27,42; li gp,42; j fail_loop
failM4:      li x26,1; li x27,43; li gp,43; j fail_loop
failM5_cnt:  li x26,1; li x27,44; li gp,44; j fail_loop
failM5_sum:  li x26,1; li x27,45; li gp,45; j fail_loop
failM6_d1:   li x26,1; li x27,46; li gp,46; j fail_loop
failM6_m:    li x26,1; li x27,47; li gp,47; j fail_loop
failM6_d2:   li x26,1; li x27,48; li gp,48; j fail_loop
failM7_div:  li x26,1; li x27,49; li gp,49; j fail_loop
failM7_rem:  li x26,1; li x27,50; li gp,50; j fail_loop
failM7_mul:  li x26,1; li x27,51; li gp,51; j fail_loop
fail_loop:
  j fail_loop

cf_mul3:
  li   a1, 3
  mul  a0, a0, a1
  ret

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
