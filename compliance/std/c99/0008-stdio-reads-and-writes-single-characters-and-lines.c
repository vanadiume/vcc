/* 0008: stdio-reads-and-writes-single-characters-and-lines
 *
 * ISO/IEC 9899:1999 7.19.7.1 to 7.19.7.4: the character functions write or
 * return one character, ungetc pushes one back, and fgets reads a line up to
 * the count it is given.
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
    FILE *f;
    char line[16];

    f = tmpfile();
    CHECK(f != NULL);
    CHECK(fputc('a', f) == 'a');
    CHECK(putc('b', f) == 'b');
    rewind(f);
    CHECK(fgetc(f) == 'a');
    CHECK(getc(f) == 'b');
    CHECK(fgetc(f) == EOF);
    CHECK(feof(f) != 0);
    CHECK(fclose(f) == 0);

    /* 7.19.7.3: ungetc pushes one character back, and EOF pushes nothing */
    f = tmpfile();
    CHECK(f != NULL);
    CHECK(fputs("ab", f) >= 0);
    rewind(f);
    CHECK(ungetc('z', f) == 'z');
    CHECK(fgetc(f) == 'z');
    CHECK(fgetc(f) == 'a');
    CHECK(ungetc(EOF, f) == EOF);
    CHECK(fgetc(f) == 'b');
    CHECK(fgetc(f) == EOF);
    CHECK(fclose(f) == 0);

    f = tmpfile();
    CHECK(f != NULL);
    CHECK(fputs("first\nsecond\n", f) >= 0);
    rewind(f);
    CHECK(fgets(line, sizeof line, f) == line);
    CHECK(strcmp(line, "first\n") == 0);
    CHECK(fgets(line, sizeof line, f) == line);
    CHECK(strcmp(line, "second\n") == 0);
    CHECK(fgets(line, sizeof line, f) == NULL);
    CHECK(feof(f) != 0);
    CHECK(fclose(f) == 0);

    /* 7.19.7.2p2: with a count of 4 a longer line arrives in pieces */
    f = tmpfile();
    CHECK(f != NULL);
    CHECK(fputs("abcdef", f) >= 0);
    rewind(f);
    CHECK(fgets(line, 4, f) == line);
    CHECK(strcmp(line, "abc") == 0);
    CHECK(fgets(line, 4, f) == line);
    CHECK(strcmp(line, "def") == 0);
    CHECK(fgets(line, 4, f) == NULL);
    CHECK(fclose(f) == 0);

    /* a line without its newline at the end of the file still terminates */
    f = tmpfile();
    CHECK(f != NULL);
    CHECK(fputs("tail", f) >= 0);
    rewind(f);
    CHECK(fgets(line, sizeof line, f) == line);
    CHECK(strcmp(line, "tail") == 0);
    CHECK(fclose(f) == 0);

    /* 7.19.7.4: fputs writes the string and not its terminator */
    f = tmpfile();
    CHECK(f != NULL);
    CHECK(fputs("xy", f) >= 0);
    CHECK(fputs("", f) >= 0);
    rewind(f);
    CHECK(fgets(line, sizeof line, f) == line);
    CHECK(strcmp(line, "xy") == 0);
    CHECK(fclose(f) == 0);
    return 0;
}
