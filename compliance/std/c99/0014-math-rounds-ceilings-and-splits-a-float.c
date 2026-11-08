/* 0014: math-rounds-ceilings-and-splits-a-float
 *
 * ISO/IEC 9899:1999 7.12.3: fabs, floor, ceil and trunc, 7.12.6: the rounding
 * functions, and 7.12.6.4 to 7.12.6.11: frexp, ldexp, modf, scalbn, ilogb and
 * logb take a value apart into parts whose product or sum is the value again.
 */

#include <float.h>
#include <math.h>
#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    double ipart = 0.0;
    long double ipartl = 0.0L;
    float ipartf = 0.0f;
    double fraction;
    int exponent = 0;
    int quotient = 0;

    CHECK(fabs(-3.5) == 3.5 && fabs(3.5) == 3.5 && fabs(-0.0) == 0.0);
    CHECK(fabsf(-3.5f) == 3.5f);
    CHECK(fabsl(-3.5L) == 3.5L);

    CHECK(floor(2.7) == 2.0 && floor(-2.1) == -3.0);
    CHECK(ceil(2.1) == 3.0 && ceil(-2.7) == -2.0);
    CHECK(trunc(2.7) == 2.0 && trunc(-2.7) == -2.0);
    CHECK(floor(3.0) == 3.0 && ceil(3.0) == 3.0 && trunc(3.0) == 3.0);
    CHECK(floorf(-2.1f) == -3.0f && ceilf(-2.7f) == -2.0f);
    CHECK(truncf(-2.7f) == -2.0f);

    /* 7.12.9.6: round takes halves away from zero, rint obeys the current
     * rounding mode, whose default sends a half to the even neighbour */
    CHECK(round(2.5) == 3.0 && round(-2.5) == -3.0);
    CHECK(round(2.4) == 2.0 && round(-2.4) == -2.0);
    CHECK(rint(2.5) == 2.0 && rint(3.5) == 4.0);
    CHECK(nearbyint(2.5) == 2.0 && nearbyint(-2.5) == -2.0);
    CHECK(roundf(2.5f) == 3.0f && nearbyintf(2.5f) == 2.0f);

    CHECK(lrint(2.5) == 2L && llrint(3.5) == 4LL);
    CHECK(lround(2.5) == 3L && lround(-2.5) == -3L);
    CHECK(llround(-2.5) == -3LL && llround(7.4) == 7LL);

    CHECK(fmod(7.5, 2.0) == 1.5);
    CHECK(fmod(-7.5, 2.0) == -1.5);
    CHECK(fmodf(7.5f, 2.0f) == 1.5f);
    CHECK(fmodl(7.5L, 2.0L) == 1.5L);

    /* 7.12.10.2: remainder is ieee-754's nearest-even quotient */
    CHECK(remainder(7.5, 2.0) == -0.5);
    CHECK(remainder(7.0, 2.0) == -1.0);
    CHECK(remquol(7.5L, 2.0L, &quotient) == -0.5L);
    CHECK(quotient == 4);
    quotient = 0;
    CHECK(remquo(7.0, 2.0, &quotient) == -1.0);
    CHECK(quotient == 4);

    CHECK(fma(2.0, 3.0, 4.0) == 10.0);
    CHECK(fmaf(2.0f, 3.0f, 4.0f) == 10.0f);
    CHECK(fmax(1.0, 2.0) == 2.0 && fmin(1.0, 2.0) == 1.0);
    CHECK(fmaxf(1.0f, 2.0f) == 2.0f && fminf(1.0f, 2.0f) == 1.0f);
    CHECK(fdim(5.0, 3.0) == 2.0 && fdim(3.0, 5.0) == 0.0);
    CHECK(fdimf(5.0f, 3.0f) == 2.0f);

    CHECK(copysign(3.0, -1.0) == -3.0 && copysign(-3.0, 1.0) == 3.0);
    CHECK(copysignf(3.0f, -1.0f) == -3.0f);

    CHECK(signbit(nextafter(-1.0, -2.0)));
    CHECK(nextafter(1.0, 2.0) == 1.0 + DBL_EPSILON);
    CHECK(nextafterf(1.0f, 2.0f) == 1.0f + FLT_EPSILON);
    CHECK(nexttowardl(1.0L, 2.0L) == 1.0L + LDBL_EPSILON);

    /* 7.12.6.4: value == mantissa * 2^exponent with 0.5 <= |mantissa| < 1 */
    CHECK(frexp(8.0, &exponent) == 0.5);
    CHECK(exponent == 4);
    exponent = 0;
    CHECK(frexpl(8.0L, &exponent) == 0.5L);
    CHECK(exponent == 4);
    exponent = 0;
    CHECK(frexpf(8.0f, &exponent) == 0.5f);
    CHECK(exponent == 4);
    CHECK(ldexp(0.5, 4) == 8.0);
    CHECK(ldexpf(0.5f, 4) == 8.0f);

    /* 7.12.6.6: modf splits into signed fraction and integral part */
    fraction = modf(-3.75, &ipart);
    CHECK(fraction == -0.75);
    CHECK(ipart == -3.0);
    fraction = (double)modfl(2.5L, &ipartl);
    CHECK(fraction == 0.5 && ipartl == 2.0L);
    fraction = (double)modff(-1.25f, &ipartf);
    CHECK(fraction == -0.25 && ipartf == -1.0f);

    CHECK(scalbn(1.0, 10) == 1024.0);
    CHECK(scalbn(1024.0, -10) == 1.0);
    CHECK(scalbln(1.0, 10) == 1024.0);
    CHECK(scalbnf(1.0f, 10) == 1024.0f);

    CHECK(ilogb(8.0) == 3);
    CHECK(ilogb(0.5) == -1);
    CHECK(logb(8.0) == 3.0);
    CHECK(logbf(8.0f) == 3.0f);
    CHECK(ilogbf(8.0f) == 3);
    return 0;
}
