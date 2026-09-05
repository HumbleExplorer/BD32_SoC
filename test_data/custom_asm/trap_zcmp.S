# trap_zcmp.S - 定向测试：cm.push 展开中途触发访存异常
#
# 背景（2026-09-05 trap 重定向寄存器化的定向回归）：
#   cm.push 微操作流在 EX 访存出错（sp 指向 BootROM 区 → store 访问错误）
#   时，trap 与 flush 当拍发生（展开 FSM 被 zcmp_flush_any 打回 IDLE、
#   未发出的微操作全部冲刷），PC 跳转由 r_trap_redirect 在下一拍发出。
#   旧实现为当拍 redirect——本测试保证寄存器化后语义不变、且展开器可恢复。
#
# 验证点：
#   1) 展开中途异常：sp=4，首条微操作 sw ra,-4(sp) 访问地址 0（BootROM 区）
#      → mcause=7，mepc 指向 cm.push 本身
#   2) handler 跳过 cm.push（mepc+4）、恢复 sp、mret 返回
#   3) 异常后展开器完整恢复：一次干净的 cm.push{ra},16 / cm.pop{ra},16
#      往返，ra 数据无损
#
# 编码（字段推导 + 与已验证的 zcmp_popret_ra.S（0xb842/0xbe42）同族核对，
# GCC 15.2 不支持 Zcmp 汇编助记符）：
#   cm.push {ra,s0-s11},64  0x0001b8f2（高半字 C.NOP 填充；rlist=15, spimm=0, adj=64）
#   cm.push {ra},16         0x0001b842
#   cm.pop  {ra},16         0x0001ba42
# 注意：Zcmp 为 16 位指令，.word 高半字必须填 C.NOP(0x0001)，否则执行流会
# 踩进全 0 半字触发非法指令 trap
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  la x1, trap_handler
  .word 0x30509073          # csrw mtvec, x1（CSR 指令手编，build_asm march 无 zicsr）
  li s1, 0

  # ---- 1) 坏 sp 触发展开中途访存异常 ----
  li a7, 7                   # 期望 mcause=7（store 访问错误）
  li x2, 4                   # sp=4：首条微操作 sw ra,-4(sp) → 地址 0
  .word 0x0001b8f2               # cm.push {ra,s0-s11},64（14 条微操作，必在展开中被打断）
  addi s1, s1, 1             # trap 计数：handler 跳过 cm.push 后到达
  li x3, 2

  # ---- 校验异常次数 ----
  li t0, 1
  bne s1, t0, fail

  # ---- 2) 展开器恢复验证：干净 push/pop 往返 ----
  li x2, 0x0001B000          # 栈顶（DTCM 内）
  li a0, 0x1234
  mv x1, a0                  # 待保存值放 ra
  .word 0x0001b842               # cm.push {ra},16（x1 压栈，sp -= 16）
  li x1, 0x5555              # 破坏 ra
  li x3, 3
  .word 0x0001ba42               # cm.pop {ra},16（x1 出栈恢复，sp += 16）
  li t0, 0x1234
  bne x1, t0, fail           # ra 必须从栈上无损恢复

  # ---- 3) 栈内容与指针复核 ----
  li t0, 0x0001B000
  bne x2, t0, fail           # sp 回到栈顶
  lw t1, -4(x2)              # push 压入的位置仍保有数据
  li t0, 0x1234
  bne t1, t0, fail

  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl

trap_handler:
  li x3, 90                 # 诊断：handler 进入
  .word 0x342022f3          # csrr t0, mcause
  mv x3, t0                 # 诊断：打印 mcause
  bne t0, a7, fail
  li x2, 0x0001B000          # 恢复 sp（trap 时 sp=4）
  .word 0x34102373          # csrr t1, mepc
  addi t1, t1, 4             # 跳过 cm.push
  .word 0x34131073          # csrw mepc, t1
  mret

  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
