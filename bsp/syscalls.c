/*
 * BD32 系统调用 Stub
 * 参考 Panda RISC-V / tinyriscv / riscv-mcu syscalls
 *
 * 用于 -nostartfiles -nodefaultlibs 编译，提供 libc 所需的底层接口
 */

#include <stdint.h>
#include <stddef.h>

int errno = 0;

/* 堆管理 */
extern char __heap_start;
extern char __heap_end;

void *_sbrk(int incr) {
    static char *heap_ptr = NULL;
    if (heap_ptr == NULL) heap_ptr = &__heap_start;
    char *prev = heap_ptr;
    heap_ptr += incr;
    if (heap_ptr > &__heap_end) return (void *)-1;
    return prev;
}

/* 文件操作 stub */
int _close(int fd)       { (void)fd; return -1; }
int _fstat(int fd, void *buf) { (void)fd; (void)buf; return 0; }
int _isatty(int fd)      { (void)fd; return 1; }
int _lseek(int fd, int ptr, int dir) { (void)fd; (void)ptr; (void)dir; return 0; }
int _read(int fd, char *ptr, int len) { (void)fd; (void)ptr; (void)len; return 0; }
int _write(int fd, const char *ptr, int len) { (void)fd; (void)ptr; (void)len; return 0; }

void _exit(int status)   { (void)status; while (1); }
int _kill(int pid, int sig) { (void)pid; (void)sig; return -1; }
int _getpid(void)        { return 1; }
