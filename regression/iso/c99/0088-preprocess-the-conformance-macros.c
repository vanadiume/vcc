/* 0088: the implementation-conformance macros are predefined

`__STDC_HOSTED__` and `__STDC_VERSION__` were the only `__STDC_` names
predefined, so portable code testing `__STDC_ISO_10646__`, the IEC 60559
macros or the C11 UTF macros took the "not supported" path.  The fix defines
the claims that describe the target in every mode and the C11 UTF macros in the
modes whose standard has them; the two complex claims stay undefined because
the tree's complex support is not finished (see the `_Complex` row in
standard/features.v).

This case is compiled `-std=c99`, which is where the two sides separate: the
three IEC 60559 and ISO 10646 claims are about the target and are defined, and
the C11 UTF macros are not.  gcc 16.2.1 answers the same way under the same
flag, measured with `gcc -std=c99 -dM -E -x c /dev/null`.  The two complex
claims are absent even after <stdio.h> has been read, because the predefines
also carry `__GCC_IEC_559_COMPLEX=0`: glibc's <stdc-predef.h> defines the two
macros unless that name is predefined and zero.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

#if !defined(__STDC_ISO_10646__)
#error "__STDC_ISO_10646__ must be defined"
#endif
#if !defined(__STDC_IEC_559__)
#error "__STDC_IEC_559__ must be defined"
#endif
#if !defined(__STDC_IEC_60559_BFP__)
#error "__STDC_IEC_60559_BFP__ must be defined"
#endif

#if defined(__STDC_UTF_16__)
#error "__STDC_UTF_16__ is C11's and must not be defined under -std=c99"
#endif
#if defined(__STDC_UTF_32__)
#error "__STDC_UTF_32__ is C11's and must not be defined under -std=c99"
#endif
#if defined(__STDC_IEC_559_COMPLEX__)
#error "__STDC_IEC_559_COMPLEX__ must not be defined: complex support is unfinished"
#endif
#if defined(__STDC_IEC_60559_COMPLEX__)
#error "__STDC_IEC_60559_COMPLEX__ must not be defined: complex support is unfinished"
#endif

int main(void)
{
    CHECK(__STDC_ISO_10646__ == 201706L);
    CHECK(__STDC_IEC_559__ == 1);
    CHECK(__STDC_IEC_60559_BFP__ == 201404L);
    return 0;
}
