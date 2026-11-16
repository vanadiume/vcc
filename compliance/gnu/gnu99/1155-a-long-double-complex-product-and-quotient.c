/* 1155: CHECK(creall(p) == -5.0L && cimagl(p) == 10.0L);
 *
 * The extended complex type travels on the x87 stack, st0 the real part and st1
 * the imaginary one, and the four arguments of __mulxc3 and __divxc3 are on the
 * stack. Every value here is written at the declaration that makes it, because
 * this compiler cannot assign to a long double _Complex object yet.
 */

#include <stdio.h>
#include <complex.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    long double _Complex z = 1.0L + 2.0Li;
    long double _Complex w = 3.0L + 4.0Li;
    long double _Complex p = z * w;
    long double _Complex q = z / w;
    CHECK(creall(p) == -5.0L);
    CHECK(cimagl(p) == 10.0L);
    CHECK(creall(q) > 0.439L && creall(q) < 0.441L);
    CHECK(cimagl(q) > 0.079L && cimagl(q) < 0.081L);
    return 0;
}
