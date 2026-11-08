/* 0011: stdio-moves-blocks-and-the-file-position
 *
 * ISO/IEC 9899:1999 7.19.8.1 and 7.19.8.2: fread and fwrite move whole items
 * and return the count they moved, and 7.19.9.1 to 7.19.9.3: the positioning
 * functions place the indicator and report it.
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
    const char data[11] = "0123456789";
    FILE *f;
    char in[8];
    fpos_t pos;

    f = tmpfile();
    CHECK(f != NULL);

    CHECK(fwrite(data, 1, 10, f) == 10);
    CHECK(ftell(f) == 10);
    CHECK(fflush(f) == 0);

    CHECK(fseek(f, 0, SEEK_SET) == 0);
    CHECK(ftell(f) == 0);
    CHECK(fread(in, 1, 4, f) == 4);
    CHECK(memcmp(in, "0123", 4) == 0);
    CHECK(ftell(f) == 4);

    CHECK(fseek(f, 2, SEEK_CUR) == 0);
    CHECK(ftell(f) == 6);
    CHECK(fgetc(f) == '6');

    CHECK(fseek(f, -2, SEEK_END) == 0);
    CHECK(ftell(f) == 8);
    CHECK(fgetc(f) == '8');

    /* 7.19.9.2p3: a position past the end of the file is a legal one */
    CHECK(fseek(f, 100, SEEK_SET) == 0);
    CHECK(ftell(f) == 100);
    CHECK(fread(in, 1, 1, f) == 0);
    CHECK(feof(f) != 0);

    /* 7.19.8.1p2: a partial item is not counted */
    CHECK(fseek(f, 8, SEEK_SET) == 0);
    CHECK(fread(in, 2, 2, f) == 1);
    CHECK(feof(f) != 0);

    /* 7.19.8.2p2: fwrite returns the items written, and the bytes land */
    CHECK(fseek(f, 0, SEEK_SET) == 0);
    CHECK(fwrite("AB", 2, 1, f) == 1);
    CHECK(fflush(f) == 0);
    CHECK(fseek(f, 0, SEEK_SET) == 0);
    CHECK(fgetc(f) == 'A');
    CHECK(fgetc(f) == 'B');
    CHECK(fgetc(f) == '2');

    /* 7.19.9.3: fgetpos saves a position fsetpos restores */
    CHECK(fseek(f, 5, SEEK_SET) == 0);
    CHECK(fgetpos(f, &pos) == 0);
    CHECK(fgetc(f) == '5');
    CHECK(fgetc(f) == '6');
    CHECK(fsetpos(f, &pos) == 0);
    CHECK(ftell(f) == 5);
    CHECK(fgetc(f) == '5');
    CHECK(fgetc(f) == '6');

    /* 7.19.9.5: rewind positions at the start and clears the indicators */
    CHECK(fseek(f, 0, SEEK_END) == 0);
    CHECK(fgetc(f) == EOF);
    CHECK(feof(f) != 0);
    rewind(f);
    CHECK(ftell(f) == 0);
    CHECK(feof(f) == 0);
    CHECK(ferror(f) == 0);

    CHECK(fclose(f) == 0);
    return 0;
}
