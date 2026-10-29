/* 0067: a long double _Complex narrowed to double _Complex keeps its parts

A value of the extended complex type converted to one of the two register
widths was read one component at a time by the instruction for an eight-byte
component.  An extended component is sixteen bytes in memory, so the real part
of the result was the first eight bytes of that representation and not the
value: the program ran, exited 1, and nothing was reported.  Fixed in a40d322
("codegen: narrow a long double _Complex value to the register widths"). */

int main(void)
{
    double _Complex z = 1.0 + 2.0i;
    long double _Complex wide = z; /* widening: this half always worked */
    double _Complex back = wide;   /* narrowing: this half did not */
    if (__real__ back != 1.0)
        return 1;
    if (__imag__ back != 2.0)
        return 2;
    float _Complex narrow = wide;
    if (__real__ narrow != 1.0f)
        return 3;
    if (__imag__ narrow != 2.0f)
        return 4;
    return 0;
}
