/* 0016: math-trigonometric-and-hyperbolic-functions
 *
 * ISO/IEC 9899:1999 7.12.4: sin, cos, tan and their inverses, 7.12.5: the
 * hyperbolic functions. Each inverse is checked on the value that makes it
 * exact, and the identities are checked where a library may lag a unit in the
 * last place.
 */

#include <math.h>
#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int near(double got, double want, double slack)
{
    double diff = got - want;
    if (diff < 0) {
        diff = -diff;
    }
    return diff <= slack;
}

int main(void)
{
    const double pi = 3.14159265358979323846;
    volatile double half_turn = pi / 2.0;
    double s;
    double c;

    CHECK(sin(0.0) == 0.0);
    CHECK(cos(0.0) == 1.0);
    CHECK(tan(0.0) == 0.0);
    CHECK(near(sin(half_turn), 1.0, 1e-15));
    CHECK(near(cos(pi), -1.0, 1e-15));
    CHECK(near(sin(pi), 0.0, 1e-15));

    s = sin(0.7);
    c = cos(0.7);
    CHECK(near(s * s + c * c, 1.0, 1e-15));
    CHECK(near(tan(0.7), s / c, 1e-15));

    CHECK(near(asin(1.0), half_turn, 1e-15));
    CHECK(asin(0.0) == 0.0);
    CHECK(acos(1.0) == 0.0);
    CHECK(near(acos(0.0), half_turn, 1e-15));
    CHECK(near(atan(1.0), pi / 4.0, 1e-15));
    CHECK(near(atan2(1.0, 1.0), pi / 4.0, 1e-15));
    CHECK(atan2(0.0, 1.0) == 0.0);
    CHECK(near(atan2(1.0, 0.0), half_turn, 1e-15));
    CHECK(near(atan2(0.0, -1.0), pi, 1e-15));

    CHECK(sinh(0.0) == 0.0);
    CHECK(cosh(0.0) == 1.0);
    CHECK(tanh(0.0) == 0.0);
    CHECK(near(cosh(0.0) * cosh(0.0) - sinh(0.0) * sinh(0.0), 1.0, 1e-15));
    CHECK(asinh(0.0) == 0.0);
    CHECK(acosh(1.0) == 0.0);
    CHECK(atanh(0.0) == 0.0);
    CHECK(near(atanh(0.5), 0.5493061443340548, 1e-15));
    CHECK(near(asinh(1.0), 0.8813735870195430, 1e-15));

    /* 7.12p2: float and long double twins agree with the double function */
    CHECK(sinf(0.0f) == 0.0f);
    CHECK(cosf(0.0f) == 1.0f);
    CHECK(tanf(0.0f) == 0.0f);
    CHECK(near(sinf(0.7f), s, 1e-6));
    CHECK(near(cosf(0.7f), c, 1e-6));
    CHECK(near(tanf(0.7f), tan(0.7), 1e-6));
    CHECK(atanf(0.0f) == 0.0f);
    CHECK(near(atanf(1.0f), pi / 4.0, 1e-6));
    CHECK(near(asinl(1.0L), (double)half_turn, 1e-15));
    CHECK(near((double)acosl(0.0L), (double)half_turn, 1e-15));
    CHECK(near(atanl(1.0L), pi / 4.0, 1e-15));
    CHECK(near(atan2l(1.0L, 1.0L), pi / 4.0, 1e-15));

    CHECK(sinhf(0.0f) == 0.0f);
    CHECK(coshf(0.0f) == 1.0f);
    CHECK(tanhf(0.0f) == 0.0f);
    CHECK(asinhf(0.0f) == 0.0f);
    CHECK(acoshf(1.0f) == 0.0f);
    CHECK(atanhf(0.0f) == 0.0f);
    CHECK(sinhl(0.0L) == 0.0L);
    CHECK(coshl(0.0L) == 1.0L);
    CHECK(tanhl(0.0L) == 0.0L);
    CHECK(asinhf(1.0f) > 0.88f && asinhf(1.0f) < 0.89f);
    CHECK(atanhf(0.5f) > 0.549f && atanhf(0.5f) < 0.550f);

    CHECK(sinl(0.0L) == 0.0L);
    CHECK(cosl(0.0L) == 1.0L);
    CHECK(tanl(0.0L) == 0.0L);
    CHECK(near((double)sinl((long double)half_turn), 1.0, 1e-15));
    CHECK(near((double)sinh(1.0), 1.1752011936438014, 1e-15));
    CHECK(near((double)cosh(1.0), 1.5430806348152437, 1e-15));
    CHECK(near((double)tanh(1.0), 0.7615941559557649, 1e-15));
    CHECK(near((double)tan(1.0), 1.5574077246549023, 1e-15));
    CHECK(near((double)atan(2.0), 1.1071487177940904, 1e-15));
    return 0;
}
