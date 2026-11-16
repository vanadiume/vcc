#include <stdio.h>

int main(void) {
    int a = 1'000'000;
    int b = 0x1'FF;
    int c = 0b1010'1010;
    double d = 1'000.5;
    printf("%d %d %d %.1f\n", a, b, c, d);
    return 0;
}
