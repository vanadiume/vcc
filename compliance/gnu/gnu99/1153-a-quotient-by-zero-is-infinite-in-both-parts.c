/* 1153: CHECK(creal(q) > 1e308 && cimag(q) > 1e308);
 *
 * Dividing by 0 + 0i is the case the runtime's helper recovers and a formula
 * written inline does not: measured on gcc 16.2.1, (1e308 + 1e308i) / (0 + 0i)
 * prints `inf inf`, where the inline formula this compiler used to emit printed
 * `-nan -nan`.
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
    double _Complex z = 1e308 + 1e308 * I;
    double _Complex q = z / (0.0 + 0.0 * I);
    CHECK(creal(q) > 1e308);
    CHECK(cimag(q) > 1e308);
    return 0;
}
