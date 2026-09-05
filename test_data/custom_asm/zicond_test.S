# zicond_test.S - Zicond（czero.eqz/czero.nez）条件零写扩展功能测试
#
# custom_asm 以 rv32im 汇编（无 Zicond 助记符），因此用 .word 直接嵌入 32 位指令编码；
# 编码用 xpack gcc 15.2.0 (-march=rv32im_zicsr_zicond) 汇编 + objdump 得到，寄存器固定：
#   czero.eqz a0,a1,a2  0x0ec5d533    czero.eqz a0,a1,x0  0x0e05d533
#   czero.eqz a3,x0,a2  0x0ec056b3    czero.eqz a0,a1,a1  0x0eb5d533
#   czero.nez a0,a1,a2  0x0ec5f533    czero.nez a0,a1,x0  0x0e05f533
#   czero.nez a3,x0,a2  0x0ec076b3    czero.nez a4,a1,a2  0x0ec5f733
#   czero.eqz a0,a1,a0  0x0ea5d533    czero.nez a0,a1,a0  0x0ea5f533
#   czero.eqz a0,a0,a2  0x0ec55533    czero.nez a0,a0,a2  0x0ec57533
#   czero.eqz t0,t0,t0  0x0e52d2b3    czero.nez t0,t0,t0  0x0e52f2b3
#   czero.eqz x0,a1,a2  0x0ec5d033    czero.nez x0,a1,a2  0x0ec5f033
#
# 语义：czero.eqz rd,rs1,rs2 → rd = (rs2==0) ? 0 : rs1
#       czero.nez rd,rs1,rs2 → rd = (rs2!=0) ? 0 : rs1
# 注意：写 a3(x13) 的指令结果用 t0(x5) 比对，避免"先 li x13 再自比较"。
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0

  # ---- 1) EQZ 基本语义：rs2=0 → 0 / rs2!=0 → rs1 ----
  li a1, 0x55
  li a2, 0
  .word 0x0ec5d533            # czero.eqz a0,a1,a2 -> 0
  li t0, 0
  bne a0, t0, fail
  li x3, 1
  li a2, 7
  .word 0x0ec5d533            # czero.eqz a0,a1,a2 -> 0x55
  li t0, 0x55
  bne a0, t0, fail
  li x3, 2

  # ---- 2) NEZ 基本语义：rs2=0 → rs1 / rs2!=0 → 0 ----
  li a1, 0x55
  li a2, 0
  .word 0x0ec5f533            # czero.nez a0,a1,a2 -> 0x55
  li t0, 0x55
  bne a0, t0, fail
  li x3, 3
  li a2, 7
  .word 0x0ec5f533            # czero.nez a0,a1,a2 -> 0
  li t0, 0
  bne a0, t0, fail
  li x3, 4

  # ---- 3) rs1=x0：两条路径结果均为 0（无非定态/非法） ----
  li a2, 5
  .word 0x0ec056b3            # czero.eqz a3,x0,a2 -> 0
  li t0, 0
  bne a3, t0, fail
  .word 0x0ec076b3            # czero.nez a3,x0,a2 -> 0
  bne a3, t0, fail
  li x3, 5

  # ---- 4) rs2==rs1：rs2 非零 → EQZ/NEZ 均输出 rs1 本身 ----
  li a1, 0x55
  .word 0x0eb5d533            # czero.eqz a0,a1,a1 -> rs2=0x55!=0 -> rs1=0x55
  li t0, 0x55
  bne a0, t0, fail
  .word 0x0ec5f533            # czero.nez a0,a1,a1 -> rs2!=0 -> 0
  li t0, 0
  bne a0, t0, fail
  li x3, 6

  # ---- 5) rd==rs1 覆盖：写回前读旧值由前递保证 ----
  li a2, 0
  li a0, 0x99
  .word 0x0ec55533            # czero.eqz a0,a0,a2 -> 0
  li t0, 0
  bne a0, t0, fail
  li a2, 1
  li a0, 0x99
  .word 0x0ec55533            # czero.eqz a0,a0,a2 -> 0x99
  li t0, 0x99
  bne a0, t0, fail
  li a0, 0x99
  .word 0x0ec57533            # czero.nez a0,a0,a2 -> 0
  li t0, 0
  bne a0, t0, fail
  li a2, 0
  li a0, 0x99
  .word 0x0ec57533            # czero.nez a0,a0,a2 -> 0x99
  li t0, 0x99
  bne a0, t0, fail
  li x3, 7

  # ---- 6) rd==rs2：rs2 读取旧值（写回不前递到自身） ----
  li a1, 0x33
  li a0, 5
  .word 0x0ea5d533            # czero.eqz a0,a1,a0 -> rs2=5!=0 -> 0x33
  li t0, 0x33
  bne a0, t0, fail
  li a0, 0
  .word 0x0ea5d533            # czero.eqz a0,a1,a0 -> rs2=0 -> 0
  li t0, 0
  bne a0, t0, fail
  li x3, 8

  # ---- 7) 背靠背依赖链（EX 前递穿 select）：结果互相作为下一拍 rs1/rs2 ----
  li a1, 0x55
  li a2, 0
  .word 0x0ec5f533            # czero.nez a0,a1,a2 -> rs2=0 透传 -> a0=0x55
  .word 0x0ea5d533            # czero.eqz a0,a1,a0 -> rs2=a0=0x55!=0 -> rs1=0x55
  .word 0x0ea5f533            # czero.nez a0,a1,a0 -> rs2=a0=0x55!=0 -> 0
  li t0, 0
  bne a0, t0, fail
  li x3, 9

  # ---- 8) x0 目的：写抑制，流水线无残留 ----
  li a1, 0x55
  li a2, 7
  .word 0x0ec5d033            # czero.eqz x0,a1,a2
  .word 0x0ec5f033            # czero.nez x0,a1,a2
  addi a0, a1, 1              # x0 写不得破坏后续执行
  li t0, 0x56
  bne a0, t0, fail
  li x3, 10

  # ---- 9) rd==rs1==rs2 自环 ----
  li t0, 0
  .word 0x0e52d2b3            # czero.eqz t0,t0,t0 -> rs2=0 -> 0
  bne t0, x0, fail
  li t0, 0x66
  .word 0x0e52f2b3            # czero.nez t0,t0,t0 -> rs2=0x66!=0 -> 0
  bne t0, x0, fail
  li x3, 11

  # ---- 10) 与分支等价性（ golden 对照，两种选择极性各一次） ----
  li a1, 0xAB
  li a2, 1
  .word 0x0ec5f533            # czero.nez a0,a1,a2 -> 0
  bnez a2, 1f                 # 分支版 golden：a2!=0 -> t0=0
  li t0, 0xAB
  j 2f
1: li t0, 0
2: bne a0, t0, fail
  li a2, 0
  .word 0x0ec5f533            # czero.nez a0,a1,a2 -> 0xAB
  bnez a2, 3f
  li t0, 0xAB
  j 4f
3: li t0, 0
4: bne a0, t0, fail
  li x3, 12

  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
