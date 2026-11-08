/* 0015: math-exponentials-logarithms-and-powers
 *
 * ISO/IEC 9899:1999 7.12.4: exp, exp2, expm1 and the logarithms, 7.12.7.4:
 * pow, and 7.12.7.2: sqrt and cbrt. Each answer is checked against an exact
 * value or against the bound the function promises.
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
    CHECK(exp(0.0) == 1.0);
    CHECK(near(exp(1.0), 2.718281828459045, 1e-12));
    CHECK(near(exp(2.0), 7.389056098930650, 1e-12));

    CHECK(exp2(10.0) == 1024.0);
    CHECK(exp2(0.0) == 1.0);
    CHECK(exp2(-1.0) == 0.5);
    CHECK(expm1(0.0) == 0.0);

    CHECK(log(1.0) == 0.0);
    CHECK(near(log(exp(2.0)), 2.0, 1e-12));
    CHECK(log10(1000.0) == 3.0);
    CHECK(log10(1.0) == 0.0);
    CHECK(log2(8.0) == 3.0);
    CHECK(log2(0.5) == -1.0);
    CHECK(log1p(0.0) == 0.0);

    CHECK(pow(2.0, 10.0) == 1024.0);
    CHECK(pow(2.0, 0.0) == 1.0);
    CHECK(pow(0.0, 0.0) == 1.0);
    CHECK(pow(9.0, 0.5) == 3.0);
    CHECK(pow(2.0, -1.0) == 0.5);
    CHECK(near(pow(2.0, 0.5), 1.414213562373095, 1e-12));

    CHECK(sqrt(16.0) == 4.0);
    CHECK(sqrt(0.0) == 0.0);
    CHECK(sqrt(0.25) == 0.5);
    /* glibc 2.44's cbrt is a unit or two off on a cube, so the check is a
     * tolerance rather than an equality: 27.0 comes back as 3.0000000000000004 */
    CHECK(near(cbrt(27.0), 3.0, 1e-15));
    CHECK(near(cbrt(-27.0), -3.0, 1e-15));
    CHECK(hypot(3.0, 4.0) == 5.0);
    CHECK(hypot(0.0, 0.0) == 0.0);

    CHECK(near(erf(0.0), 0.0, 1e-15));
    CHECK(near(erfc(0.0), 1.0, 1e-15));
    CHECK(tgamma(5.0) == 24.0);
    CHECK(tgamma(1.0) == 1.0);
    CHECK(near(lgamma(1.0), 0.0, 1e-15));
    CHECK(near(lgamma(5.0), log(24.0), 1e-12));

    /* 7.12p2: each function has a float and a long double twin */
    CHECK(expf(0.0f) == 1.0f);
    CHECK(near(expf(1.0f), 2.718281828f, 1e-5));
    CHECK(exp2f(10.0f) == 1024.0f);
    CHECK(expm1f(0.0f) == 0.0f);
    CHECK(logf(1.0f) == 0.0f);
    CHECK(log10f(1000.0f) == 3.0f);
    CHECK(log2f(8.0f) == 3.0f);
    CHECK(log1pf(0.0f) == 0.0f);
    CHECK(powf(2.0f, 10.0f) == 1024.0f);
    CHECK(sqrtf(16.0f) == 4.0f);
    CHECK(near(cbrtf(27.0f), 3.0f, 1e-6f));
    CHECK(hypotf(3.0f, 4.0f) == 5.0f);
    CHECK(erff(0.0f) == 0.0f);
    CHECK(erfcf(0.0f) == 1.0f);
    CHECK(tgammaf(5.0f) == 24.0f);
    CHECK(lgammaf(1.0f) == 0.0f);

    CHECK(expl(0.0L) == 1.0L);
    CHECK(exp2l(10.0L) == 1024.0L);
    CHECK(logl(1.0L) == 0.0L);
    CHECK(near((double)log10l(1000.0L), 3.0, 1e-15));
    CHECK(log2l(8.0L) == 3.0L);
    CHECK(log1pl(0.0L) == 0.0L);
    CHECK(expm1l(0.0L) == 0.0L);
    CHECK(powl(2.0L, 10.0L) == 1024.0L);
    CHECK(sqrtl(16.0L) == 4.0L);
    CHECK(near((double)cbrtl(27.0L), 3.0, 1e-15));
    CHECK(hypotl(3.0L, 4.0L) == 5.0L);
    CHECK(erfl(0.0L) == 0.0L);
    CHECK(erfcl(0.0L) == 1.0L);
    CHECK(tgammal(5.0L) == 24.0L);
    CHECK(lgammal(1.0L) == 0.0L);
    return 0;
}
