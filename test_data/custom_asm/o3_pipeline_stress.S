# =============================================================================
# o3_pipeline_stress.S — 精确复制 CoreMark -O3 热循环指令序列
# =============================================================================
# 背景：CoreMark -O2 PASS，-O3 FAIL（CRC 全错）。
# 反汇编发现 -O3 热循环大量使用 lh/lhu/sh（半字操作）+ MUL 组合，
# 而 -O2 的指令调度不同（load 和 addi 交错，不是背靠背）。
# 本测试精确复制 -O3 的指令序列：
#   N: lh+lh 背靠背 → mul → add → bne 循环（matrix multiply 内循环 @ 0x11c80）
#   P: lh → mul → sw → bne 循环（matrix scale 循环 @ 0x11b9c）
#   Q: lhu → add → sh → bne 循环（matrix init 循环 @ 0x11b60）
#   R: sh → lh 往返（store 半字后 signed load 回来验证符号扩展）
#   S: 负值半字 → lh 符号扩展 → mul（验证负数乘法）
#   T: 长循环持续压力（100+ 次迭代的 lh+lh+mul+add）
#   U: lh+lh 背靠背 → divu（半字 load + 跨单元）
#   V: 混合 lh/lw/sh/sw 交替访存 + MUL
#   W: lh 后立即 lh 同地址（半字读-读时序）
#   X: sh 后立即 lh 同地址（半字写-读最紧时序）
#
# 约定：x26=1 done, x27=1 pass; fail 时 gp(x3)=子测试编号
# 数据区：0x1A000（CORE_TEST DTCM tag=0x0001 范围内）
# =============================================================================

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ==================================================================
  # N: lh+lh 背靠背 → mul → add → bne 循环
  #    精确复制 matrix_test @ 0x11c80 的 -O3 内循环：
  #      lh   a4, 0(a3)
  #      lh   a6, 0(a5)
  #      addi a5, a5, 2
  #      addi a3, a3, 2
  #      mul  a4, a4, a6
  #      add  a2, a2, a4
  #      bne  a5, a0, loop
  # ==================================================================

  # 准备数据：A[] = {2, 3, 4, 5}（半字），B[] = {10, 20, 30, 40}（半字）
  # 点积 = 2*10 + 3*20 + 4*30 + 5*40 = 20+60+120+200 = 400
  la   x20, 0x1A000
  li   x10, 2;  sh x10, 0(x20)     # A[0] = 2
  li   x10, 3;  sh x10, 2(x20)     # A[1] = 3
  li   x10, 4;  sh x10, 4(x20)     # A[2] = 4
  li   x10, 5;  sh x10, 6(x20)     # A[3] = 5
  li   x10, 10; sh x10, 8(x20)     # B[0] = 10
  li   x10, 20; sh x10, 10(x20)    # B[1] = 20
  li   x10, 30; sh x10, 12(x20)    # B[2] = 30
  li   x10, 40; sh x10, 14(x20)    # B[3] = 40
  nop
  nop
  nop

  # 精确复制 -O3 循环（4 次迭代）
  la   x11, 0x1A000       # a3 = A 指针
  la   x12, 0x1A008       # a5 = B 指针
  la   x13, 0x1A010       # a0 = B 结束地址（B + 4*2 = B+8）
  li   x14, 0             # a2 = 累加器
n_loop:
  lh   x15, 0(x11)        # a4 = *A（signed half-word）
  lh   x16, 0(x12)        # a6 = *B（signed half-word）← 背靠背 lh！
  addi x12, x12, 2        # B++
  addi x11, x11, 2        # A++
  mul  x15, x15, x16      # a4 = A[i] * B[i]
  add  x14, x14, x15      # acc += product
  bne  x12, x13, n_loop   # loop
  li   x15, 400
  bne  x14, x15, failN

  # ==================================================================
  # P: lh → mul → sw → bne 循环
  #    精确复制 matrix_test @ 0x11b9c 的 scale 循环：
  #      lh   a4, 0(a5)
  #      addi a5, a5, 2
  #      addi a3, a3, 4
  #      mul  a4, a4, s3
  #      sw   a4, -4(a3)
  #      bne  a2, a5, loop
  # ==================================================================

  # 数据：src[] = {3, 5, 7, 9}（半字），scalar = 4
  # 结果：dst[] = {12, 20, 28, 36}（字）
  la   x20, 0x1A000
  li   x10, 3;  sh x10, 32(x20)    # src[0]
  li   x10, 5;  sh x10, 34(x20)    # src[1]
  li   x10, 7;  sh x10, 36(x20)    # src[2]
  li   x10, 9;  sh x10, 38(x20)    # src[3]
  nop
  nop
  nop

  la   x11, 0x1A020       # src 指针（0x1A000+32）
  la   x12, 0x1A060       # dst 指针（0x1A000+96）
  la   x13, 0x1A028       # src 结束（src + 4*2）
  li   x14, 4             # scalar
p_loop:
  lh   x15, 0(x11)        # load src[i]（signed half-word）
  addi x11, x11, 2        # src++
  addi x12, x12, 4        # dst++ (word)
  mul  x15, x15, x14      # src[i] * scalar
  sw   x15, -4(x12)       # store to dst[i]
  bne  x13, x11, p_loop   # loop
  # 验证
  la   x12, 0x1A060
  lw   x15, 0(x12);  li x16, 12; bne x15, x16, failP1
  lw   x15, 4(x12);  li x16, 20; bne x15, x16, failP2
  lw   x15, 8(x12);  li x16, 28; bne x15, x16, failP3
  lw   x15, 12(x12); li x16, 36; bne x15, x16, failP4

  # ==================================================================
  # Q: lhu → add → sh → bne 循环
  #    精确复制 matrix_test @ 0x11b60 的 init 循环：
  #      lhu  a4, 0(a5)
  #      addi a5, a5, 2
  #      add  a4, s3, a4
  #      sh   a4, -2(a5)
  #      bne  a5, a3, loop
  # ==================================================================

  # 数据：arr[] = {100, 200, 300, 400}（半字），scalar = 7
  # 结果：arr[i] += 7 → {107, 207, 307, 407}
  la   x20, 0x1A000
  li   x10, 100; sh x10, 64(x20)
  li   x10, 200; sh x10, 66(x20)
  li   x10, 300; sh x10, 68(x20)
  li   x10, 400; sh x10, 70(x20)
  nop
  nop
  nop

  la   x11, 0x1A040       # arr 指针（0x1A000+64）
  la   x12, 0x1A048       # arr 结束（arr + 4*2）
  li   x13, 7             # scalar
q_loop:
  lhu  x14, 0(x11)        # load unsigned half-word
  addi x11, x11, 2        # pointer++
  add  x14, x13, x14      # scalar + arr[i]
  sh   x14, -2(x11)       # store back (half-word)
  bne  x11, x12, q_loop   # loop
  # 验证
  la   x11, 0x1A040
  lhu  x14, 0(x11); li x15, 107; bne x14, x15, failQ1
  lhu  x14, 2(x11); li x15, 207; bne x14, x15, failQ2
  lhu  x14, 4(x11); li x15, 307; bne x14, x15, failQ3
  lhu  x14, 6(x11); li x15, 407; bne x14, x15, failQ4

  # ==================================================================
  # R: sh → lh 往返（验证半字 store 后 signed load 的符号扩展）
  # ==================================================================

  # R1: 正值半字
  la   x20, 0x1A000
  li   x10, 0x1234
  sh   x10, 128(x20)
  nop
  nop
  lh   x11, 128(x20)      # signed load → 应该还是 0x1234
  bne  x10, x11, failR1

  # R2: 负值半字（0xFFF0 = -16 as int16）
  li   x10, 0xFFF0         # -16 as 16-bit signed
  sh   x10, 130(x20)
  nop
  nop
  lh   x11, 130(x20)      # signed load → 应该符号扩展为 0xFFFFFFF0
  li   x12, 0xFFFFFFF0
  bne  x11, x12, failR2

  # R3: lhu 同一地址（应该零扩展为 0x0000FFF0）
  lhu  x11, 130(x20)      # unsigned load → 0x0000FFF0
  li   x12, 0x0000FFF0
  bne  x11, x12, failR3

  # R4: 0x8000（最小负半字 = -32768）
  li   x10, 0x8000
  sh   x10, 132(x20)
  nop
  nop
  lh   x11, 132(x20)      # → 0xFFFF8000
  li   x12, 0xFFFF8000
  bne  x11, x12, failR4

  # R5: 0x7FFF（最大正半字 = 32767）
  li   x10, 0x7FFF
  sh   x10, 134(x20)
  nop
  nop
  lh   x11, 134(x20)      # → 0x00007FFF
  li   x12, 0x00007FFF
  bne  x11, x12, failR5

  # ==================================================================
  # S: 负值半字 → lh 符号扩展 → mul（验证负数乘法）
  # ==================================================================

  # S1: (-16) * 3 = -48
  la   x20, 0x1A000
  li   x10, 0xFFF0         # -16 as int16
  sh   x10, 160(x20)
  nop
  nop
  lh   x11, 160(x20)      # x11 = 0xFFFFFFF0 = -16
  li   x12, 3
  mul  x13, x11, x12      # -16 * 3 = -48 = 0xFFFFFFD0
  li   x14, -48
  bne  x13, x14, failS1

  # S2: (-32768) * 2 = -65536 = 0xFFFF0000
  li   x10, 0x8000
  sh   x10, 162(x20)
  nop
  nop
  lh   x11, 162(x20)      # x11 = 0xFFFF8000 = -32768
  li   x12, 2
  mul  x13, x11, x12      # -32768 * 2 = -65536
  li   x14, -65536
  bne  x13, x14, failS2

  # S3: (-1) * (-1) = 1
  li   x10, 0xFFFF         # -1 as int16
  sh   x10, 164(x20)
  nop
  nop
  lh   x11, 164(x20)      # x11 = 0xFFFFFFFF = -1
  mul  x13, x11, x11      # (-1)*(-1) = 1
  li   x14, 1
  bne  x13, x14, failS3

  # S4: 两个负半字相乘：(-100) * (-200) = 20000
  li   x10, -100           # 0xFF9C as int16
  sh   x10, 166(x20)
  li   x10, -200           # 0xFF38 as int16
  sh   x10, 168(x20)
  nop
  nop
  lh   x11, 166(x20)      # -100
  lh   x12, 168(x20)      # -200 ← 背靠背 lh
  mul  x13, x11, x12      # (-100)*(-200) = 20000
  li   x14, 20000
  bne  x13, x14, failS4

  # ==================================================================
  # T: 长循环持续压力（100 次迭代的 lh+lh+mul+add）
  #    模拟 CoreMark matrix multiply 的持续运行
  # ==================================================================

  # 准备 100 个半字对：A[i] = i+1, B[i] = 1（所以 sum = Σ(i+1) = 5050）
  la   x20, 0x1A000
  li   x10, 0              # i
  li   x11, 100            # count
t_init:
  addi x12, x10, 1        # A[i] = i+1
  sh   x12, 0(x20)        # store A[i]
  li   x12, 1
  sh   x12, 200(x20)      # B[i] = 1（偏移 200 字节 = 100 个半字后）
  addi x20, x20, 2        # next half-word
  addi x10, x10, 1
  bne  x10, x11, t_init

  # 重置指针，跑 100 次 lh+lh+mul+add 循环
  la   x11, 0x1A000       # A 指针
  la   x12, 0x1A0C8       # B 指针（0x1A000 + 200）
  la   x13, 0x1A0C8       # B 结束 = B + 100*2 = B+200
  addi x13, x13, 200
  li   x14, 0             # acc = 0
  nop
  nop
t_loop:
  lh   x15, 0(x11)        # A[i]
  lh   x16, 0(x12)        # B[i] ← 背靠背 lh
  addi x12, x12, 2
  addi x11, x11, 2
  mul  x15, x15, x16      # A[i] * B[i] = (i+1)*1
  add  x14, x14, x15      # acc += product
  bne  x12, x13, t_loop
  li   x15, 5050           # Σ(1..100) = 5050
  bne  x14, x15, failT

  # ==================================================================
  # U: lh+lh 背靠背 → divu（半字 load + 跨单元）
  # ==================================================================

  la   x20, 0x1A000
  li   x10, 100; sh x10, 400(x20)
  li   x10, 7;   sh x10, 402(x20)
  nop
  nop
  nop
  lh   x11, 400(x20)      # 100
  lh   x12, 402(x20)      # 7 ← 背靠背
  divu x13, x11, x12      # 100/7 = 14
  remu x14, x11, x12      # 100%7 = 2
  li   x15, 14
  bne  x13, x15, failU1
  li   x15, 2
  bne  x14, x15, failU2

  # ==================================================================
  # V: 混合 lh/lw/sh/sw 交替访存 + MUL
  # ==================================================================

  la   x20, 0x1A000
  # 写一些半字和字
  li   x10, 6;   sh x10, 500(x20)
  li   x10, 7;   sh x10, 502(x20)
  li   x10, 8;   sw x10, 504(x20)
  li   x10, 9;   sw x10, 508(x20)
  nop
  nop
  nop

  # 混合读取 + 乘法
  lh   x11, 500(x20)      # 6 (half)
  lw   x12, 504(x20)      # 8 (word)
  mul  x13, x11, x12      # 6*8 = 48
  lh   x11, 502(x20)      # 7 (half)
  lw   x12, 508(x20)      # 9 (word)
  mul  x14, x11, x12      # 7*9 = 63
  add  x15, x13, x14      # 111
  li   x16, 111
  bne  x15, x16, failV

  # ==================================================================
  # W: lh 后立即 lh 同地址（半字读-读时序）
  # ==================================================================

  la   x20, 0x1A000
  li   x10, 0x1234
  sh   x10, 600(x20)
  nop
  nop
  nop
  lh   x11, 600(x20)      # 第一次读
  lh   x12, 600(x20)      # 紧跟第二次读（同地址）
  bne  x11, x12, failW1
  li   x13, 0x1234
  bne  x11, x13, failW2

  # ==================================================================
  # X: sh 后立即 lh 同地址（半字写-读最紧时序）
  # ==================================================================

  # X1: sh→lh 紧邻（0 间隔）
  la   x20, 0x1A000
  li   x10, 0x5678
  sh   x10, 700(x20)
  lh   x11, 700(x20)      # ← 紧跟同地址 load
  bne  x10, x11, failX1

  # X2: 负值 sh→lh 紧邻
  li   x10, 0xABCD         # 作为 int16 = -21555
  sh   x10, 702(x20)
  lh   x11, 702(x20)      # ← 紧跟，应符号扩展为 0xFFFFABCD
  li   x12, 0xFFFFABCD
  bne  x11, x12, failX2

  # X3: 连续多组 sh→lh
  li   x10, 0x1111; sh x10, 704(x20); lh x11, 704(x20)
  li   x12, 0x1111; bne x11, x12, failX3a
  li   x10, 0xEEEE; sh x10, 706(x20); lh x11, 706(x20)
  li   x12, 0xFFFFEEEE; bne x11, x12, failX3b
  li   x10, 0x7FFF; sh x10, 708(x20); lh x11, 708(x20)
  li   x12, 0x7FFF; bne x11, x12, failX3c

  # X4: sh→lh→mul 链（半字写-读-乘）
  li   x10, -5             # 0xFFFB
  sh   x10, 710(x20)
  lh   x11, 710(x20)      # -5
  li   x12, 9
  mul  x13, x11, x12      # -5*9 = -45
  li   x14, -45
  bne  x13, x14, failX4

  # ==================================================================
  # Y: 混合字/半字访问同一地址（DTCM 字节使能正确性）
  #    CoreMark -O3 大量混用 sw/sh/lh/lw 访问同一内存区域
  # ==================================================================

  la   x20, 0x1A000

  # Y1: sw 写满字，lh 分别读低半字和高半字
  li   x10, 0xAABBCCDD
  sw   x10, 800(x20)
  nop
  nop
  lh   x11, 800(x20)      # 低半字 = 0xCCDD → 符号扩展 = 0xFFFFCCDD
  lh   x12, 802(x20)      # 高半字 = 0xAABB → 符号扩展 = 0xFFFFAABB
  li   x13, 0xFFFFCCDD
  bne  x11, x13, failY1
  li   x13, 0xFFFFAABB
  bne  x12, x13, failY2

  # Y3: lhu 读同一位置（零扩展）
  lhu  x11, 800(x20)      # 0x0000CCDD
  lhu  x12, 802(x20)      # 0x0000AABB
  li   x13, 0x0000CCDD
  bne  x11, x13, failY3
  li   x13, 0x0000AABB
  bne  x12, x13, failY4

  # Y5: 两个 sh 写同一字的低半和高半，lw 读回完整字
  li   x10, 0x1111
  sh   x10, 808(x20)      # 低半字 = 0x1111
  li   x10, 0x2222
  sh   x10, 810(x20)      # 高半字 = 0x2222
  nop
  nop
  lw   x11, 808(x20)      # 应该 = 0x22221111
  li   x12, 0x22221111
  bne  x11, x12, failY5

  # Y6: sw 写满字，sh 覆盖低半字，lw 读回
  li   x10, 0xDEADBEEF
  sw   x10, 816(x20)      # 全字 = 0xDEADBEEF
  li   x10, 0x1234
  sh   x10, 816(x20)      # 覆盖低半字 → 0xDEAD1234
  nop
  nop
  lw   x11, 816(x20)
  li   x12, 0xDEAD1234
  bne  x11, x12, failY6

  # Y7: sw 写满字，sh 覆盖高半字，lw 读回
  li   x10, 0xCAFEBABE
  sw   x10, 824(x20)      # 全字 = 0xCAFEBABE
  li   x10, 0x5678
  sh   x10, 826(x20)      # 覆盖高半字 → 0x5678BABE
  nop
  nop
  lw   x11, 824(x20)
  li   x12, 0x5678BABE
  bne  x11, x12, failY7

  # Y8: sh 写低半字，sw 读（验证 sh 不破坏高半字）
  li   x10, 0x99998888
  sw   x10, 832(x20)      # 先写全字
  li   x10, 0x7777
  sh   x10, 832(x20)      # 只改低半字 → 0x99997777
  nop
  nop
  lw   x11, 832(x20)
  li   x12, 0x99997777
  bne  x11, x12, failY8

  # ==================================================================
  # Z: 字节操作（lb/lbu/sb）+ 混合访存
  #    CoreMark state machine kernel 大量使用字节操作
  # ==================================================================

  la   x20, 0x1A000

  # Z1: sb 写 4 个字节，lw 读回
  li   x10, 0x11; sb x10, 900(x20)
  li   x10, 0x22; sb x10, 901(x20)
  li   x10, 0x33; sb x10, 902(x20)
  li   x10, 0x44; sb x10, 903(x20)
  nop
  nop
  lw   x11, 900(x20)      # 小端：0x44332211
  li   x12, 0x44332211
  bne  x11, x12, failZ1

  # Z2: sw 写字，lb 逐字节读（signed）
  li   x10, 0x80FF01FE
  sw   x10, 908(x20)
  nop
  nop
  lb   x11, 908(x20)      # byte0 = 0xFE → 符号扩展 = 0xFFFFFFFE
  lb   x12, 909(x20)      # byte1 = 0x01 → 0x00000001
  lb   x13, 910(x20)      # byte2 = 0xFF → 0xFFFFFFFF
  lb   x14, 911(x20)      # byte3 = 0x80 → 0xFFFFFF80
  li   x15, 0xFFFFFFFE; bne x11, x15, failZ2a
  li   x15, 0x00000001; bne x12, x15, failZ2b
  li   x15, 0xFFFFFFFF; bne x13, x15, failZ2c
  li   x15, 0xFFFFFF80; bne x14, x15, failZ2d

  # Z3: lbu 逐字节读（unsigned）
  lbu  x11, 908(x20)      # 0x000000FE
  lbu  x12, 909(x20)      # 0x00000001
  lbu  x13, 910(x20)      # 0x000000FF
  lbu  x14, 911(x20)      # 0x00000080
  li   x15, 0x000000FE; bne x11, x15, failZ3a
  li   x15, 0x00000001; bne x12, x15, failZ3b
  li   x15, 0x000000FF; bne x13, x15, failZ3c
  li   x15, 0x00000080; bne x14, x15, failZ3d

  # Z4: sb 覆盖字的某一个字节，lw 验证其他字节不变
  # 小端序：0xAABBCCDD 在内存中 = [DD, CC, BB, AA]
  # sb 到 offset+1 替换 byte1(CC→11)，读回 = 0xAABB11DD
  li   x10, 0xAABBCCDD
  sw   x10, 916(x20)
  li   x10, 0x11
  sb   x10, 917(x20)      # 覆盖 byte1: CC→11
  nop
  nop
  lw   x11, 916(x20)
  li   x12, 0xAABB11DD
  bne  x11, x12, failZ4

  # Z5: sh + sb 混合写同一字
  li   x10, 0x00000000
  sw   x10, 924(x20)      # 清零
  li   x10, 0xBEEF
  sh   x10, 924(x20)      # 低半字 = 0xBEEF
  li   x10, 0xDE
  sb   x10, 926(x20)      # byte2 = 0xDE → 0x00DEBEEF
  nop
  nop
  lw   x11, 924(x20)
  li   x12, 0x00DEBEEF
  bne  x11, x12, failZ5

  # ==================================================================
  # AA: 混合访存 + MUL 循环（模拟 CoreMark 完整数据流）
  #     sh 写半字数组 → lh 读回 → mul → sw 存结果 → lw 验证
  # ==================================================================

  # 初始化：arr[i] = i+1 (半字), i=0..15
  la   x20, 0x1A000
  li   x10, 0
aa_init:
  addi x11, x10, 1
  sh   x11, 1000(x20)
  addi x20, x20, 2
  addi x10, x10, 1
  li   x11, 16
  bne  x10, x11, aa_init

  # 计算：result[i] = arr[i] * arr[i]（平方），存为字
  la   x20, 0x1A000
  la   x21, 0x1A000
  addi x21, x21, 1032     # result 区（1000 + 16*2 = 1032）
  li   x10, 0              # counter
  li   x11, 16             # limit
aa_loop:
  lh   x12, 0(x20)        # load arr[i]（signed half-word）
  addi x20, x20, 2
  mul  x13, x12, x12      # arr[i]^2
  sw   x13, 0(x21)        # store result
  addi x21, x21, 4
  addi x10, x10, 1
  bne  x10, x11, aa_loop

  # 验证：sum of squares 1^2+2^2+...+16^2 = 1496
  la   x21, 0x1A000
  addi x21, x21, 1032
  li   x10, 0              # sum
  li   x11, 0              # counter
  li   x12, 16             # limit
aa_verify:
  lw   x13, 0(x21)
  add  x10, x10, x13
  addi x21, x21, 4
  addi x11, x11, 1
  bne  x11, x12, aa_verify
  li   x13, 1496
  bne  x10, x13, failAA

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
failN:   li x26,1; li x27,2; li gp,2;  j fail_loop
failP1:  li x26,1; li x27,3; li gp,3;  j fail_loop
failP2:  li x26,1; li x27,4; li gp,4;  j fail_loop
failP3:  li x26,1; li x27,5; li gp,5;  j fail_loop
failP4:  li x26,1; li x27,6; li gp,6;  j fail_loop
failQ1:  li x26,1; li x27,7; li gp,7;  j fail_loop
failQ2:  li x26,1; li x27,8; li gp,8;  j fail_loop
failQ3:  li x26,1; li x27,9; li gp,9;  j fail_loop
failQ4:  li x26,1; li x27,10; li gp,10; j fail_loop
failR1:  li x26,1; li x27,11; li gp,11; j fail_loop
failR2:  li x26,1; li x27,12; li gp,12; j fail_loop
failR3:  li x26,1; li x27,13; li gp,13; j fail_loop
failR4:  li x26,1; li x27,14; li gp,14; j fail_loop
failR5:  li x26,1; li x27,15; li gp,15; j fail_loop
failS1:  li x26,1; li x27,16; li gp,16; j fail_loop
failS2:  li x26,1; li x27,17; li gp,17; j fail_loop
failS3:  li x26,1; li x27,18; li gp,18; j fail_loop
failS4:  li x26,1; li x27,19; li gp,19; j fail_loop
failT:   li x26,1; li x27,20; li gp,20; j fail_loop
failU1:  li x26,1; li x27,21; li gp,21; j fail_loop
failU2:  li x26,1; li x27,22; li gp,22; j fail_loop
failV:   li x26,1; li x27,23; li gp,23; j fail_loop
failW1:  li x26,1; li x27,24; li gp,24; j fail_loop
failW2:  li x26,1; li x27,25; li gp,25; j fail_loop
failX1:  li x26,1; li x27,26; li gp,26; j fail_loop
failX2:  li x26,1; li x27,27; li gp,27; j fail_loop
failX3a: li x26,1; li x27,28; li gp,28; j fail_loop
failX3b: li x26,1; li x27,29; li gp,29; j fail_loop
failX3c: li x26,1; li x27,30; li gp,30; j fail_loop
failX4:  li x26,1; li x27,31; li gp,31; j fail_loop
failY1:  li x26,1; li x27,32; li gp,32; j fail_loop
failY2:  li x26,1; li x27,33; li gp,33; j fail_loop
failY3:  li x26,1; li x27,34; li gp,34; j fail_loop
failY4:  li x26,1; li x27,35; li gp,35; j fail_loop
failY5:  li x26,1; li x27,36; li gp,36; j fail_loop
failY6:  li x26,1; li x27,37; li gp,37; j fail_loop
failY7:  li x26,1; li x27,38; li gp,38; j fail_loop
failY8:  li x26,1; li x27,39; li gp,39; j fail_loop
failZ1:  li x26,1; li x27,40; li gp,40; j fail_loop
failZ2a: li x26,1; li x27,41; li gp,41; j fail_loop
failZ2b: li x26,1; li x27,42; li gp,42; j fail_loop
failZ2c: li x26,1; li x27,43; li gp,43; j fail_loop
failZ2d: li x26,1; li x27,44; li gp,44; j fail_loop
failZ3a: li x26,1; li x27,45; li gp,45; j fail_loop
failZ3b: li x26,1; li x27,46; li gp,46; j fail_loop
failZ3c: li x26,1; li x27,47; li gp,47; j fail_loop
failZ3d: li x26,1; li x27,48; li gp,48; j fail_loop
failZ4:  li x26,1; li x27,49; li gp,49; j fail_loop
failZ5:  li x26,1; li x27,50; li gp,50; j fail_loop
failAA:  li x26,1; li x27,51; li gp,51; j fail_loop
fail_loop:
  j    fail_loop

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
