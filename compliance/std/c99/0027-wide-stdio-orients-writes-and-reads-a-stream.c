/* 0027: wide-stdio-orients-writes-and-reads-a-stream
 *
 * ISO/IEC 9899:1999 7.24.2 and 7.24.3: fwide asks or sets a stream's
 * orientation, and a wide stream takes wide text through fputws, fgetws,
 * fgetwc, fputwc and the formatted wide functions, including the v forms that
 * take a va_list.
 */

#include <locale.h>
#include <stdarg.h>
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

static int wide_format_into(wchar_t *buffer, size_t size, const wchar_t *fmt,
                            ...)
{
    va_list args;
    int written;

    va_start(args, fmt);
    written = vswprintf(buffer, size, fmt, args);
    va_end(args);
    return written;
}

static int wide_scan_text(const wchar_t *text, const wchar_t *fmt, ...)
{
    va_list args;
    int read;

    va_start(args, fmt);
    read = vswscanf(text, fmt, args);
    va_end(args);
    return read;
}

static void wide_write(FILE *stream, const wchar_t *fmt, ...)
{
    va_list args;

    va_start(args, fmt);
    vfwprintf(stream, fmt, args);
    va_end(args);
}

static int wide_scan(FILE *stream, const wchar_t *fmt, ...)
{
    va_list args;
    int read;

    va_start(args, fmt);
    read = vfwscanf(stream, fmt, args);
    va_end(args);
    return read;
}

static void wide_write_stdout(const wchar_t *fmt, ...)
{
    va_list args;

    va_start(args, fmt);
    vwprintf(fmt, args);
    va_end(args);
}

static int wide_scan_stdin(const wchar_t *fmt, ...)
{
    va_list args;
    int read;

    va_start(args, fmt);
    read = vwscanf(fmt, args);
    va_end(args);
    return read;
}

int main(void)
{
    FILE *f;
    wchar_t text[32];
    wchar_t word[16];
    int value = 0;
    int other = 0;

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

    /* 7.24.2.5 and 7.24.2.6: the va_list forms of the same two */
    CHECK(wide_format_into(text, 32, L"%d-%ls", 9, L"nine") == 6);
    CHECK(wcscmp(text, L"9-nine") == 0);
    /* a buffer too small is not the snprintf case: 7.24.2.1p3 promises only a
     * negative value on an error, so the truncated answer is not checked */
    CHECK(wide_scan_text(L"7 x", L"%d %ls", &value, word) == 2);
    CHECK(value == 7);
    CHECK(wcscmp(word, L"x") == 0);

    f = tmpfile();
    CHECK(f != NULL);
    CHECK(fwide(f, 1) == 1);
    wide_write(f, L"%d-%ls", 9, L"nine");
    CHECK(fflush(f) == 0);
    rewind(f);
    CHECK(wide_scan(f, L"%d-%ls", &value, word) == 2);
    CHECK(value == 9);
    CHECK(wcscmp(word, L"nine") == 0);
    CHECK(fclose(f) == 0);

    /* 7.24.2.1: the wide functions write to stdout too, through freopen */
    CHECK(freopen("t0027-out.txt", "w", stdout) == stdout);
    CHECK(wprintf(L"%d\n", 5) == 2);
    CHECK(putwchar(L'W') == L'W');
    wide_write_stdout(L"%d\n", 6);
    CHECK(fflush(stdout) == 0);
    freopen("/dev/null", "w", stdout);

    f = fopen("t0027-out.txt", "r");
    CHECK_ERR(f != NULL);
    CHECK_ERR(fgetws(text, 32, f) == text);
    CHECK_ERR(wcscmp(text, L"5\n") == 0);
    CHECK_ERR(fgetws(text, 32, f) == text);
    CHECK_ERR(wcscmp(text, L"W6\n") == 0);
    CHECK_ERR(fgetws(text, 32, f) == NULL);
    CHECK_ERR(fclose(f) == 0);
    CHECK_ERR(remove("t0027-out.txt") == 0);

    /* 7.24.2.2: and read from stdin */
    f = fopen("t0027-in.txt", "w");
    CHECK_ERR(f != NULL);
    CHECK_ERR(fputs("7\n8\n", f) >= 0);
    CHECK_ERR(fclose(f) == 0);
    CHECK_ERR(freopen("t0027-in.txt", "r", stdin) == stdin);
    CHECK_ERR(wscanf(L"%d", &value) == 1);
    CHECK_ERR(value == 7);
    CHECK_ERR(wide_scan_stdin(L"%d", &other) == 1);
    CHECK_ERR(other == 8);
    /* %d leaves the newline behind */
    CHECK_ERR(getwchar() == L'\n');
    CHECK_ERR(getwchar() == WEOF);
    return 0;
}
