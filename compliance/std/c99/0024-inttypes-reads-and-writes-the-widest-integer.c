/* 0024: inttypes-reads-and-writes-the-widest-integer
 *
 * ISO/IEC 9899:1999 7.8: imaxabs and imaxdiv on intmax_t, strtoimax and
 * strtoumax to convert text to it, and the PRI and SCN macros that name its
 * conversion for printf and scanf.
 */

#include <inttypes.h>
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
    char buf[64];
    char *end = NULL;
    intmax_t widest;
    uintmax_t widest_unsigned;
    imaxdiv_t parts;
    int8_t small = -7;
    uint64_t big = 7;
    uint32_t thirty_two = 0;
    int_least32_t least = 0;

    CHECK(imaxabs((intmax_t)-5) == 5);
    CHECK(imaxabs((intmax_t)5) == 5);

    parts = imaxdiv((intmax_t)7, (intmax_t)2);
    CHECK(parts.quot == 3 && parts.rem == 1);
    parts = imaxdiv((intmax_t)-7, (intmax_t)2);
    CHECK(parts.quot == -3 && parts.rem == -1);
    CHECK(parts.quot * 2 + parts.rem == -7);

    widest = strtoimax("-9223372036854775808", &end, 10);
    CHECK(widest == INTMAX_MIN);
    CHECK(end != NULL && *end == '\0');
    widest = strtoimax("42 tail", &end, 10);
    CHECK(widest == 42);
    CHECK(end != NULL && strcmp(end, " tail") == 0);
    widest = strtoimax("0x1f", &end, 0);
    CHECK(widest == 31);

    widest_unsigned = strtoumax("18446744073709551615", &end, 10);
    CHECK(widest_unsigned == UINTMAX_MAX);
    widest_unsigned = strtoumax("777", &end, 8);
    CHECK(widest_unsigned == 511);

    /* 7.8.1: the PRI macros name the length modifier for printf */
    CHECK(sprintf(buf, "%" PRIdMAX, (intmax_t)-7) == 2);
    CHECK(strcmp(buf, "-7") == 0);
    CHECK(sprintf(buf, "%" PRIuMAX, (uintmax_t)7) == 1);
    CHECK(strcmp(buf, "7") == 0);
    CHECK(sprintf(buf, "%" PRIxMAX, (uintmax_t)255) == 2);
    CHECK(strcmp(buf, "ff") == 0);
    CHECK(sprintf(buf, "%" PRIoMAX, (uintmax_t)8) == 2);
    CHECK(strcmp(buf, "10") == 0);
    CHECK(sprintf(buf, "%" PRId8, small) == 2);
    CHECK(strcmp(buf, "-7") == 0);
    CHECK(sprintf(buf, "%" PRIu64, big) == 1);
    CHECK(sprintf(buf, "%" PRId32, (int32_t)-12) == 3);
    CHECK(strcmp(buf, "-12") == 0);
    CHECK(sprintf(buf, "%" PRIuPTR, (uintptr_t)9) == 1);
    CHECK(sprintf(buf, "%" PRIdLEAST32, least) == 1);

    /* 7.8.1: and the SCN macros name it for scanf */
    CHECK(sscanf("42", "%" SCNdMAX, &widest) == 1);
    CHECK(widest == 42);
    CHECK(sscanf("-9", "%" SCNd64, &widest) == 1);
    CHECK(widest == -9);
    CHECK(sscanf("255", "%" SCNuMAX, &widest_unsigned) == 1);
    CHECK(widest_unsigned == 255);
    CHECK(sscanf("ff", "%" SCNx32, &thirty_two) == 1);
    CHECK(thirty_two == 255);
    return 0;
}
