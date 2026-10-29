/* 1126: a-complex-value-converted-to-another-complex-type-converts-both-parts
 *
 * ISO/IEC 9899:1999 6.3.1.6: when a value of complex type is converted to
 * another complex type, both the real and the imaginary parts are converted to
 * the corresponding real type and the result is the complex value those parts
 * make.  6.3.1.5 is the other direction: a real value converted to a complex
 * type has a positive zero imaginary part.  creal and cimag (7.3.9.3) read the
 * two parts, and sizeof (6.5.3.4) is the width of each type.
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
    double _Complex z = 1.0 + 2.0i;

    /* A real value becomes a complex one with a zero imaginary part, and the
       type it is written into decides the width of the components. */
    float _Complex from_float = 1.5f;
    double _Complex from_double = 2.5;
    long double _Complex from_long = 3.5L;
    CHECK(creal(from_float) == 1.5 && cimag(from_float) == 0.0);
    CHECK(creal(from_double) == 2.5 && cimag(from_double) == 0.0);
    CHECK(creal(from_long) == 3.5 && cimag(from_long) == 0.0);

    /* Between the two register widths, both components convert. */
    float _Complex narrow = z;
    CHECK(creal(narrow) == 1.0 && cimag(narrow) == 2.0);
    double _Complex wide = narrow;
    CHECK(creal(wide) == 1.0 && cimag(wide) == 2.0);

    /* The extended type is wider than both, in either direction. */
    long double _Complex extended = z;
    CHECK(creal(extended) == 1.0 && cimag(extended) == 2.0);
    double _Complex back = extended;
    CHECK(creal(back) == 1.0 && cimag(back) == 2.0);
    float _Complex down = extended;
    CHECK(creal(down) == 1.0 && cimag(down) == 2.0);

    /* The components keep their own widths, which is what sizeof says. */
    CHECK(sizeof z == 2 * sizeof(double));
    CHECK(sizeof narrow == 2 * sizeof(float));
    CHECK(sizeof extended == 2 * sizeof(long double));

    /* The parts are the values a conversion hands over, both of them. */
    CHECK(creal(z) == 1.0 && cimag(z) == 2.0);
    CHECK(creal(z * z) == -3.0 && cimag(z * z) == 4.0);

    return 0;
}
