/* Test 64-bit division (requires __udivdi3 from libgcc or compiler-rt) */
unsigned long long test_div64(unsigned long long a, unsigned long long b) {
    return a / b;
}
/* Test software float emulation */
int test_mul(int a, int b) {
    return a * b;  /* should use mul instruction, ok on rv32im */
}
