/* 0086: a nested brace list of addresses initializes a pointer table row by row

`static char *cast_table[][11] = { { NULL, NULL, NULL, i32i64, ... }, ... };`,
the shape of chibicc's codegen.c:373, was refused with `unsupported: a nested
brace initializer is not implemented` at the first `{` inside the outer list.
The number path and the struct path walked a nested list; the path that reads a
pointer object's list read one level and refused the rest, though an address is
an ordinary initializer (6.6p7-9, 6.7.8).  That path now reads its list with the
brace reader every other list uses and places it with the same walk, so each
inner list initializes one row, the entries a row does not write stay zero, and
a flat list of a two-dimensional table fills the rows one after another
(6.7.8p20).  Fixed in ff042c3 ("parser: read a pointer table's list the way
every other list is read").
 */

#include <stdio.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

#define COLUMNS 11

static char name_i8i8[] = "i8i8";
static char name_i8u8[] = "i8u8";
static char name_i16i16[] = "i16i16";
static char name_i32i32[] = "i32i32";
static char name_i32i64[] = "i32i64";
static char name_i64i64[] = "i64i64";
static char name_u64u64[] = "u64u64";

/* Rows of unequal length: the first two write nine of eleven entries, the
 * third four, and the fourth one.  A row shorter than COLUMNS must leave the
 * rest of its own row zero and must not run into the row below it. */
static char *cast_table[][COLUMNS] = {
    {NULL, NULL, NULL, name_i8i8, name_i8u8, name_i16i16, name_i32i32, name_i32i64, name_i64i64},
    {NULL, NULL, NULL, NULL, NULL, NULL, name_i32i32, name_i32i64, name_u64u64},
    {NULL, NULL, NULL, name_i8i8},
    {name_u64u64}
};

static int add(int a, int b) { return a + b; }
static int mul(int a, int b) { return a * b; }
static int sub(int a, int b) { return a - b; }

static int (*handlers[2][3])(int, int) = {{add, mul}, {sub}};

/* A flat list of a two-dimensional table fills the rows one after another. */
static char *elided[2][3] = {"a", "b", "c", "d"};

static char slot0[] = "zero";
static char slot2[] = "two";

static char *designated[4] = {[2] = slot2, [0] = slot0};

int main(void)
{
    /* The object is the size its rows ask for, which is what the image
     * reserved for it. */
    CHECK(sizeof cast_table / sizeof cast_table[0] == 4);
    CHECK(sizeof cast_table[0] / sizeof cast_table[0][0] == COLUMNS);
    CHECK(sizeof cast_table == 4 * COLUMNS * sizeof(char *));

    /* Each value is the address of the object the row named. */
    CHECK(cast_table[0][3] == name_i8i8);
    CHECK(cast_table[0][4] == name_i8u8);
    CHECK(cast_table[0][5] == name_i16i16);
    CHECK(cast_table[0][6] == name_i32i32);
    CHECK(cast_table[0][7] == name_i32i64);
    CHECK(cast_table[0][8] == name_i64i64);
    CHECK(strcmp(cast_table[0][8], "i64i64") == 0);

    /* The entries a row did not write are the zeros the storage starts as,
     * and the row below starts at its own first entry. */
    CHECK(cast_table[0][9] == NULL);
    CHECK(cast_table[0][10] == NULL);
    CHECK(cast_table[1][0] == NULL);
    CHECK(cast_table[1][6] == name_i32i32);
    CHECK(cast_table[1][8] == name_u64u64);
    CHECK(cast_table[1][9] == NULL);
    CHECK(cast_table[2][0] == NULL);
    CHECK(cast_table[2][3] == name_i8i8);
    CHECK(cast_table[2][4] == NULL);
    CHECK(cast_table[2][10] == NULL);
    CHECK(cast_table[3][0] == name_u64u64);
    CHECK(cast_table[3][1] == NULL);

    /* A table of function addresses, with an empty tail in each row. */
    CHECK(handlers[0][0](3, 4) == 7);
    CHECK(handlers[0][1](3, 4) == 12);
    CHECK(handlers[0][2] == NULL);
    CHECK(handlers[1][0](3, 4) == -1);
    CHECK(handlers[1][1] == NULL);
    CHECK(handlers[1][2] == NULL);

    /* A flat list of a table of rows: four entries over two rows of three. */
    CHECK(strcmp(elided[0][0], "a") == 0);
    CHECK(strcmp(elided[0][2], "c") == 0);
    CHECK(strcmp(elided[1][0], "d") == 0);
    CHECK(elided[1][1] == NULL);
    CHECK(elided[1][2] == NULL);

    /* A designator names the element it initializes, in any order. */
    CHECK(designated[0] == slot0);
    CHECK(designated[1] == NULL);
    CHECK(designated[2] == slot2);
    CHECK(designated[3] == NULL);

    return 0;
}
