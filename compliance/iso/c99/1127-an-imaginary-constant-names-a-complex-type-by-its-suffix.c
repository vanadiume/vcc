/* 1127: an-imaginary-constant-names-a-complex-type-by-its-suffix
 *
 * ISO/IEC 9899:1999 6.4.4.2: a floating constant followed by `i` or `j` is an
 * imaginary constant, whose value is the imaginary part it names and whose real
 * part is a positive zero.  The suffix before the marker names the type the way
 * it does for a real constant: an `f` is a `float _Complex`, an `l` a
 * `long double _Complex`, and neither a `double _Complex`.  The marker may be
 * written on either side of the floating suffix.
 */

#include <complex.h>
#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    float _Complex f = 1.5if;
    float _Complex f_after = 1.5Fi;
    double _Complex d = 2.5i;
    long double _Complex l = 3.5iL;
    long double _Complex l_after = 3.5Li;

    CHECK(sizeof f == 2 * sizeof(float));
    CHECK(sizeof d == 2 * sizeof(double));
    CHECK(sizeof l == 2 * sizeof(long double));

    /* The coefficient is the imaginary part and the real part is zero. */
    CHECK(creal(f) == 0.0 && cimag(f) == 1.5);
    CHECK(creal(f_after) == 0.0 && cimag(f_after) == 1.5);
    CHECK(creal(d) == 0.0 && cimag(d) == 2.5);
    CHECK(creal(l) == 0.0 && cimag(l) == 3.5);
    CHECK(creal(l_after) == 0.0 && cimag(l_after) == 3.5);

    /* An imaginary constant is a value like any other: added to a real one it
       makes the complex number the two name. */
    double _Complex sum = 1.0 + 2.0i;
    CHECK(creal(sum) == 1.0 && cimag(sum) == 2.0);

    return 0;
}
