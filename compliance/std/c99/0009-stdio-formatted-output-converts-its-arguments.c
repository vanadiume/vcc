/* 0009: stdio-formatted-output-converts-its-arguments
 *
 * ISO/IEC 9899:1999 7.19.6.1 and 7.19.6.3: the printf functions convert each
 * argument under the conversion its directive names; the return is the number
 * of characters the result needs, which snprintf counts even when the buffer
 * is too small to hold them.
 */

#include <stddef.h>
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
    char line[16];
    volatile size_t cap = 4;
    int written = -1;
    FILE *f;

    CHECK(sprintf(buf, "%d", 42) == 2);
    CHECK(strcmp(buf, "42") == 0);
    CHECK(sprintf(buf, "%+d", 42) == 3);
    CHECK(strcmp(buf, "+42") == 0);
    CHECK(sprintf(buf, "% d", 42) == 3);
    CHECK(strcmp(buf, " 42") == 0);
    CHECK(sprintf(buf, "%5d", 42) == 5);
    CHECK(strcmp(buf, "   42") == 0);
    CHECK(sprintf(buf, "%-5d|", 42) == 6);
    CHECK(strcmp(buf, "42   |") == 0);
    CHECK(sprintf(buf, "%05d", 42) == 5);
    CHECK(strcmp(buf, "00042") == 0);
    CHECK(sprintf(buf, "%+05d", 42) == 5);
    CHECK(strcmp(buf, "+0042") == 0);
    CHECK(sprintf(buf, "%*d", 4, 7) == 4);
    CHECK(strcmp(buf, "   7") == 0);

    CHECK(sprintf(buf, "%x", 255) == 2);
    CHECK(strcmp(buf, "ff") == 0);
    CHECK(sprintf(buf, "%X", 255) == 2);
    CHECK(strcmp(buf, "FF") == 0);
    CHECK(sprintf(buf, "%#x", 255) == 4);
    CHECK(strcmp(buf, "0xff") == 0);
    CHECK(sprintf(buf, "%o", 8) == 2);
    CHECK(strcmp(buf, "10") == 0);
    CHECK(sprintf(buf, "%#o", 8) == 3);
    CHECK(strcmp(buf, "010") == 0);

    CHECK(sprintf(buf, "%c", 'q') == 1);
    CHECK(buf[0] == 'q' && buf[1] == '\0');
    CHECK(sprintf(buf, "%s", "hi") == 2);
    CHECK(strcmp(buf, "hi") == 0);
    CHECK(sprintf(buf, "%.2s", "abc") == 2);
    CHECK(strcmp(buf, "ab") == 0);
    CHECK(sprintf(buf, "%4s|", "ab") == 5);
    CHECK(strcmp(buf, "  ab|") == 0);
    CHECK(sprintf(buf, "%%.%d", 5) == 3);
    CHECK(strcmp(buf, "%.5") == 0);
    CHECK(sprintf(buf, "%.*s", 2, "xyz") == 2);
    CHECK(strcmp(buf, "xy") == 0);

    CHECK(sprintf(buf, "%ld", 3000000000L) == 10);
    CHECK(strcmp(buf, "3000000000") == 0);
    CHECK(sprintf(buf, "%lld", 1234567890123LL) == 13);
    CHECK(strcmp(buf, "1234567890123") == 0);
    CHECK(sprintf(buf, "%u", 4294967295u) == 10);
    CHECK(strcmp(buf, "4294967295") == 0);
    CHECK(sprintf(buf, "%lu", 18446744073709551615UL) == 20);
    CHECK(strcmp(buf, "18446744073709551615") == 0);
    CHECK(sprintf(buf, "%zu", (size_t)7) == 1);
    CHECK(sprintf(buf, "%td", (ptrdiff_t)-2) == 2);
    CHECK(strcmp(buf, "-2") == 0);
    CHECK(sprintf(buf, "%hd", (short)-3) == 2);
    CHECK(strcmp(buf, "-3") == 0);
    CHECK(sprintf(buf, "%hhd", (signed char)-3) == 2);
    CHECK(sprintf(buf, "%hhu", (unsigned char)255) == 3);
    CHECK(strcmp(buf, "255") == 0);

    CHECK(sprintf(buf, "%.3f", 3.14159) == 5);
    CHECK(strcmp(buf, "3.142") == 0);
    CHECK(sprintf(buf, "%f", 2.5) == 8);
    CHECK(strcmp(buf, "2.500000") == 0);
    CHECK(sprintf(buf, "%e", 1234.5) == 12);
    CHECK(strcmp(buf, "1.234500e+03") == 0);
    CHECK(sprintf(buf, "%g", 0.0001) == 6);
    CHECK(strcmp(buf, "0.0001") == 0);
    CHECK(sprintf(buf, "%g", 100000.0) == 6);
    CHECK(strcmp(buf, "100000") == 0);
    CHECK(sprintf(buf, "%a", 3.0) == 8);
    CHECK(strcmp(buf, "0x1.8p+1") == 0);
    CHECK(sprintf(buf, "%8.2f", 1.5) == 8);
    CHECK(strcmp(buf, "    1.50") == 0);
    CHECK(sprintf(buf, "%-8.2f|", 1.5) == 9);
    CHECK(strcmp(buf, "1.50    |") == 0);

    /* 7.19.6.1p8: %n stores the count so far and adds nothing to the result */
    CHECK(sprintf(buf, "ab%ncd", &written) == 4);
    CHECK(written == 2);
    CHECK(strcmp(buf, "abcd") == 0);

    /* 7.19.6.5p3: the needed length is returned even when the buffer is short */
    memset(buf, 'Z', sizeof buf);
    CHECK(snprintf(buf, cap, "%s", "abcdef") == 6);
    CHECK(strcmp(buf, "abc") == 0);
    CHECK(buf[3] == '\0' && buf[4] == 'Z');
    CHECK(snprintf(buf, sizeof buf, "%s", "abcdef") == 6);
    CHECK(strcmp(buf, "abcdef") == 0);
    CHECK(snprintf(buf, cap, "%d", 1234567) == 7);

    /* 7.19.6.1p2: fprintf on a stream returns what the same conversion needs */
    f = tmpfile();
    CHECK(f != NULL);
    CHECK(fprintf(f, "%d-%s", 12, "ab") == 5);
    CHECK(fflush(f) == 0);
    rewind(f);
    CHECK(fgets(line, sizeof line, f) == line);
    CHECK(strcmp(line, "12-ab") == 0);
    CHECK(fclose(f) == 0);
    return 0;
}
