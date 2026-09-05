# trap_basic.S - 基础 trap 测试：非法指令 / ecall / load 访存错误
#
# 验证点：
#   1) mtvec 分发与 handler 返回（mepc+4 跳过故障指令 + mret）
#   2) mcause 逐项核对：非法指令=2 / ecall(M-mode)=11 / load 访存错误=5
#   3) trap 重定向寄存器化（r_trap_redirect）后的完整 trap 流程
# handler 只动 t0(x5)/t1(x6)，期望 mcause 放 a7(x17)，trap 计数放 s1(x9)
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  la x1, trap_handler
  .word 0x30509073          # csrw mtvec, x1（CSR 指令手编，build_asm march 无 zicsr）
  li s1, 0

  # ---- 1) 非法指令（全 1 编码）→ mcause=2 ----
  li a7, 2
  .word 0xffffffff           # opcode=1111111，落 Decoder default → 非法
  addi s1, s1, 1             # handler mepc+4 跳回到这里

  # ---- 2) ecall（M-mode）→ mcause=11 ----
  li a7, 11
  ecall                      # mepc 指向 ecall 本身，handler +4 跳过
  addi s1, s1, 1

  # ---- 3) load 访存错误：地址 0 属 BootROM 区（LSU 禁入）→ mcause=5 ----
  li a7, 5
  lw a0, 0(x0)
  addi s1, s1, 1

  # ---- 校验：恰好 3 次 trap ----
  li t0, 3
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
