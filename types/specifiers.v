module types

// The type words a declaration writes in front of a declarator, and the type they
// add up to.
//
// The standard lists the combinations in 6.7.2.2 and this is that list: a
// combination the standard does not have is refused rather than read as the
// nearest one, because `long float` and `unsigned void` are programs gcc refuses
// and a compiler that accepted them would be reading C nobody wrote. The words
// may be written in any order, and the two that may be written twice are `long`
// and `int`.

// TypeWord is the table of words a type spelling is made of, one flag each. A run
// is a handful of words and no caller keeps the answer, so the table is flags and
// not a map: a map spends an entry per word on every question codegen asks of a
// spelling, for an answer that is compared once and dropped.
@[flag]
enum TypeWord {
	signed_
	unsigned_
	short_
	void_
	bool_
	imaginary
	complex_
	float_
	double_
	char_
	int128
	float128
	decimal32
	decimal64
	decimal128
}

// type_word answers which word of the table a spelling word is, and none for a word
// the table does not have.
fn type_word(word string) ?TypeWord {
	match word {
		'signed' { return .signed_ }
		'unsigned' { return .unsigned_ }
		'short' { return .short_ }
		'void' { return .void_ }
		'_Bool' { return .bool_ }
		'_Imaginary' { return .imaginary }
		'_Complex' { return .complex_ }
		'float' { return .float_ }
		'double' { return .double_ }
		'char' { return .char_ }
		'__int128' { return .int128 }
		'__float128' { return .float128 }
		'_Decimal32' { return .decimal32 }
		'_Decimal64' { return .decimal64 }
		'_Decimal128' { return .decimal128 }
		else { return none }
	}
}

// SpecifierRun is a run of type words as it is read, whether the caller holds the
// words or the spelling they were cut from: from_specifiers fills it from a list,
// spelling_kind fills it from a string, and kind reads the answer out of it.
struct SpecifierRun {
mut:
	longs int
	ints  int
	seen  TypeWord
	// others is how many words stand beside `long` and `int`, each written once.
	// It is the length of the set the table below asks about: `void` alone, one
	// word and `long` with `_Complex`, and so on.
	others int
	// other is the one word the table has no flag for. A run keeps it because a
	// `_BitInt` width is read off the word; a run with more than one is refused
	// below wherever the count of words is a type's, and the last is the one kept.
	other string
}

// add reads one word of the run and answers whether the run can hold it. A word
// written twice is not a type, except for `long` and `int`, which are counted
// because the table allows each of them to be written twice.
fn (mut r SpecifierRun) add(word string) bool {
	if word == 'long' {
		r.longs++
		return true
	}
	if word == 'int' {
		r.ints++
		return true
	}
	marker := type_word(word) or {
		r.other = word
		r.others++
		return true
	}
	if r.seen.has(marker) {
		return false
	}
	r.seen = r.seen | marker
	r.others++
	return true
}

// kind answers the kind the run names, and none when the run is not one the
// standard has a type for.
fn (r &SpecifierRun) kind() ?Kind {
	longs := r.longs
	ints := r.ints
	others := r.others
	seen := r.seen
	other := r.other
	if longs > 2 || ints > 1 {
		return none
	}
	if seen.has(.signed_) && seen.has(.unsigned_) {
		return none
	}
	if seen.has(.void_) {
		if others == 1 && longs == 0 && ints == 0 {
			return Kind.void_
		}
		return none
	}
	if seen.has(.bool_) {
		if others == 1 && longs == 0 && ints == 0 {
			return Kind.bool_
		}
		return none
	}
	if seen.has(.imaginary) {
		// C99 makes _Imaginary optional, and this compiler has no model for an
		// imaginary type. It is refused by name rather than read as a complex
		// one, which is a different type.
		return none
	}
	if seen.has(.complex_) {
		if seen.has(.float_) {
			if others == 2 && longs == 0 && ints == 0 {
				return Kind.complex_float
			}
			return none
		}
		if seen.has(.double_) {
			if ints != 0 || seen.has(.short_) {
				return none
			}
			if longs == 1 && others == 2 {
				return Kind.complex_long_double
			}
			if longs == 0 && others == 2 {
				return Kind.complex_double
			}
			return none
		}
		if others == 1 && longs == 0 && ints == 0 {
			// A lone `_Complex` is `double _Complex`. Measured: gcc 16.2.1
			// says the two are compatible types and that both occupy 16 bytes.
			return Kind.complex_double
		}
		return none
	}
	if seen.has(.float_) {
		if others == 1 && longs == 0 && ints == 0 {
			return Kind.float
		}
		return none
	}
	if seen.has(.double_) {
		if ints != 0 || seen.has(.short_) {
			return none
		}
		if longs == 1 && others == 1 {
			return Kind.long_double
		}
		if longs == 0 && others == 1 {
			return Kind.double
		}
		return none
	}
	if seen.has(.char_) {
		if longs != 0 || ints != 0 || seen.has(.short_) {
			return none
		}
		if seen.has(.signed_) {
			return Kind.signed_char
		}
		if seen.has(.unsigned_) {
			return Kind.unsigned_char
		}
		if others == 1 {
			return Kind.char_
		}
		return none
	}
	if seen.has(.int128) {
		// The 128-bit type is gcc's, and the combinations it takes are the
		// ones the other integer words take: `signed` adds nothing to it and
		// `unsigned` is the other type. Measured on gcc 16.2.1: `signed
		// __int128` is `__int128`, `unsigned __int128` is a different type of
		// the same width, `long __int128` and `__int128 short` are refused, and
		// the words may be written in either order, so `__int128 unsigned` is
		// the unsigned type.
		if longs != 0 || ints != 0 || seen.has(.short_) || seen.has(.float_) || seen.has(.double_) {
			return none
		}
		if seen.has(.signed_) && seen.has(.unsigned_) {
			return none
		}
		if seen.has(.unsigned_) {
			return Kind.unsigned_int128
		}
		if others == 1 || (others == 2 && seen.has(.signed_)) {
			return Kind.int128
		}
		return none
	}
	if seen.has(.float128) {
		// The 128-bit floating type is gcc's, and the words it takes are none:
		// measured on gcc 16.2.1, `signed __float128`, `unsigned __float128`,
		// `long __float128`, `short __float128` and `__float128 __float128`
		// are each refused, and `__float128` alone is the one spelling. The
		// header glibc writes for it is `typedef __float128 _Float128;`, so a
		// program that names `_Float128` reaches the same kind through that
		// typedef.
		if longs != 0 || ints != 0 || others != 1 {
			return none
		}
		return Kind.float128
	}
	if seen.has(.decimal32) || seen.has(.decimal64) || seen.has(.decimal128) {
		// A decimal type is one word and takes no other: measured on gcc
		// 16.2.1, `signed _Decimal32`, `unsigned _Decimal32`, `long
		// _Decimal32` and `short _Decimal32` are each refused with `both
		// 'signed' and '_Decimal32' in declaration specifiers`, and two of
		// the three decimal words together with `two or more data types in
		// declaration specifiers`. Only a qualifier may stand beside one,
		// which the caller reads before these words arrive.
		if longs != 0 || ints != 0 || others != 1 {
			return none
		}
		if seen.has(.decimal32) {
			return Kind.decimal32
		}
		if seen.has(.decimal64) {
			return Kind.decimal64
		}
		return Kind.decimal128
	}
	if other.starts_with('_BitInt(') {
		word := other
		// A _BitInt specifier wrote its width in parentheses, and the
		// word arrives here whole: `_BitInt(128)`. The width is the
		// type, and the one value this compiler has of that kind is the
		// 128-bit pair, so a width it has no value for is refused
		// rather than answered with the nearest type it does have.
		// Measured on gcc 16.2.1: `_BitInt(65)` occupies sixteen bytes
		// and wraps at 65 bits, which is not what the pair does.
		//
		// The word is read here as well as where the width was read,
		// because these words are what any caller hands in.
		if longs != 0 || ints != 0 || seen.has(.short_) || seen.has(.float_) || seen.has(.double_) {
			return none
		}
		if seen.has(.signed_) && seen.has(.unsigned_) {
			return none
		}
		if word.len < 10 {
			return none
		}
		// The width is written in digits, and a word that is not is
		// refused here rather than handed to a reader that would answer
		// for whatever prefix of it it could read.
		mut digits := true
		for ch in word[8..word.len - 1] {
			if ch < 48 || ch > 57 {
				digits = false
				break
			}
		}
		if !digits {
			return none
		}
		if word[8..word.len - 1].int() != 128 {
			return none
		}
		if seen.has(.unsigned_) {
			return Kind.unsigned_int128
		}
		if others == 1 || (others == 2 && seen.has(.signed_)) {
			return Kind.int128
		}
		return none
	}
	if seen.has(.short_) {
		if longs != 0 {
			return none
		}
		if seen.has(.signed_) {
			return Kind.short
		}
		if seen.has(.unsigned_) {
			return Kind.unsigned_short
		}
		if others == 1 {
			return Kind.short
		}
		return none
	}
	if longs > 0 {
		// `long` and `long long` name a type on their own, and `int` written
		// with either of them adds nothing: `long int` is a long.
		if others == 0 {
			if longs == 1 {
				return Kind.long
			}
			return Kind.long_long
		}
		if others == 1 && seen.has(.signed_) {
			if longs == 1 {
				return Kind.long
			}
			return Kind.long_long
		}
		if others == 1 && seen.has(.unsigned_) {
			if longs == 1 {
				return Kind.unsigned_long
			}
			return Kind.unsigned_long_long
		}
		return none
	}
	if seen.has(.signed_) && others == 1 {
		return Kind.int_
	}
	if seen.has(.unsigned_) && others == 1 {
		return Kind.unsigned_int
	}
	if others == 0 && ints == 1 {
		return Kind.int_
	}
	return none
}

// from_specifiers answers the kind a run of type words names, and none when the
// run is not one the standard has a type for. The caller reports the refusal: it
// knows where in the file the words were written.
pub fn from_specifiers(words []string) ?Kind {
	mut run := SpecifierRun{}
	for word in words {
		if !run.add(word) {
			return none
		}
	}
	return run.kind()
}

// from_words is from_specifiers with the kind turned into the type, which is what
// a declaration needs. A run of words the table does not have is refused here and
// reported by the reader that wrote them down.
pub fn from_words(words []string) ?Type {
	kind := from_specifiers(words) or { return none }
	return scalar(kind)
}

// spelling_kind is from_specifiers for a caller that holds the spelling of a type
// rather than its words: `unsigned long`, `long double _Complex`. The words are cut
// out of the string as it is read, so the run costs no allocation, and every piece
// between two spaces is a word, an empty piece included, because splitting the same
// string would produce one and the two answers have to be the same.
fn spelling_kind(written string) ?Kind {
	mut run := SpecifierRun{}
	mut start := 0
	for i := 0; i <= written.len; i++ {
		if i < written.len && written[i] != ` ` {
			continue
		}
		if !run.add(written[start..i]) {
			return none
		}
		start = i + 1
	}
	return run.kind()
}

// from_spelling is from_words for a spelling: the type a string like `unsigned
// long` names, and none for a string the standard has no type for.
pub fn from_spelling(written string) ?Type {
	kind := spelling_kind(written) or { return none }
	return scalar(kind)
}
