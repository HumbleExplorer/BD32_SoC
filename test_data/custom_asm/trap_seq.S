# trap_seq.S - 连续 trap 测试：handler 直接返回到下一条故障指令
#
# 验证点：
#   1) 背靠背异常：handler 跳过当前故障指令后立即落入下一条故障指令，
#      r_trap_redirect 需正确地重复锁存-发出（回归 2026-09-05 重定向寄存器化）
#   2) 全 0 指令（0x00000000）作为故障源之一（2026-09-04 判非法的回归）
#   3) store 访存错误（mcause=7）
# trap 源依次：非法(2) → 全0(2) → 非法(2) → store 访存错误(7)，共 4 次
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  la x1, trap_handler
  .word 0x30509073          # csrw mtvec, x1（CSR 指令手编，build_asm march 无 zicsr）
  li s1, 0

  # ---- 连续三个故障指令，handler 逐个跳过 ----
  li a7, 2
  .word 0xffffffff           # 非法 → mcause=2
  .word 0x00000000           # 全 0（判非法的回归）→ mcause=2
  .word 0xffffffff           # 非法 → mcause=2
  addi s1, s1, 3             # 三连跳过后到达

  # ---- store 访存错误：地址 0 属 BootROM 区 → mcause=7 ----
  li a7, 7
  sw a0, 0(x0)
  addi s1, s1, 1

  # ---- 校验：恰好 4 次 trap ----
  li t0, 4
  bne s1, t0, fail

  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl

trap_handler:
  .word 0x342022f3          # csrr t0, mcause
  bne t0, a7, fail
  .word 0x34102373          # csrr t1, mepc
  addi t1, t1, 4
  .word 0x34131073          # csrw mepc, t1
  mret

  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
