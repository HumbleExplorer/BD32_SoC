/*
 * BD32 CLINT 底层操作 — 纯汇编实现，避免 C 编译器生成的访存问题
 *
 * 提供 C 可调用的函数接口，让 C 代码不直接访问 CLINT 地址
 * 参考：ti_sim.s 的汇编代码（已验证能正常工作）
 */

.text
.align 2

.global clint_asm_get_mtime_lo
.global clint_asm_get_mtime
.global clint_asm_set_mtimecmp
.global clint_asm_set_timeout_ticks

.equ CLINT_BASE,    0xF2000000
.equ MTIME_LO,      0xBFF8
.equ MTIME_HI,      0xBFFC
.equ MTIMECMP_LO,   0x4000
.equ MTIMECMP_HI,   0x4004

/* uint32_t clint_asm_get_mtime_lo(void)
 * 读 mtime 低 32 位（单次读取，不做双字校验） */
clint_asm_get_mtime_lo:
    li   t0, CLINT_BASE
    li   t1, MTIME_LO
    add  t0, t0, t1
    lw   a0, 0(t0)
    ret

/* uint64_t clint_asm_get_mtime(void)
 * 读完整 64 位 mtime（带双读校验） */
clint_asm_get_mtime:
    li   t0, CLINT_BASE
1:  li   t1, MTIME_HI
    add  t2, t0, t1
    lw   t3, 0(t2)          # hi 第一次
    li   t1, MTIME_LO
    add  t2, t0, t1
    lw   t4, 0(t2)          # lo
    li   t1, MTIME_HI
    add  t2, t0, t1
    lw   t5, 0(t2)          # hi 第二次
    bne  t3, t5, 1b         # 校验

    # 拼接 64 位返回值 (a0 = lo, a1 = hi)
    mv   a0, t4
    mv   a1, t3
    ret

/* void clint_asm_set_mtimecmp(uint64_t val)
 * 写 mtimecmp，遵循 RISC-V 规范：先写 lo=-1 防止中间状态误触发 */
clint_asm_set_mtimecmp:
    li   t0, CLINT_BASE

    // Step 1: mtimecmp_lo = -1 (防止 hi 写入期间误触发)
    li   t2, MTIMECMP_LO
    add  t3, t0, t2
    li   t4, -1
    sw   t4, 0(t3)

    // Step 2: mtimecmp_hi = val.hi
    li   t2, MTIMECMP_HI
    add  t3, t0, t2
    sw   a1, 0(t3)

    // Step 3: mtimecmp_lo = val.lo
    li   t2, MTIMECMP_LO
    add  t3, t0, t2
    sw   a0, 0(t3)
    ret

/* void clint_asm_set_timeout_ticks(uint32_t ticks)
 * 设 mtimecmp = mtime + ticks（32位版本，按规范先写 lo=-1 防误触发） */
clint_asm_set_timeout_ticks:
    li   t0, CLINT_BASE

    // 读 mtime[31:0]
    li   t1, MTIME_LO
    add  t2, t0, t1
    lw   t3, 0(t2)          # t3 = mtime_lo
    add  t3, t3, a0         # t3 = mtime_lo + ticks

    // Step 1: mtimecmp_lo = -1 (防止 hi 写入期间误触发)
    li   t1, MTIMECMP_LO
    add  t2, t0, t1
    li   t4, -1
    sw   t4, 0(t2)

    // Step 2: mtimecmp_hi = 0
    li   t1, MTIMECMP_HI
    add  t2, t0, t1
    sw   zero, 0(t2)

    // Step 3: mtimecmp_lo = target
    li   t1, MTIMECMP_LO
    add  t2, t0, t1
    sw   t3, 0(t2)
    ret
