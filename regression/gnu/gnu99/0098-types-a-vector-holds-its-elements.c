/* 0098: CHECK(sizeof(v4) == 16); CHECK(__alignof__(v4) == 16);
 *       CHECK((int)a[0] == 1); CHECK(take(b) == 40);
 *       CHECK((int)c[2] == 39); CHECK((int)d[3] == 36);
 *       CHECK((int)g[3] == 8); CHECK(j[3] == 8);
 *
 * A `__attribute__((vector_size(16)))` typedef names a type of its own: four
 * floats in the sixteen bytes the attribute named, aligned to the sixteen it
 * occupies, initialized one component at a time, indexed as an lvalue, and
 * passed and returned as the object it is. The first CHECKs are the size and
 * the alignment, which gcc gives as the attribute's bytes rather than the
 * component's four. The element read is `a[0]`, a component of the value the
 * brace list wrote, and `a[2] = 9` is the lvalue store the same subscript
 * makes. `make` returns a vector and `take` is handed one by value, which is
 * the two directions an object of the type travels.
 *
 * The arithmetic is GNU C's element-wise form: `a + b` and `a - b` between two
 * vectors of one type, `a * 2` with a scalar converted to the component type,
 * and the same on an integer vector, where the components are ints rather
 * than floats. Every lane is the scalar operator, which is the whole of what
 * element-wise means here.
 *
 * The statuses are gcc 16.2.1's: the same file compiled with
 * `gcc -std=gnu99` exits 0 and prints nothing, and so does this compiler.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

typedef float v4 __attribute__((vector_size(16)));
typedef int v4i __attribute__((vector_size(16)));
typedef double v2 __attribute__((vector_size(16)));

static v4 make(void) {
    v4 a = {10, 20, 30, 40};
    return a;
}

static int take(v4 a) {
    return (int)a[3];
}

static v4i makei(void) {
    v4i a = {1, 2, 3, 4};
    return a;
}

static v2 maked(void) {
    v2 a = {1.5, 2.5};
    return a;
}

int main(void) {
    v4 a = {1, 2, 3, 4};

    CHECK(sizeof(v4) == 16);
    CHECK(__alignof__(v4) == 16);
    CHECK(sizeof(a[0]) == 4);
    CHECK(__alignof__(v4i) == 16);

    CHECK((int)a[0] == 1);
    CHECK((int)a[3] == 4);

    a[2] = 9;
    CHECK((int)a[2] == 9);

    v4 b = make();
    CHECK((int)b[0] == 10);
    CHECK(take(b) == 40);

    v4 c = a + b;
    CHECK((int)c[0] == 11);
    CHECK((int)c[2] == 39);

    v4 d = b - a;
    CHECK((int)d[0] == 9);
    CHECK((int)d[3] == 36);

    v4 e = a * b;
    CHECK((int)e[1] == 40);

    v4 f = b / a;
    CHECK((int)f[0] == 10);

    v4 g = a * 2;
    CHECK((int)g[3] == 8);

    v4 h = {0};
    CHECK((int)h[2] == 0);

    v4i i = makei();
    CHECK(i[3] == 4);

    v4i j = i * 2;
    CHECK(j[3] == 8);

    v2 k = maked();
    CHECK((int)(k[0] * 2.0) == 3);
    CHECK((int)(k[1] * 2.0) == 5);

    return 0;
}
