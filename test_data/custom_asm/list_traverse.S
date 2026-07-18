# list_traverse.S - linked-list traversal mirroring coremark's list operation.
#
# x27 = 0 (fail) / 1 (pass) on completion; gp = fail code.
# In CORE_TEST mode DTCM_BASE_TAG=0x0001, so DTCM is at 0x00010000.
# We place nodes + data blocks in 0x1B000 / 0x1C000 regions (above the ITCM code).
#
# coremark's list_head:  { list_head *next; list_data *data; }   (pointers!)
#   traversal does a TWO-LEVEL dereference:
#     t  = p->data   (lw t, 4(p))      # address from p
#     k  = t->key    (lw k, 0(t))      # address from t (just loaded) -> LOAD->LOAD(ADDR)
#     p  = p->next   (lw p, 0(p))      # address from p
# This is exactly the load->load(address) hazard chain that pure load/store
# and array-loop tests do NOT exercise.
#
# Layout (sum of keys = 1+2+3+4 = 10):
#   Node0 @0x1B000: next=0x1B010 data=0x1C000
#   Node1 @0x1B010: next=0x1B020 data=0x1C008
#   Node2 @0x1B020: next=0x1B030 data=0x1C010
#   Node3 @0x1B030: next=0        data=0x1C018
#   Data0 @0x1C000: key=1
#   Data1 @0x1C008: key=2
#   Data2 @0x1C010: key=3
#   Data3 @0x1C018: key=4

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ---- build linked list (nodes + data blocks) ----
  li x2, 0x1B000
  li x3, 0x1B010
  sw x3, 0(x2)          # node0.next
  li x4, 0x1C000
  sw x4, 4(x2)          # node0.data

  li x5, 0x1B020
  sw x5, 0(x3)          # node1.next
  li x6, 0x1C008
  sw x6, 4(x3)          # node1.data

  li x7, 0x1B030
  sw x7, 0(x5)          # node2.next
  li x8, 0x1C010
  sw x8, 4(x5)          # node2.data

  sw x0, 0(x7)          # node3.next = 0
  li x9, 0x1C018
  sw x9, 4(x7)          # node3.data

  li x10, 1
  sw x10, 0(x4)         # data0.key = 1
  li x11, 2
  sw x11, 0(x6)         # data1.key = 2
  li x12, 3
  sw x12, 0(x8)         # data2.key = 3
  li x13, 4
  sw x13, 0(x9)         # data3.key = 4

  # ---- traverse: two-level dereference (coremark list pattern) ----
  li x14, 0x1B000       # p = head
  li x15, 0             # sum = 0
loop:
  beq x14, x0, done     # if p == 0 exit
  lw x16, 4(x14)        # x16 = p->data   (address from p)
  lw x17, 0(x16)        # x17 = p->data->key  (address from x16, just loaded)
  add x15, x15, x17     # sum += key
  lw x14, 0(x14)        # p = p->next    (address from p)
  j loop
done:
  li x18, 10
  bne x15, x18, failLIST

  # all passed
  li x26, 1
  li x27, 1
pass_loop:
  j pass_loop

failLIST:
  li x26, 1
  li x27, 0
  li gp, 30
fail_loop:
  j fail_loop

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
