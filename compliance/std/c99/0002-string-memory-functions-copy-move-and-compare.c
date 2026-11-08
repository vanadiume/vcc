/* 0002: string-memory-functions-copy-move-and-compare
 *
 * ISO/IEC 9899:1999 7.21.6: the memcpy, memmove, memset, memcmp and memchr
 * functions operate on a span of bytes and know nothing about terminators.
 */

#include <stdio.h>
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
    char src[16] = "abcdefgh";
    char dst[16];
    char overlap[16];
    char zeroed[8];
    const char *p;

    CHECK(memset(dst, 'x', 5) == dst);
    dst[5] = '\0';
    CHECK(strcmp(dst, "xxxxx") == 0);

    CHECK(memcpy(dst, src, 9) == dst);
    CHECK(strcmp(dst, "abcdefgh") == 0);

    /* 7.21.4.4p3: a zero count copies nothing, not even to a null-ish pair */
    CHECK(memcpy(dst, src, 0) == dst);
    CHECK(strcmp(dst, "abcdefgh") == 0);

    CHECK(memcmp(src, dst, 9) == 0);
    CHECK(memcmp("abc", "abd", 3) < 0);
    CHECK(memcmp("abd", "abc", 3) > 0);
    CHECK(memcmp("abc", "abc", 0) == 0);

    /* 7.21.4.2: memmove is the one that promises an overlapping copy works */
    strcpy(overlap, "abcdef");
    CHECK(memmove(overlap + 1, overlap, 7) == overlap + 1);
    CHECK(strcmp(overlap, "aabcdef") == 0);

    strcpy(overlap, "abcdef");
    CHECK(memmove(overlap, overlap + 2, 5) == overlap);
    CHECK(strcmp(overlap, "cdef") == 0);

    p = memchr(src, 'd', 8);
    CHECK(p != NULL && *p == 'd');
    CHECK(memchr(src, 'z', 8) == NULL);
    /* the span, not the string: a NUL inside the count is a match */
    CHECK(memchr(src, '\0', 9) == src + 8);
    CHECK(memchr(src, '\0', 8) == NULL);

    memset(zeroed, 0xff, sizeof zeroed);
    CHECK(memset(zeroed, 0, sizeof zeroed) == zeroed);
    CHECK(zeroed[0] == 0 && zeroed[7] == 0);

    {
        volatile size_t none = 0;
        CHECK(memset(zeroed, 'q', none) == zeroed);
    }
    CHECK(zeroed[0] == 0);
    return 0;
}
