# hpm_test.S - HPM 架构指令计数与每扩展独立计数测试
#
# 验证点：
#   1. cm.push 的内部 store 不计入 STORE 计数器（0xBC5）——架构指令计数证据；
#   2. mhp_counter12 (0xBCC) 把一条 cm.push 计为 1（整条架构指令）；
#   3. mhp_counter10 (0xBCA) 计 Zcb 指令；
#   4. mhp_counter11 (0xBCB) 计 B 扩展指令；
#   5. mhp_counter12 把 2 条 cm.push 计为 2。
#   6. mhp_counter13 (0xBCD) 计 CSR 指令；
#   7. mhp_counter14 (0xBCE) 计系统指令（fence）。
# 计数前先 mcounteren=0x7FFF 使能 bit0-14。
# .word 高半字是 C.NOP(0x0001)，会作为普通指令退休（计入 minstret 但不计入扩展计数）。
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0
  li t0, 0x7FFF
  .word 0x30629073               # csrw mcounteren, t0（使能 bit0-14）

  # ---- 1) STORE 计数器：cm.push 内部 3 个 store 不计入（0xBC5）----
  li sp, 0x1B000
  nop
  nop
  nop
  nop
  .word 0xBC502373               # csrr t1, 0xBC5（STORE 计数）
  .word 0x0001b866               # nop; cm.push {ra,s0-s1},-32
  .word 0xBC5023F3               # csrr t2, 0xBC5
  sub t3, t2, t1
  li t0, 0
  bne t3, t0, fail

  # ---- 2) Zcmp 计数器（0xBCC）：1 条 cm.push 计 1 ----
  li x3, 1
  li sp, 0x1B000
  nop
  nop
  nop
  nop
  .word 0xBCC02373               # csrr t1, 0xBCC（Zcmp 计数）
  .word 0x0001b866               # nop; cm.push {ra,s0-s1},-32
  .word 0xBCC023F3               # csrr t2, 0xBCC
  sub t3, t2, t1
  li t0, 1
  bne t3, t0, fail               # 若按微操作计，这里会是 4

  # ---- 3) Zcb 计数器（0xBCA）：4 条 c.lbu ----
  li x3, 2
  li a1, 0x1B000
  nop
  nop
  nop
  nop
  .word 0xBCA02373               # csrr t1, 0xBCA（Zcb 计数）
  .word 0x00018188               # nop; c.lbu a0,0(a1)
  .word 0x00018188
  .word 0x00018188
  .word 0x00018188
  nop
  nop
  nop
  nop
  nop
  nop
  .word 0xBCA023F3               # csrr t2, 0xBCA
  sub t3, t2, t1
  li t0, 4
  bne t3, t0, fail

  # ---- 4) B 扩展计数器（0xBCB）：3 条（sh1add/andn/clz）----
  li x3, 3
  li a1, 3
  li a2, 5
  nop
  nop
  nop
  nop
  .word 0xBCB02373               # csrr t1, 0xBCB（B 扩展计数）
  .word 0x20c5a533               # sh1add a0,a1,a2
  .word 0x40c5f533               # andn a0,a1,a2
  .word 0x60059513               # clz a0,a1
  nop
  nop
  nop
  nop
  nop
  nop
  .word 0xBCB023F3               # csrr t2, 0xBCB
  sub t3, t2, t1
  li t0, 3
  bne t3, t0, fail

  # ---- 5) Zcmp 计数器（0xBCC）：2 条 cm.push ----
  li x3, 4
  li sp, 0x1B000
  nop
  nop
  nop
  nop
  .word 0xBCC02373               # csrr t1, 0xBCC（Zcmp 计数）
  .word 0x0001b866               # nop; cm.push {ra,s0-s1},-32
  .word 0x0001b842               # nop; cm.push {ra},-16
  nop
  nop
  nop
  nop
  nop
  nop
  .word 0xBCC023F3               # csrr t2, 0xBCC
  sub t3, t2, t1
  li t0, 2
  bne t3, t0, fail

  # ---- 6) CSR 计数器（0xBCD）：3 条 csrrw（读取用的 csrr t1 也会在窗口内退休，+1）----
  li x3, 5
  nop
  nop
  nop
  nop
  .word 0xBCD02373               # csrr t1, 0xBCD（CSR 计数）
  .word 0xB0001073               # csrrw x0, mcycle, x0
  .word 0xB0001073
  .word 0xB0001073
  nop
  nop
  nop
  nop
  nop
  nop
  .word 0xBCD023F3               # csrr t2, 0xBCD
  sub t3, t2, t1
  li t0, 4                       # 3 条 csrrw + 读取用 csrr t1 自身
  bne t3, t0, fail

  # ---- 7) 系统指令计数器（0xBCE）：3 条 fence ----
  li x3, 6
  nop
  nop
  nop
  nop
  .word 0xBCE02373               # csrr t1, 0xBCE（系统指令计数）
  .word 0x0000000F               # fence
  .word 0x0000000F
  .word 0x0000000F
  nop
  nop
  nop
  nop
  nop
  nop
  .word 0xBCE023F3               # csrr t2, 0xBCE
  sub t3, t2, t1
  li t0, 3
  bne t3, t0, fail

  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
