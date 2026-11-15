/* 0087: an unsigned literal in an #if is uintmax_t, not intmax_t

`#if 0xffffffffffffffffULL > 0` took the false branch and
`0xffffffffffffffffULL == -1` was true.  The bits were right and the
signedness was gone, because the #if reader held every operand in an i64, so a
header asking `#if UINT64_MAX > 0` took the branch written for a signed value.
C99 6.4.4.1 gives a hexadecimal literal with the high bit set and a `U` suffix
the unsigned type, and 6.10.1p4 evaluates the controlling expression in
intmax_t and uintmax_t, so the comparison is the unsigned one.  Fixed in
49316f7 ("preprocess: evaluate an #if in intmax_t and uintmax_t").
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int taken;

int main(void)
{
    /* A hexadecimal literal that needs the high bit and wears a `u` suffix is
     * uintmax_t, so it is greater than zero. */
#if 0xffffffffffffffffULL > 0
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 1);

#if 0x8000000000000000ULL > 0
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 1);

    /* So is a decimal one with the suffix, and a hexadecimal one without it
     * that does not fit intmax_t. */
#if 18446744073709551615ULL > 0
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 1);

#if 0xffffffffffffffff > 0
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 1);

    /* The same value converted back to intmax_t is -1, and the comparison is
     * still the unsigned one, so it holds. */
#if 0xffffffffffffffffULL == -1
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 1);

    /* A literal that fits intmax_t stays signed, and so does one written with
     * a minus sign. */
#if 0x7fffffffffffffffLL > 0
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 1);

#if -1 < 0
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 1);

    /* One unsigned operand makes the comparison unsigned: -1 converted to
     * uintmax_t is the largest value there is, so it is not less than zero. */
#if -1 < 0u
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 0);

#if -1 > 0u
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 1);

    /* Arithmetic and shifts follow the same conversion: the addition wraps at
     * 64 bits, the shift brings a zero in rather than a copy of the sign. */
#if 0xffffffffffffffffULL + 1 == 0
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 1);

#if (0xffffffffffffffffULL >> 1) > 0
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 1);

#if 0xffffffffffffffffULL / 2 == 0x7fffffffffffffff
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 1);

    /* A conditional is as unsigned as either arm, including the arm that is
     * not selected, so this one answers the unsigned question. */
#if (0 ? -1 : 0u) > 0
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 0);

    /* An octal zero with a suffix is still zero; before this it was refused
     * because the base prefix took the only digit with it. */
#if !0u
    taken = 1;
#else
    taken = 0;
#endif
    CHECK(taken == 1);

    return 0;
}
