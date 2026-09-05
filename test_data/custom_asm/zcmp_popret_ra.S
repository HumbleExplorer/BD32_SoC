# zcmp_popret_ra.S - 聚焦：cm.push/cm.popret {ra}, ±16（rlist=4, 0xb842/0xbe42）
# 复现 measure_cpu_freq 的帧模式：进入 push ra，末尾 popret 恢复并跳回。
# 关键：函数被连续调用两次（验证第二次调用的参数/ra 正确）。
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  li x3, 0
  li sp, 0x1B000
  li a0, 0x1234                 # 模拟第一次调用参数
  jal ra, func                  # 调用 1
  li t0, 0x1235
  bne a0, t0, fail              # a0 应被 func 返回覆盖（返回 a0+1）
  li x3, 1
  li a0, 0x5678                 # 第二次调用参数（关键：不能残留第一次的 ra/返回值）
  jal ra, func                  # 调用 2
  li t0, 0x5679
  bne a0, t0, fail
  li x3, 2
  li t0, 0x1B000
  bne sp, t0, fail              # sp 恢复

  li x27, 1
  li x26, 1
p: j p

# func: push ra；返回 a0+1；popret 跳回
func:
  .word 0x0001b842              # nop; cm.push {ra},-16
  addi a0, a0, 1
  .word 0x0001be42              # nop; cm.popret {ra},16

fail: li x27, 0; li x26, 1
fl: j fl
  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
