/* 0010: stdio-formatted-input-parses-its-conversions
 *
 * ISO/IEC 9899:1999 7.19.6.2: a scanf conversion consumes the longest prefix
 * that matches and stores the value, and the return is the number of input
 * items assigned, zero for a matching failure and EOF for an input failure
 * before any assignment.
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
    char word[16];
    char two[3] = {0, 0, 0};
    char ch = '\0';
    int value = 0;
    int used = -1;
    long along = 0;
    unsigned int uvalue = 0;
    double dv = 0;
    float fv = 0;
    FILE *f;

    CHECK(sscanf("42 apples", "%d %15s", &value, word) == 2);
    CHECK(value == 42);
    CHECK(strcmp(word, "apples") == 0);

    CHECK(sscanf("3.25", "%lf", &dv) == 1);
    CHECK(dv == 3.25);
    CHECK(sscanf("1.5", "%f", &fv) == 1);
    CHECK(fv == 1.5f);

    CHECK(sscanf("z", "%c", &ch) == 1);
    CHECK(ch == 'z');
    CHECK(sscanf("abc", "%2c", two) == 1);
    CHECK(two[0] == 'a' && two[1] == 'b');

    /* 7.19.6.2p12: %i takes the base from the prefix, and %x is always hex */
    CHECK(sscanf("010", "%i", &value) == 1);
    CHECK(value == 8);
    CHECK(sscanf("0x1f", "%i", &value) == 1);
    CHECK(value == 31);
    CHECK(sscanf("1010", "%i", &value) == 1);
    CHECK(value == 1010);
    CHECK(sscanf("ff", "%x", &uvalue) == 1);
    CHECK(uvalue == 255);
    CHECK(sscanf("777", "%o", &uvalue) == 1);
    CHECK(uvalue == 511);

    CHECK(sscanf("3000000000", "%ld", &along) == 1);
    CHECK(along == 3000000000L);
    CHECK(sscanf("-12", "%d", &value) == 1);
    CHECK(value == -12);
    CHECK(sscanf("+12", "%d", &value) == 1);
    CHECK(value == 12);

    /* 7.19.6.2p3: an assignment suppression star stores nothing */
    CHECK(sscanf("7 8", "%d %*d", &value) == 1);
    CHECK(value == 7);

    CHECK(sscanf("abc", "%[abc]", word) == 1);
    CHECK(strcmp(word, "abc") == 0);
    CHECK(sscanf("abc123", "%[a-c]", word) == 1);
    CHECK(strcmp(word, "abc") == 0);
    CHECK(sscanf("a1", "%[^0-9]", word) == 1);
    CHECK(strcmp(word, "a") == 0);

    /* 7.19.6.2p12: %n stores the characters consumed and is not an item */
    CHECK(sscanf("12x", "%d%n", &value, &used) == 1);
    CHECK(value == 12);
    CHECK(used == 2);

    /* 7.19.6.2p16: a matching failure returns zero, an input failure returns
     * EOF when nothing has been assigned */
    CHECK(sscanf("x", "%d", &value) == 0);
    CHECK(sscanf("", "%d", &value) == EOF);
    CHECK(sscanf("   ", "%d", &value) == EOF);

    f = tmpfile();
    CHECK(f != NULL);
    CHECK(fprintf(f, "7 seven\n2.5 tail\n") > 0);
    CHECK(fflush(f) == 0);
    rewind(f);
    CHECK(fscanf(f, "%d %15s", &value, word) == 2);
    CHECK(value == 7);
    CHECK(strcmp(word, "seven") == 0);
    CHECK(fscanf(f, "%lf %15s", &dv, word) == 2);
    CHECK(dv == 2.5);
    CHECK(strcmp(word, "tail") == 0);
    CHECK(fscanf(f, "%d", &value) == EOF);
    CHECK(fclose(f) == 0);
    return 0;
}
