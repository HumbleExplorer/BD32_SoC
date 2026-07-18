# call_stack_stress.S - isolate coremark CRC-corruption root cause.
#
# coremark fails with BOTH computed CRC and the "should be" (known_id) garbage.
# list_traverse (no function calls) PASSES, all 50 riscv-tests PASS.
# Differentiator = function calls (recursion/stack) combined with MUL/OITF.
#
# ABI-safe: do NOT use x1(ra)/x2(sp)/x3(gp) as general operands.
# Sub-tests (each sets gp=failcode, x27=0 on fail, x27=1 only on full pass):
#   A: MUL result read AFTER retirement (bd32 scenario G recomputes every iter,
#      so it never reads a retired MUL from the regfile -> coverage gap).
#   B: function call does MUL and must preserve caller's callee-saved s0; returns product.
#   C: recursion + MUL + stack (factorial(5)=120).
#   D: MUL in-flight in OITF, immediate function call, then read retired MUL result.
#
# x27=1 on completion => pass;  x27=0 + gp=failcode => which sub-test failed.

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  li sp, 0x1F000            # set up stack (CORE_TEST shares one 0x10000 TCM space)

  # ===================== Test A: MUL read-after-retire =====================
  li x5, 7
  li x6, 6
  mul x28, x5, x6           # x28 = 42, dispatched to OITF
  # filler (independent, avoid x1/x2/x3/x28) to force the MUL to RETIRE first
  li x7, 1
  li x8, 2
  li x9, 3
  li x10, 4
  li x11, 5
  li x12, 6
  li x13, 7
  li x14, 8
  li x15, 9
  li x16, 10
  li x17, 11
  li x18, 12
  li x19, 13
  li x20, 14
  li x21, 15
  li x22, 16
  li x23, 17
  li x24, 18
  li x25, 19
  li x26, 20
  li x27, 21
  li x29, 22
  li x30, 23
  li x31, 24
  li x4, 25
  add x29, x28, x0          # read x28 now (should be in regfile after retire)
  li x30, 42
  bne x29, x30, fail_A

  # ===================== Test B: call does MUL, preserves s0 =====================
  li s0, 0x12345678
  li x10, 5                 # a0 = 5
  li x11, 9                 # a1 = 9
  jal ra, mulsub            # x10 = 5*9 = 45, must preserve s0
  li x30, 0x12345678
  bne s0, x30, fail_B
  li x30, 45
  bne x10, x30, fail_B2

  # ===================== Test C: recursion + MUL + stack (factorial) =====================
  li x10, 5
  jal ra, fact              # x10 = 120
  li x30, 120
  bne x10, x30, fail_C

  # ===================== Test D: MUL in OITF + immediate call =====================
  li x5, 8
  li x6, 7
  mul x28, x5, x6           # x28 = 56, in OITF
  jal ra, leaf              # immediate function call while MUL in flight
  add x29, x28, x0          # read retired MUL result
  li x30, 56
  bne x29, x30, fail_D

  # ===================== Test E: MUL result as STORE/LOAD ADDRESS (matrix pattern) =====================
  li x5, 0x1B000          # base
  li x6, 0                # i
  li x7, 8                # words per row (stride)
  li x28, 0xAB           # data
  li x29, 0               # accum
E_loop:
  mul x8, x6, x7           # x8 = i*stride  (offset from MUL)
  add x9, x5, x8           # x9 = base + offset  (address from MUL)
  sw x28, 0(x9)           # store at computed address
  lw x10, 0(x9)           # load back
  add x29, x29, x10
  addi x6, x6, 1
  li x11, 8
  bne x6, x11, E_loop
  li x30, 0x558           # 8 * 0xAB = 0x558
  bne x29, x30, fail_E

  # ===================== Test F: recursion chasing linked list (core_list_find pattern) =====================
  li x5, 0x1C000
  li x6, 0x1C010
  sw x6, 0(x5)            # node0.next
  li x7, 1
  sw x7, 4(x5)            # node0.data
  li x8, 0x1C020
  sw x8, 0(x6)            # node1.next
  li x9, 2
  sw x9, 4(x6)            # node1.data
  sw x0, 0(x8)            # node2.next = 0
  li x10, 3
  sw x10, 4(x8)           # node2.data
  li x11, 0x1C000         # head
  jal ra, listsum
  li x30, 6                # 1+2+3 = 6
  bne x10, x30, fail_F

  # ===================== Test G: in-place list reversal (core_list_reverse pattern) =====================
  # build 1->2->3->NULL with data 1,2,3
  li x5, 0x1D000
  li x6, 0x1D010
  sw x6, 0(x5)            # node0.next = node1
  li x7, 1
  sw x7, 4(x5)            # node0.data = 1
  li x8, 0x1D020
  sw x8, 0(x6)            # node1.next = node2
  li x9, 2
  sw x9, 4(x6)            # node1.data = 2
  sw x0, 0(x8)            # node2.next = 0
  li x10, 3
  sw x10, 4(x8)           # node2.data = 3
  # reverse in place: prev=0; cur=head; while(cur){ next=cur->next; cur->next=prev; prev=cur; cur=next; }
  li x11, 0               # prev = NULL
  li x12, 0x1D000         # cur = head
G_rev_loop:
  beq x12, x0, G_rev_done
  lw x13, 0(x12)          # x13 = cur->next  (load)
  sw x11, 0(x12)          # cur->next = prev  (store to cur)
  mv x14, x12             # prev = cur
  mv x11, x14
  mv x12, x13             # cur = next
  j G_rev_loop
G_rev_done:
  # head is now x11 (node2, data 3). traverse, expect order 3,2,1.
  li x15, 0               # sum (should still be 6)
  li x16, 3               # expected first data
  mv x12, x11             # cur = new head
G_chk_loop:
  beq x12, x0, G_chk_done
  lw x17, 4(x12)          # x17 = cur->data
  bne x17, x16, fail_G     # data must match expected (3 then 2 then 1)
  add x15, x15, x17
  addi x16, x16, -1        # next expected = prev-1
  lw x12, 0(x12)          # cur = cur->next
  j G_chk_loop
G_chk_done:
  li x30, 6
  bne x15, x30, fail_G

  # ===================== Test H: store to a LOAD-computed address (load->store-addr fwd) =====================
  li x5, 0x1E000          # base
  li x6, 0x1E008          # ptr
  sw x6, 0(x5)            # base[0] = ptr
  li x7, 0x55             # value
  lw x8, 0(x5)            # x8 = *base = ptr  (load)
  sw x7, 0(x8)            # *(ptr) = 0x55  (store to LOADED address)
  lw x9, 0(x6)            # x9 = *ptr
  li x30, 0x55
  bne x9, x30, fail_H

  # ===================== Test I: indirect call via jalr (core_list_find cmp pattern) =====================
  # cmp_func(a,b) = (a==b) ? 1 : 0
  # 1) direct jalr with address from auipc
  # 2) store ptr to mem, reload via lw, jalr (coremark loads cmp_ptr from struct)
  # 3) loop over list, call cmp for each node's data vs target, count matches
  # build list: node0 @0x1F100 data=7 -> node1 @0x1F110 data=7 -> 0
  li x20, 0x1F100
  li x21, 0x1F110
  sw x21, 0(x20)            # n0.next
  li x22, 7
  sw x22, 4(x20)           # n0.data = 7
  sw x0, 0(x21)            # n1.next = 0
  li x23, 7
  sw x23, 4(x21)           # n1.data = 7

  # get cmp_func address via PC-relative load-local-address
  lla x5, cmp_func
  # direct jalr sanity: cmp(7,7) => 1
  li x10, 7
  li x11, 7
  jalr ra, x5
  li x30, 1
  bne x10, x30, fail_I

  # store ptr, reload via lw, jalr: cmp(7,3) => 0 (coremark reloads cmp from struct)
  li x6, 0x1F200
  sw x5, 0(x6)             # fp slot
  lw x7, 0(x6)             # reload fp
  li x10, 7
  li x11, 3
  jalr ra, x7
  li x30, 0
  bne x10, x30, fail_I2

  # loop over list calling cmp(data,7); both nodes data=7 => 2 matches
  li x8, 0x1F100           # head
  li x9, 0                 # count
I_loop:
  beq x8, x0, I_done
  lw x10, 4(x8)            # x10 = node->data
  li x11, 7                # target
  lw x7, 0(x6)             # reload fp each iteration (coremark reloads cmp)
  jalr ra, x7              # x10 = cmp(data,7)
  add x9, x9, x10          # count += match
  lw x8, 0(x8)             # x8 = node->next
  j I_loop
I_done:
  li x30, 2
  bne x9, x30, fail_I3

  # ===================== Test J: half-load result feeds branch condition (load->branch) =====================
  li x5, 0x1F300
  li x6, 0x1234
  sh x6, 2(x5)            # store half 0x1234 at x5+2
  lh x7, 2(x5)            # x7 = 0x00001234 (positive)
  bgez x7, J_pos          # taken (x7 >= 0)
  j fail_J                # must NOT reach
J_pos:
  li x8, 0x1F308
  li x9, 0x8000           # half 0x8000 -> signed -32768
  sh x9, 2(x8)
  lh x10, 2(x8)           # x10 = 0xFFFF8000 (negative)
  bltz x10, J_neg         # taken (negative)
  j fail_J2
J_neg:
  li x11, 0x1F310
  li x12, 0x00FF
  sh x12, 0(x11)          # store half 0x00FF
  lh x13, 0(x11)          # x13 = 0xFF = 255
  addi x14, x13, 1        # x14 = 256
  li x30, 256
  bne x14, x30, fail_J3

  # ===================== Test K: byte/half load from a freshly-loaded address (load->byte-load addr) =====================
  li x5, 0x1F400          # ptr slot
  li x6, 0x1F408          # target
  sw x6, 0(x5)            # *(x5) = x6
  li x7, 0xAB
  sb x7, 0(x6)            # *(x6) = 0xAB
  lw x8, 0(x5)            # x8 = loaded ptr (=x6)
  lbu x9, 0(x8)           # x9 = *(byte*)x8 = 0xAB
  li x30, 0xAB
  bne x9, x30, fail_K
  li x10, 0x80
  sb x10, 1(x6)           # *(x6+1) = 0x80
  lb x11, 1(x8)           # x11 = 0xFFFFFF80 (sign-extended)
  li x30, 0xFFFFFF80
  bne x11, x30, fail_K2
  li x12, 0x1234
  sh x12, 2(x6)           # *(x6+2) = 0x1234
  lh x13, 2(x8)           # x13 = 0x1234
  li x30, 0x1234
  bne x13, x30, fail_K3

  # all passed
  li x26, 1
  li x27, 1
pass_loop:
  j pass_loop

fail_A:  li gp, 41;  li x27, 0;  li x26, 1;  j fail_loop
fail_B:  li gp, 42;  li x27, 0;  li x26, 1;  j fail_loop
fail_B2: li gp, 422; li x27, 0;  li x26, 1;  j fail_loop
fail_C:  li gp, 43;  li x27, 0;  li x26, 1;  j fail_loop
fail_D:  li gp, 44;  li x27, 0;  li x26, 1;  j fail_loop
fail_E:  li gp, 45;  li x27, 0;  li x26, 1;  j fail_loop
fail_F:  li gp, 46;  li x27, 0;  li x26, 1;  j fail_loop
fail_G:  li gp, 47;  li x27, 0;  li x26, 1;  j fail_loop
fail_H:  li gp, 48;  li x27, 0;  li x26, 1;  j fail_loop
fail_I:  li gp, 49;   li x27, 0;  li x26, 1;  j fail_loop
fail_I2: li gp, 492;  li x27, 0;  li x26, 1;  j fail_loop
fail_I3: li gp, 493;  li x27, 0;  li x26, 1;  j fail_loop
fail_J:  li gp, 50;   li x27, 0;  li x26, 1;  j fail_loop
fail_J2: li gp, 502;  li x27, 0;  li x26, 1;  j fail_loop
fail_J3: li gp, 503;  li x27, 0;  li x26, 1;  j fail_loop
fail_K:  li gp, 51;   li x27, 0;  li x26, 1;  j fail_loop
fail_K2: li gp, 512;  li x27, 0;  li x26, 1;  j fail_loop
fail_K3: li gp, 513;  li x27, 0;  li x26, 1;  j fail_loop
fail_loop:
  j fail_loop

  # ---- mulsub: x10 = a0 * a1, preserves s0, uses stack ----
mulsub:
  addi sp, sp, -16
  sw ra, 12(sp)
  sw s0, 8(sp)
  mul x10, x10, x11          # x10 = a0 * a1 = 45
  sw x10, 4(sp)              # store to stack (exercise OITF->store-data forward)
  lw s0, 8(sp)
  lw ra, 12(sp)
  addi sp, sp, 16
  ret

  # ---- leaf: trivial callee, just returns (exercise call/ret under OITF) ----
leaf:
  addi sp, sp, -8
  sw ra, 4(sp)
  lw ra, 4(sp)
  addi sp, sp, 8
  ret

  # ---- fact: x10 = factorial(a0), recursive, MUL + stack ----
fact:
  addi sp, sp, -16
  sw ra, 12(sp)
  sw s0, 8(sp)
  mv s0, x10                 # save n (a0)
  bnez x10, fact_rec
  li x10, 1                  # fact(0) = 1
  j fact_done
fact_rec:
  addi x10, x10, -1          # n-1
  jal ra, fact               # x10 = fact(n-1)
  mv x11, s0                 # x11 = n
  mul x10, x10, x11          # x10 = fact(n-1) * n
fact_done:
  lw s0, 8(sp)
  lw ra, 12(sp)
  addi sp, sp, 16
  ret

  # ---- listsum: x10 = recursive sum of linked-list data (core_list_find pattern) ----
  #   x11 = current node pointer (a0)
  #   sum(p) = p==0 ? 0 : p->data + sum(p->next)
  #   p->data must survive the recursive call => use callee-saved s1.
listsum:
  addi sp, sp, -16
  sw ra, 12(sp)
  sw s1, 8(sp)                  # save callee-saved s1 (holds p->data across call)
  beq x11, x0, listsum_done     # if p == 0 return 0
  lw s1, 4(x11)                # s1 = p->data  (callee-saved, survives recursive call)
  lw x11, 0(x11)               # x11 = p->next  (pointer chase)
  jal ra, listsum              # x10 = sum(p->next)
  add x10, x10, s1             # x10 += p->data
  j listsum_ret
listsum_done:
  li x10, 0
listsum_ret:
  lw s1, 8(sp)
  lw ra, 12(sp)
  addi sp, sp, 16
  ret

  # ---- cmp_func: x10 = (a0 == a1) ? 1 : 0  (leaf, used via jalr) ----
cmp_func:
  sub x12, x10, x11          # x12 = a - b
  seqz x10, x12              # x10 = (a==b)
  ret

  RVTEST_CODE_END
