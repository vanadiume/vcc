/* 0003: string-functions-copy-concatenate-and-search
 *
 * ISO/IEC 9899:1999 7.21.3: the strn* functions take a count that bounds the
 * operation, and 7.21.5: the search functions return pointers into the string
 * they were given.
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
    char buf[32];
    char tok[] = "a,b,,c";
    char xf[32];
    const char *p;
    volatile size_t three = 3;
    size_t needed;

    strcpy(buf, "hello");
    CHECK(strlen(buf) == 5);
    CHECK(strcmp(buf, "hello") == 0);
    CHECK(strcat(buf, " world") == buf);
    CHECK(strcmp(buf, "hello world") == 0);
    CHECK(strlen(buf) == 11);

    strcpy(buf, "abc");
    CHECK(strncat(buf, "defgh", three) == buf);
    CHECK(strcmp(buf, "abcdef") == 0); /* strncat always terminates */

    strcpy(buf, "abc");
    strncat(buf, "d", 0);
    CHECK(strcmp(buf, "abc") == 0);

    /* 7.21.2.4: strncpy pads with NULs when the count exceeds the source */
    memset(buf, 'Z', sizeof buf);
    strncpy(buf, "xy", 4);
    CHECK(buf[0] == 'x' && buf[1] == 'y');
    CHECK(buf[2] == '\0' && buf[3] == '\0');
    CHECK(buf[4] == 'Z');

    /* and does not terminate when the count cuts the source short */
    memset(buf, 'Z', sizeof buf);
    strncpy(buf, "abcdef", three);
    CHECK(buf[0] == 'a' && buf[1] == 'b' && buf[2] == 'c');
    CHECK(buf[3] == 'Z');

    strcpy(buf, "abc");
    CHECK(strcpy(buf, "def") == buf);
    CHECK(strcmp(buf, "def") == 0);

    CHECK(strcmp("abc", "abc") == 0);
    CHECK(strcmp("abc", "abd") < 0);
    CHECK(strcmp("abd", "abc") > 0);
    CHECK(strcmp("ab", "abc") < 0);

    CHECK(strncmp("abcdef", "abcxyz", 3) == 0);
    CHECK(strncmp("abcdef", "abcxyz", 4) < 0);
    CHECK(strncmp("abc", "abd", 0) == 0);

    p = strchr("banana", 'n');
    CHECK(p != NULL && p[0] == 'n' && p[1] == 'a');
    p = strrchr("banana", 'a');
    CHECK(p != NULL && p[1] == '\0');
    CHECK(strchr("banana", 'z') == NULL);
    p = strchr("abc", '\0');
    CHECK(p != NULL && *p == '\0');

    CHECK(strspn("abcxyz", "abc") == 3);
    CHECK(strspn("xyz", "abc") == 0);
    CHECK(strcspn("abcxyz", "xyz") == 3);
    CHECK(strcspn("abcxyz", "q") == 6);

    p = strpbrk("hello", "lo");
    CHECK(p != NULL && *p == 'l');
    CHECK(strpbrk("hello", "z") == NULL);

    p = strstr("hello world", "lo w");
    CHECK(p != NULL && p[0] == 'l');
    CHECK(strstr("hello", "z") == NULL);
    CHECK(strstr("hello", "") != NULL);

    p = strtok(tok, ",");
    CHECK(p != NULL && strcmp(p, "a") == 0);
    p = strtok(NULL, ",");
    CHECK(p != NULL && strcmp(p, "b") == 0);
    p = strtok(NULL, ",");
    CHECK(p != NULL && strcmp(p, "c") == 0);
    CHECK(strtok(NULL, ",") == NULL);

    /* 7.21.5.4: an empty prefix set consumes nothing */
    CHECK(strspn("", "abc") == 0);

    /* 7.21.5.3: in the C locale collation is code point order */
    CHECK(strcoll("abc", "abd") < 0);
    CHECK(strcoll("abc", "abc") == 0);

    needed = strxfrm(xf, "abc", sizeof xf);
    CHECK(needed == 3);
    CHECK(strcmp(xf, "abc") == 0);

    /* 7.21.5.5: with a zero count the array is not written */
    xf[0] = 'Z';
    CHECK(strxfrm(xf, "abcdef", 0) == 6);
    CHECK(xf[0] == 'Z');

    CHECK(strerror(0) != NULL);
    CHECK(strlen(strerror(0)) > 0);
    return 0;
}
