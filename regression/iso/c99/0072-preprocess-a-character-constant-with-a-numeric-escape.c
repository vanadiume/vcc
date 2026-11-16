/* 0072: a character constant with a numeric escape is read in an #if

`#if 'A' == '\301'`, SQLite's EBCDIC probe at sqlite3.c:16004, was refused with
`'\301' is not a character constant the #if evaluator can read`.  Every numeric
escape was refused the same way, because the evaluator kept a second reader
that knew only the named ones.  It now calls the parser's reader, so the escape
set and the value are the same in a condition and in an expression.  Fixed in
721f79b ("preprocess: read a character constant in an #if with the parser's
reader").
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

#if 'A' == '\301'
#define EBCDIC_PROBE 1
#else
#define EBCDIC_PROBE 0
#endif

#if '\x41' == 'A'
#define HEX_ESCAPE_IS_A 1
#else
#define HEX_ESCAPE_IS_A 0
#endif

#if '\177' == 127
#define OCTAL_177_IS_127 1
#else
#define OCTAL_177_IS_127 0
#endif

#if '\377' == -1
#define OCTAL_377_IS_MINUS_1 1
#else
#define OCTAL_377_IS_MINUS_1 0
#endif

#if '\200' == -128
#define OCTAL_200_IS_MINUS_128 1
#else
#define OCTAL_200_IS_MINUS_128 0
#endif

#if '\0' + '\n' + '\\' + '\'' == 141
#define NAMED_ESCAPES 1
#else
#define NAMED_ESCAPES 0
#endif

int main(void)
{
    /* SQLite's probe: 'A' is 65 and '\301' is -63 in a plain char, so the
     * EBCDIC arm is not taken and SQLITE_ASCII is defined. */
    CHECK(EBCDIC_PROBE == 0);

    /* The rest are the numeric escapes the evaluator refused.  The values are
     * the ones gcc 16.2.1 gives on x86-64. */
    CHECK(HEX_ESCAPE_IS_A == 1);
    CHECK(OCTAL_177_IS_127 == 1);
    CHECK(OCTAL_377_IS_MINUS_1 == 1);
    CHECK(OCTAL_200_IS_MINUS_128 == 1);

    /* The named escapes still work. */
    CHECK(NAMED_ESCAPES == 1);

    /* The reader is shared with an expression, so the same constants are the
     * same values here. */
    CHECK('\301' == -63);
    CHECK('\377' == -1);
    CHECK('\200' == -128);
    CHECK('\x41' == 'A');

    return 0;
}
