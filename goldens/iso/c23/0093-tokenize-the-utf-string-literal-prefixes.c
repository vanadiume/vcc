#include <uchar.h>
#include <stdio.h>

int main(void) {
    const char16_t *a = u"hi";
    const char32_t *b = U"hi";
    int c = u8'c';
    printf("%d %d %d\n", (int)a[0], (int)b[0], c);
    return 0;
}
