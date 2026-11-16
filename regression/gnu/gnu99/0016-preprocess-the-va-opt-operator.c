/* 0016: CHECK(ADD(4) == 4); CHECK(ADD(4, 3) == 7); CHECK(PAIR(1, 2) == 12);
 *       CHECK(EMPTY(1,) == 1);
 *
 * __VA_OPT__ is C23 6.10.4.1, and before C23 it is a GNU extension: the content
 * inside the parentheses is there when the variable arguments are non-empty and
 * gone when they are not, which is the portable spelling of a separator that
 * goes away with the last argument. The first CHECK is the operator with no
 * variadic argument at all, the second with one; the third is the content naming
 * a macro of its own, so the separator is a second expansion; the fourth is an
 * empty variadic argument, which gcc measures as empty.
 *
 * The statuses here are gcc 16.2.1's: the same file compiled with
 * `gcc -std=gnu99` exits 0 and prints nothing, and so does the same file under
 * `-std=c23`.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

/* The operator as a separator: `ADD(4)` is 4 and `ADD(4, 3)` is 7. */
#define ADD(a, ...) ((a) __VA_OPT__(+) __VA_ARGS__)

/* The content is a macro of its own, expanded after the operator is read. */
#define COMMA ,
#define PAIR(a, ...) pair((a) __VA_OPT__(COMMA) __VA_ARGS__)

/* One empty variadic argument is empty, measured on gcc: the content goes. */
#define EMPTY(a, ...) ((a) __VA_OPT__(+ 100) __VA_ARGS__)

static int pair(int a, int b)
{
    return a * 10 + b;
}

int main(void)
{
    CHECK(ADD(4) == 4);
    CHECK(ADD(4, 3) == 7);
    CHECK(PAIR(1, 2) == 12);
    CHECK(EMPTY(1,) == 1);
    return 0;
}
