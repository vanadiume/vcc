/*
 * The memory and string builtins at their edges: zero counts, overlapping moves in
 * both directions, empty strings, a terminator at the last counted byte, and the
 * fill strncpy writes past the end of its source. Each group answers with its own
 * status so a break names the function it is in.
 *
 * These are the cases the library function is easy to get wrong at, and every
 * expectation here is gcc 16.2.1's: the same file compiled with it exits 0. Two
 * of them were wrong when they were worked out on paper and gcc's answers are
 * what this case holds, which is why a case that a second compiler agrees with is
 * worth more than one that reads correctly.
 */
int main(void) {
    char a[16] = "abc";
    char b[16] = "xyz";
    char big[32];

    /* memset: a count of zero writes nothing */
    __builtin_memset(big, 0x41, 8);
    if (big[0] != 'A' || big[7] != 'A') return 1;
    __builtin_memset(big, 0x42, 0);
    if (big[0] != 'A') return 2;

    /* memcpy forwards, including a zero count */
    __builtin_memset(big, 0, 32);
    __builtin_memcpy(big, "hello", 5);
    if (big[0] != 'h' || big[4] != 'o' || big[5] != 0) return 3;
    __builtin_memcpy(big, "zzz", 0);
    if (big[0] != 'h') return 4;

    /* memmove: destination above the source, overlapping */
    __builtin_memset(big, 0, 32);
    __builtin_memcpy(big, "abcdef", 6);
    __builtin_memmove(big + 2, big, 4);
    if (big[2] != 'a' || big[5] != 'd' || big[6] != 0) return 5;
    /* memmove: destination below the source, overlapping */
    __builtin_memset(big, 0, 32);
    __builtin_memcpy(big, "abcdef", 6);
    __builtin_memmove(big, big + 2, 4);
    if (big[0] != 'c' || big[3] != 'f' || big[4] != 'e') return 6;
    /* memmove: the same pointer and a zero count */
    __builtin_memmove(big, big, 4);
    if (big[0] != 'c') return 7;

    /* memcmp */
    if (__builtin_memcmp("abc", "abc", 3) != 0) return 8;
    if (__builtin_memcmp("abc", "abd", 3) >= 0) return 9;
    if (__builtin_memcmp("abd", "abc", 3) <= 0) return 10;
    if (__builtin_memcmp("abc", "xyz", 0) != 0) return 11;
    if (__builtin_memcmp("\xff", "\x01", 1) <= 0) return 12;

    /* memchr */
    if ((char *)__builtin_memchr("abc", 'a', 3) == (void *)0) return 13;
    if ((char *)__builtin_memchr("abc", 'c', 3) != "abc" + 2) return 14;
    if (__builtin_memchr("abc", 'z', 3) != (void *)0) return 15;
    if (__builtin_memchr("abc", 'a', 0) != (void *)0) return 16;

    /* strlen and strnlen */
    if (__builtin_strlen("") != 0) return 17;
    if (__builtin_strlen("a") != 1) return 18;
    if (__builtin_strnlen("abc", 0) != 0) return 19;

    /* strcmp and strncmp */
    if (__builtin_strcmp("", "") != 0) return 20;
    if (__builtin_strcmp("abc", "abc") != 0) return 21;
    if (__builtin_strcmp("abc", "ab") <= 0) return 22;
    if (__builtin_strcmp("ab", "abc") >= 0) return 23;
    if (__builtin_strncmp("abc", "abd", 0) != 0) return 24;
    if (__builtin_strncmp("abc", "abd", 2) != 0) return 25;
    if (__builtin_strncmp("abc", "abd", 3) >= 0) return 26;

    /* strcpy and strncpy */
    __builtin_memset(a, 'x', 16);
    if (__builtin_strcpy(a, "") != a) return 27;
    if (a[0] != 0 || a[1] != 'x') return 28;
    __builtin_strcpy(a, "hi");
    if (a[0] != 'h' || a[1] != 'i' || a[2] != 0) return 29;
    __builtin_memset(b, 'y', 16);
    __builtin_strncpy(b, "ab", 5);
    if (b[0] != 'a' || b[1] != 'b' || b[2] != 0 || b[4] != 0 || b[5] != 'y') return 30;
    __builtin_memset(b, 'y', 16);
    __builtin_strncpy(b, "abcdef", 3);
    if (b[0] != 'a' || b[2] != 'c' || b[3] != 'y') return 31;
    __builtin_strncpy(b, "abcdef", 0);
    if (b[0] != 'a') return 32;
    return 0;
}
