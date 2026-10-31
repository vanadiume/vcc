/*
 * The machine builtins at every width their names spell.
 *
 * A regression case is silent and exits zero: the status is the check, and a
 * line of output would be the failure. Each group of assertions answers with
 * its own status when it fails, so a break names which family it is in. The
 * values are the ones gcc 16.2.1 answers on this machine, measured by compiling
 * the same program with it, and the cases that are easy to get wrong on paper
 * are the ones written down here: __builtin_ffs(0) is 0 while bsf of zero is
 * undefined, an unsigned subtraction answers an overflow when the mathematical
 * result is negative, and the 64-bit counts and swaps see all 64 bits.
 *
 * The program declares none of them, which is how the gcc headers are written
 * and how the goldens beside this file reach the same builtins.
 */

int main(void) {
    /* counts of leading and trailing zeros */
    if (__builtin_clz(1u) != 31) return 1;
    if (__builtin_clz(0x80000000u) != 0) return 2;
    if (__builtin_clzl(1ul) != 63) return 3;
    if (__builtin_clzll(1ull) != 63) return 4;
    if (__builtin_ctz(8u) != 3) return 5;
    if (__builtin_ctzl(1ul << 40) != 40) return 6;
    if (__builtin_ctzll(1ull << 63) != 63) return 7;
    /* first set bit, counted from one */
    if (__builtin_ffs(8) != 4) return 8;
    if (__builtin_ffs(0) != 0) return 9;
    if (__builtin_ffsl(1L << 40) != 41) return 10;
    if (__builtin_ffsll(1LL << 63) != 64) return 11;
    if (__builtin_ffsll(0) != 0) return 12;
    /* parity and population count */
    if (__builtin_parity(0u) != 0) return 13;
    if (__builtin_parity(7u) != 1) return 14;
    if (__builtin_parityl(0x8000000000000000UL) != 1) return 15;
    if (__builtin_parityll(0xFFFFFFFFFFFFFFFFull) != 0) return 16;
    if (__builtin_popcount(0xF0F0u) != 8) return 17;
    if (__builtin_popcountl(0xF0F0F0F0F0F0F0F0UL) != 32) return 18;
    if (__builtin_popcountll(0xFFFFFFFFFFFFFFFFull) != 64) return 19;
    if (__builtin_popcountll(0) != 0) return 20;
    /* overflow, signed and unsigned, at both widths the result types name */
    {
        int r = 0;
        if (__builtin_add_overflow(2147483647, 1, &r) != 1) return 21;
        if (r != -2147483648) return 22;
        unsigned u = 0;
        if (__builtin_add_overflow(4294967295u, 2u, &u) != 1) return 23;
        if (u != 1u) return 24;
        if (__builtin_add_overflow(1, 2, &r) != 0) return 25;
        if (r != 3) return 26;
        long long ll = 0;
        if (__builtin_add_overflow(9223372036854775807ll, 1ll, &ll) != 1) return 27;
        if (ll != -9223372036854775807ll - 1) return 28;
        int s = 0;
        if (__builtin_sub_overflow(0, 1, &s) != 0) return 29;
        if (s != -1) return 30;
        if (__builtin_sub_overflow(-2147483647 - 1, 1, &s) != 1) return 31;
        if (s != 2147483647) return 32;
        unsigned us = 0;
        if (__builtin_sub_overflow(0u, 1u, &us) != 1) return 33;
        if (us != 4294967295u) return 34;
        if (__builtin_sub_overflow(5, 2, &s) != 0) return 35;
        if (s != 3) return 36;
        long long lls = 0;
        if (__builtin_sub_overflow(0ll, 9223372036854775807ll, &lls) != 0) return 37;
        if (lls != -9223372036854775807ll) return 38;
        int m = 0;
        if (__builtin_mul_overflow(65536, 65536, &m) != 1) return 39;
        unsigned um = 0;
        if (__builtin_mul_overflow(65536u, 65536u, &um) != 1) return 40;
        if (um != 0u) return 41;
        if (__builtin_mul_overflow(6, 7, &m) != 0) return 42;
        if (m != 42) return 43;
    }
    /* byte reversal */
    if (__builtin_bswap16(0x0102u) != 0x0201u) return 44;
    if (__builtin_bswap32(0x01020304u) != 0x04030201u) return 45;
    if (__builtin_bswap64(0x0102030405060708ull) != 0x0807060504030201ull) return 46;
    /* the promise about alignment, whose value is the pointer itself */
    {
        int storage[8];
        int *p = (int *)__builtin_assume_aligned((void *)storage, 16);
        if (p != storage) return 47;
    }
    /* the same counts over values the program computes, which is where a 32-bit
       operand counted over a whole word instead of over its own bits would show:
       an int with its top bit set has no leading zero, and a value of 0x8000 has
       sixteen of them. */
    {
        int low = -2147483647 - 1;
        int mid = 0x8000;
        unsigned small = 8u;
        unsigned long high = 0x100000000UL;
        unsigned long long top = 0x8000000000000000ull;
        short negative = -1;
        char bit = 0x40;
        if (__builtin_clz((unsigned)mid) != 16) return 48;
        if (__builtin_clz((unsigned)low) != 0) return 49;
        if (__builtin_ctz(small) != 3) return 50;
        if (__builtin_ctzl(high) != 32) return 51;
        if (__builtin_clzll(top) != 0) return 52;
        if (__builtin_ffs(mid) != 16) return 53;
        if (__builtin_popcount((unsigned)negative) != 32) return 54;
        if (__builtin_popcount(bit) != 1) return 55;
        if (__builtin_parity((unsigned)low) != 1) return 56;
        if (__builtin_popcountl(high) != 1) return 57;
        if (__builtin_popcountll(top) != 1) return 58;
        if (__builtin_bswap64(top) != 0x80ull) return 59;
    }
    return 0;
}
