/* 0020: locale-sets-the-conventions-of-the-program
 *
 * ISO/IEC 9899:1999 7.11: setlocale names the locale whose conventions the
 * program uses, and 7.11.2: localeconv reports the numeric and monetary
 * conventions of the one in force. In the "C" locale the decimal point is a
 * period and collation is code point order.
 */

#include <limits.h>
#include <locale.h>
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
    struct lconv *conventions;
    char *chosen;
    char transformed[64];
    size_t needed;

    /* 7.11.1.1p3: a null string asks which locale is in force */
    chosen = setlocale(LC_ALL, NULL);
    CHECK(chosen != NULL);

    CHECK(setlocale(LC_ALL, "C") != NULL);
    chosen = setlocale(LC_ALL, NULL);
    CHECK(chosen != NULL);
    CHECK(strcmp(chosen, "C") == 0);

    CHECK(setlocale(LC_NUMERIC, "C") != NULL);
    CHECK(setlocale(LC_COLLATE, "C") != NULL);
    CHECK(setlocale(LC_CTYPE, "C") != NULL);
    CHECK(setlocale(LC_MONETARY, "C") != NULL);
    CHECK(setlocale(LC_TIME, "C") != NULL);

    /* 7.11.1.1p4: a name this implementation does not know fails and leaves
     * the locale as it was */
    CHECK(setlocale(LC_ALL, "vcc_no_such_locale_name") == NULL);
    chosen = setlocale(LC_ALL, NULL);
    CHECK(chosen != NULL);
    CHECK(strcmp(chosen, "C") == 0);

    /* 7.11.2.1: the conventions of the C locale */
    conventions = localeconv();
    CHECK(conventions != NULL);
    CHECK(strcmp(conventions->decimal_point, ".") == 0);
    CHECK(conventions->thousands_sep != NULL);
    CHECK(conventions->currency_symbol != NULL);
    CHECK(conventions->int_curr_symbol != NULL);
    CHECK(conventions->negative_sign != NULL);
    CHECK(strcmp(conventions->negative_sign, "") == 0);
    CHECK(conventions->frac_digits >= 0 || conventions->frac_digits == CHAR_MAX);

    /* 7.21.5.3 and 7.21.5.5: collation and transformation agree with strcmp
     * in the C locale */
    CHECK(strcoll("abc", "abd") < 0);
    CHECK(strcoll("abc", "abc") == 0);
    CHECK(strcoll("abd", "abc") > 0);

    needed = strxfrm(transformed, "abc", sizeof transformed);
    CHECK(needed == 3);
    CHECK(strcmp(transformed, "abc") == 0);
    CHECK(strxfrm(transformed, "abcdef", 0) == 6);

    /* 7.11.1.1p2: an empty string asks for the environment's native locale */
    chosen = setlocale(LC_ALL, "");
    CHECK(chosen != NULL);
    /* and the C locale is what the rest of the corpus assumes */
    CHECK(setlocale(LC_ALL, "C") != NULL);
    return 0;
}
