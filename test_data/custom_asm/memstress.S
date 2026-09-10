# memstress.S - 中断风暴下的 store/load 一致性压力测试
#
# 目的：验证 BD32 流水线在高频 timer 中断打断 store/load 序列时，
#       DTCM 写路径（字/字节/半字/突发/同址/前递）是否丢失或错写。
# 方法：TB 以 force 注入 1.5us 周期的 timer_int 脉冲；固件开 MTIE+MIE 后
#       反复执行 7 类存储模式并立即回读比对，任何不一致即 FAIL 并留下标签。
# 约定：缓冲区 0x18000..0x180FC（CORE_TEST 共享窗口内），COUNT @ 0x18100。
# 寄存器：x3=模式标签 x4=指针 x5/x6/x7=暂存 a0=图案 s0=sweep 计数
#         handler 保存/恢复 ra,x4,x5,x6,x13
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U
  RVTEST_CODE_BEGIN

  # ---- 栈初始化（handler 需要在栈上保存寄存器）----
  li sp, 0x1B000

  # ---- 中断使能：mtvec / mie.MTIE / mstatus.MIE（CSR 手编，march 无 zicsr）----
  la x1, timer_handler
  .word 0x30509073          # csrw mtvec, x1（csrs x0 形式，trap_basic 同款已验证）
  li x5, 0x80
  .word 0x30429073          # csrw mie, x5   （MTIE = bit7；编码经 gcc 验证）
  li x5, 8
  .word 0x30029073          # csrs mstatus, x5（MIE = bit3）

  li x3, 0
  li x8, 0                  # sweep 计数
  li x9, 8                  # sweep 总数
  li x14, 0x18000           # 缓冲区基址
  li x15, 0x18100           # 结束地址（= 64 字末尾）
  li x12, 0x18104           # COUNT 地址

sweep:
  # ---- P1 (id=10)：字存储-立即回读，xorshift 图案扫 64 字 ----
  li x3, 10
  li x4, 0
  li a0, 0x1234567
p1_loop:
  slli x7, a0, 13
  xor a0, a0, x7
  srli x7, a0, 17
  xor a0, a0, x7
  slli x7, a0, 5
  xor a0, a0, x7
  add x6, x14, x4
  sw a0, 0(x6)
  lw x7, 0(x6)
  bne a0, x7, fail
  addi x4, x4, 4
  blt x6, x15, p1_loop

  # ---- P2 (id=11)：8 字突发存储 → 8 字集中回读（写缓冲压力）----
  li x3, 11
  li x4, 0
  li a0, 0x40000000
p2_fill:
  add x6, x14, x4
  add x7, a0, x4
  sw x7, 0(x6)
  addi x4, x4, 4
  li x5, 32
  blt x4, x5, p2_fill
  li x4, 0
p2_check:
  add x6, x14, x4
  add x5, a0, x4
  lw x7, 0(x6)
  bne x5, x7, fail
  addi x4, x4, 4
  li x5, 32
  blt x4, x5, p2_check

  # ---- P3 (id=12)：字节存储 4 通道 + 字回读（sb 字节通道，nest 用的就是 sb）----
  li x3, 12
  mv x6, x14
  li x5, 0xA1
  sb x5, 0(x6)
  li x5, 0xB2
  sb x5, 1(x6)
  li x5, 0xC3
  sb x5, 2(x6)
  li x5, 0xD4
  sb x5, 3(x6)
  lw x7, 0(x6)
  li x5, 0xD4C3B2A1
  bne x7, x5, fail
  li x5, 0x00
  sb x5, 4(x6)
  li x5, 0x00
  sb x5, 5(x6)
  li x5, 0x12
  sb x5, 7(x6)
  li x5, 0x34
  sb x5, 6(x6)
  lw x7, 4(x6)
  li x5, 0x12340000
  bne x7, x5, fail

  # ---- P4 (id=13)：半字存储 + 字回读 ----
  li x3, 13
  mv x6, x14
  li x5, 0x1234
  sh x5, 16(x6)
  li x5, 0x5678
  sh x5, 18(x6)
  lw x7, 16(x6)
  li x5, 0x56781234
  bne x7, x5, fail

  # ---- P5 (id=14)：同址连续存储（写合并/覆盖）----
  li x3, 14
  mv x6, x14
  li x5, 0x111
  sw x5, 20(x6)
  li x5, 0x222
  sw x5, 20(x6)
  li x5, 0x333
  sw x5, 20(x6)
  lw x7, 20(x6)
  li x5, 0x333
  bne x7, x5, fail

  # ---- P6 (id=15)：存储-加载紧邻背靠背（前递路径）×16 ----
  li x3, 15
  li x4, 0
  li a0, 0x99
p6_loop:
  add x6, x14, x4
  sw a0, 24(x6)
  lw x7, 24(x6)
  bne a0, x7, fail
  addi a0, a0, 1
  addi x4, x4, 4
  li x5, 64
  blt x4, x5, p6_loop

  # ---- P7 (id=16)：handler 自身存储完整性（COUNT 单调不回退）----
  li x3, 16
  lw x7, 0(x12)
  li x4, 0
p7_delay:
  addi x4, x4, 1
  bne x4, x5, p7_delay      # x5=64：短延迟，让几个中断打进 Handler
  lw x6, 0(x12)
  blt x6, x7, fail          # COUNT 回退 = handler 的 sw 丢失/错写

  addi x8, x8, 1
  blt x8, x9, sweep

  # ---- 收尾：中断确实发生过（否则测试空转）----
  li x3, 17
  lw x7, 0(x12)
  beq x7, x0, fail

  li x27, 1
  li x26, 1
p: j p
fail: li x27, 0; li x26, 1
fl: j fl

# ---- timer handler：只动 ra/x5/x6/x7/x4/x13，全保存全恢复 ----
# mtimecmp reload 遵循 NMSIS/E203 软件契约：CLINT 电平中断（mtime>=mtimecmp），
# handler 必须写新 mtimecmp 才能产生周期中断，否则 mret 后立刻重触发死循环
# （XT_RISC-V 是唯一"写清中断"特例，E203/SparrowRV/Ibex/BD32 均为纯电平+软件 reload）
timer_handler:
  addi sp, sp, -24
  sw ra, 0(sp)
  sw x4, 4(sp)
  sw x5, 8(sp)
  sw x6, 12(sp)
  sw x7, 16(sp)
  sw x13, 20(sp)
  .word 0x342022f3          # csrr x5, mcause
  blt x5, x0, th_int        # mcause bit31=1 → 中断
  j th_done
th_int:
  # ---- mtimecmp reload（先清中断条件，再干活）----
  li   x7, 0xF2004000           # &mtimecmp_lo（APB CLINT @ 0xF200_4000）
  li   x6, 0xF200BFF8           # &mtime_lo（APB CLINT @ 0xF200_BFF8）
  lw   x5, 0(x6)                # x5 = mtime_lo
  li   x6, 1000                 # delta = 1000 ticks（1MHz → 1ms 周期）
  add  x5, x5, x6               # x5 = mtime + delta
  sw   x5, 0(x7)                # mtimecmp_lo = 新值（handler 自身的 store 走被测路径）
  # ---- COUNT++ ----
  lw x6, 0(x12)                 # COUNT++（handler 自身的 store 也走被测路径）
  addi x6, x6, 1
  sw x6, 0(x12)
th_done:
  lw ra, 0(sp)
  lw x4, 4(sp)
  lw x5, 8(sp)
  lw x6, 12(sp)
  lw x7, 16(sp)
  lw x13, 20(sp)
  addi sp, sp, 24
  mret

  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
