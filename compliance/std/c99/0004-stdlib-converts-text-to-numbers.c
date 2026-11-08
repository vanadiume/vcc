/* 0004: stdlib-converts-text-to-numbers
 *
 * ISO/IEC 9899:1999 7.20.1: the ato* and strto* functions read a number from
 * the earliest characters of a string, and strto* reports where it stopped and
 * whether the value overflowed the type it returns.
 */

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    char *end = NULL;
    const char *none;
    div_t d;
    ldiv_t ld;
    lldiv_t lld;

    /* 7.20.1.2: the ato* functions are the strto* ones without the report */
    CHECK(atoi("42") == 42);
    CHECK(atoi("  -7") == -7);
    CHECK(atoi("0") == 0);
    CHECK(atol("-2147483648") == -2147483648L);
    CHECK(atoll("9223372036854775807") == 9223372036854775807LL);
    CHECK(atof("2.5") == 2.5);
    CHECK(atof("-1e3") == -1000.0);

    CHECK(strtol("123", &end, 10) == 123L);
    CHECK(end != NULL && *end == '\0');
    CHECK(strtol("12abc", &end, 10) == 12L);
    CHECK(end != NULL && strcmp(end, "abc") == 0);
    CHECK(strtol("  7", &end, 10) == 7L);
    CHECK(strtol("+7", &end, 10) == 7L);
    CHECK(strtol("-31", &end, 10) == -31L);

    /* 7.20.1.4: base 0 reads the prefix, base 16 asks for it */
    CHECK(strtol("0x1f", &end, 0) == 31L);
    CHECK(strtol("010", &end, 0) == 8L);
    CHECK(strtol("0x1f", &end, 16) == 31L);
    CHECK(strtol("z", &end, 36) == 35L);
    CHECK(strtol("Z", &end, 36) == 35L);

    none = "abc";
    end = NULL;
    CHECK(strtol(none, &end, 10) == 0L);
    CHECK(end == none);

    errno = 0;
    CHECK(strtol("99999999999999999999999999", &end, 10) == LONG_MAX);
    CHECK(errno == ERANGE);
    errno = 0;
    CHECK(strtol("-99999999999999999999999999", &end, 10) == LONG_MIN);
    CHECK(errno == ERANGE);

    CHECK(strtoul("4294967295", &end, 10) == 4294967295UL);
    CHECK(strtoull("18446744073709551615", &end, 10) == 18446744073709551615ULL);
    errno = 0;
    CHECK(strtoull("18446744073709551616", &end, 10) == ULLONG_MAX);
    CHECK(errno == ERANGE);

    CHECK(strtod("3.5", &end) == 3.5);
    CHECK(strtod("-0.25e2", &end) == -25.0);
    CHECK(strtod("1e3", &end) == 1000.0);
    CHECK(strtod("0x1p3", &end) == 8.0);
    CHECK(strtof("1.5", &end) == 1.5f);
    CHECK(strtold("2.5", &end) == 2.5L);

    CHECK(isinf(strtod("inf", &end)));
    CHECK(isnan(strtod("nan", &end)));
    errno = 0;
    CHECK(isinf(strtod("1e999", &end)));
    CHECK(strtod("1e999", &end) == HUGE_VAL);
    CHECK(errno == ERANGE);

    /* 7.20.6.2: division truncates toward zero and the remainder keeps the
     * sign of the dividend, so quot * divisor + rem is the dividend again */
    d = div(7, 2);
    CHECK(d.quot == 3 && d.rem == 1);
    d = div(-7, 2);
    CHECK(d.quot == -3 && d.rem == -1);
    CHECK(d.quot * 2 + d.rem == -7);

    ld = ldiv(-7L, 2L);
    CHECK(ld.quot == -3L && ld.rem == -1L);
    CHECK(ld.quot * 2L + ld.rem == -7L);

    lld = lldiv(-7LL, 2LL);
    CHECK(lld.quot == -3LL && lld.rem == -1LL);

    CHECK(abs(-5) == 5);
    CHECK(abs(5) == 5);
    CHECK(labs(-5L) == 5L);
    CHECK(llabs(-5LL) == 5LL);
    return 0;
}
