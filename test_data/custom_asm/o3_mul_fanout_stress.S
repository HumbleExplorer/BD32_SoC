# =============================================================================
# o3_mul_fanout_stress.S — MUL 结果扇出 / MUL→ALU→MUL 链 / OITF 压力测试
# =============================================================================
# 背景：CoreMark -O3 CRC 全错，-O2 正确。
# -O3 热循环（Loop F @ 0x11e98）核心模式：
#   mul  a5, a5, a4     ← MUL1
#   add  t3, t3, s1     ← 独立 ALU（OITF 期间执行）
#   srai a6, a5, 2      ← 使用 MUL1 结果（扇出 1）
#   srai a5, a5, 5      ← 使用 MUL1 结果（扇出 2，同时覆写 a5）
#   andi a6, a6, 15
#   andi a5, a5, 127
#   mul  a5, a6, a5     ← MUL2（依赖 MUL1 经 ALU 链）
#   add  t4, t4, a5
#   bltu a7, s0, loop
#
# 本测试覆盖：
#   F1: MUL 扇出基础（MUL → 两条连续指令使用同一结果）
#   F2: Loop F 精确序列（单次迭代）
#   F3: Loop F 循环（多次迭代，持续 OITF 压力）
#   F4: MUL→MUL 背靠背依赖（OITF RAW 停顿 + 前递）
#   F5: DIV→ALU→MUL 跨单元依赖
#   F6: lh→MUL（load-use 停顿后 MUL 启动）
#   F7: MUL→sh（MUL 结果直接 store 半字）
#   F8: OITF 填满（4 条 MUL 同时在飞）
#   F9: MUL 扇出到 rs2（两条指令用 MUL 结果作 rs2）
#   F10: MUL 结果扇出 + 分支回边（循环中 MUL 扇出）
#
# 约定：x26=1 done, x27=1 pass; fail 时 gp(x3)=子测试编号
# 数据区：0x1B000（CORE_TEST DTCM tag=0x0001 范围内）
# =============================================================================

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ==================================================================
  # F1: MUL 扇出基础
  #     mul  a5, a5, a4   → a5 = 700
  #     srai a6, a5, 2    → a6 = 175  (扇出 1: rs1=a5)
  #     srai a5, a5, 5    → a5 = 21   (扇出 2: rs1=a5, 同时覆写 a5)
  #     验证 a6==175, a5==21
  # ==================================================================
  li   x10, 100            # a5 初始值
  li   x11, 7              # a4
  mul  x10, x10, x11      # x10 = 100*7 = 700
  srai x12, x10, 2        # x12 = 700>>2 = 175 (扇出 1)
  srai x10, x10, 5        # x10 = 700>>5 = 21  (扇出 2, 覆写 x10)
  li   x13, 175
  bne  x12, x13, failF1a
  li   x13, 21
  bne  x10, x13, failF1b

  # ==================================================================
  # F2: Loop F 精确序列（单次迭代）
  #     100*7=700, 700>>2&15=15, 700>>5&127=21, 15*21=315
  # ==================================================================
  li   x10, 100            # a5 初始
  li   x11, 7              # a4
  li   x14, 0              # t4 = 累加器
  li   x15, 2              # s1 (用于 add t3, t3, s1)
  li   x16, 0              # t3 初始
  # --- Loop F 序列 ---
  mul  x10, x10, x11      # MUL1: a5 = 100*7 = 700
  add  x16, x16, x15      # 独立 ALU: t3 += s1
  srai x12, x10, 2        # a6 = 700>>2 = 175
  srai x10, x10, 5        # a5 = 700>>5 = 21
  andi x12, x12, 15       # a6 = 175 & 15 = 15
  andi x10, x10, 127      # a5 = 21 & 127 = 21
  mul  x10, x12, x10      # MUL2: a5 = 15*21 = 315
  add  x14, x14, x10      # t4 += 315
  # --- 验证 ---
  li   x13, 315
  bne  x14, x13, failF2

  # ==================================================================
  # F3: Loop F 循环（8 次迭代，持续 OITF 压力）
  #     每次迭代：a5_init * a4 → 扇出 → andi → MUL2 → 累加
  #     数据：a5_init[] = {100,200,50,80,120,30,60,90}
  #           a4 = 7 (固定)
  #     每次: val*7 → (>>2 & 15) * (>>5 & 127) → 累加
  #     100*7=700:  (175&15)=15, (21&127)=21, 15*21=315
  #     200*7=1400: (350&15)=14, (43&127)=43, 14*43=602
  #     50*7=350:   (87&15)=7,   (10&127)=10, 7*10=70
  #     80*7=560:   (140&15)=12, (17&127)=17, 12*17=204
  #     120*7=840:  (210&15)=2,  (26&127)=26, 2*26=52
  #     30*7=210:   (52&15)=4,   (6&127)=6,   4*6=24
  #     60*7=420:   (105&15)=9,  (13&127)=13, 9*13=117
  #     90*7=630:   (157&15)=13, (19&127)=19, 13*19=247
  #     总和 = 315+602+70+204+52+24+117+247 = 1631
  # ==================================================================
  la   x20, 0x1B000
  li   x10, 100; sw x10, 0(x20)
  li   x10, 200; sw x10, 4(x20)
  li   x10, 50;  sw x10, 8(x20)
  li   x10, 80;  sw x10, 12(x20)
  li   x10, 120; sw x10, 16(x20)
  li   x10, 30;  sw x10, 20(x20)
  li   x10, 60;  sw x10, 24(x20)
  li   x10, 90;  sw x10, 28(x20)
  nop
  nop
  nop

  la   x20, 0x1B000       # 数据指针
  li   x21, 0              # 累加器 t4
  li   x22, 7              # a4 = 7 (固定乘数)
  li   x23, 0              # 循环计数
  li   x24, 8              # 循环上限
  li   x25, 2              # s1 (独立 ALU 用)
  li   x16, 0              # t3 初始
f3_loop:
  lw   x10, 0(x20)        # a5 = data[i]
  addi x20, x20, 4        # 指针++
  addi x23, x23, 1        # 计数++
  # --- Loop F 核心 ---
  mul  x10, x10, x22      # MUL1: a5 = data[i] * 7
  add  x16, x16, x25      # 独立 ALU: t3 += s1
  srai x12, x10, 2        # a6 = result >> 2
  srai x10, x10, 5        # a5 = result >> 5
  andi x12, x12, 15       # a6 &= 15
  andi x10, x10, 127      # a5 &= 127
  mul  x10, x12, x10      # MUL2: a5 = a6 * a5
  add  x21, x21, x10      # 累加
  bne  x23, x24, f3_loop
  # --- 验证 ---
  li   x13, 1631
  bne  x21, x13, failF3

  # ==================================================================
  # F4: MUL→MUL 背靠背依赖（OITF RAW 停顿 + 前递）
  #     mul  a5, a1, a2   → a5 = 6*7 = 42
  #     mul  a6, a5, a3   → a6 = 42*3 = 126 (依赖 a5)
  #     mul  a7, a6, a4   → a7 = 126*2 = 252 (依赖 a6)
  # ==================================================================
  li   x10, 6
  li   x11, 7
  li   x12, 3
  li   x13, 2
  mul  x14, x10, x11      # x14 = 42
  mul  x15, x14, x12      # x15 = 42*3 = 126 (RAW on x14)
  mul  x16, x15, x13      # x16 = 126*2 = 252 (RAW on x15)
  li   x17, 42
  bne  x14, x17, failF4a
  li   x17, 126
  bne  x15, x17, failF4b
  li   x17, 252
  bne  x16, x17, failF4c

  # ==================================================================
  # F5: DIV→ALU→MUL 跨单元依赖
  #     div  a5, a1, a2   → a5 = 100/7 = 14
  #     addi a5, a5, 1    → a5 = 15
  #     mul  a6, a5, a3   → a6 = 15*3 = 45
  # ==================================================================
  li   x10, 100
  li   x11, 7
  li   x12, 3
  div  x13, x10, x11      # x13 = 100/7 = 14
  addi x13, x13, 1        # x13 = 15 (依赖 DIV 结果)
  mul  x14, x13, x12      # x14 = 15*3 = 45 (依赖 ALU 结果)
  li   x15, 15
  bne  x13, x15, failF5a
  li   x15, 45
  bne  x14, x15, failF5b

  # ==================================================================
  # F6: lh→MUL（load-use 停顿后 MUL 启动）
  #     lh   a5, 0(t0)    → a5 = 12 (from memory)
  #     mul  a6, a5, a4   → a6 = 12*5 = 60
  #     精确复制 CoreMark 的 lh→mul 时序
  # ==================================================================
  la   x20, 0x1B000
  li   x10, 12
  sh   x10, 64(x20)       # mem[0x1B040] = 12
  nop
  nop
  nop
  la   x20, 0x1B000
  lh   x10, 64(x20)       # x10 = 12 (signed half-word)
  li   x11, 5
  mul  x12, x10, x11      # x12 = 12*5 = 60 (load-use → stall → MUL)
  li   x13, 60
  bne  x12, x13, failF6

  # ==================================================================
  # F7: MUL→sh（MUL 结果直接 store 半字，然后 lh 读回验证）
  #     mul  a5, a1, a2   → a5 = 9*9 = 81
  #     sh   a5, 0(t0)    → store 81 as half-word
  #     lh   a6, 0(t0)    → a6 = 81
  # ==================================================================
  la   x20, 0x1B000
  li   x10, 9
  li   x11, 9
  mul  x12, x10, x11      # x12 = 81
  sh   x12, 72(x20)       # store half-word
  nop
  nop
  lh   x13, 72(x20)       # load back
  li   x14, 81
  bne  x13, x14, failF7

  # ==================================================================
  # F8: OITF 填满（4 条独立 MUL 同时在飞，第 5 条等待）
  #     mul r1, a, b   → 3
  #     mul r2, c, d   → 5
  #     mul r3, e, f   → 7
  #     mul r4, g, h   → 11
  #     mul r5, r1, r2 → 15 (依赖前两条，必须等 OITF 退休)
  #     验证所有结果
  # ==================================================================
  li   x10, 1
  li   x11, 3
  li   x12, 1
  li   x13, 5
  li   x14, 1
  li   x15, 7
  li   x16, 1
  li   x17, 11
  mul  x18, x10, x11      # x18 = 1*3 = 3   → OITF entry 0
  mul  x19, x12, x13      # x19 = 1*5 = 5   → OITF entry 1
  mul  x20, x14, x15      # x20 = 1*7 = 7   → OITF entry 2
  mul  x21, x16, x17      # x21 = 1*11 = 11 → OITF entry 3 (FIFO full!)
  mul  x22, x18, x19      # x22 = 3*5 = 15  → 等待 OITF 退休 (RAW on x18)
  # 验证
  li   x23, 3
  bne  x18, x23, failF8a
  li   x23, 5
  bne  x19, x23, failF8b
  li   x23, 7
  bne  x20, x23, failF8c
  li   x23, 11
  bne  x21, x23, failF8d
  li   x23, 15
  bne  x22, x23, failF8e

  # ==================================================================
  # F9: MUL 扇出到 rs2（两条指令用 MUL 结果作 rs2）
  #     mul  a5, a1, a2   → a5 = 8*6 = 48
  #     add  a6, a3, a5   → a6 = 10 + 48 = 58 (rs2=a5)
  #     sub  a7, a4, a5   → a7 = 100 - 48 = 52 (rs2=a5)
  # ==================================================================
  li   x10, 8
  li   x11, 6
  li   x12, 10
  li   x13, 100
  mul  x14, x10, x11      # x14 = 48
  add  x15, x12, x14      # x15 = 10+48 = 58 (扇出 1, rs2)
  sub  x16, x13, x14      # x16 = 100-48 = 52 (扇出 2, rs2)
  li   x17, 58
  bne  x15, x17, failF9a
  li   x17, 52
  bne  x16, x17, failF9b

  # ==================================================================
  # F10: MUL 扇出 + 循环回边（Loop F 带 lh 数据加载，16 次迭代）
  #      精确复制 CoreMark -O3 matrix multiply 内循环：
  #      lh+lh → mul → 扇出(srai×2) → andi×2 → mul → add → bltu
  #      A[] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16} (半字)
  #      B[] = {2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2} (半字, 固定乘数 2)
  #      每次: A[i]*2 → (>>2 & 15) * (>>5 & 127) → 累加
  #      A[i]*2: 2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32
  #      >>2 & 15: 0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8
  #      >>5 & 127: 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
  #      product: 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,8
  #      总和 = 8
  # ==================================================================
  la   x20, 0x1B000
  # 初始化 A[] (半字, 偏移 128): A[0..15] = 1..16
  li   x10, 1
  li   x11, 17             # 循环上限 17 → 存储 1..16
f10_init_a:
  sh   x10, 128(x20)
  addi x20, x20, 2
  addi x10, x10, 1
  bne  x10, x11, f10_init_a
  # 初始化 B[] (半字, 偏移 192, 全部填 2)
  la   x20, 0x1B000
  li   x10, 2
  li   x11, 0
  li   x12, 16
f10_init_b:
  sh   x10, 192(x20)
  addi x20, x20, 2
  addi x11, x11, 1
  bne  x11, x12, f10_init_b
  nop
  nop
  nop

  # 主循环
  la   x20, 0x1B000
  addi x20, x20, 128      # A 指针
  la   x21, 0x1B000
  addi x21, x21, 192      # B 指针
  li   x22, 0              # 累加器
  li   x23, 0              # 计数
  li   x24, 16             # 上限
  li   x25, 2              # s1 (独立 ALU)
  li   x16, 0              # t3
f10_loop:
  lh   x10, 0(x20)        # a5 = A[i]
  lh   x11, 0(x21)        # a4 = B[i]
  addi x23, x23, 1        # 计数++
  addi x20, x20, 2        # A++
  addi x21, x21, 2        # B++
  # --- Loop F 核心 ---
  mul  x10, x10, x11      # MUL1: a5 = A[i]*B[i]
  add  x16, x16, x25      # 独立 ALU
  srai x12, x10, 2        # a6 = result>>2
  srai x10, x10, 5        # a5 = result>>5
  andi x12, x12, 15       # a6 &= 15
  andi x10, x10, 127      # a5 &= 127
  mul  x10, x12, x10      # MUL2: a5 = a6*a5
  add  x22, x22, x10      # 累加
  bne  x23, x24, f10_loop
  # --- 验证 ---
  li   x13, 8
  bne  x22, x13, failF10

  # ==================================================================
  # F11: MUL 扇出三路（3 条连续指令使用同一 MUL 结果）
  #      mul  a5, a1, a2  → a5 = 12*8 = 96
  #      addi a6, a5, 1   → a6 = 97  (扇出 1)
  #      addi a7, a5, 2   → a7 = 98  (扇出 2)
  #      slli a1, a5, 1   → a1 = 192 (扇出 3)
  # ==================================================================
  li   x10, 12
  li   x11, 8
  mul  x12, x10, x11      # x12 = 96
  addi x13, x12, 1        # x13 = 97 (扇出 1)
  addi x14, x12, 2        # x14 = 98 (扇出 2)
  slli x15, x12, 1        # x15 = 192 (扇出 3)
  li   x16, 97
  bne  x13, x16, failF11a
  li   x16, 98
  bne  x14, x16, failF11b
  li   x16, 192
  bne  x15, x16, failF11c

  # ==================================================================
  # F12: core_init_matrix 精确模式
  #      mul  a2, a2, a5   → 7*3 = 21
  #      srai a4, a2, 31   → 0 (正数)
  #      srli a4, a4, 16   → 0
  #      add  a2, a2, a4   → 21+0 = 21 (第二次使用 MUL 结果!)
  #      slli a2, a2, 16   → 0x00150000
  #      srli a2, a2, 16   → 21
  #      sub  a2, a2, a4   → 21-0 = 21
  #      add  a6, a5, a2   → 3+21 = 24
  #      add  a4, a6, a5   → 24+3 = 27
  # ==================================================================
  li   x10, 7              # a2
  li   x11, 3              # a5
  mul  x10, x10, x11      # a2 = 7*3 = 21
  srai x12, x10, 31       # a4 = 21>>31 = 0 (扇出 1: rs1=a2)
  srli x12, x12, 16       # a4 = 0>>16 = 0
  add  x10, x10, x12      # a2 = 21+0 = 21 (扇出 2: rs1=a2, 间隔 2 条)
  slli x10, x10, 16       # a2 = 21<<16 = 0x150000
  srli x10, x10, 16       # a2 = 0x15 = 21
  sub  x10, x10, x12      # a2 = 21-0 = 21
  add  x13, x11, x10      # a6 = 3+21 = 24
  add  x14, x13, x11      # a4 = 24+3 = 27
  li   x15, 24
  bne  x13, x15, failF12a
  li   x15, 27
  bne  x14, x15, failF12b

  # ==================================================================
  # F13: 负数 MUL 扇出（验证符号扩展正确性）
  #      mul  a5, a1, a2  → (-3)*4 = -12 = 0xFFFFFFF4
  #      srai a6, a5, 2   → -12>>2 = -3 (算术右移保持符号)
  #      srai a5, a5, 1   → -12>>1 = -6
  # ==================================================================
  li   x10, -3
  li   x11, 4
  mul  x12, x10, x11      # x12 = -12
  srai x13, x12, 2        # x13 = -12>>2 = -3 (扇出 1)
  srai x12, x12, 1        # x12 = -12>>1 = -6 (扇出 2, 覆写)
  li   x14, -3
  bne  x13, x14, failF13a
  li   x14, -6
  bne  x12, x14, failF13b

  # ==================================================================
  # F14: MUL 扇出 + store + load 混合
  #      mul  a5, a1, a2  → 11*13 = 143
  #      sw   a5, 0(t0)   → store (扇出 1: 作为 store 数据)
  #      addi a6, a5, 1   → 144 (扇出 2: ALU 使用)
  #      lw   a7, 0(t0)   → 143 (从内存读回)
  #      验证 a6==144, a7==143
  # ==================================================================
  la   x20, 0x1B000
  li   x10, 11
  li   x11, 13
  mul  x12, x10, x11      # x12 = 143
  sw   x12, 256(x20)      # store to mem (扇出 1)
  addi x13, x12, 1        # x13 = 144 (扇出 2)
  nop
  nop
  lw   x14, 256(x20)      # x14 = 143 (load back)
  li   x15, 144
  bne  x13, x15, failF14a
  li   x15, 143
  bne  x14, x15, failF14b

  # ==================================================================
  # F15: 交替 MUL/DIV 依赖链
  #      mul  a5, a1, a2  → 5*6 = 30
  #      div  a6, a5, a3  → 30/4 = 7 (依赖 MUL)
  #      mul  a7, a6, a4  → 7*3 = 21 (依赖 DIV)
  #      div  a1, a7, a5  → 21/30 = 0 (依赖 MUL 和 DIV)
  # ==================================================================
  li   x10, 5
  li   x11, 6
  li   x12, 4
  li   x13, 3
  mul  x14, x10, x11      # x14 = 30
  div  x15, x14, x12      # x15 = 30/4 = 7
  mul  x16, x15, x13      # x16 = 7*3 = 21
  div  x17, x16, x14      # x17 = 21/30 = 0
  li   x18, 30
  bne  x14, x18, failF15a
  li   x18, 7
  bne  x15, x18, failF15b
  li   x18, 21
  bne  x16, x18, failF15c
  li   x18, 0
  bne  x17, x18, failF15d

  # ==================================================================
  # F16: MULH 扇出（高 32 位结果被两条指令使用）
  #      mulh a5, a1, a2  → (0x10000 * 0x10000) >> 32 = 1
  #      addi a6, a5, 10  → 11 (扇出 1)
  #      addi a7, a5, 20  → 21 (扇出 2)
  # ==================================================================
  li   x10, 0x10000
  li   x11, 0x10000
  mulh x12, x10, x11      # x12 = high32(0x10000*0x10000) = 1
  addi x13, x12, 10       # x13 = 11 (扇出 1)
  addi x14, x12, 20       # x14 = 21 (扇出 2)
  li   x15, 11
  bne  x13, x15, failF16a
  li   x15, 21
  bne  x14, x15, failF16b

  # ==================================================================
  # 全部通过
  # ==================================================================
  li   x26, 1
  li   x27, 1
pass_loop:
  j    pass_loop

  # ==================================================================
  # Fail handlers
  # ==================================================================
failF1a:  li x26,1; li x27,2;  li gp,2;  j fail_loop
failF1b:  li x26,1; li x27,3;  li gp,3;  j fail_loop
failF2:   li x26,1; li x27,4;  li gp,4;  j fail_loop
failF3:   li x26,1; li x27,5;  li gp,5;  j fail_loop
failF4a:  li x26,1; li x27,6;  li gp,6;  j fail_loop
failF4b:  li x26,1; li x27,7;  li gp,7;  j fail_loop
failF4c:  li x26,1; li x27,8;  li gp,8;  j fail_loop
failF5a:  li x26,1; li x27,9;  li gp,9;  j fail_loop
failF5b:  li x26,1; li x27,10; li gp,10; j fail_loop
failF6:   li x26,1; li x27,11; li gp,11; j fail_loop
failF7:   li x26,1; li x27,12; li gp,12; j fail_loop
failF8a:  li x26,1; li x27,13; li gp,13; j fail_loop
failF8b:  li x26,1; li x27,14; li gp,14; j fail_loop
failF8c:  li x26,1; li x27,15; li gp,15; j fail_loop
failF8d:  li x26,1; li x27,16; li gp,16; j fail_loop
failF8e:  li x26,1; li x27,17; li gp,17; j fail_loop
failF9a:  li x26,1; li x27,18; li gp,18; j fail_loop
failF9b:  li x26,1; li x27,19; li gp,19; j fail_loop
failF10:  li x26,1; li x27,20; li gp,20; j fail_loop
failF11a: li x26,1; li x27,21; li gp,21; j fail_loop
failF11b: li x26,1; li x27,22; li gp,22; j fail_loop
failF11c: li x26,1; li x27,23; li gp,23; j fail_loop
failF12a: li x26,1; li x27,24; li gp,24; j fail_loop
failF12b: li x26,1; li x27,25; li gp,25; j fail_loop
failF13a: li x26,1; li x27,26; li gp,26; j fail_loop
failF13b: li x26,1; li x27,27; li gp,27; j fail_loop
failF14a: li x26,1; li x27,28; li gp,28; j fail_loop
failF14b: li x26,1; li x27,29; li gp,29; j fail_loop
failF15a: li x26,1; li x27,30; li gp,30; j fail_loop
failF15b: li x26,1; li x27,31; li gp,31; j fail_loop
failF15c: li x26,1; li x27,32; li gp,32; j fail_loop
failF15d: li x26,1; li x27,33; li gp,33; j fail_loop
failF16a: li x26,1; li x27,34; li gp,34; j fail_loop
failF16b: li x26,1; li x27,35; li gp,35; j fail_loop
fail_loop:
  j    fail_loop

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
