/* 0017: math-classifies-and-compares-floating-values
 *
 * ISO/IEC 9899:1999 7.12.3 and 7.12.3.2: the classification macros name the
 * kind of a value and the comparison macros answer quietly where an operator
 * would raise an invalid operation; 7.12.1: a range error returns HUGE_VAL and
 * sets errno to ERANGE.
 */

#include <errno.h>
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
    volatile double one = 1.0;
    volatile double zero = 0.0;
    volatile double huge = 1e308;
    volatile double tiny = DBL_MIN / 4.0;
    double infinity = HUGE_VAL;
    double not_a_number = NAN;
    double big_result;

    CHECK(isfinite(one));
    CHECK(!isfinite(infinity));
    CHECK(!isfinite(not_a_number));

    CHECK(isinf(infinity));
    CHECK(isinf(-infinity));
    CHECK(!isinf(one));

    CHECK(isnan(not_a_number));
    CHECK(!isnan(one));
    CHECK(not_a_number != not_a_number);

    CHECK(isnormal(one));
    CHECK(!isnormal(zero));
    CHECK(!isnormal(infinity));
    CHECK(!isnormal(not_a_number));
    CHECK(!isnormal(tiny));

    CHECK(signbit(-one));
    CHECK(!signbit(one));
    CHECK(signbit(-zero));

    CHECK(fpclassify(0.0) == FP_ZERO);
    CHECK(fpclassify(one) == FP_NORMAL);
    CHECK(fpclassify(infinity) == FP_INFINITE);
    CHECK(fpclassify(not_a_number) == FP_NAN);
    CHECK(fpclassify(tiny) == FP_SUBNORMAL);

    /* 7.12.14: the comparison macros answer false, not a trap, on a NaN */
    CHECK(isgreater(2.0, 1.0));
    CHECK(!isgreater(1.0, 1.0));
    CHECK(!isgreater(1.0, 2.0));
    CHECK(isgreaterequal(1.0, 1.0));
    CHECK(isless(1.0, 2.0));
    CHECK(!isless(2.0, 1.0));
    CHECK(islessequal(1.0, 1.0));
    CHECK(islessgreater(1.0, 2.0));
    CHECK(!islessgreater(1.0, 1.0));
    CHECK(isunordered(not_a_number, 1.0));
    CHECK(!isunordered(1.0, 2.0));
    CHECK(!isgreater(not_a_number, 1.0));
    CHECK(!isless(not_a_number, 1.0));

    CHECK(HUGE_VAL > DBL_MAX);
    CHECK(HUGE_VALF > FLT_MAX);
    CHECK(HUGE_VALL > LDBL_MAX);
    CHECK(isinf(INFINITY));

    /* 7.12.1p5: an overflow returns HUGE_VAL with the sign of the result and
     * sets ERANGE. The operand is volatile so the call reaches the library
     * instead of being folded away. */
    errno = 0;
    big_result = exp(huge);
    CHECK(isinf(big_result) && big_result > 0.0);
    CHECK(errno == ERANGE);

    errno = 0;
    big_result = exp(-huge);
    CHECK(big_result == 0.0);
    CHECK(errno == ERANGE);

    errno = 0;
    big_result = log(zero);
    CHECK(!isfinite(big_result));
    (void)big_result;

    /* 7.12.1p3 and annex F: a domain error yields a NaN on this platform */
    CHECK(isnan(sqrt(-one)));
    CHECK(isnan(log(-one)));
    return 0;
}
