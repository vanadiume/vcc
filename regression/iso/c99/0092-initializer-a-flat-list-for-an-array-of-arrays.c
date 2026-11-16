/* 0092: a flat list for an array of arrays fills rows, not elements

`int m[][3] = { 1, 2, 3, 4, 5, 6 };` was sized as six rows (72 bytes) and
wrote each value at a row boundary, so the program read `1 0 0 / 2 0 0` where
gcc 16.2.1 reads `1 2 3 / 4 5 6` from a 24-byte object.  A flat list
initializes the subobjects of an aggregate in row-major order by brace
elision (C99 6.7.9p20), so the outer bound counts the rows the list reaches
and value i starts at i * element_size inside the object.  The same rule
sizes `int m[][3] = { 1, 2, 3, 4 };` to two rows, and it fills an array of
character arrays and a three-dimensional array the same way.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int m[][3] = { 1, 2, 3, 4, 5, 6 };
static int sized[2][3] = { 1, 2, 3, 4, 5, 6 };
static int partial[][3] = { 1, 2, 3, 4 };
static int spare[3][3] = { 1, 2, 3 };
static char text[][2] = { 'a', 'b', 'c' };
static int cube[][2][2] = { 1, 2, 3, 4, 5, 6, 7, 8 };
static int braced[][3] = { { 1, 2, 3 }, { 4, 5, 6 } };

int main(void)
{
    CHECK(sizeof(m) == 6 * sizeof(int));
    CHECK(m[0][0] == 1 && m[0][1] == 2 && m[0][2] == 3);
    CHECK(m[1][0] == 4 && m[1][1] == 5 && m[1][2] == 6);

    CHECK(sizeof(sized) == 6 * sizeof(int));
    CHECK(sized[0][0] == 1 && sized[0][1] == 2 && sized[0][2] == 3);
    CHECK(sized[1][0] == 4 && sized[1][1] == 5 && sized[1][2] == 6);

    CHECK(sizeof(partial) == 6 * sizeof(int));
    CHECK(partial[0][0] == 1 && partial[0][1] == 2 && partial[0][2] == 3);
    CHECK(partial[1][0] == 4 && partial[1][1] == 0 && partial[1][2] == 0);

    CHECK(sizeof(spare) == 9 * sizeof(int));
    CHECK(spare[0][0] == 1 && spare[0][1] == 2 && spare[0][2] == 3);
    CHECK(spare[1][0] == 0 && spare[1][1] == 0 && spare[1][2] == 0);

    CHECK(sizeof(text) == 4);
    CHECK(text[0][0] == 'a' && text[0][1] == 'b');
    CHECK(text[1][0] == 'c' && text[1][1] == 0);

    CHECK(sizeof(cube) == 8 * sizeof(int));
    CHECK(cube[0][0][0] == 1 && cube[0][0][1] == 2);
    CHECK(cube[0][1][0] == 3 && cube[0][1][1] == 4);
    CHECK(cube[1][0][0] == 5 && cube[1][0][1] == 6);
    CHECK(cube[1][1][0] == 7 && cube[1][1][1] == 8);

    CHECK(sizeof(braced) == 6 * sizeof(int));
    CHECK(braced[0][0] == 1 && braced[0][1] == 2 && braced[0][2] == 3);
    CHECK(braced[1][0] == 4 && braced[1][1] == 5 && braced[1][2] == 6);
    return 0;
}
