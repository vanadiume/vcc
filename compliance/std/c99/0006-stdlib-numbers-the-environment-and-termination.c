/* 0006: stdlib-numbers-the-environment-and-termination
 *
 * ISO/IEC 9899:1999 7.20.2: rand is a pseudo-random sequence a seed restarts,
 * 7.20.4: getenv and system reach the host environment, and 7.20.4.2: atexit
 * registers functions that exit runs in reverse order of registration.
 */

#include <stdio.h>
#include <stdlib.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

/* The handler registered first runs last, so it is the one that can tell
 * whether the other one already ran. _Exit overrides the status main chose,
 * which is how a wrong order reaches the runner. */
static int ran;

static void registered_first(void)
{
    if (ran != 1) {
        printf("FAIL %s:%d: atexit handlers ran out of order\n", __FILE__,
               __LINE__);
        _Exit(1);
    }
    ran = 2;
}

static void registered_second(void)
{
    ran = 1;
}

int main(void)
{
    unsigned int first[8];
    unsigned int second[8];
    int i;
    int in_range = 1;
    const char *path;
    int status;

    /* 7.20.2.2: the sequence from one seed is the sequence from that seed */
    srand(42);
    for (i = 0; i < 8; i++) {
        first[i] = (unsigned int)rand();
    }
    srand(42);
    for (i = 0; i < 8; i++) {
        second[i] = (unsigned int)rand();
    }
    for (i = 0; i < 8; i++) {
        CHECK(first[i] == second[i]);
    }
    for (i = 1; i < 8; i++) {
        if (first[i] != first[0]) {
            in_range = 0;
        }
    }
    CHECK(!in_range); /* one seed does not hand out one value */

    /* 7.20.2p1 and 7.20.2.1: rand stays inside [0, RAND_MAX] */
    CHECK(RAND_MAX >= 32767);
    for (i = 0; i < 256; i++) {
        int value = rand();
        CHECK(value >= 0);
        CHECK(value <= RAND_MAX);
    }

    /* 7.20.4.5: getenv returns the value or the null pointer */
    path = getenv("PATH");
    CHECK(path != NULL && path[0] != '\0');
    CHECK(getenv("VCC_LIBRARY_TEST_VARIABLE_THAT_IS_NOT_SET") == NULL);

    /* 7.20.4.6: a null string asks whether a command processor exists */
    CHECK(system(NULL) != 0);
    status = system("exit 0");
    CHECK(status == 0);

    /* 7.20.4.1: exit runs the handlers, last registered first */
    CHECK(atexit(registered_first) == 0);
    CHECK(atexit(registered_second) == 0);
    exit(0);
    return 0;
}
