/* 0005: stdlib-allocates-searches-and-sorts
 *
 * ISO/IEC 9899:1999 7.20.3: the allocation functions hand out storage or the
 * null pointer, and 7.20.5: qsort and bsearch order and find into an array of
 * objects of one size.
 */

#include <stdint.h>
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

static int ascending(const void *pa, const void *pb)
{
    int a = *(const int *)pa;
    int b = *(const int *)pb;
    return (a > b) - (a < b);
}

static int descending(const void *pa, const void *pb)
{
    int a = *(const int *)pa;
    int b = *(const int *)pb;
    return (a < b) - (a > b);
}

static int by_text(const void *pa, const void *pb)
{
    return strcmp(*(const char *const *)pa, *(const char *const *)pb);
}

int main(void)
{
    int *a;
    int *grown;
    long *zeros;
    unsigned long big;
    void *huge;
    int *found;
    int key;
    int i;

    a = malloc(4 * sizeof *a);
    CHECK(a != NULL);
    for (i = 0; i < 4; i++) {
        a[i] = i + 1;
    }
    CHECK(a[0] == 1 && a[3] == 4);

    /* 7.20.3.2: realloc moves or grows, and the old bytes are still there */
    grown = realloc(a, 8 * sizeof *grown);
    CHECK(grown != NULL);
    CHECK(grown[0] == 1 && grown[3] == 4);
    for (i = 4; i < 8; i++) {
        grown[i] = i + 1;
    }
    CHECK(grown[7] == 8);

    /* realloc with a null pointer is a malloc */
    CHECK(realloc(NULL, sizeof *grown) != NULL);

    /* 7.20.3.1: calloc zeroes every byte of what it returns */
    zeros = calloc(16, sizeof *zeros);
    CHECK(zeros != NULL);
    for (i = 0; i < 16; i++) {
        CHECK(zeros[i] == 0);
    }
    free(zeros);

    /* 7.20.3p1: an allocation that cannot be satisfied yields a null pointer */
    big = strtoul("18446744073709551615", NULL, 10);
    CHECK(big > (unsigned long)PTRDIFF_MAX);
    huge = malloc((size_t)big);
    CHECK(huge == NULL);

    free(grown);
    free(NULL);

    /* 7.20.5.2: qsort orders in place through the comparison function */
    {
        int values[7] = {5, 3, 9, 1, 7, 3, 8};
        qsort(values, 7, sizeof values[0], ascending);
        for (i = 1; i < 7; i++) {
            CHECK(values[i - 1] <= values[i]);
        }
        CHECK(values[0] == 1 && values[6] == 9);

        qsort(values, 7, sizeof values[0], descending);
        CHECK(values[0] == 9 && values[6] == 1);

        key = 7;
        found = bsearch(&key, values, 7, sizeof values[0], descending);
        CHECK(found != NULL && *found == 7);

        key = 4;
        CHECK(bsearch(&key, values, 7, sizeof values[0], descending) == NULL);
    }

    {
        const char *words[4] = {"pear", "apple", "fig", "banana"};
        const char *want = "fig";
        const char **hit;
        qsort(words, 4, sizeof words[0], by_text);
        CHECK(strcmp(words[0], "apple") == 0);
        CHECK(strcmp(words[1], "banana") == 0);
        CHECK(strcmp(words[2], "fig") == 0);
        CHECK(strcmp(words[3], "pear") == 0);
        hit = bsearch(&want, words, 4, sizeof words[0], by_text);
        CHECK(hit != NULL && strcmp(*hit, "fig") == 0);
    }

    /* 7.20.5.1: a zero count is a legal search that finds nothing */
    key = 1;
    CHECK(bsearch(&key, &key, 0, sizeof key, ascending) == NULL);
    return 0;
}
