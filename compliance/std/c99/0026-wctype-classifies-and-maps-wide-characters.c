/* 0026: wctype-classifies-and-maps-wide-characters
 *
 * ISO/IEC 9899:1999 7.25: the wide classification functions answer for a wide
 * character as the ctype ones answer for a narrow one, and 7.25.3: wctype,
 * wctrans and towctrans name a class or a mapping by a string.
 */

#include <locale.h>
#include <stdio.h>
#include <wchar.h>
#include <wctype.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    wctype_t class_of_letters;
    wctype_t class_of_digits;
    wctrans_t to_upper;
    wctrans_t to_lower;

    CHECK(setlocale(LC_ALL, "C") != NULL);

    CHECK(iswalpha(L'a') && iswalpha(L'Z'));
    CHECK(!iswalpha(L'0') && !iswalpha(L' '));
    CHECK(iswdigit(L'5') && !iswdigit(L'a'));
    CHECK(iswalnum(L'a') && iswalnum(L'7') && !iswalnum(L' '));
    CHECK(iswspace(L' ') && iswspace(L'\n') && !iswspace(L'a'));
    CHECK(iswblank(L' ') && iswblank(L'\t') && !iswblank(L'\n'));
    CHECK(iswcntrl(L'\n') && iswcntrl(L'\0') && !iswcntrl(L'a'));
    CHECK(iswlower(L'a') && !iswlower(L'A'));
    CHECK(iswupper(L'A') && !iswupper(L'a'));
    CHECK(iswprint(L' ') && !iswprint(L'\n'));
    CHECK(iswgraph(L'!') && !iswgraph(L' '));
    CHECK(iswpunct(L'!') && !iswpunct(L'a') && !iswpunct(L' '));
    CHECK(iswxdigit(L'0') && iswxdigit(L'f') && !iswxdigit(L'g'));

    CHECK(towlower(L'A') == L'a');
    CHECK(towlower(L'q') == L'q');
    CHECK(towlower(L'7') == L'7');
    CHECK(towupper(L'a') == L'A');
    CHECK(towupper(L'Q') == L'Q');

    /* 7.25.1p1: WEOF is an argument every one of these accepts */
    CHECK(iswalpha(WEOF) == 0);
    CHECK(iswdigit(WEOF) == 0);
    CHECK(towupper(WEOF) == WEOF);
    CHECK(towlower(WEOF) == WEOF);

    /* 7.25.3.1 and 7.25.2.2.1: a class named by a string */
    class_of_letters = wctype("alpha");
    class_of_digits = wctype("digit");
    CHECK(class_of_letters != 0);
    CHECK(class_of_digits != 0);
    CHECK(iswctype(L'a', class_of_letters));
    CHECK(!iswctype(L'5', class_of_letters));
    CHECK(iswctype(L'5', class_of_digits));
    CHECK(!iswctype(L'a', class_of_digits));
    CHECK(wctype("no-such-class") == 0);

    /* 7.25.3.2 and 7.25.1.1: a mapping named by a string */
    to_upper = wctrans("toupper");
    to_lower = wctrans("tolower");
    CHECK(to_upper != 0);
    CHECK(to_lower != 0);
    CHECK(towctrans(L'a', to_upper) == L'A');
    CHECK(towctrans(L'A', to_lower) == L'a');
    CHECK(towctrans(L'7', to_upper) == L'7');
    CHECK(wctrans("no-such-mapping") == 0);
    return 0;
}
