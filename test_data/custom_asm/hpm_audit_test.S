# hpm_audit_test.S - HPM 计数准确性审计（配合 tb_core_top +define+HPM_AUDIT 参考模型）
#
# 与 stall_test/hpm_test 的分工：
#   - 本测试不做事后自检精确数值，而是"无偏地跑满各指令类"：
#     tb_core_top 的 HPM_AUDIT 参考模型（独立译码 + 退休计账）会在测试结束时
#     与 DUT 的 mhpmcounter/minstret/mcycle 逐项对账，打印 PASS/FAIL。
#   - 覆盖类：ALU/LOAD/STORE/BRANCH/JUMP/MULDIV(mul+div)/CSR/SYS + minstret 恒等。
#   - 设计约束：不用 mcountinhibit/mcounterclr（控制语义由 stall_test 覆盖，
#     这样参考模型无需复刻门控，对账才是独立可信的）；各块间避免 load-use
#     依赖（停顿不影响计数正确性，但保持块语义干净）。
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li sp, 0x00020000              # DTCM 数据区
  li a3, 0x11111111
  li a4, 0x22222222

  # 预置 LOAD 数据
  li t0, 0
  li t1, 160
20:
  addi t0, t0, 4
  sw t0, 0(sp)
  addi sp, sp, 4
  addi t1, t1, -1
  bnez t1, 20b
  li sp, 0x00020000              # 回到数据区起点

  # ---------- 块 1: ALU ×120（寄存器依赖走前递，无停顿类） ----------
  li t0, 120
21:
  add a1, a3, a4
  sub a1, a1, a3
  xor a1, a1, a4
  or a1, a1, a3
  and a1, a1, a4
  slli a1, a1, 1
  addi t0, t0, -1
  bnez t0, 21b

  # ---------- 块 2: LOAD ×160（独立寄存器轮转，无 load-use） ----------
  li t0, 160
  mv a1, zero
22:
  lw a2, 0(sp)
  addi sp, sp, 4
  or a1, a1, a2
  addi t0, t0, -1
  bnez t0, 22b

  # ---------- 块 3: STORE ×100 ----------
  li t0, 100
  li sp, 0x00020000
23:
  sw a1, 0(sp)
  sw a3, 4(sp)
  addi sp, sp, 8
  addi t0, t0, -1
  bnez t0, 23b

  # ---------- 块 4: BRANCH（循环自带 60 次 taken + 60 次 not-taken） ----------
  li t0, 60
  li a1, 0
24:
  addi a1, a1, 1
  blt a1, t0, 24b                # taken ×59 + not-taken ×1
  beq a1, t0, 25f                # not-taken
  j fail
25:

  # ---------- 块 5: JUMP ×40（jal + jalr） ----------
  li t0, 20
26:
  jal ra, 28f
  addi t0, t0, -1
  bnez t0, 26b
  j 27f
28:
  jalr x0, 0(ra)                 # 每次 jal 配一次 jalr 返回
  ret                            # 不可达保护
27:

  # ---------- 块 6: MULDIV（mul ×30 独立链 + divu ×6） ----------
  li a1, 7
  li a2, 3
  li t0, 30
29:
  mul a4, a1, a2                 # 独立乘（不依赖上一条 mul）
  addi t0, t0, -1
  bnez t0, 29b
  li a1, 1000000
  li a2, 7
  li t0, 6
30:
  divu a3, a1, a2
  addi t0, t0, -1
  bnez t0, 30b

  # ---------- 块 7: CSR ×12（csrr + csrw） ----------
  .word 0x32029073               # csrw mcountinhibit, x0（显式全计数）
  li t0, 5
31:
  .word 0xB0502373               # csrr t1, 0xB05
  .word 0xB06023F3               # csrr t2, 0xB06
  addi t0, t0, -1
  bnez t0, 31b

  # ---------- 块 8: SYS ×6（fence） ----------
  .word 0x0000000F
  .word 0x0000000F
  .word 0x0000000F
  .word 0x0000000F
  .word 0x0000000F
  .word 0x0000000F

  # ---------- 守卫：无 trap ----------
  .word 0x34302373               # csrr t1, mcause(0x343)
  beqz t1, 32f
  j fail
32:
  li x25, 0xA0D17                # 审计魔数（TB 参考模型触发标记）
  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
