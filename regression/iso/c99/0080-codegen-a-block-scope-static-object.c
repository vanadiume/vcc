/* 0080: a block-scope static object keeps its value across calls

A `static` declaration inside a function was read as an automatic object: the
emitter reserved a frame slot for it and wrote the initializer on every call, so
`static int f = 4567; f++;` printed 4567 every time and an uninitialized one
started at whatever the stack held.  C99 6.2.4p3 gives such an object static
storage duration: it is initialized once, before the program starts, and lasts
as long as the program.  The object now lives in the image under a symbol built
from its function and a counter, and every use of the spelling reaches it.  The
declaration reserves no frame slot, so `nm` on an object file shows the object
as a data symbol and two functions may each declare one of the same name.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

struct Pair {
    int left;
    int right;
};

static int grid_step(int row, int column)
{
    static int grid[2][3] = {{1, 2, 3}, {4, 5, 6}};
    grid[row][column] = grid[row][column] + 10;
    return grid[row][column];
}

static int counter(void)
{
    static int value = 3 * 7 + 2;
    return value++;
}

static int zeroed(void)
{
    static int value;
    return value++;
}

static int buffer_put(int at, char c)
{
    static char buffer[8];
    buffer[at] = c;
    return buffer[at];
}

static int pair_step(void)
{
    static struct Pair pair = {1, 2};
    pair.left += 10;
    pair.right += 20;
    return pair.left * 100 + pair.right;
}

static int recurse(int step)
{
    static int total;
    total += step;
    return total;
}

static int first_name(void)
{
    static int value = 100;
    return ++value;
}

static int second_name(void)
{
    static int value = 200;
    return ++value;
}

static const char *message(void)
{
    static const char *text = "static";
    return text;
}

static int *address(void)
{
    static int storage;
    return &storage;
}

static int call_counter(void)
{
    return counter();
}

static int loop_counter(int turns)
{
    int last = 0;
    for (int i = 0; i < turns; i++)
        last = counter();
    return last;
}

static int shadow_parameter(int value)
{
    static int shadowed = 40;
    int sum = value;
    {
        static int value = 7;
        sum += value;
    }
    shadowed += sum;
    return sum + value * 100 + shadowed;
}

int main(void)
{
    int total = 0;

    /* The initializer is a constant expression and runs once. */
    CHECK(counter() == 23);
    CHECK(counter() == 24);
    CHECK(counter() == 25);

    /* No initializer means zero, not stack garbage. */
    CHECK(zeroed() == 0);
    CHECK(zeroed() == 1);

    /* An array object in the image, one element written per call. */
    CHECK(buffer_put(0, 'a') == 'a');
    CHECK(buffer_put(3, 'd') == 'd');
    CHECK(buffer_put(0, 'z') == 'z');

    /* A struct's members are the object's bytes, and both persist. */
    CHECK(pair_step() == 1122);
    CHECK(pair_step() == 2142);

    /* An array of arrays is placed row by row, and each element persists. */
    CHECK(grid_step(1, 2) == 16);
    CHECK(grid_step(0, 0) == 11);
    CHECK(grid_step(1, 2) == 26);
    CHECK(grid_step(1, 1) == 15);

    /* Recursion shares one object rather than one per frame. */
    CHECK(recurse(2) == 2);
    CHECK(recurse(3) == 5);

    /* Two functions may each declare a static of the same name. */
    CHECK(first_name() == 101);
    CHECK(second_name() == 201);
    CHECK(first_name() == 102);

    /* A call from another function and from a loop reaches the same object. */
    for (int i = 0; i < 3; i++) {
        total += counter();
    }
    CHECK(total == 26 + 27 + 28);

    /* The address of the object is one address on every call. */
    CHECK(address() == address());

    /* An initializer that is an address constant. */
    CHECK(message()[0] == 's' && message()[5] == 'c' && message()[6] == 0);

    /* The same object through another function and through a loop. */
    CHECK(call_counter() == 29);
    CHECK(loop_counter(2) == 31);

    /* A block-scope static shadows a parameter of the same name. */
    CHECK(shadow_parameter(3) == 360);
    CHECK(shadow_parameter(3) == 370);

    return 0;
}
