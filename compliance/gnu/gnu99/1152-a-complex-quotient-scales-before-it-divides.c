/* 1152: CHECK(creal(z / z) == 1.0 && cimag(z / z) == 0.0);
 *
 * The naive formula c*c + d*d overflows for a divisor of 1e308, so gcc's
 * __divdc3 scales the operands before it divides and this compiler calls the
 * same helper. Every constant here is what gcc 16.2.1 prints with %.17g for the
 * same expression, measured at -O0 -fno-builtin.
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
    double _Complex big = 1e308 + 1e308 * I;
    double _Complex one = big / big;
    CHECK(creal(one) == 1.0);
    CHECK(cimag(one) == 0.0);

    double _Complex tiny = 1e-308 + 1e-308 * I;
    double _Complex small = tiny / (3.0 + 0.0 * I);
    CHECK(creal(small) == 3.3333333333333314e-309);
    CHECK(cimag(small) == 3.3333333333333314e-309);

    double _Complex q = (1.0 + 2.0 * I) / (3.0 + 4.0 * I);
    CHECK(creal(q) == 0.44);
    CHECK(cimag(q) == 0.080000000000000002);
    return 0;
}
