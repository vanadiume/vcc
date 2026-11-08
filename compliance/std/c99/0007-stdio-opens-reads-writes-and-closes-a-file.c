/* 0007: stdio-opens-reads-writes-and-closes-a-file
 *
 * ISO/IEC 9899:1999 7.19.5: fopen opens a file in a mode, fclose and freopen
 * end or replace that association, remove and rename act on the name, and
 * 7.19.5.4 to 7.19.5.6 name the buffering and the stream-status interface.
 */

#include <errno.h>
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
    static char big[BUFSIZ];
    FILE *f;
    char buf[16];

    f = fopen("t0007.txt", "w");
    CHECK(f != NULL);
    CHECK(fputs("line\n", f) >= 0);
    CHECK(fflush(f) == 0);
    CHECK(fclose(f) == 0);

    f = fopen("t0007.txt", "r");
    CHECK(f != NULL);
    CHECK(fgetc(f) == 'l');
    CHECK(fclose(f) == 0);

    /* 7.19.5.3p7: a failed open hands back a null pointer and sets errno */
    errno = 0;
    CHECK(fopen("t0007-not-there", "r") == NULL);
    CHECK(errno == ENOENT);

    /* 7.19.4.1: the second remove of the same name is a failure */
    CHECK(remove("t0007.txt") == 0);
    CHECK(remove("t0007.txt") != 0);

    f = fopen("t0007-a", "w");
    CHECK(f != NULL);
    fputs("x", f);
    CHECK(fclose(f) == 0);

    CHECK(rename("t0007-a", "t0007-b") == 0);
    CHECK(fopen("t0007-a", "r") == NULL);
    f = fopen("t0007-b", "r");
    CHECK(f != NULL);
    CHECK(fgetc(f) == 'x');
    CHECK(fclose(f) == 0);
    CHECK(remove("t0007-b") == 0);

    /* 7.19.5.4p2: freopen closes what the stream held and opens the new file */
    f = tmpfile();
    CHECK(f != NULL);
    fputs("abc", f);
    CHECK(freopen("t0007-c", "w", f) == f);
    fputs("xyz", f);
    CHECK(fclose(f) == 0);

    f = fopen("t0007-c", "r");
    CHECK(f != NULL);
    CHECK(fread(buf, 1, 3, f) == 3);
    buf[3] = '\0';
    CHECK(strcmp(buf, "xyz") == 0);
    CHECK(fclose(f) == 0);
    CHECK(remove("t0007-c") == 0);

    /* 7.19.5.6: a caller's buffer is used, and _IOLBF still writes through */
    f = tmpfile();
    CHECK(f != NULL);
    CHECK(setvbuf(f, big, _IOFBF, sizeof big) == 0);
    CHECK(fputs("hello", f) >= 0);
    CHECK(fflush(f) == 0);
    rewind(f);
    CHECK(fgetc(f) == 'h');
    CHECK(fclose(f) == 0);

    f = tmpfile();
    CHECK(f != NULL);
    setbuf(f, NULL); /* 7.19.5.5: the null pointer asks for no buffering */
    CHECK(fputc('q', f) == 'q');
    rewind(f);
    CHECK(fgetc(f) == 'q');
    CHECK(fclose(f) == 0);

    /* 7.19.5.3p10-11: feof is set by an attempt to read past the end, and
     * clearerr clears the indicator without moving the position */
    f = tmpfile();
    CHECK(f != NULL);
    fputs("a", f);
    rewind(f);
    CHECK(feof(f) == 0);
    CHECK(fgetc(f) == 'a');
    CHECK(feof(f) == 0);
    CHECK(fgetc(f) == EOF);
    CHECK(feof(f) != 0);
    clearerr(f);
    CHECK(feof(f) == 0);
    CHECK(fgetc(f) == EOF);
    CHECK(feof(f) != 0);
    CHECK(fclose(f) == 0);

    /* 7.19.5.3p9: ferror reports an indicator a failed operation sets */
    f = tmpfile();
    CHECK(f != NULL);
    CHECK(ferror(f) == 0);
    CHECK(fputc('z', f) == 'z');
    CHECK(ferror(f) == 0);
    CHECK(fclose(f) == 0);

    f = fopen("t0007-d", "w");
    CHECK(f != NULL);
    CHECK(fclose(f) == 0);
    f = fopen("t0007-d", "r");
    CHECK(f != NULL);
    CHECK(fputc('z', f) == EOF); /* the stream is not open for writing */
    CHECK(ferror(f) != 0);
    CHECK(fclose(f) == 0);
    CHECK(remove("t0007-d") == 0);
    return 0;
}
