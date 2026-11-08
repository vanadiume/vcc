/* 0025: wchar-copies-searches-and-converts-wide-strings
 *
 * ISO/IEC 9899:1999 7.24.2 and 7.24.4: the wide-string functions are the
 * narrow ones over wchar_t, and the conversions turn a multibyte string into a
 * wide one and back. The C locale has one byte per wide character, so the
 * conversion is a widening of the same characters.
 */

#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    const wchar_t *hay = L"hello world";
    wchar_t text[32];
    wchar_t other[32];
    char narrow[32];
    wchar_t *piece;
    wchar_t *wide_rest;
    const char *narrow_src;
    const wchar_t *wide_src;
    wchar_t one_wide = 0;
    wint_t wide = 0;
    mbstate_t state;
    size_t count;

    CHECK(setlocale(LC_ALL, "C") != NULL);
    memset(&state, 0, sizeof state);

    CHECK(wcslen(L"abc") == 3);
    CHECK(wcslen(L"") == 0);

    CHECK(wcscpy(text, L"abc") == text);
    CHECK(wcscmp(text, L"abc") == 0);
    CHECK(wcscmp(L"abc", L"abd") < 0);
    CHECK(wcscmp(L"abd", L"abc") > 0);
    CHECK(wcsncmp(L"abcdef", L"abcxyz", 3) == 0);
    CHECK(wcsncmp(L"abc", L"abd", 0) == 0);

    CHECK(wcscat(text, L"def") == text);
    CHECK(wcscmp(text, L"abcdef") == 0);
    CHECK(wcsncat(text, L"ghij", 2) == text);
    CHECK(wcscmp(text, L"abcdefgh") == 0);

    wmemset(other, L'Z', 4);
    CHECK(wcsncpy(other, L"xy", 3) == other);
    CHECK(other[0] == L'x' && other[1] == L'y' && other[2] == 0);
    CHECK(other[3] == L'Z');

    piece = wcschr(hay, L'o');
    CHECK(piece != NULL && *piece == L'o');
    CHECK(wcschr(hay, L'z') == NULL);
    piece = wcsrchr(hay, L'o');
    CHECK(piece != NULL && *(piece + 1) == L'r');

    CHECK(wcsstr(hay, L"lo w") != NULL);
    CHECK(wcsstr(hay, L"z") == NULL);
    CHECK(wcsspn(L"abcxyz", L"abc") == 3);
    CHECK(wcscspn(L"abcxyz", L"xyz") == 3);
    CHECK(wcspbrk(hay, L"lo") != NULL);
    CHECK(wcspbrk(hay, L"z") == NULL);

    /* 7.24.4.9: wcstok walks a wide string the way strtok walks a narrow one */
    wcscpy(text, L"a,b,,c");
    piece = wcstok(text, L",", &wide_rest);
    CHECK(piece != NULL && wcscmp(piece, L"a") == 0);
    piece = wcstok(NULL, L",", &wide_rest);
    CHECK(piece != NULL && wcscmp(piece, L"b") == 0);
    piece = wcstok(NULL, L",", &wide_rest);
    CHECK(piece != NULL && wcscmp(piece, L"c") == 0);
    CHECK(wcstok(NULL, L",", &wide_rest) == NULL);

    /* 7.24.4.6: the wmem functions work on a count of wide characters */
    CHECK(wmemchr(L"abc", L'b', 3) != NULL);
    CHECK(wmemchr(L"abc", L'z', 3) == NULL);
    wmemcpy(other, L"abcd", 4);
    CHECK(wmemcmp(other, L"abcd", 4) == 0);
    CHECK(wmemcmp(L"abcd", L"abce", 4) < 0);
    wmemmove(other + 1, other, 3);
    CHECK(other[0] == L'a' && other[1] == L'a' && other[3] == L'c');
    CHECK(wmemset(other, L'q', 2) == other && other[0] == L'q');

    /* 7.24.4.4: collation and the transform that sorts like it */
    CHECK(wcscoll(L"abc", L"abd") < 0);
    CHECK(wcscoll(L"abc", L"abc") == 0);
    CHECK(wcscoll(L"abd", L"abc") > 0);
    count = wcsxfrm(text, L"abc", 32);
    CHECK(count == 3);
    CHECK(wcscmp(text, L"abc") == 0);
    CHECK(wcsxfrm(text, L"abcdef", 0) == 6);

    /* 7.24.4.1: the multibyte conversions in the C locale */
    CHECK(wcstombs(narrow, L"abc", sizeof narrow) == 3);
    CHECK(strcmp(narrow, "abc") == 0);
    wide_src = L"abc";
    CHECK(wcsrtombs(narrow, &wide_src, sizeof narrow, &state) == 3);
    CHECK(strcmp(narrow, "abc") == 0);

    CHECK(mbstowcs(text, "abc", 32) == 3);
    CHECK(text[0] == L'a' && text[3] == 0);
    narrow_src = "abc";
    memset(&state, 0, sizeof state);
    CHECK(mbsrtowcs(text, &narrow_src, 32, &state) == 3);
    CHECK(text[2] == L'c');

    /* 7.24.6.1 to 7.24.6.3: one character at a time */
    CHECK(mblen("abc", 3) == 1);
    CHECK(mblen("", 3) == 0);
    CHECK(mbtowc(&one_wide, "a", 1) == 1);
    CHECK(one_wide == L'a');
    CHECK(wctomb(narrow, L'a') == 1);
    CHECK(narrow[0] == 'a');
    CHECK(wctob(L'a') == 'a');
    CHECK(btowc('a') == L'a');

    /* 7.24.6.3 and 7.24.6.4: the stateful pair */
    memset(&state, 0, sizeof state);
    CHECK(mbsinit(&state) != 0);
    count = mbrtowc(&one_wide, "a", 1, &state);
    CHECK(count == 1 && one_wide == L'a');
    memset(&state, 0, sizeof state);
    count = wcrtomb(narrow, L'a', &state);
    CHECK(count == 1 && narrow[0] == 'a');

    memset(&state, 0, sizeof state);
    count = mbrlen("a", 1, &state);
    CHECK(count == 1);

    wide = WEOF;
    CHECK(wide == WEOF);
    return 0;
}
