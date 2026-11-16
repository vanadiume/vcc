/* 1151: CHECK(creal(product) == 11.0 && cimag(product) == -2.0);
 *
 * A product of two complex doubles is a call to __muldc3: the compiler emits
 * the call and this tree provides no definition of it, so the program runs only
 * while the runtime archive answers the name. (3 + 4i)(1 - 2i) is 11 - 2i.
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
    double _Complex z = 3.0 + 4.0 * I;
    double _Complex w = 1.0 - 2.0 * I;
    double _Complex product = z * w;
    double _Complex sum = z + w;
    CHECK(creal(product) == 11.0);
    CHECK(cimag(product) == -2.0);
    /* the sum is inline arithmetic and stays right beside the call */
    CHECK(creal(sum) == 4.0);
    CHECK(cimag(sum) == 2.0);
    return 0;
}
