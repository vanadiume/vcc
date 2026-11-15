/* 0089: the size of an inferred pointer array

`const char *s[] = {"a", "b"};` at file scope was refused with
`unsupported: sizeof asks how many bytes s takes, and this compiler has no size
for const char *[]`.  The same shape with `int a[] = {1, 2, 3}` compiled: the
scalar path completed the array's type from its initializer and the file-scope
pointer path only counted the elements, so the type kept the array the empty
brackets named.  Fixed in 58f1d71 ("parser: complete an inferred pointer
array's type from its initializer"). */

#include <stdio.h>

const char *s[] = {"a", "b"};

int main(void)
{
    if (sizeof s != 2 * sizeof(char *)) { fprintf(stderr, "an inferred pointer array has the wrong size\n"); return 1; }
    if (sizeof s[0] != sizeof(char *)) { fprintf(stderr, "an element of an inferred pointer array has the wrong size\n"); return 1; }
    if (s[0][0] != 'a' || s[1][0] != 'b') { fprintf(stderr, "an inferred pointer array holds the wrong addresses\n"); return 1; }
    {
        const char *local[] = {"c"};
        if (sizeof local != sizeof(char *)) { fprintf(stderr, "an inferred pointer array in a body has the wrong size\n"); return 1; }
    }
    return 0;
}
