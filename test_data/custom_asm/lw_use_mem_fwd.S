# lw_use_mem_fwd.S
# 验证: load 在 MEM 阶段时,数据(func3_expanded_data)已就绪,但 forward_A[2]=0
# (因 load 的 reg_rd_wen_mem=0),导致紧密 load->use 在 load 的 MEM 阶段拿不到
# 前递数据,只能用 ID_EX 锁存的旧值 -> 计算错误.
#
# DTCM 是同步读(bus_ready stall 让 load 在 EX 停 1 拍),use 恰好在 load 的 MEM
# 阶段进 EX. 若此时无 MEM 阶段前递,use 拿旧值.
#
# 机制: store 一个非零值, load 后立即 use. 若 MEM 阶段无前递, use 用旧值(0
# 或 store 前的值), 结果错误.

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # 准备 DTCM 地址与已知值
  li t0, 0x00019000      # DTCM 内一个地址 (DTCM base 0x00010000)
  li t1, 0x12345678      # 已知值

  # 先把 a0/a1/a2 置为可识别的"旧值"(非0), 便于判断是否用了旧值
  li a0, 0xAAAA0001
  li a1, 0xAAAA0002
  li a2, 0xAAAA0003

  # store 已知值到 DTCM
  sw t1, 0(t0)           # DTCM[0x1000] = 0x12345678

  # ---- 紧密 load -> use (use 在 load 的 MEM 阶段需要前递) ----
  lw a0, 0(t0)           # a0 = 0x12345678 (DTCM 同步读)
  add a1, a0, x0         # a1 = a0 + 0 = 0x12345678 (立即用 a0 作 rs1)
  add a2, x0, a0         # a2 = 0 + a0 = 0x12345678 (立即用 a0 作 rs2)

  # 校验: a1 应 = 0x12345678, 不是旧值 0xAAAA0002 或 0xAAAA0001
  li t2, 0x12345678
  bne a1, t2, fail       # a1 错 -> MEM 阶段无前递
  bne a2, t2, fail       # a2 错 -> MEM 阶段无前递

  # ---- 第二个场景: load 后立即做算术 ----
  li a3, 0xBBBB0004
  lw a3, 0(t0)           # a3 = 0x12345678
  addi a4, a3, 8         # a4 = a3 + 8 = 0x12345680 (立即用 a3)
  li t3, 0x12345680
  bne a4, t3, fail

  # ---- 第三个场景: 连续 load -> use (冒泡排序式的比较) ----
  li t4, 0x00019004
  li t5, 0x00000005
  sw t5, 0(t4)           # DTCM[0x1004] = 5
  li a5, 0xCCCC0005
  lw a5, 0(t4)           # a5 = 5
  sub a6, a5, t5         # a6 = a5 - 5 = 0 (立即用 a5 比较)
  bne a6, x0, fail       # 若 a5 是旧值, a6 != 0 -> fail

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
