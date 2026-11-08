/* 0027: wide-stdio-orients-writes-and-reads-a-stream
 *
 * ISO/IEC 9899:1999 7.24.2 and 7.24.3: fwide asks or sets a stream's
 * orientation, and a wide stream takes wide text through fputws, fgetws,
 * fgetwc, fputwc and the formatted wide functions.
 */

#include <locale.h>
#include <stdio.h>
#include <wchar.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

/* once stdout has been pointed somewhere else a failure has to be reported on
 * stderr, or the runner sees only the status */
#define CHECK_ERR(...)                                                        \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__,           \
                    #__VA_ARGS__);                                            \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    FILE *f;
    wchar_t text[32];
    int value = 0;

    CHECK(setlocale(LC_ALL, "C") != NULL);

    f = tmpfile();
    CHECK(f != NULL);

    /* 7.24.2.1: an unoriented stream takes whichever comes first and keeps it */
    CHECK(fwide(f, 0) == 0);
    CHECK(fwide(f, 1) == 1);
    CHECK(fwide(f, 0) == 1);
    CHECK(fwide(f, -1) == 1);

    CHECK(fputws(L"wide\n", f) >= 0);
    CHECK(fflush(f) == 0);
    rewind(f);
    CHECK(fgetws(text, 32, f) == text);
    CHECK(wcscmp(text, L"wide\n") == 0);

    rewind(f);
    CHECK(fgetwc(f) == L'w');
    CHECK(getwc(f) == L'i');
    CHECK(ungetwc(L'z', f) == L'z');
    CHECK(fgetwc(f) == L'z');
    /* 7.19.5.3p6: an update stream needs a positioning call between a read
     * and a write */
    CHECK(fseek(f, 0, SEEK_SET) == 0);
    CHECK(fputwc(L'q', f) == L'q');
    CHECK(putwc(L'r', f) == L'r');
    CHECK(fflush(f) == 0);
    CHECK(fclose(f) == 0);

    /* 7.24.2.1: swprintf writes into a wide array and counts the result */
    CHECK(swprintf(text, 32, L"%d-%ls", 7, L"x") == 3);
    CHECK(wcscmp(text, L"7-x") == 0);
    CHECK(swprintf(text, 32, L"%ls", L"abcdef") == 6);

    /* 7.24.2.4: swscanf reads it back */
    CHECK(swscanf(L"42 abc", L"%d %ls", &value, text) == 2);
    CHECK(value == 42);
    CHECK(wcscmp(text, L"abc") == 0);

    /* 7.24.2.1: the wide functions write to stdout too, through freopen */
    CHECK(freopen("t0027-out.txt", "w", stdout) == stdout);
    CHECK(wprintf(L"%d\n", 5) == 2);
    CHECK(putwchar(L'W') == L'W');
    CHECK(fflush(stdout) == 0);
    freopen("/dev/null", "w", stdout);
    CHECK_ERR(fclose(fopen("t0027-out.txt", "r")) == 0);
    CHECK_ERR(remove("t0027-out.txt") == 0);

    /* 7.24.2.2: and read from stdin */
    f = fopen("t0027-in.txt", "w");
    CHECK_ERR(f != NULL);
    CHECK_ERR(fputs("7\n", f) >= 0);
    CHECK_ERR(fclose(f) == 0);
    CHECK_ERR(freopen("t0027-in.txt", "r", stdin) == stdin);
    CHECK_ERR(wscanf(L"%d", &value) == 1);
    CHECK_ERR(value == 7);
    /* %d leaves the newline behind */
    CHECK_ERR(getwchar() == L'\n');
    CHECK_ERR(getwchar() == WEOF);
    return 0;
}
