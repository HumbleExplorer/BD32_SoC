# list_reverse.S - in-place linked-list reversal (coremark list benchmark modify pattern).
#
# x27 = 0 (fail) / 1 (pass); gp = fail code.
# CORE_TEST mode: DTCM at 0x00010000.
#
# coremark's core_list_reverse / mergesort REASSIGN next pointers via stores:
#     next = cur->next;        # lw x, 0(cur)
#     cur->next = prev;        # sw prev, 0(cur)   <-- STORE modifying list (addr from reg)
#     prev = cur; cur = next;
# seedcrc (init only) is correct but crclist (after reverse/sort) is wrong,
# so the STORE-MODIFY of the list is the prime suspect.
#
# Layout: 4 nodes {next@0, val@4}, val = 1,2,3,4  (sum = 10 either order)
#   0x1B000: next=0x1B008 val=1
#   0x1B008: next=0x1B010 val=2
#   0x1B010: next=0x1B018 val=3
#   0x1B018: next=0        val=4

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ---- build list ----
  li x2, 0x1B000
  li x3, 0x1B008
  sw x3, 0(x2)
  li x4, 1
  sw x4, 4(x2)
  li x5, 0x1B010
  sw x5, 0(x3)
  li x6, 2
  sw x6, 4(x3)
  li x7, 0x1B018
  sw x7, 0(x5)
  li x8, 3
  sw x8, 4(x5)
  sw x0, 0(x7)
  li x9, 4
  sw x9, 4(x7)

  # ---- in-place reverse ----
  li x10, 0            # prev = NULL
  li x11, 0x1B000      # cur = head
revloop:
  beq x11, x0, revdone
  lw x12, 0(x11)       # x12 = cur->next
  sw x10, 0(x11)       # cur->next = prev   <-- STORE modifying list (addr from cur)
  mv x10, x11          # prev = cur
  mv x11, x12          # cur = next
  j revloop
revdone:
  # x10 = new head (== 0x1B018)
  li x13, 0            # sum = 0
trav:
  beq x10, x0, check
  lw x14, 4(x10)       # val
  add x13, x13, x14
  lw x10, 0(x10)       # next
  j trav
check:
  li x15, 10
  bne x13, x15, failREV

  li x26, 1
  li x27, 1
pass_loop:
  j pass_loop

failREV:
  li x26, 1
  li x27, 0
  li gp, 31
fail_loop:
  j fail_loop

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
