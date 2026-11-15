/* 0073: a trailing comma before the close of a brace initializer

`int a[] = { 1, 2, 3, };` was refused with `unsupported: an element of a brace
initializer is a written number or an address, found '}'`, and a struct list
with the comma was refused twice, at the `}` and again as a struct brace
initializer that is not implemented.  C99 6.7.8p1 makes `initializer-list ,` a
list, and gcc accepts the comma in every mode.  It blocks every generated table
written one element per line with a trailing comma; in SQLite 3.54.1 the first
one is `sqlite3azCompileOpt[]`.  The loop read the comma as `continue` and came
back to the element arms with `}` as the next token, because the closing brace
was only checked after an element had been read.  The list and pointer readers
now read `}` at the top of the loop, where the comma leaves the cursor.  Fixed
in c9776b0 ("parser: read a trailing comma before the close of a brace list").
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int counted[] = { 1, 2, 3, };
static int sized[3] = { 7, 8, 9, };
static const char *named[] = { "a", "b", };

struct pair {
    int x;
    int y;
};

static struct pair one = { 4, };
static struct pair grid[2] = { { 1, 2, }, { 3, 4, }, };

int main(void)
{
    struct pair here = { 5, 6, };
    int local[] = { 10, 20, 30, };
    int matrix[2][2] = { { 1, 2, }, { 3, 4, }, };
    int n = (int)(sizeof counted / sizeof counted[0]);
    int m = (int)(sizeof local / sizeof local[0]);

    /* The comma ends the list and adds no element: a list read as one longer
     * would size the array wrong and leave a zero at the end. */
    CHECK(n == 3);
    CHECK(m == 3);
    CHECK(counted[0] == 1 && counted[1] == 2 && counted[2] == 3);
    CHECK(local[2] == 30);
    CHECK(sized[0] == 7 && sized[2] == 9);
    CHECK(named[0][0] == 'a' && named[1][0] == 'b');

    /* A struct list keeps the members the comma did not name at zero. */
    CHECK(one.x == 4 && one.y == 0);
    CHECK(grid[1].x == 3 && grid[1].y == 4);
    CHECK(here.x == 5 && here.y == 6);
    CHECK(matrix[1][1] == 4);
    return 0;
}
