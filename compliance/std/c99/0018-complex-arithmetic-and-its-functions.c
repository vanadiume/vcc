/* 0018: complex-arithmetic-and-its-functions
 *
 * ISO/IEC 9899:1999 7.3: the complex type and the functions in <complex.h>.
 * The parts are read with creal and cimag, the four operators work on the type
 * itself, and each function has a float and a long double twin.
 */

#include <complex.h>
#include <math.h>
#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int near_parts(double complex got, double re, double im, double slack)
{
    double dr = creal(got) - re;
    double di = cimag(got) - im;
    if (dr < 0) {
        dr = -dr;
    }
    if (di < 0) {
        di = -di;
    }
    return dr <= slack && di <= slack;
}

static int near_float_parts(float complex got, float re, float im, float slack)
{
    float dr = crealf(got) - re;
    float di = cimagf(got) - im;
    if (dr < 0) {
        dr = -dr;
    }
    if (di < 0) {
        di = -di;
    }
    return dr <= slack && di <= slack;
}

int main(void)
{
    double complex z = 3.0 + 4.0 * I;
    double complex w = 1.0 - 2.0 * I;
    double complex sum;
    double complex diff;
    double complex product;
    double complex quotient;
    float complex fz = 1.0f + 2.0f * I;
    long double complex lz = 1.0L + 2.0L * I;

    CHECK(creal(z) == 3.0);
    CHECK(cimag(z) == 4.0);
    CHECK(cabs(z) == 5.0);
    CHECK(conj(z) == 3.0 - 4.0 * I);
    CHECK(carg(1.0 + 0.0 * I) == 0.0);
    CHECK(cproj(z) == z);

    CHECK(crealf(fz) == 1.0f && cimagf(fz) == 2.0f);
    CHECK(creall(lz) == 1.0L && cimagl(lz) == 2.0L);
    CHECK(cabsf(3.0f + 4.0f * I) == 5.0f);
    CHECK(cabsl(3.0L + 4.0L * I) == 5.0L);
    CHECK(conjf(fz) == 1.0f - 2.0f * I);
    CHECK(conjl(lz) == 1.0L - 2.0L * I);
    CHECK(cargf(fz) > 1.10f && cargf(fz) < 1.11f);
    CHECK(cprojf(fz) == fz);

    /* 6.2.5p11: the operators are the arithmetic of the type */
    sum = z + w;
    CHECK(creal(sum) == 4.0 && cimag(sum) == 2.0);
    diff = z - w;
    CHECK(creal(diff) == 2.0 && cimag(diff) == 6.0);
    product = z * w;
    CHECK(creal(product) == 11.0 && cimag(product) == -2.0);
    quotient = z / w;
    CHECK(near_parts(quotient, -1.0, 2.0, 1e-15));
    CHECK(creal(-z) == -3.0 && cimag(-z) == -4.0);

    /* 7.3.8: the exponential, logarithm and square root */
    CHECK(near_parts(cexp(0.0 + 0.0 * I), 1.0, 0.0, 1e-15));
    CHECK(near_parts(clog(1.0 + 0.0 * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(csqrt(-1.0 + 0.0 * I), 0.0, 1.0, 1e-15));
    CHECK(near_parts(csqrt(4.0 + 0.0 * I), 2.0, 0.0, 1e-15));
    CHECK(near_parts(cpow(2.0 + 0.0 * I, 10.0 + 0.0 * I), 1024.0, 0.0, 1e-12));
    CHECK(near_float_parts(cexpf(0.0f + 0.0f * I), 1.0f, 0.0f, 1e-6f));
    CHECK(near_float_parts(cpowf(2.0f + 0.0f * I, 10.0f + 0.0f * I), 1024.0f,
                           0.0f, 1e-3f));
    CHECK(near_parts(cexpl(0.0L + 0.0L * I), 1.0, 0.0, 1e-15));
    CHECK(near_parts(csqrtl(4.0L + 0.0L * I), 2.0, 0.0, 1e-15));

    /* 7.3.5 and 7.3.6: the trigonometric functions at zero */
    CHECK(near_parts(csin(0.0 + 0.0 * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(ccos(0.0 + 0.0 * I), 1.0, 0.0, 1e-15));
    CHECK(near_parts(ctan(0.0 + 0.0 * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(casin(0.0 + 0.0 * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(cacos(1.0 + 0.0 * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(catan(0.0 + 0.0 * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(csinh(0.0 + 0.0 * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(ccosh(0.0 + 0.0 * I), 1.0, 0.0, 1e-15));
    CHECK(near_parts(ctanh(0.0 + 0.0 * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(casinh(0.0 + 0.0 * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(cacosh(1.0 + 0.0 * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(catanh(0.0 + 0.0 * I), 0.0, 0.0, 1e-15));

    CHECK(near_float_parts(csinf(0.0f + 0.0f * I), 0.0f, 0.0f, 1e-6f));
    CHECK(near_float_parts(ccosf(0.0f + 0.0f * I), 1.0f, 0.0f, 1e-6f));
    CHECK(near_float_parts(ctanf(0.0f + 0.0f * I), 0.0f, 0.0f, 1e-6f));
    CHECK(near_float_parts(casinf(0.0f + 0.0f * I), 0.0f, 0.0f, 1e-6f));
    CHECK(near_float_parts(cacosf(1.0f + 0.0f * I), 0.0f, 0.0f, 1e-6f));
    CHECK(near_float_parts(catanf(0.0f + 0.0f * I), 0.0f, 0.0f, 1e-6f));
    CHECK(near_float_parts(csinhf(0.0f + 0.0f * I), 0.0f, 0.0f, 1e-6f));
    CHECK(near_float_parts(ccoshf(0.0f + 0.0f * I), 1.0f, 0.0f, 1e-6f));
    CHECK(near_float_parts(ctanhf(0.0f + 0.0f * I), 0.0f, 0.0f, 1e-6f));
    CHECK(near_float_parts(casinhf(0.0f + 0.0f * I), 0.0f, 0.0f, 1e-6f));
    CHECK(near_float_parts(cacoshf(1.0f + 0.0f * I), 0.0f, 0.0f, 1e-6f));
    CHECK(near_float_parts(catanhf(0.0f + 0.0f * I), 0.0f, 0.0f, 1e-6f));

    CHECK(near_parts(csinl(0.0L + 0.0L * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(ccosl(0.0L + 0.0L * I), 1.0, 0.0, 1e-15));
    CHECK(near_parts(ctanl(0.0L + 0.0L * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(casinl(0.0L + 0.0L * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(cacosl(1.0L + 0.0L * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(catanl(0.0L + 0.0L * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(csinhl(0.0L + 0.0L * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(ccoshl(0.0L + 0.0L * I), 1.0, 0.0, 1e-15));
    CHECK(near_parts(ctanhl(0.0L + 0.0L * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(casinhl(0.0L + 0.0L * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(cacoshl(1.0L + 0.0L * I), 0.0, 0.0, 1e-15));
    CHECK(near_parts(catanhl(0.0L + 0.0L * I), 0.0, 0.0, 1e-15));

    /* 7.3.5.1: the angle of a value in the second quadrant */
    CHECK(carg(-1.0 + 0.0 * I) > 3.14 && carg(-1.0 + 0.0 * I) < 3.15);
    return 0;
}
