#include <stdio.h>

int main(void)
{
    int a = -1;
    short s = -1;
    char c = -1;
    unsigned int u = 0xffffffffu;
    printf("int   %llx\n", (unsigned long long)__builtin_bswap64(a));
    printf("short %llx\n", (unsigned long long)__builtin_bswap64(s));
    printf("char  %llx\n", (unsigned long long)__builtin_bswap64(c));
    printf("uint  %llx\n", (unsigned long long)__builtin_bswap64(u));
    printf("direct%llx\n", (unsigned long long)__builtin_bswap64(-1));
    return 0;
}
