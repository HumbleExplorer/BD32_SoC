# DTCM lui+addi+store stress test
# Targets the exact pattern from CoreMark's g_cpu_freq_hz bug:
#   lui   a5, 0x4c4b           # a5 = 0x04C4B000
#   addi  a5, a5, 1024         # a5 = 0x04C4B400 (80000000)
#   sw    a5, offset(base)     # store to DTCM
#
# Also tests:
#   - lui+addi RAW hazard (back-to-back dependent pair)
#   - Multiple lui+addi chains (register pressure)
#   - Store with large negative offset (as compiler generates)
#   - Store-then-load round trip with lui-computed data
#   - Adjacent stores to consecutive addresses (DTCM write port stress)
#   - Call+return preserving lui-computed values across function boundary

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # Use DTCM region above loaded code for test data
  # In core_test: DTCM at 0x00010000, use 0x00019000+

  # ==== A: Exact CoreMark pattern (lui+addi+sw) ====
  # This is the EXACT sequence from _init() that fails
  li   x2, 0x00019000           # base address
  lui  x3, 0x4c4b               # x3 = 0x04C4B000
  addi x3, x3, 1024             # x3 = 0x04C4B400 = 80000000
  sw   x3, 0(x2)                # [0x19000] = 80000000
  lw   x4, 0(x2)                # x4 = [0x19000]
  bne  x4, x3, failA            # must match

  # ==== B: lui+addi RAW hazard (no NOP between) ====
  # Test multiple lui+addi pairs back-to-back
  lui  x5, 0x12345
  addi x5, x5, 0x678            # x5 = 0x12345678
  lui  x6, 0xABCDE
  addi x6, x6, -1               # x6 = 0xABCDEFFF (addi sign-extends -1 = 0xFFF)
  sw   x5, 4(x2)
  sw   x6, 8(x2)
  lw   x7, 4(x2)
  lw   x8, 8(x2)
  bne  x7, x5, failB1
  bne  x8, x6, failB2

  # ==== C: lui with zero immediate ====
  lui  x9, 0                    # x9 = 0
  sw   x9, 12(x2)
  lw   x10, 12(x2)
  bne  x10, x9, failC

  # ==== D: lui + addi with max positive offset ====
  lui  x11, 0x80000             # x11 = 0x80000000
  addi x11, x11, 2047           # x11 = 0x800007FF (max positive addi)
  sw   x11, 16(x2)
  lw   x12, 16(x2)
  bne  x12, x11, failD

  # ==== E: lui + addi with max negative offset ====
  lui  x13, 0x1                 # x13 = 0x00001000
  addi x13, x13, -2048          # x13 = 0x00000800 (min negative addi)
  sw   x13, 20(x2)
  lw   x14, 20(x2)
  bne  x14, x13, failE

  # ==== F: Chain of 4 lui+addi pairs (register pressure) ====
  lui  x15, 0x11111
  addi x15, x15, 0x111          # x15 = 0x11111111
  lui  x16, 0x22222
  addi x16, x16, 0x222          # x16 = 0x22222222
  lui  x17, 0x33333
  addi x17, x17, 0x333          # x17 = 0x33333333
  lui  x18, 0x44444
  addi x18, x18, 0x444          # x18 = 0x44444444
  sw   x15, 24(x2)
  sw   x16, 28(x2)
  sw   x17, 32(x2)
  sw   x18, 36(x2)
  lw   x19, 24(x2)
  lw   x20, 28(x2)
  lw   x21, 32(x2)
  lw   x22, 36(x2)
  bne  x19, x15, failF1
  bne  x20, x16, failF2
  bne  x21, x17, failF3
  bne  x22, x18, failF4

  # ==== G: Store with large negative offset (mimics compiler -G0 pattern) ====
  # Compiler uses: lui s0, 0x21; sw a5, -1528(s0)
  li   s0, 0x0001A000           # base = 0x0001A000
  lui  a5, 0x4c4b
  addi a5, a5, 1024             # a5 = 80000000
  sw   a5, -1528(s0)            # [0x0001A000 - 1528] = [0x00019A08] = 80000000
  lw   a6, -1528(s0)            # load back
  bne  a6, a5, failG

  # ==== H: Adjacent stores to consecutive words ====
  li   x2, 0x00019100
  li   x3, 0xAAAAAAAA
  li   x4, 0x55555555
  li   x5, 0xDEADBEEF
  li   x6, 0xCAFEBABE
  sw   x3, 0(x2)
  sw   x4, 4(x2)
  sw   x5, 8(x2)
  sw   x6, 12(x2)
  lw   x7, 0(x2)
  lw   x8, 4(x2)
  lw   x9, 8(x2)
  lw   x10, 12(x2)
  bne  x7, x3, failH1
  bne  x8, x4, failH2
  bne  x9, x5, failH3
  bne  x10, x6, failH4

  # ==== I: lui+addi value preserved across function call ====
  lui  s0, 0x4c4b
  addi s0, s0, 1024             # s0 = 80000000 (callee-saved)
  li   sp, 0x0001F000
  jal  ra, dummy_func           # call function (should preserve s0)
  li   x11, 0x00019200
  sw   s0, 0(x11)               # store s0 after call
  lw   x12, 0(x11)
  lui  x13, 0x4c4b
  addi x13, x13, 1024
  bne  x12, x13, failI          # s0 must survive the call

  # ==== J: Store to 16 consecutive words, then read all back ====
  li   x2, 0x00019300           # base
  li   x3, 0                    # counter = 0
loopJ:
  li   x4, 16
  bge  x3, x4, endJ
  slli x5, x3, 2                # offset = counter * 4
  add  x6, x2, x5              # addr = base + offset
  lui  x7, 0xAAAAA
  add  x7, x7, x3              # data = 0xAAAAA000 + counter
  sw   x7, 0(x6)
  addi x3, x3, 1
  j    loopJ
endJ:
  # Read back and verify
  li   x3, 0
loopJv:
  li   x4, 16
  bge  x3, x4, endJv
  slli x5, x3, 2
  add  x6, x2, x5
  lw   x7, 0(x6)
  lui  x8, 0xAAAAA
  add  x8, x8, x3
  bne  x7, x8, failJ
  addi x3, x3, 1
  j    loopJv
endJv:

  # ==== K: Repeated store to SAME address (overwrite pattern) ====
  li   x2, 0x00019400
  li   x3, 0x11111111
  sw   x3, 0(x2)
  li   x3, 0x22222222
  sw   x3, 0(x2)
  li   x3, 0x33333333
  sw   x3, 0(x2)
  li   x3, 0x44444444
  sw   x3, 0(x2)                # final value
  lw   x4, 0(x2)
  li   x5, 0x44444444
  bne  x4, x5, failK

  # all passed
  li x26, 1
  li x27, 1
pass_loop:
  j pass_loop

failA:  li x26,1; li x27,2;  j fail_loop
failB1: li x26,1; li x27,3;  j fail_loop
failB2: li x26,1; li x27,4;  j fail_loop
failC:  li x26,1; li x27,5;  j fail_loop
failD:  li x26,1; li x27,6;  j fail_loop
failE:  li x26,1; li x27,7;  j fail_loop
failF1: li x26,1; li x27,8;  j fail_loop
failF2: li x26,1; li x27,9;  j fail_loop
failF3: li x26,1; li x27,10; j fail_loop
failF4: li x26,1; li x27,11; j fail_loop
failG:  li x26,1; li x27,12; j fail_loop
failH1: li x26,1; li x27,13; j fail_loop
failH2: li x26,1; li x27,14; j fail_loop
failH3: li x26,1; li x27,15; j fail_loop
failH4: li x26,1; li x27,16; j fail_loop
failI:  li x26,1; li x27,17; j fail_loop
failJ:  li x26,1; li x27,18; j fail_loop
failK:  li x26,1; li x27,19; j fail_loop
fail_loop:
  j fail_loop

dummy_func:
  # Clobbers caller-saved regs, preserves s0
  li   a0, 0x99999999
  li   a1, 0x88888888
  li   t0, 0x77777777
  li   t1, 0x66666666
  ret

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
