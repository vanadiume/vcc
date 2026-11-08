/* 0013: stdio-reads-and-writes-the-standard-streams
 *
 * ISO/IEC 9899:1999 7.19.7.9 to 7.19.7.13: putchar, getchar, puts and printf
 * work on stdout and stdin, which freopen can send to a named file.
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
    FILE *f;
    int value = 0;

    CHECK(freopen("t0013-out.txt", "w", stdout) == stdout);
    CHECK(ferror(stdout) == 0);
    CHECK(puts("line") >= 0);
    CHECK(putchar('X') == 'X');
    CHECK(putchar('\n') == '\n');
    CHECK(printf("%d\n", 7) == 2);
    CHECK(fflush(stdout) == 0);
    /* later failures in this file have already been reported on the run's
     * own stdout, so the stream goes somewhere harmless before it is read */
    freopen("/dev/null", "w", stdout);

    f = fopen("t0013-out.txt", "r");
    CHECK(f != NULL);
    CHECK(fgets(buf, sizeof buf, f) == buf);
    CHECK(strcmp(buf, "line\n") == 0);
    CHECK(fgets(buf, sizeof buf, f) == buf);
    CHECK(strcmp(buf, "X\n") == 0);
    CHECK(fgets(buf, sizeof buf, f) == buf);
    CHECK(strcmp(buf, "7\n") == 0);
    CHECK(fgets(buf, sizeof buf, f) == NULL);
    CHECK(fclose(f) == 0);
    CHECK(remove("t0013-out.txt") == 0);

    f = fopen("t0013-in.txt", "w");
    CHECK(f != NULL);
    CHECK(fputs("hi\n42", f) >= 0);
    CHECK(fclose(f) == 0);

    CHECK(freopen("t0013-in.txt", "r", stdin) == stdin);
    CHECK(getchar() == 'h');
    CHECK(getchar() == 'i');
    CHECK(getchar() == '\n');
    CHECK(scanf("%d", &value) == 1);
    CHECK(value == 42);
    CHECK(getchar() == EOF);
    CHECK(feof(stdin) != 0);
    return 0;
}
