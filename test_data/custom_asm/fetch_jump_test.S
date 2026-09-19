# fetch_jump_test.S - fetch_wait 归因微基准（Phase 0：跳转密度 vs 取指等待）
#
# 背景：CoreMark 板测 fetch 停顿占 C 构建 8~17.5% ticks，且 GCC(17.5%)>LLVM(11.4%)。
# fetch_bench 已证明顺序/跨字流 CPI=1.00，剩余嫌疑 = taken 跳转后的取指流断档
# （ITCM 同步 BRAM 重启 + 无目标预取）。本测试用 0xB11 计数器自测量：
#   V0 纯 ALU ×300（零控制流）        → 期望 wait ≈ 0
#   V1 jal ×100 背靠背                → 假设：wait ≈ 100~200（每 taken 1~2 拍）
#   V2 jal ×100 + addi ×300 稀疏      → 假设：与 V1 同量级（每 taken 成本恒定）
# 判定（宽松回归界）：s0<15 且 50<s1<400 且 50<s2<400。
# 结果寄存器：s0=V0 增量 s1=V1 增量 s2=V2 增量（供 do 文件 exa 读取分析）。
# CSR 编码沿用 .word 风格（build_asm 为 -march=rv32im 无 zicsr）。
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li t0, 0
  .word 0x32029073               # csrw mcountinhibit, t0（全计数）
  li t0, 0x38000
  .word 0xBC029073               # csrw mcounterclr, t0（清停顿计数器）

  # ============ V0: 纯 ALU ×300（零控制流） ============
  .word 0xB1102373               # csrr t1, 0xB11（fetch wait 起点）
  li a1, 1
  .rept 300
  addi a1, a1, 1
  .endr
  .word 0xB11023F3               # csrr t2, 0xB11
  sub s0, t2, t1

  # ============ V1: jal ×100 背靠背（每条必 taken） ============
  li t0, 0x38000
  .word 0xBC029073               # 清零
  .word 0xB1102373               # csrr t1, 0xB11
  .rept 100
  jal x0, 1f
  nop                            # 被跳过：目标 1f 在下一个字（跨字跳转）
1:
  .endr
  nop
  nop
  .word 0xB11023F3               # csrr t2, 0xB11
  sub s1, t2, t1

  # ============ V2: jal ×100 + addi ×300 稀疏 ============
  li t0, 0x38000
  .word 0xBC029073               # 清零
  .word 0xB1102373               # csrr t1, 0xB11
  .rept 100
  addi a2, a2, 1
  addi a2, a2, 1
  addi a2, a2, 1
  jal x0, 2f
  nop                            # 被跳过：目标 2f 跨字
2:
  .endr
  nop
  nop
  .word 0xB11023F3               # csrr t2, 0xB11
  sub s2, t2, t1

  # ============ 判定 ============
  # 2026-09-19 FIFO 重构后：V1/V2 fetch wait ≈ 0~2（跨字/跳转零气泡），
  # 下界无意义（小值 = 修复成功的证据）；仅保留上界防异常暴涨/取指错位。
  li t5, 15
  bltu s0, t5, 3f
  j fail
3:
  li t5, 400
  bltu t5, s1, fail
  li t5, 400
  bltu t5, s2, fail

  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
