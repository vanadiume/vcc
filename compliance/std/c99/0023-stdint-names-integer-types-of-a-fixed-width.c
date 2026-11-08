/* 0023: stdint-names-integer-types-of-a-fixed-width
 *
 * ISO/IEC 9899:1999 7.18.1 and 7.18.2: the exact-width types, their limits,
 * and the macros that spell a constant of one of those types. 7.18.3: the
 * types wide enough to hold a converted pointer and the widest integer type.
 */

#include <limits.h>
#include <stdint.h>
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
    int object = 0;
    intptr_t as_integer;
    uintptr_t as_unsigned;
    intmax_t widest;
    uintmax_t widest_unsigned;

    CHECK(INT8_MAX == 127);
    CHECK(INT8_MIN == -128);
    CHECK(UINT8_MAX == 255);

    CHECK(INT16_MAX == 32767);
    CHECK(INT16_MIN == -32768);
    CHECK(UINT16_MAX == 65535);

    CHECK(INT32_MAX == 2147483647);
    CHECK(INT32_MIN == -2147483647 - 1);
    CHECK(UINT32_MAX == 4294967295u);

    CHECK(INT64_MAX == 9223372036854775807LL);
    CHECK(INT64_MIN == -9223372036854775807LL - 1);
    CHECK(UINT64_MAX == 18446744073709551615ULL);

    CHECK(sizeof(int8_t) == 1 && sizeof(uint8_t) == 1);
    CHECK(sizeof(int16_t) == 2 && sizeof(uint16_t) == 2);
    CHECK(sizeof(int32_t) == 4 && sizeof(uint32_t) == 4);
    CHECK(sizeof(int64_t) == 8 && sizeof(uint64_t) == 8);

    CHECK(sizeof(int_least8_t) <= sizeof(int8_t));
    CHECK(sizeof(int_fast8_t) >= sizeof(int8_t));
    CHECK(INT_LEAST32_MAX >= INT32_MAX);
    CHECK(INT_FAST32_MAX >= INT32_MAX);

    /* 7.18.4.1: the constant macros carry the type the suffix names */
    CHECK(INT8_C(7) == 7);
    CHECK(UINT8_C(7) == 7);
    CHECK(INT16_C(7) == 7);
    CHECK(UINT16_C(7) == 7);
    CHECK(INT32_C(7) == 7);
    CHECK(UINT32_C(7) == 7);
    CHECK(INT64_C(7) == 7);
    CHECK(UINT64_C(7) == 7);
    CHECK(INTMAX_C(7) == 7);
    CHECK(UINTMAX_C(7) == 7);
    CHECK(sizeof(UINT64_C(7)) == 8);
    CHECK(sizeof(UINT32_C(7)) >= 4);

    /* 7.18.3: the pointer-holding types round trip an address */
    as_integer = (intptr_t)&object;
    CHECK((int *)as_integer == &object);
    as_unsigned = (uintptr_t)&object;
    CHECK((int *)as_unsigned == &object);
    CHECK(sizeof(intptr_t) == sizeof(void *));
    CHECK(sizeof(uintptr_t) == sizeof(void *));

    widest = 1;
    CHECK(widest << 40 != 0); /* intmax_t is wider than 32 bits here */
    widest_unsigned = (uintmax_t)widest << 40;
    CHECK(widest_unsigned != 0);
    CHECK(INTMAX_MAX >= INT64_MAX);
    CHECK(UINTMAX_MAX >= UINT64_MAX);

    /* 7.18.2.5: a signed type's minimum is its maximum plus one, negated */
    CHECK(INT8_MIN + INT8_MAX == -1);
    CHECK(INT64_MIN + INT64_MAX == -1);
    return 0;
}
