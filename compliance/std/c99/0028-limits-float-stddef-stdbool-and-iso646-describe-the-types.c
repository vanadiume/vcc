/* 0028: limits-float-stddef-stdbool-and-iso646-describe-the-types
 *
 * ISO/IEC 9899:1999 7.10: the limits of the integer types, 7.7: the
 * characteristics of the floating types, 7.17: the common definitions, 7.16:
 * the boolean type, and 7.9: the alternative spellings for the operators.
 */

#include <float.h>
#include <iso646.h>
#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

struct pair {
    char first;
    int second;
};

int main(void)
{
    size_t biggest = (size_t)-1;
    ptrdiff_t difference = -1;
    bool yes = true;
    bool no = false;

    /* 7.10: the limits of the integer types */
    CHECK(CHAR_BIT == 8);
    CHECK(SCHAR_MIN == -128 && SCHAR_MAX == 127);
    CHECK(UCHAR_MAX == 255);
    CHECK(SHRT_MIN == -32768 && SHRT_MAX == 32767);
    CHECK(USHRT_MAX == 65535);
    CHECK(INT_MIN == -2147483647 - 1 && INT_MAX == 2147483647);
    CHECK(UINT_MAX == 4294967295u);
    CHECK(LONG_MAX >= 2147483647L);
    CHECK(LONG_MIN <= -2147483647L);
    CHECK(ULONG_MAX >= 4294967295ul);
    CHECK(LLONG_MAX == 9223372036854775807LL);
    CHECK(LLONG_MIN == -9223372036854775807LL - 1);
    CHECK(ULLONG_MAX == 18446744073709551615ULL);
    CHECK(MB_LEN_MAX >= 1);

    /* 7.17: the common definitions */
    CHECK(sizeof(size_t) == sizeof(void *));
    CHECK(biggest > 0);
    CHECK(difference < 0);
    CHECK(NULL == (void *)0);
    CHECK(offsetof(struct pair, first) == 0);
    CHECK(offsetof(struct pair, second) >= 1);
    CHECK(offsetof(struct pair, second) < sizeof(struct pair));

    /* 7.7: the floating characteristics, none of which may be a guess */
    CHECK(FLT_RADIX == 2);
    CHECK(FLT_MANT_DIG == 24);
    CHECK(DBL_MANT_DIG == 53);
    CHECK(LDBL_MANT_DIG >= 53);
    CHECK(FLT_DIG == 6);
    CHECK(DBL_DIG == 15);
    CHECK(LDBL_DIG >= 15);
    CHECK(FLT_MAX > 1e37 && DBL_MAX > 1e307);
    CHECK(FLT_MIN < 1e-37 && DBL_MIN < 1e-307);
    CHECK(FLT_EPSILON > 0 && DBL_EPSILON > 0 && LDBL_EPSILON > 0);
    CHECK(DBL_EPSILON < FLT_EPSILON);
    CHECK(FLT_MAX_EXP == FLT_MANT_DIG + FLT_MAX_EXP - FLT_MANT_DIG);
    CHECK(DBL_MIN_EXP < DBL_MAX_EXP);
    CHECK(FLT_MIN_10_EXP < FLT_MAX_10_EXP);

    /* 7.16: the boolean type, and the macro that says it is there */
    CHECK(__bool_true_false_are_defined == 1);
    CHECK(sizeof(bool) == 1);
    CHECK(yes && !no);
    CHECK((yes == 1) && (no == 0));

    /* 7.9: the alternative spellings */
    CHECK((1 and 1) == 1);
    CHECK((0 and 1) == 0);
    CHECK((1 or 0) == 1);
    CHECK((0 or 0) == 0);
    CHECK((not 0) == 1);
    CHECK((not 1) == 0);
    CHECK((1 bitand 3) == 1);
    CHECK((1 bitor 2) == 3);
    CHECK((3 xor 1) == 2);
    CHECK((compl 1u) == 4294967294u);
    CHECK((1 not_eq 2) == 1);
    CHECK((2 not_eq 2) == 0);
    return 0;
}
