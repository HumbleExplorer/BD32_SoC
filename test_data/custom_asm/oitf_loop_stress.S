# oitf_loop_stress.S - Stress test replicating CoreMark -O3 matrix multiply
# and bitextract inner loops with multiple iterations.
# Tests OITF forwarding across loop iterations with branch flushes.
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0

  # ============================================================
  # Test 1: Matrix multiply inner loop pattern (N=4 iterations)
  # mul a5,a5,a4 → add t3,t3,a5 → branch back
  # ============================================================
  li t3, 0            # accumulator = 0
  li a6, 0            # counter = 0
  li s0, 4            # N = 4 iterations
  li s1, 2            # stride

  # Setup arrays in DTCM
  li a7, 0x1B000      # array A pointer
  li t1, 0x1C000      # array B pointer
  li t0, 3; sh t0, 0(a7)
  li t0, 5; sh t0, 2(a7)
  li t0, 7; sh t0, 4(a7)
  li t0, 2; sh t0, 6(a7)
  li t0, 2; sh t0, 0(t1)
  li t0, 4; sh t0, 2(t1)
  li t0, 6; sh t0, 4(t1)
  li t0, 8; sh t0, 6(t1)

  # Reset pointers
  li a7, 0x1B000
  li t1, 0x1C000

mat_loop:
  lh a5, 0(a7)       # A[i]
  lh a4, 0(t1)       # B[i]
  addi a6, a6, 1     # counter++
  addi a7, a7, 2     # A ptr += 2
  mul a5, a5, a4     # a5 = A[i] * B[i] → OITF
  add t1, t1, s1     # B ptr += stride
  add t3, t3, a5     # acc += a5 (depends on MUL)
  bltu a6, s0, mat_loop

  # Expected: 3*2 + 5*4 + 7*6 + 2*8 = 6+20+42+16 = 84
  li x13, 84
  bne t3, x13, fail

  # ============================================================
  # Test 2: Bitextract inner loop pattern (N=4 iterations)
  # mul→srai→srai→andi→andi→mul→add→branch
  # ============================================================
  li t4, 0            # accumulator = 0
  li a7, 0            # counter = 0
  li s0, 4            # N = 4

  # Setup arrays
  li t1, 0x1B000      # array A
  li t3, 0x1C000      # array B
  li t0, 3; sh t0, 0(t1)
  li t0, 7; sh t0, 2(t1)
  li t0, 11; sh t0, 4(t1)
  li t0, 2; sh t0, 6(t1)
  li t0, 5; sh t0, 0(t3)
  li t0, 2; sh t0, 2(t3)
  li t0, 3; sh t0, 4(t3)
  li t0, 9; sh t0, 6(t3)

  # Reset pointers
  li t1, 0x1B000
  li t3, 0x1C000
  li s1, 2            # B stride = 2

bit_loop:
  lh a5, 0(t1)       # A[i]
  lh a4, 0(t3)       # B[i]
  addi a7, a7, 1     # counter++
  addi t1, t1, 2     # A ptr += 2
  mul a5, a5, a4     # MUL1: a5 = A[i]*B[i] → OITF
  add t3, t3, s1     # B ptr += stride (independent)
  srai a6, a5, 2     # a6 = a5 >> 2 (first reader of a5)
  srai a5, a5, 5     # a5 = a5 >> 5 (SECOND reader of a5!)
  andi a6, a6, 15    # a6 &= 0xF
  andi a5, a5, 127   # a5 &= 0x7F
  mul a5, a6, a5     # MUL2: a5 = a6 * a5 → OITF
  add t4, t4, a5     # acc += a5 (depends on MUL2)
  bltu a7, s0, bit_loop

  # Compute expected:
  # i=0: A=3,B=5: mul=15, >>2=3, >>5=0, 3&15=3, 0&127=0, 3*0=0
  # i=1: A=7,B=2: mul=14, >>2=3, >>5=0, 3&15=3, 0&127=0, 3*0=0
  # i=2: A=11,B=3: mul=33, >>2=8, >>5=1, 8&15=8, 1&127=1, 8*1=8
  # i=3: A=2,B=9: mul=18, >>2=4, >>5=0, 4&15=4, 0&127=0, 4*0=0
  # Total: 0+0+8+0 = 8
  li x13, 8
  bne t4, x13, fail

  # ============================================================
  # Test 3: DIV→load→ALU→MUL→store pattern (from main iterations calc)
  # ============================================================
  li a5, 100
  li a0, 7
  li t5, 0x1D000      # use fixed DTCM address as pseudo-stack
  li a4, 5
  sw a4, 0(t5)        # store seed=5

  divu a5, a5, a0    # a5 = 100/7 = 14 → OITF (DIV)
  lw a4, 0(t5)       # a4 = 5 (load from DTCM, independent of DIV)
  addi a5, a5, 1     # a5 = 14+1 = 15 (depends on DIV)
  mul a5, a4, a5     # a5 = 5*15 = 75 → OITF (MUL)
  sw a5, 4(t5)       # store result (depends on MUL)
  lw a3, 4(t5)       # read back

  li x13, 75
  bne a3, x13, fail

  # ============================================================
  # Test 4: Back-to-back MULs with same rd (WAW via OITF)
  # ============================================================
  li a1, 3
  li a2, 4
  li a3, 5
  li a4, 6
  mul a5, a1, a2     # a5 = 12 → OITF
  mul a5, a3, a4     # a5 = 30 → OITF (WAW with prev, but no RAW on a5)
  add a6, a5, a1     # a6 = 30 + 3 = 33 (should get SECOND mul's result)

  li x13, 30
  bne a5, x13, fail_t4
  li x13, 33
  bne a6, x13, fail_t4
  j test5
fail_t4:
  j fail

  # ============================================================
  # Test 5: MUL→branch→MUL (branch between two MULs)
  # ============================================================
test5:
  li a1, 10
  li a2, 20
  li a3, 30
  li a4, 40
  mul a5, a1, a2     # a5 = 200 → OITF
  beq x0, x0, t5_skip # unconditional branch (always taken)
  nop                 # wrong path (should be flushed)
  nop
t5_skip:
  mul a6, a3, a4     # a6 = 1200 → OITF
  add a7, a5, a6     # a7 = 200 + 1200 = 1400

  li x13, 1400
  bne a7, x13, fail

  # PASS
  li x27, 1
  li x26, 1
p: j p

fail:
  li x27, 0
  li x26, 1
fl: j fl

  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
