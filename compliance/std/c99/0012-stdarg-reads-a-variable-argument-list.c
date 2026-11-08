/* 0012: stdarg-reads-a-variable-argument-list
 *
 * ISO/IEC 9899:1999 7.15: va_start opens a list, va_arg reads the next
 * argument at the type it is given, va_copy copies a list so it can be read
 * twice, and va_end closes it.
 */

#include <stdarg.h>
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

static int sum_twice(int count, ...)
{
    va_list ap;
    va_list copy;
    int total = 0;
    int i;

    va_start(ap, count);
    va_copy(copy, ap);
    for (i = 0; i < count; i++) {
        total += va_arg(ap, int);
    }
    va_end(ap);
    for (i = 0; i < count; i++) {
        total += va_arg(copy, int);
    }
    va_end(copy);
    return total;
}

static double by_spec(const char *spec, ...)
{
    va_list ap;
    double total = 0.0;
    const char *p;

    va_start(ap, spec);
    for (p = spec; *p != '\0'; p++) {
        if (*p == 'd') {
            total += va_arg(ap, int);
        } else if (*p == 'f') {
            total += va_arg(ap, double);
        } else if (*p == 'l') {
            total += (double)va_arg(ap, long long);
        } else if (*p == 'u') {
            total += (double)va_arg(ap, unsigned int);
        } else if (*p == 's') {
            total += (double)strlen(va_arg(ap, const char *));
        }
    }
    va_end(ap);
    return total;
}

static int format_into(char *buf, const char *fmt, ...)
{
    va_list ap;
    int written;

    va_start(ap, fmt);
    written = vsprintf(buf, fmt, ap);
    va_end(ap);
    return written;
}

static int format_bounded(char *buf, size_t size, const char *fmt, ...)
{
    va_list ap;
    int written;

    va_start(ap, fmt);
    written = vsnprintf(buf, size, fmt, ap);
    va_end(ap);
    return written;
}

static void write_formatted(FILE *stream, const char *fmt, ...)
{
    va_list ap;

    va_start(ap, fmt);
    vfprintf(stream, fmt, ap);
    va_end(ap);
}

int main(void)
{
    char buf[32];
    char line[32];
    FILE *f;

    CHECK(sum_twice(3, 1, 2, 3) == 12); /* read once forwards and once again */
    CHECK(sum_twice(0) == 0);
    CHECK(by_spec("dflus", 1, 2.5, 3LL, 4u, "abc") == 13.5);
    CHECK(by_spec("") == 0.0);

    CHECK(format_into(buf, "%d/%s", 5, "x") == 3);
    CHECK(strcmp(buf, "5/x") == 0);

    CHECK(format_bounded(buf, 3, "%s", "abcdef") == 6);
    CHECK(strcmp(buf, "ab") == 0);

    f = tmpfile();
    CHECK(f != NULL);
    write_formatted(f, "%d|%s", 9, "nine");
    CHECK(fflush(f) == 0);
    rewind(f);
    CHECK(fgets(line, sizeof line, f) == line);
    CHECK(strcmp(line, "9|nine") == 0);
    CHECK(fclose(f) == 0);
    return 0;
}
