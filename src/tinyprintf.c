/*
 * BD32 SoC — 轻量级 printf 实现
 * 无 malloc、无 heap、无浮点支持
 * 直接调用 _putchar() 输出到 UART
 *
 * 基于 mpaland/printf 精简
 */

#include <stdarg.h>
#include <stdint.h>

/* 用户需实现的底层输出函数 */
extern void _putchar(char c);

static void _outchar(char c) {
    if (c == '\n') _putchar('\r');
    _putchar(c);
}

static void _outstr(const char *s) {
    while (*s) _outchar(*s++);
}

static void _outnum(uint32_t n, unsigned base, int sign) {
    char buf[12];       // 10 进制最多 10 位 + '-' + '\0' = 12
    char *p = buf + sizeof(buf) - 1;
    *p = '\0';

    if (sign && (int32_t)n < 0) {
        _outchar('-');
        n = -(int32_t)n;
    }

    if (n == 0) *--p = '0';
    else while (n) {
        unsigned d = n % base;
        *--p = d < 10 ? '0' + d : 'a' + d - 10;
        n /= base;
    }

    _outstr(p);
}

int vprintf(const char *fmt, va_list ap) {
    int count = 0;

    while (*fmt) {
        if (*fmt != '%') {
            _outchar(*fmt++);
            count++;
            continue;
        }

        fmt++; /* skip '%' */

        int lflag = 0;

        /* skip flags and width (%-+ #0123456789) - 忽略不做格式化 */
        while (*fmt == '-' || *fmt == '+' || *fmt == ' ' ||
               *fmt == '#' || *fmt == '0' ||
               (*fmt >= '0' && *fmt <= '9')) {
            fmt++;
        }

        /* length */
        if (*fmt == 'l') {
            lflag = 1;
            fmt++;
        }

        switch (*fmt) {
            case 'd':
            case 'i': {
                int32_t v = lflag ? (int32_t)va_arg(ap, long)
                                  : va_arg(ap, int);
                _outnum((uint32_t)v, 10, 1);
                break;
            }
            case 'u': {
                uint32_t v = lflag ? va_arg(ap, unsigned long)
                                   : va_arg(ap, unsigned int);
                _outnum(v, 10, 0);
                break;
            }
            case 'x':
            case 'X': {
                uint32_t v = lflag ? va_arg(ap, unsigned long)
                                   : va_arg(ap, unsigned int);
                _outnum(v, 16, 0);
                break;
            }
            case 'p': {
                _outstr("0x");
                _outnum(va_arg(ap, uint32_t), 16, 0);
                break;
            }
            case 's': {
                const char *s = va_arg(ap, const char*);
                if (!s) s = "(null)";
                _outstr(s);
                break;
            }
            case 'c': {
                char c = (char)va_arg(ap, int);
                _outchar(c);
                break;
            }
            case '%':
                _outchar('%');
                break;
            default:
                _outchar('%');
                _outchar(*fmt);
                break;
        }
        fmt++;
        count++;
    }

    return count;
}

int printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int ret = vprintf(fmt, ap);
    va_end(ap);
    return ret;
}
