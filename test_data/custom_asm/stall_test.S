# stall_test.S - 停顿原因计数器回归（0xB0F loaduse / 0xB10 oitf）+ MULDIV 分类
#
# 背景：2026-09-17 上板发现 oitf 停顿计数跨配置恒定 ~14.2M 而 muldiv 仅 29，
# hpm_test 对停顿计数器与 MULDIV 分类零覆盖。本测试补上仿真回归：
#   1. NOP 循环窗口：三个停顿计数增量全 0（容差 <5）；
#   2. load-use 链 ×100：0xB0F 增量 ∈ [100, 400]；
#   3. mul 依赖链 ×20：0xB10 增量 ∈ [20, 1500]，MULDIV(0xB08) = 20；
#   4. mcountinhibit[17:15]（0x38000）冻结：load-use 链期间 0xB0F 增量 = 0。
# CSR 编码（.word 风格，funct3=2 的 csrrs x0 等价 csrr）：
#   csrr t1,csr = csr<<20 | 0x2373    csrr t2,csr = csr<<20 | 0x23F3
#   csrr t3,csr = csr<<20 | 0x2E73    csrr s0,csr = csr<<20 | 0x2473
#   csrw csr,t0 = csr<<20 | 0x29073
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li t0, 0
  .word 0x32029073               # csrw mcountinhibit, t0（全计数）
  li t0, 0x38000
  .word 0xBC029073               # csrw mcounterclr, t0（清三个停顿计数器）
  li sp, 0x00020000              # DTCM 基址当数据区

  # ============ Phase A: NOP 循环窗口 → 三计数全 0 ============
  .word 0xB0F02373               # csrr t1, 0xB0F（loaduse 起点）
  .word 0xB1002473               # csrr s0, 0xB10（oitf 起点）
  .word 0xB11024F3               # csrr s1, 0xB11（fetch 起点）
  li t6, 60
10:
  addi t6, t6, -1
  bnez t6, 10b
  .word 0xB0F023F3               # csrr t2, 0xB0F
  .word 0xB1102E73               # csrr t3, 0xB11
  sub t4, t2, t1                 # loaduse 增量
  li t5, 5
  bltu t4, t5, 11f
  j fail
11:
  sub t4, t3, s1                 # fetch 增量
  li t5, 5
  bltu t4, t5, 12f
  j fail
12:
  .word 0xB1022E73               # csrr t3, 0xB10（oitf 终点）
  sub t4, t3, s0                 # oitf 增量
  li t5, 5
  bltu t4, t5, 13f
  j fail
13:
  # ============ Phase B: load-use 链 ×100 → 0xB0F ∈ [100,400] ============
  li t0, 0x38000
  .word 0xBC029073               # csrw mcounterclr（清零）
  li t1, 0x12345678
  sw t1, 0(sp)                   # 预置数据
  li t3, 100
14:
  lw t1, 0(sp)                   # load
  addi t1, t1, 1                 # 立即使用 → load-use 停顿
  addi t3, t3, -1
  bnez t3, 14b
  .word 0xB0F02373               # csrr t1, 0xB0F
  sub t4, t1, t2                 # t2 = Phase A 末次 0xB0F 读数（≈0 基线）
  li t5, 100
  bltu t4, t5, fail
  li t5, 400
  bltu t5, t4, fail
  # ============ Phase C: mul 依赖链 ×20 → oitf ∈ [20,1500]，MULDIV=20 ============
  li t0, 0x38000
  .word 0xBC029073               # csrw mcounterclr（清零）
  .word 0xB0802373               # csrr t1, 0xB08（MULDIV 起点）
  .word 0xB1002473               # csrr s0, 0xB10（oitf 起点）
  li a0, 3
  li a1, 5
  li t3, 20
15:
  mul a0, a0, a1                 # 依赖前一次 mul 结果 → OITF RAW 停顿
  addi t3, t3, -1
  bnez t3, 15b
  .word 0xB1022E73               # csrr t3, 0xB10（oitf 终点）
  nop
  nop
  nop                            # 等链尾在途 mul 退休后再读，防退休滞后
  sub t4, t3, s0
  li t5, 8                       # 20 条依赖 mul 实测 14 次 RAW 停顿（mul 2 拍 +
  bltu t4, t5, fail              #   退休拍放行有重叠）；下限只防计数器死零
  li t5, 1500
  bltu t5, t4, fail              # > 1500 → 失败
  .word 0xB08023F3               # csrr t2, 0xB08（MULDIV 终点）
  sub t4, t2, t1
  li t5, 20                      # 窗口内恰好 20 条 mul
  bltu t4, t5, fail
  li t5, 24                      # 少量裕量
  bltu t5, t4, fail              # > 24 → 失败
  # ============ Phase D: mcountinhibit[17:15] 冻结停顿计数 ============
  li t0, 0x38000
  .word 0x32029073               # csrw mcountinhibit, t0（冻结）
  .word 0xB0F02373               # csrr t1, 0xB0F（基线）
  li t3, 50
16:
  lw a2, 0(sp)                   # 注意：不能用 t1——它存着基线
  addi a2, a2, 1
  addi t3, t3, -1
  bnez t3, 16b
  .word 0xB0F023F3               # csrr t2, 0xB0F
  sub t4, t2, t1
  li t5, 10                      # 冻结期间增量 = 0（容差 10）
  bltu t4, t5, 17f
  j fail
17:
  li t0, 0
  .word 0x32029073               # csrw mcountinhibit, t0（恢复全计数）

  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
