/* 0013: CHECK((w >> 64) == 0); CHECK(((a >> 1) >> 64) == 0x0091a2b3c4d5e6f7ULL);
 * CHECK(((a / 3) >> 64) == 0x00611722833944a5ULL);
 *
 * An unsigned value as wide as a word keeps its own bits when it widens into a
 * 128-bit object, with zero in the word above it. It was sign-extended, so an
 * `unsigned long` whose top bit was set became a negative value: the word above
 * came out as all ones and the low word was right, which made every shift and
 * every division of such a value answer with the wrong high word. `a >> 1` of
 * 0x0123456789abcdef_fedcba9876543210 read 0x7fffffffffffffff for its high word,
 * because that is what shifting the all-ones word above it leaves.
 *
 * The statuses here are gcc 16.2.1's, and the same file compiled with it exits 0.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

typedef unsigned long long u64;
typedef unsigned __int128 u128;

int main(void)
{
    unsigned long top = 0xfedcba9876543210UL;
    unsigned int wide = 0xffffffffu;
    long negative = -1L;
    u128 w = (u128)top;
    u128 a = ((u128)0x0123456789abcdefULL << 64) | top;

    /* The unsigned word puts zero above it, and the value below is the word. */
    CHECK((w >> 64) == 0);
    CHECK((u64)w == 0xfedcba9876543210ULL);
    CHECK(((w >> 60) & 0xff) == 0xf);

    /* A signed word, and a pointer, are still extended from their own top bit. */
    CHECK((((u128)negative) >> 64) == 0xffffffffffffffffULL);

    /* A narrower unsigned value is zero above it too, however it is written. */
    CHECK((((u128)wide) >> 64) == 0);
    CHECK(((u128)wide) == 0xffffffffULL);

    /* The value the report was about: its high word survives into a shift, a
     * wider shift, and a division. */
    CHECK((a >> 64) == 0x0123456789abcdefULL);
    CHECK(((a >> 1) >> 64) == 0x0091a2b3c4d5e6f7ULL);
    CHECK(((a >> 32) >> 64) == 0x01234567ULL);
    CHECK((a >> 64) >> 64 == 0);
    CHECK((a << 70) >> 64 == 0xb72ea61d950c8400ULL);
    CHECK(((a / 3) >> 64) == 0x00611722833944a5ULL);
    CHECK(((a / 3) & 0xffffffffffffffffULL) == 0x54f43e32d21c10b0ULL);
    CHECK((a / (((u128)1) << 64)) == 0x0123456789abcdefULL);
    return 0;
}
