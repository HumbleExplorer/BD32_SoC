/*
 * Demo: newlib-nano 全功能测试
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <errno.h>
#include "bsp.h"

static int tests = 0, passed = 0;
#define CHECK(cond, msg) do { \
    tests++; \
    if (cond) { passed++; printf("  OK %s\r\n", msg); } \
    else      { printf("  FAIL %s\r\n", msg); } \
} while(0)

int main(void)
{
    uart_init(115200);
    printf("\r\n=== BD32 newlib-nano Test ===\r\n");

    /* 1. 格式化输出 */
    printf("\r\n--- printf ---\r\n");
    printf("  dec=%d\r\n", 42);
    printf("  hex=0x%x\r\n", 0xFF);
    printf("  str=%s\r\n", "hello");
    printf("  char='%c'\r\n", 'A');

    char buf[64];
    sprintf(buf, "sprintf: %d + %d = %d", 1, 2, 1+2);
    printf("  %s\r\n", buf);
    CHECK(strcmp(buf, "sprintf: 1 + 2 = 3") == 0, "sprintf");

    /* 2. 字符串 */
    printf("\r\n--- string ---\r\n");
    CHECK(strlen("hello") == 5, "strlen");
    char dst[16];
    strcpy(dst, "copy_test");
    CHECK(strcmp(dst, "copy_test") == 0, "strcpy");
    memset(dst, 0, sizeof(dst));
    memcpy(dst, "memcpy", 6);
    CHECK(strcmp(dst, "memcpy") == 0, "memcpy");
    CHECK(strchr("abc", 'b') != NULL, "strchr");
    CHECK(strstr("hello world", "world") != NULL, "strstr");

    /* 3. 类型转换 */
    printf("\r\n--- stdlib ---\r\n");
    CHECK(atoi("123") == 123, "atoi");
    CHECK(strtol("0xFF", NULL, 16) == 255, "strtol hex");
    CHECK(abs(-7) == 7, "abs");

    /* 4. malloc */
    printf("\r\n--- malloc ---\r\n");
    void *p1 = malloc(128);
    void *p2 = malloc(256);
    CHECK(p1 != NULL && p2 != NULL, "malloc x2");
    free(p1); free(p2);
    p1 = calloc(10, 4);
    CHECK(p1 != NULL, "calloc");
    free(p1);

    /* 5. 数学 */
    printf("\r\n--- math ---\r\n");
    CHECK(abs(-5) == 5, "abs");
    double d = sqrt(9.0);
    CHECK(d > 2.99 && d < 3.01, "sqrt(9)");
    d = sin(0.0);
    CHECK(d > -0.01 && d < 0.01, "sin(0)");
    d = cos(0.0);
    CHECK(d > 0.99 && d < 1.01, "cos(0)");
    d = fabs(-3.14);
    CHECK(d > 3.13 && d < 3.15, "fabs(-3.14)");

    /* 6. errno */
    printf("\r\n--- errno ---\r\n");
    errno = ENOMEM;
    CHECK(errno == ENOMEM, "errno set");

    /* 结果 */
    printf("\r\n=== RESULT: %d/%d passed ===\r\n", passed, tests);
    if (passed == tests)
        printf("PASS!\r\n");
    else
        printf("SOME TESTS FAILED!\r\n");

    while (1);
    return 0;
}
