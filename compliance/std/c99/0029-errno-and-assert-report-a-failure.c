/* 0029: errno-reports-a-failed-library-call
 *
 * ISO/IEC 9899:1999 7.5: errno is the error indicator a failed library call
 * sets, and 7.5p2: each error macro is a distinct positive value. assert is
 * not exercised here: under strict ISO C99 its glibc expansion is a shape this
 * compiler refuses, and compliance/gnu/gnu99/0941 already holds the gnu99
 * spelling of it.
 */

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    FILE *f;

    /* 7.5p3: errno is zero at program startup and only a failure sets it */
    CHECK(errno == 0);

    f = fopen("t0029-a-file-that-is-not-there", "r");
    CHECK(f == NULL);
    CHECK(errno == ENOENT);

    errno = 0;
    CHECK(remove("t0029-a-file-that-is-not-there") != 0);
    CHECK(errno == ENOENT);

    /* 7.20.1.4p8: an out-of-range conversion is the ERANGE case */
    errno = 0;
    CHECK(strtol("999999999999999999999999999", NULL, 10) == LONG_MAX);
    CHECK(errno == ERANGE);

    errno = 0;
    CHECK(strtol("0", NULL, 10) == 0);
    CHECK(errno == 0);

    /* 7.5p2: a distinct positive value for each error */
    CHECK(EDOM > 0 && ERANGE > 0 && EILSEQ > 0);
    CHECK(EDOM != ERANGE);
    CHECK(ERANGE != EILSEQ);

    CHECK(1);
    return 0;
}
