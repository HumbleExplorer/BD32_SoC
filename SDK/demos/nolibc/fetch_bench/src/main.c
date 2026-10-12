/*
 * 取指路径微基准：隔离 RV32C 对流水线取指的影响（与代码生成无关）
 *
 * 四个循环，每迭代指令数/分支模式完全相同，仅指令位宽与对齐不同：
 *   A none32     : 10×32 位（9 addi + bne 循环回跳），循环头 4 字节对齐
 *   B c16_aligned: 10×16 位（9 c.addi + c.bnez），循环头 4 字节对齐
 *   C c16_up2    : 同 B，但循环头错位到字内 +2 半字
 *   D c_straddle : 循环体 = [c.addi][32 位 bne 跨字]，bne 每次都被取指跨越字边界
 *
 * 若取指路径对 16 位流零开销，B/A 的 cycles/inst 应≈1:1（分支数相同）；
 * C/B 差值 = 重定向到 +2 目标的代价；D 显式暴露跨字 32 位取指成本。
 */
#include "bsp.h"

typedef unsigned int u32;

static inline u32 rdcycle(void) {
    u32 x;
    asm volatile("csrr %0, mcycle" : "=r"(x));
    return x;
}

#define BENCH_N 200000

/* A: 纯 32 位参照（march 含 c 也不会自动压缩显式助记符） */
asm(
    ".balign 4\n"
    "bench_a_none32:\n"
    "1: addi a1, a1, 1\n"
    "   addi a2, a2, 1\n"
    "   addi a3, a3, 1\n"
    "   addi a4, a4, 1\n"
    "   addi a5, a5, 1\n"
    "   addi a1, a1, 2\n"
    "   addi a2, a2, 2\n"
    "   addi a3, a3, 2\n"
    "   addi a0, a0, -1\n"
    "   bne  a0, zero, 1b\n"
    "   ret\n"
);

/* B: 纯 16 位，循环头 4 字节对齐 */
asm(
    ".balign 4\n"
    "bench_b_c16_aligned:\n"
    "1: c.addi a1, 1\n"
    "   c.addi a2, 1\n"
    "   c.addi a3, 1\n"
    "   c.addi a4, 1\n"
    "   c.addi a5, 1\n"
    "   c.addi a1, 2\n"
    "   c.addi a2, 2\n"
    "   c.addi a3, 2\n"
    "   c.addi a0, -1\n"
    "   c.bnez a0, 1b\n"
    "   ret\n"
);

/* C: 纯 16 位，循环头在字内 +2（垫一条 c.nop=0x0001） */
asm(
    ".balign 4\n"
    "   .half 0x0001\n"
    "bench_c_c16_up2:\n"
    "1: c.addi a1, 1\n"
    "   c.addi a2, 1\n"
    "   c.addi a3, 1\n"
    "   c.addi a4, 1\n"
    "   c.addi a5, 1\n"
    "   c.addi a1, 2\n"
    "   c.addi a2, 2\n"
    "   c.addi a3, 2\n"
    "   c.addi a0, -1\n"
    "   c.bnez a0, 1b\n"
    "   ret\n"
);

/* D: 16 位体 + 32 位跨字 bne（bne 起点=循环头+2，跨越字边界） */
asm(
    ".balign 4\n"
    "bench_d_straddle:\n"
    "1: c.addi a1, 1\n"
    "   c.addi a2, 1\n"
    "   c.addi a3, 1\n"
    "   c.addi a4, 1\n"
    "   c.addi a5, 1\n"
    "   c.addi a1, 2\n"
    "   c.addi a2, 2\n"
    "   c.addi a3, 2\n"
    "   c.addi a0, -1\n"
    "   bne  a0, zero, 1b\n"   /* 从 1:+16B 起，32 位，跨到下一字 */
    "   ret\n"
);

/* E: 长直线流（64 条指令，无taken分支）：顺序取指吞吐，10 条一组的
      16/32 混合按 1:1 交错，末尾 dec/jnz，n 次外层 */
asm(
    ".balign 4\n"
    "bench_e_linear:\n"
    "1: c.addi a1, 1\n"
    "   addi  a2, a2, 1\n"
    "   c.addi a3, 1\n"
    "   addi  a4, a4, 1\n"
    "   c.addi a5, 1\n"
    "   addi  a1, a1, 2\n"
    "   c.addi a2, 2\n"
    "   addi  a3, a3, 2\n"
    "   c.addi a4, 2\n"
    "   addi  a5, a5, 2\n"
    "   c.addi a1, 3\n"
    "   addi  a2, a2, 3\n"
    "   c.addi a3, 3\n"
    "   addi  a4, a4, 3\n"
    "   c.addi a5, 3\n"
    "   addi  a1, a1, 4\n"
    "   c.addi a2, 4\n"
    "   addi  a3, a3, 4\n"
    "   c.addi a4, 4\n"
    "   addi  a5, a5, 4\n"
    "   c.addi a0, -1\n"
    "   bne  a0, zero, 1b\n"
    "   ret\n"
);

/* F: 16 位串行依赖链（同一寄存器连加，测 EX→ID 前递/旁路） */
asm(
    ".balign 4\n"
    "bench_f_serial16:\n"
    "1: c.addi a1, 1\n"
    "   c.addi a1, 1\n"
    "   c.addi a1, 1\n"
    "   c.addi a1, 1\n"
    "   c.addi a1, 1\n"
    "   c.addi a1, 1\n"
    "   c.addi a1, 1\n"
    "   c.addi a1, 1\n"
    "   c.addi a0, -1\n"
    "   c.bnez a0, 1b\n"
    "   ret\n"
);

/* G: 32 位串行依赖链（对照 F） */
asm(
    ".balign 4\n"
    "bench_g_serial32:\n"
    "1: addi a1, a1, 1\n"
    "   addi a1, a1, 1\n"
    "   addi a1, a1, 1\n"
    "   addi a1, a1, 1\n"
    "   addi a1, a1, 1\n"
    "   addi a1, a1, 1\n"
    "   addi a1, a1, 1\n"
    "   addi a1, a1, 1\n"
    "   addi a0, a0, -1\n"
    "   bne  a0, zero, 1b\n"
    "   ret\n"
);

/* H: 16 位 call/ret（c.jal + c.jr）——测 RAS 对压缩调用/返回的识别 */
asm(
    ".balign 4\n"
    "bench_h_call16:\n"
    "   c.addi16sp sp, -16\n"
    "   c.swsp ra, 12(sp)\n"
    "1: c.jal h_inner\n"
    "   c.addi a0, -1\n"
    "   c.bnez a0, 1b\n"
    "   c.lwsp ra, 12(sp)\n"
    "   c.addi16sp sp, 16\n"
    "   ret\n"
    "h_inner:\n"
    "   c.addi a1, 1\n"
    "   c.jr ra\n"
);

/* I: 32 位 call/ret（jal + jalr，.option norvc 强制 32 位编码） */
asm(
    ".balign 4\n"
    "bench_i_call32:\n"
    "   .option push\n"
    "   .option norvc\n"
    "   addi sp, sp, -16\n"
    "   sw ra, 12(sp)\n"
    "1: jal  ra, i_inner\n"
    "   addi a0, a0, -1\n"
    "   bne  a0, zero, 1b\n"
    "   lw   ra, 12(sp)\n"
    "   addi sp, sp, 16\n"
    "   ret\n"
    "i_inner:\n"
    "   addi a1, a1, 1\n"
    "   jalr zero, ra, 0\n"
    "   .option pop\n"
);

/* J: 16 位调用 + 32 位返回（隔离哪一侧破坏 RAS） */
asm(
    ".balign 4\n"
    "bench_j_mix1:\n"
    "   c.addi16sp sp, -16\n"
    "   c.swsp ra, 12(sp)\n"
    "1: c.jal j_inner\n"
    "   c.addi a0, -1\n"
    "   c.bnez a0, 1b\n"
    "   c.lwsp ra, 12(sp)\n"
    "   c.addi16sp sp, 16\n"
    "   ret\n"
    "j_inner:\n"
    "   .option push\n"
    "   .option norvc\n"
    "   addi a1, a1, 1\n"
    "   jalr zero, ra, 0\n"
    "   .option pop\n"
);

/* K: 32 位调用 + 16 位返回 */
asm(
    ".balign 4\n"
    "bench_k_mix2:\n"
    "   .option push\n"
    "   .option norvc\n"
    "   addi sp, sp, -16\n"
    "   sw ra, 12(sp)\n"
    "   .option pop\n"
    "1: jal  ra, k_inner\n"
    "   c.addi a0, -1\n"
    "   c.bnez a0, 1b\n"
    "   .option push\n"
    "   .option norvc\n"
    "   lw ra, 12(sp)\n"
    "   addi sp, sp, 16\n"
    "   ret\n"
    "   .option pop\n"
    "k_inner:\n"
    "   c.addi a1, 1\n"
    "   c.jr ra\n"
);

extern void bench_a_none32(unsigned n);
extern void bench_b_c16_aligned(unsigned n);
extern void bench_c_c16_up2(unsigned n);
extern void bench_d_straddle(unsigned n);
extern void bench_e_linear(unsigned n);
extern void bench_f_serial16(unsigned n);
extern void bench_g_serial32(unsigned n);
extern void bench_h_call16(unsigned n);
extern void bench_i_call32(unsigned n);
extern void bench_j_mix1(unsigned n);
extern void bench_k_mix2(unsigned n);

typedef void (*bench_fn)(unsigned);

/* 每迭代指令数：A/B/C/D=10，E=22 */
static void report(const char *name, bench_fn fn, u32 insts_per_iter, u32 n) {
    u32 t0, t1, cyc;
    t0 = rdcycle();
    fn(n);
    t1 = rdcycle();
    cyc = t1 - t0;
    uart_puts(name);
    uart_puts(" cycles=");
    uart_puthex(cyc);
    uart_puts(" insts=");
    uart_puthex(insts_per_iter * n);
    uart_puts(" cpi_x100=");
    if (insts_per_iter * n > 0)
        uart_putdec((u32)((unsigned long long)cyc * 100 / ((unsigned long long)insts_per_iter * n)));
    uart_puts("\r\n");
}

int main(void) {
    uart_init(115200);
    uart_puts("\r\nBD32 fetch-path microbench (rv32imc build)\r\n");

    report("A_none32      ", bench_a_none32,      10, BENCH_N);
    report("B_c16_aligned ", bench_b_c16_aligned, 10, BENCH_N);
    report("C_c16_up2     ", bench_c_c16_up2,     10, BENCH_N);
    report("D_straddle    ", bench_d_straddle,    10, BENCH_N);
    report("E_linear_mix  ", bench_e_linear,      22, BENCH_N);
    report("F_serial16    ", bench_f_serial16,    10, BENCH_N);
    report("G_serial32    ", bench_g_serial32,    10, BENCH_N);
    report("H_call16      ", bench_h_call16,       5, BENCH_N);
    report("I_call32      ", bench_i_call32,       5, BENCH_N);
    report("J_call16ret32 ", bench_j_mix1,         5, BENCH_N);
    report("K_call32ret16 ", bench_k_mix2,         5, BENCH_N);
    uart_puts("done\r\n");
    while (1);
    return 0;
}
