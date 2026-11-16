/* 1156: CHECK(groups[0].run == run)
 *
 * ISO/IEC 9899:1999 6.7.8p4: an initializer for an object of static storage
 * duration must be a constant expression, and the address of a function is an
 * address constant. A table of function pointers declared static inside a
 * function is the shape this test holds.
 *
 * unimplemented: a block-scope static object is initialized with an address
 * constant that is not a string literal.
 */

#include <stdio.h>

static void run(void) { }

struct group {
    const char *name;
    void (*run)(void);
};

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    static const struct group groups[] = {
        { "run", run }
    };
    CHECK(groups[0].run == run);
    CHECK(groups[0].name[0] == 'r');
    return 0;
}
