# DTCM store/load/forwarding stress test.
# x27 = FAIL_CODE on failure (1 = pass). Pure DTCM ops + forwarding checks.
# In CORE_TEST mode DTCM_BASE_TAG=0x0001, so DTCM is at 0x00010000.
# We use 0x00019000+ region (above the loaded ITCM code) for data buffers.
#
# Covers patterns coremark stresses but riscv-tests (ITCM-only data) don't:
#   A: word store -> load round trip
#   B: halfword store/load (sign + zero extend)
#   C: byte store/load (sign + zero extend)
#   D: load -> dependent (load_use forwarding via WB)
#   E: store -> load same address (store-load forwarding)
#   F: consecutive store/load of multiple words + arithmetic
#   G: load addr from forwarded reg (addi produces base, lw uses it)
#   H: store data from forwarded reg

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ---- A: word store -> load round trip ----
  li   x2, 0x00019000
  li   x3, 0x12345678
  sw   x3, 0(x2)            # [0x19000] = 0x12345678
  lw   x4, 0(x2)            # x4 = [0x19000]
  li   x5, 0x12345678
  bne  x4, x5, failA

  # ---- B: halfword ----
  li   x6, 0x00019004
  # positive halfword (bit15=0)
  li   x7, 0x00007ABC
  sh   x7, 0(x6)            # store half
  lhu  x8, 0(x6)            # zero-extend -> 0x7ABC
  li   x9, 0x00007ABC
  bne  x8, x9, failB1
  lh   x10, 0(x6)           # sign-extend -> 0x00007ABC (positive)
  li   x11, 0x00007ABC
  bne  x10, x11, failB2
  # negative halfword (bit15=1)
  li   x12, 0x0000CDEF
  sh   x12, 0(x6)
  lh   x13, 0(x6)           # sign-extend -> 0xFFFFCDEF
  li   x14, 0xFFFFCDEF
  bne  x13, x14, failB3

  # ---- C: byte ----
  li   x15, 0x00019008
  li   x16, 0x0000005A
  sb   x16, 0(x15)          # store byte 0x5A
  lbu  x17, 0(x15)          # zero-ext -> 0x5A
  li   x18, 0x0000005A
  bne  x17, x18, failC1
  lb   x19, 0(x15)          # sign-ext -> 0x5A (positive)
  bne  x19, x18, failC2
  # signed byte negative
  li   x20, 0x000000EF
  sb   x20, 0(x15)
  lb   x21, 0(x15)          # sign-ext -> 0xFFFFFFEF
  li   x22, 0xFFFFFFEF
  bne  x21, x22, failC3

  # ---- D: load -> dependent (load_use forwarding) ----
  li   x2, 0x00019000
  lw   x23, 0(x2)           # x23 = 0x12345678
  addi x24, x23, 1          # x24 = 0x12345679  (RAW on load result)
  li   x25, 0x12345679
  bne  x24, x25, failD

  # ---- E: store -> load same address ----
  li   x26, 0x0001900C
  li   x27, 0x00000055
  sw   x27, 0(x26)          # [0x1900C] = 0x55
  lw   x28, 0(x26)          # x28 = 0x55 (store-load forwarding)
  li   x29, 0x00000055
  bne  x28, x29, failE

  # ---- F: consecutive multi-word + arithmetic ----
  li   x2, 0x00019010
  li   x3, 10
  sw   x3, 0(x2)
  li   x4, 20
  sw   x4, 4(x2)
  li   x5, 30
  sw   x5, 8(x2)
  li   x6, 40
  sw   x6, 12(x2)
  lw   x7, 0(x2)
  lw   x8, 4(x2)
  lw   x9, 8(x2)
  lw   x10, 12(x2)
  add  x11, x7, x8
  add  x11, x11, x9
  add  x11, x11, x10        # sum = 100
  li   x12, 100
  bne  x11, x12, failF

  # ---- G: load addr from forwarded reg ----
  li   x13, 0x00019000
  addi x14, x13, 0x10       # x14 = 0x00019010 (base+0x10)
  lw   x15, 0(x14)          # x15 = [0x19010] = 10  (addr via forwarded addi)
  li   x16, 10
  bne  x15, x16, failG

  # ---- H: store data from forwarded reg (load->store) ----
  li   x2, 0x00019000       # reload base (clobbered in F)
  li   x17, 0x00019020
  lw   x18, 0(x2)           # x18 = [0x19000] = 0x12345678
  sw   x18, 0(x17)          # [0x19020] = x18 (data via forwarded load)
  lw   x19, 0(x17)
  li   x20, 0x12345678
  bne  x19, x20, failH

  # ---- I: auipc PC-source check ----
  # jal writes pc+4 (= address of the NEXT instruction, the auipc below).
  # auipc must compute rd = pc_of_auipc (its own address). If the CPU feeds
  # pc+4 instead of pc, auipc result is off by 4 -> global access breaks.
  jal  x3, 2f
2:
  auipc x4, 0               # x4 must == x3 (address of this auipc)
  bne  x4, x3, failI1

  # ---- J: function call with stack save/restore (calling convention) ----
  li   sp, 0x0001F000       # stack pointer in high DTCM
  li   a0, 7
  jal  ra, myfunc           # call myfunc(a0=7)
  li   x5, 14               # myfunc doubles argument
  bne  a0, x5, failJ
  li   a0, 5
  jal  ra, myfunc2          # nested: 5*3
  li   x6, 15
  bne  a0, x6, failJ2

  # ---- K: array-processing loop (branch + shift + load + alu + store) ----
  li   x2, 0x00019000       # array base
  li   x10, 10; sw x10, 0(x2)
  li   x10, 20; sw x10, 4(x2)
  li   x10, 30; sw x10, 8(x2)
  li   x10, 40; sw x10, 12(x2)
  li   x3, 0                # i = 0
  li   x4, 4                # N = 4
  li   x5, 0                # sum = 0
loopK:
  bge  x3, x4, endK         # if i>=N exit
  slli x6, x3, 2            # x6 = i*4
  add  x7, x2, x6           # x7 = &array[i]
  lw   x8, 0(x7)            # x8 = array[i]
  add  x5, x5, x8           # sum += array[i]
  addi x3, x3, 1            # i++
  j    loopK
endK:
  li   x9, 100              # 10+20+30+40
  bne  x5, x9, failK

  # ---- L: store address from forwarded load ----
  li   x11, 0x00019008      # [0x19008] = 30 (set above)
  lw   x12, 0(x11)          # x12 = 30
  li   x13, 0x00019044
  sw   x12, 0(x13)          # store 30 to [0x19044] (addr via loaded reg)
  lw   x14, 0(x13)
  li   x15, 30
  bne  x14, x15, failL

  # all passed
  li x26, 1
  li x27, 1
pass_loop:
  j pass_loop

failA:  li x26,1; li x27,2;  li gp,2;  j fail_loop
failB1: li x26,1; li x27,3;  li gp,3;  j fail_loop
failB2: li x26,1; li x27,4;  li gp,4;  j fail_loop
failB3: li x26,1; li x27,5;  li gp,5;  j fail_loop
failC1: li x26,1; li x27,6;  li gp,6;  j fail_loop
failC2: li x26,1; li x27,7;  li gp,7;  j fail_loop
failC3: li x26,1; li x27,8;  li gp,8;  j fail_loop
failD:  li x26,1; li x27,9;  li gp,9;  j fail_loop
failE:  li x26,1; li x27,10; li gp,10; j fail_loop
failF:  li x26,1; li x27,11; li gp,11; j fail_loop
failG:  li x26,1; li x27,12; li gp,12; j fail_loop
failH:  li x26,1; li x27,13; li gp,13; j fail_loop
failI1: li x26,1; li x27,16; li gp,16; j fail_loop
failJ:  li x26,1; li x27,14; li gp,14; j fail_loop
failJ2: li x26,1; li x27,15; li gp,15; j fail_loop
failK:  li x26,1; li x27,17; li gp,17; j fail_loop
failL:  li x26,1; li x27,18; li gp,18; j fail_loop
fail_loop:
  j fail_loop

myfunc:
  addi sp, sp, -16
  sw   ra, 12(sp)
  sw   s0, 8(sp)
  li   s0, 2
  mul  a0, a0, s0          # a0 = a0*2
  lw   s0, 8(sp)
  lw   ra, 12(sp)
  addi sp, sp, 16
  ret

myfunc2:
  addi sp, sp, -16
  sw   ra, 12(sp)
  sw   s1, 8(sp)
  li   s1, 3
  mul  a0, a0, s1          # a0 = a0*3
  lw   s1, 8(sp)
  lw   ra, 12(sp)
  addi sp, sp, 16
  ret

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
