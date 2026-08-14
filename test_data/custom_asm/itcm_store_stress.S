# ITCM 单端口让路压力测试
# 针对 ITCM 单端口化后 LSU 访问（CORE_TEST 共享窗口下 store 镜像写 + 取指让路）的时序压力：
#   A: 连续 8 次 store（真正背靠背，无间隔）→ 逐字读回校验
#   B: store → load 同地址紧接（让路后立即读回）
#   C: store → load → 依赖 add（load-use 停顿与让路重叠，Test E 模式，8 轮不同地址）
#   D: store 紧接 mul（rs1==rd 自依赖，OITF 派发与让路重叠）
#   E: store 紧接 jal 分支（让路与分支冲刷交互）
#   F: store / mul / load / bne 交错循环（OITF + 让路混合，16 轮）
#   G: 连续 store 交替两个地址（交叉让路）

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ---- A: 连续 8 次 store（背靠背）到 0x19000 ----
  li   x2, 0x00019000
  li   x5, 0x11111111
  li   x6, 0x22222222
  li   x7, 0x33333333
  li   x8, 0x44444444
  li   x9, 0x55555555
  li   x10, 0x66666666
  li   x11, 0x77777777
  li   x12, 0x88888888
  sw   x5, 0(x2)
  sw   x6, 4(x2)
  sw   x7, 8(x2)
  sw   x8, 12(x2)
  sw   x9, 16(x2)
  sw   x10, 20(x2)
  sw   x11, 24(x2)
  sw   x12, 28(x2)
  # 逐字读回
  lw   x13, 0(x2);  bne  x13, x5, failA1
  lw   x13, 4(x2);  bne  x13, x6, failA2
  lw   x13, 8(x2);  bne  x13, x7, failA3
  lw   x13, 12(x2); bne  x13, x8, failA4
  lw   x13, 16(x2); bne  x13, x9, failA5
  lw   x13, 20(x2); bne  x13, x10, failA6
  lw   x13, 24(x2); bne  x13, x11, failA7
  lw   x13, 28(x2); bne  x13, x12, failA8

  # ---- B: store → load 同地址紧接 ----
  li   x2, 0x00019100
  li   x5, 0x1234ABCD
  sw   x5, 0(x2)
  lw   x6, 0(x2)
  bne  x5, x6, failB

  # ---- C: store → load → 依赖 add（8 轮，地址递增，MUL 生成偏移）----
  li   x2, 0x00019180
  li   x28, 0xAB
  li   x29, 0
  li   x20, 8
  li   x21, 0
loopC:
  mul  x22, x21, x20          # offset = i*8（OITF 在途）
  add  x23, x2, x22           # addr = base + offset
  sw   x28, 0(x23)
  lw   x24, 0(x23)
  add  x29, x29, x24          # load-use：x24 依赖 lw
  addi x21, x21, 1
  bne  x21, x20, loopC
  li   x25, 0x558             # 8 * 0xAB
  bne  x29, x25, failC

  # ---- D: store 紧接 mul（rs1==rd）----
  li   x2, 0x00019200
  li   x5, 0x12345678
  sw   x5, 0(x2)
  li   x14, 7
  mul  x14, x14, x14          # x14 = 49（rs1==rd，让路后 OITF 派发）
  li   x15, 49
  bne  x14, x15, failD
  lw   x6, 0(x2)
  bne  x6, x5, failD2

  # ---- E: store 紧接 jal（让路与分支冲刷）----
  li   x2, 0x00019280
  li   x5, 0xDEADBEEF
  sw   x5, 0(x2)
  jal  x0, targetE
  li   x30, 0                  # 不应执行
  li   x27, 99
  j    fail_loop
targetE:
  lw   x6, 0(x2)
  bne  x6, x5, failE

  # ---- F: store / mul / load / bne 交错循环（16 轮）----
  li   x2, 0x00019300
  li   x20, 16
  li   x21, 0
  li   x29, 0
loopF:
  li   x5, 0x55
  sw   x5, 0(x2)
  mul  x22, x21, x21           # 平方（OITF）
  lw   x6, 0(x2)
  bne  x5, x6, failF
  add  x29, x29, x22
  addi x2, x2, 4
  addi x21, x21, 1
  bne  x21, x20, loopF
  li   x25, 0x4D8              # sum(i^2, i=0..15) = 1240
  bne  x29, x25, failF2

  # ---- G: 连续 store 交替两个地址 ----
  li   x2, 0x00019400
  li   x5, 0x11111111
  li   x6, 0x22222222
  sw   x5, 0(x2)
  sw   x6, 4(x2)
  sw   x5, 8(x2)
  sw   x6, 12(x2)
  sw   x5, 16(x2)
  sw   x6, 20(x2)
  sw   x5, 24(x2)
  sw   x6, 28(x2)
  lw   x7, 0(x2);  bne  x7, x5, failG
  lw   x7, 4(x2);  bne  x7, x6, failG
  lw   x7, 8(x2);  bne  x7, x5, failG
  lw   x7, 12(x2); bne  x7, x6, failG
  lw   x7, 16(x2); bne  x7, x5, failG
  lw   x7, 20(x2); bne  x7, x6, failG
  lw   x7, 24(x2); bne  x7, x5, failG
  lw   x7, 28(x2); bne  x7, x6, failG

  # all passed
  li x26, 1
  li x27, 1
pass_loop:
  j pass_loop

failA1: li x26,1; li x27,2;  li gp,2;  j fail_loop
failA2: li x26,1; li x27,3;  li gp,3;  j fail_loop
failA3: li x26,1; li x27,4;  li gp,4;  j fail_loop
failA4: li x26,1; li x27,5;  li gp,5;  j fail_loop
failA5: li x26,1; li x27,6;  li gp,6;  j fail_loop
failA6: li x26,1; li x27,7;  li gp,7;  j fail_loop
failA7: li x26,1; li x27,8;  li gp,8;  j fail_loop
failA8: li x26,1; li x27,9;  li gp,9;  j fail_loop
failB:  li x26,1; li x27,10; li gp,10; j fail_loop
failC:  li x26,1; li x27,11; li gp,11; j fail_loop
failD:  li x26,1; li x27,12; li gp,12; j fail_loop
failD2: li x26,1; li x27,13; li gp,13; j fail_loop
failE:  li x26,1; li x27,14; li gp,14; j fail_loop
failF:  li x26,1; li x27,15; li gp,15; j fail_loop
failF2: li x26,1; li x27,16; li gp,16; j fail_loop
failG:  li x26,1; li x27,17; li gp,17; j fail_loop
fail_loop:
  j fail_loop

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
