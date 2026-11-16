/* 1154: CHECK(crealf(q) == 0.439999998f && cimagf(q) == 0.0799999982f);
 *
 * gcc's __divsc3 promotes both operands to double, divides there and rounds
 * each component back to a float, which is what the runtime helper does. The
 * constants are what gcc 16.2.1 prints with %.17g for the same expression at
 * -O0 -fno-builtin.
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
    float _Complex p = (1.0f + 2.0f * I) * (3.0f + 4.0f * I);
    CHECK(crealf(p) == -5.0f);
    CHECK(cimagf(p) == 10.0f);
    float _Complex q = (1.0f + 2.0f * I) / (3.0f + 4.0f * I);
    CHECK(crealf(q) == 0.439999998f);
    CHECK(cimagf(q) == 0.0799999982f);
    return 0;
}
