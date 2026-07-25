# lw_load_chain.S
# 验证: load -> load 地址依赖（第二个 load 的地址来自第一个 load 的结果）。
# 这是 coremark list 指针解引用(list->next->info->data16)的核心模式:
#   lw  t3, 0(t0)   # 先 load 一个指针值
#   lh  t4, 0(t3)   # 再用该指针解引用 load 数据
# DTCM 同步读 + bus_ready stall 下, 第二个 load 在第一个 load 的 MEM/WB 阶段
# 需要正确的地址前递, 否则用到旧地址读错数据.

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ---- 准备 DTCM 数据 ----
  li t0, 0x00019000        # 槽A: 存"指针"
  li t1, 0x00019004        # 槽B: 存"数据"
  sw t1, 0(t0)             # DTCM[0x19000] = 0x19004 (指针指向槽B)
  li t2, 0x00005678
  sw t2, 0(t1)             # DTCM[0x19004] = 0x5678

  # ---- load -> load 地址依赖 ----
  li t3, 0x0000AAAA        # t3 旧值(若被误用, 会读 DTCM[0xAAAA])
  lw t3, 0(t0)             # t3 = 0x19004 (load 指针)
  lh t4, 0(t3)             # t4 = DTCM[t3] = DTCM[0x19004] = 0x5678 (解引用)

  li t5, 0x5678
  bne t4, t5, fail         # t4 必须 = 0x5678

  # ---- 连续两级解引用 (list->next->info->data16 的雏形) ----
  li t0, 0x00019010        # 槽C: 存指向槽A的指针
  li t1, 0x00019000        # 槽A 地址
  sw t1, 0(t0)             # DTCM[0x19010] = 0x19000
  # 槽A(0x19000)=0x19004 已在上面设置, 槽B(0x19004)=0x5678 已设置

  li s0, 0x0000BBBB        # s0 旧值
  lw s0, 0(t0)             # s0 = 0x19000 (一级指针)
  lw s1, 0(s0)             # s1 = DTCM[0x19000] = 0x19004 (二级指针)
  lh s2, 0(s1)             # s2 = DTCM[0x19004] = 0x5678 (解引用)

  li t5, 0x5678
  bne s2, t5, fail

  # ---- load -> load 后立即参与运算 ----
  li t0, 0x00019020
  li t1, 0x00019024
  sw t1, 0(t0)             # DTCM[0x19020] = 0x19024
  li t2, 0x00000100
  sw t2, 0(t1)             # DTCM[0x19024] = 0x100

  li a0, 0x0000CCCC
  lw a0, 0(t0)             # a0 = 0x19024
  lw a1, 0(a0)             # a1 = DTCM[0x19024] = 0x100
  add a2, a1, a1           # a2 = 0x200 (立即用 a1)

  li t5, 0x200
  bne a2, t5, fail

  # PASS
  li x27, 1
  li x26, 1
p: j p

fail:
  li x27, 0
  li x26, 1
fl: j fl

  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
