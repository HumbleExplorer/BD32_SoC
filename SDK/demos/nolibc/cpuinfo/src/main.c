/*
 * Demo: CPU Info — CSR 寄存器 dump
 * 验证：CSR 读写全通路 (mstatus/mtvec/mie/mcause/mepc/mcycle 等)
 */
#include "bsp.h"

static void print_csr(const char *name, uint32_t val)
{
    uart_puts(name);
    uart_puts(" = ");
    uart_puthex(val);
    uart_puts("\r\n");
}

int main(void)
{
    uart_init();
    uart_puts("\r\nBD32 CPU Info\r\n");

    print_csr("mstatus", read_csr(mstatus));
    print_csr("mtvec",   read_csr(mtvec));
    print_csr("mie",     read_csr(mie));
    print_csr("mip",     read_csr(mip));
    print_csr("mcause",  read_csr(mcause));
    print_csr("mepc",    read_csr(mepc));
    print_csr("mtval",   read_csr(mtval));
    print_csr("mcycle",  read_csr(mcycle));
    print_csr("mhartid", read_csr(mhartid));

    uart_puts("BD32: RV32IM M-mode\r\n");
    while (1);
    return 0;
}
