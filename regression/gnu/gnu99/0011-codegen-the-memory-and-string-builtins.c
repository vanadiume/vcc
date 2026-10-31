/*
 * The memory and string builtins, which are the library functions under the
 * compiler's own name.
 *
 * A regression case is silent and exits zero, and the status is the check: each
 * assertion answers with its own number so a break names which builtin it is in.
 * The answers here are the ones gcc 16.2.1 gives the same program on this
 * machine, measured by compiling it with gcc and reading the status, which is
 * how the two assertions that were wrong on paper were found: strncpy of three
 * bytes over a longer destination leaves no terminator, and a memmove of four
 * bytes from dst to dst + 1 leaves the last byte it copied where the source's
 * fourth byte was.
 *
 * The builtins declare nothing, as gcc's own headers do not, and every call the
 * program makes is a call to the library function: the names in the image are
 * memcpy, memmove, memset, memcmp, memchr, strlen, strnlen, strcmp, strncmp,
 * strcpy and strncpy.
 */
int main(void) {
    char src[16] = "hello, world";
    char dst[16];
    char *p;
    if (__builtin_memcpy(dst, src, 13) != (void *)dst) return 1;
    if (__builtin_strlen(dst) != 12) return 2;
    if (__builtin_strcmp(dst, "hello, world") != 0) return 3;
    if (__builtin_strncmp(dst, "hello", 5) != 0) return 4;
    if (__builtin_strncmp(dst, "hellx", 5) >= 0) return 5;
    if (__builtin_memcmp(dst, src, 12) != 0) return 6;
    if (__builtin_memcmp(dst, "HELLO", 5) <= 0) return 7;
    p = (char *)__builtin_memchr(dst, 'w', 13);
    if (p != dst + 7) return 8;
    if (__builtin_memchr(dst, 'z', 13) != (void *)0) return 9;
    if (__builtin_memset(dst, 'a', 3) != (void *)dst) return 10;
    if (dst[0] != 'a' || dst[2] != 'a' || dst[3] != 'l') return 11;
    if (__builtin_memmove(dst + 1, dst, 4) != (void *)(dst + 1)) return 12;
    if (dst[1] != 'a' || dst[4] != 'l') return 13;
    {
        char word[16] = "abcdef";
        if (__builtin_strnlen(word, 3) != 3) return 14;
        if (__builtin_strnlen(word, 9) != 6) return 15;
    }
    if (__builtin_strcpy(dst, "xy") != dst) return 16;
    if (dst[0] != 'x' || dst[1] != 'y' || dst[2] != 0) return 17;
    if (__builtin_strncpy(dst, "abcdef", 3) != dst) return 18;
    if (dst[0] != 'a' || dst[2] != 'c') return 19;
    if (__builtin_strcmp("abc", "abd") >= 0) return 20;
    return 0;
}
