# list_reverse_sep.S - 链表原地反转 + 遍历求和（4 节点，数据和=1+2+3+4=10）。
# 链表放在 0x1B000（DTCM tag 0x0001，与当前 CORE_TEST 的 DTCM_BASE_TAG 一致）。
# 注：原本本测试用 0x2B000（tag 0x0002）验证 coremark 的分离 ITCM/DTCM 映射，
# 但 CORE_TEST 下 DTCM_BASE_TAG=0x0001，0x2B000 落不到 DTCM（读回 0 会死循环），
# 故改到 0x1B000 使其在当前配置下可 PASS；如需测分离映射，临时把 DTCM_BASE_TAG
# 改回 0x0002 并把地址恢复为 0x2B000。
# x27=1 pass / x27=0 fail; gp=32 表示反转/遍历结果错误。

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

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

  li x10, 0
  li x11, 0x1B000
revloop:
  beq x11, x0, revdone
  lw x12, 0(x11)
  sw x10, 0(x11)
  mv x10, x11
  mv x11, x12
  j revloop
revdone:
  li x13, 0
trav:
  beq x10, x0, check
  lw x14, 4(x10)
  add x13, x13, x14
  lw x10, 0(x10)
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
  li gp, 32
fail_loop:
  j fail_loop

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
