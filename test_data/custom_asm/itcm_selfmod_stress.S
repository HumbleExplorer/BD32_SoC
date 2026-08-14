# 自修改代码多轮压力测试
# 每轮改写 ITCM 中 slot_inst 指令（addi/lui/负立即数），fence.i 后 jalr 跳入执行并校验结果。
# 验证：ITCM 镜像写（CORE_TEST 共享窗口） + FENCE.I 冲刷取指 + 重取新指令，多轮覆盖不同编码。

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # 计算 slot_inst 绝对地址（PC 相对，la 生成 auipc+addi）
  la    x10, slot_inst

  # ---- Round 1: addi x15, x0, 0x222 ----
  li   x8, 0x22200793
  sw   x8, 0(x10)
  .word 0x0000100F            # fence.i（-march=rv32im 无 zifencei，用原始编码）
  jalr x1, 0(x10)            # 跳入 slot_inst（x1 = 返回地址）
  li   x9, 0x222
  bne  x15, x9, failR1

  # ---- Round 2: addi x15, x0, 0x333 ----
  li   x8, 0x33300793
  sw   x8, 0(x10)
  .word 0x0000100F            # fence.i
  jalr x1, 0(x10)
  li   x9, 0x333
  bne  x15, x9, failR2

  # ---- Round 3: addi x15, x0, 0x444 ----
  li   x8, 0x44400793
  sw   x8, 0(x10)
  .word 0x0000100F            # fence.i
  jalr x1, 0(x10)
  li   x9, 0x444
  bne  x15, x9, failR3

  # ---- Round 4: addi x15, x0, 0x555 ----
  li   x8, 0x55500793
  sw   x8, 0(x10)
  .word 0x0000100F            # fence.i
  jalr x1, 0(x10)
  li   x9, 0x555
  bne  x15, x9, failR4

  # ---- Round 5: addi x16, x0, -1（负立即数）----
  li   x8, 0xFFF00813
  sw   x8, 0(x10)
  .word 0x0000100F            # fence.i
  jalr x1, 0(x10)
  li   x9, -1
  bne  x16, x9, failR5

  # ---- Round 6: lui x17, 0x12345（0x12345<<12 | 17<<7 | 0x37 = 0x123458B7）----
  li   x8, 0x123458B7
  sw   x8, 0(x10)
  .word 0x0000100F            # fence.i
  jalr x1, 0(x10)
  li   x9, 0x12345000
  bne  x17, x9, failR6

  # all passed
  li x26, 1
  li x27, 1
pass_loop:
  j pass_loop

failR1: li x26,1; li x27,2;  li gp,2;  j fail_loop
failR2: li x26,1; li x27,3;  li gp,3;  j fail_loop
failR3: li x26,1; li x27,4;  li gp,4;  j fail_loop
failR4: li x26,1; li x27,5;  li gp,5;  j fail_loop
failR5: li x26,1; li x27,6;  li gp,6;  j fail_loop
failR6: li x26,1; li x27,7;  li gp,7;  j fail_loop
fail_loop:
  j fail_loop

  # 被改写的指令槽：初始 nop，每轮写入新指令后 fence.i + jalr 执行
slot_inst:
  nop
slot_ret:
  jalr x0, 0(x1)             # 返回 jalr 后的检查代码

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
