/* 1125: a-complex-value-converted-to-a-real-type-drops-the-imaginary-part
 *
 * ISO/IEC 9899:1999 6.3.1.7: when a value of complex type is converted to a
 * real type, the imaginary part is discarded and the real part is converted to
 * the corresponding real type.  6.5.16.1 makes that conversion the one an
 * assignment, an initialization, an argument and a return each make, and
 * 6.3.1.2 makes a _Bool hold 0 or 1 according to whether the whole value is
 * unequal to zero, which for a complex value is either part.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static double as_double(double _Complex z) { return z; }
static int as_int(double _Complex z) { return z; }
static float as_float(double _Complex z) { return z; }
static char as_char(double _Complex z) { return z; }
static _Bool as_bool(double _Complex z) { return z; }

int main(void)
{
    double _Complex z = 3.0 + 4.0i;
    double _Complex imaginary_only = 0.0 + 2.0i;

    double d = z;
    int n = z;
    float f = z;
    char c = z;
    unsigned u = z;
    _Bool nonzero = imaginary_only;
    _Bool zero = 0.0 + 0.0i;

    CHECK(d == 3.0);
    CHECK(n == 3);
    CHECK(f == 3.0f);
    CHECK(c == 3);
    CHECK(u == 3);
    CHECK(nonzero == 1);
    CHECK(zero == 0);

    CHECK(as_double(z) == 3.0);
    CHECK(as_int(z) == 3);
    CHECK(as_float(z) == 3.0f);
    CHECK(as_char(z) == 3);
    CHECK(as_bool(imaginary_only) == 1);

    CHECK((double)z == 3.0);
    CHECK((int)z == 3);
    CHECK((float)z == 3.0f);
    CHECK((char)z == 3);
    CHECK((unsigned)z == 3u);

    /* The real part is converted; the imaginary part is not read, so a
       complex value whose real part is negative converts as that value. */
    double _Complex negative = -2.5 - 7.0i;
    CHECK((int)negative == -2);
    CHECK((double)negative == -2.5);

    /* A compound assignment converts the sum it stands for, so `n += z`
       writes the real part of `n + z` (measured on gcc 16.2.1: 4 here). */
    int total = 1;
    total += z;
    CHECK(total == 4);

    return 0;
}
