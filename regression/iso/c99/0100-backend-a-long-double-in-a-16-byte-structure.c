/* 0100: a 16-byte structure holding one long double follows the SysV ABI

Issue #142. SysV x86-64 gives a struct with one long double the classes X87 and
X87UP. Its caller passes it in memory, padding the stack when an odd number of
eightbytes is already there, and its callee returns it on the x87 stack. vcc
classified both eightbytes as INTEGER, passed them in rdi and rsi, and returned
them in rax and rdx. A caller and callee built by different compilers then saw
nan or zero, while two halves built by the same compiler agreed by accident.

The checks below cover the argument, the result, a call result used as an
argument, a member read from a call result, the stack padding with seven integers
ahead of the structure, and a larger structure that stays in general registers.
 */

#include <stdio.h>

#define CHECK(...)                                                             \
    do {                                                                       \
        if (!(__VA_ARGS__)) {                                                  \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); \
            return 1;                                                          \
        }                                                                      \
    } while (0)

struct H1 {
    long double a;
};

struct H2 {
    long double a;
    int i;
};

static struct H1 make(long double v)
{
    struct H1 h = { v };
    return h;
}

static long double take(struct H1 h)
{
    return h.a;
}

static long double padded(int a, int b, int c, int d, int e, int f, int g,
                          struct H1 h)
{
    return h.a + a + g;
}

static struct H2 make2(long double v, int i)
{
    struct H2 h = { v, i };
    return h;
}

static long double take2(struct H2 h)
{
    return h.a + h.i;
}

int main(void)
{
    struct H1 v = make(31.25L);

    CHECK(v.a == 31.25L);
    CHECK(take(v) == 31.25L);
    CHECK(take(make(12.5L)) == 12.5L);
    CHECK(make(47.25L).a == 47.25L);
    CHECK(padded(1, 2, 3, 4, 5, 6, 7, v) == 39.25L);
    CHECK(take2(make2(9.5L, 3)) == 12.5L);
    return 0;
}
