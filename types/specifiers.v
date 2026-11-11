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

// TypeWordSpelling is one word of the table with its spelling: from_specifiers
// holds the words and spelling_kind holds only the text they were read from, and
// both ask the same table. A word is added in one place.
struct TypeWordSpelling {
	word     TypeWord
	spelling string
}

const type_word_spellings = [
	TypeWordSpelling{TypeWord.signed_, 'signed'},
	TypeWordSpelling{TypeWord.unsigned_, 'unsigned'},
	TypeWordSpelling{TypeWord.short_, 'short'},
	TypeWordSpelling{TypeWord.void_, 'void'},
	TypeWordSpelling{TypeWord.bool_, '_Bool'},
	TypeWordSpelling{TypeWord.imaginary, '_Imaginary'},
	TypeWordSpelling{TypeWord.complex_, '_Complex'},
	TypeWordSpelling{TypeWord.float_, 'float'},
	TypeWordSpelling{TypeWord.double_, 'double'},
	TypeWordSpelling{TypeWord.char_, 'char'},
	TypeWordSpelling{TypeWord.int128, '__int128'},
	TypeWordSpelling{TypeWord.float128, '__float128'},
	TypeWordSpelling{TypeWord.decimal32, '_Decimal32'},
	TypeWordSpelling{TypeWord.decimal64, '_Decimal64'},
	TypeWordSpelling{TypeWord.decimal128, '_Decimal128'},
]

// span_is says whether the text of written between start and end spells a name.
// The bytes are compared where they lie: cutting the word out with a slice copies
// it, and a copy per word of a spelling was 23.5 MB of the compiler's own
// generated C.
fn span_is(written string, start int, end int, spelling string) bool {
	if end - start != spelling.len {
		return false
	}
	mut i := 0
	for i < spelling.len {
		if written[start + i] != spelling[i] {
			return false
		}
		i++
	}
	return true
}

// span_has_prefix says whether the text of written from start begins a name,
// which is how a _BitInt width is told from any other word without a copy.
fn span_has_prefix(written string, start int, end int, prefix string) bool {
	if end - start < prefix.len {
		return false
	}
	mut i := 0
	for i < prefix.len {
		if written[start + i] != prefix[i] {
			return false
		}
		i++
	}
	return true
}

// type_word_span answers which word of the table the text between start and end
// is, and none for a word the table does not have.
fn type_word_span(written string, start int, end int) ?TypeWord {
	for entry in type_word_spellings {
		if span_is(written, start, end, entry.spelling) {
			return entry.word
		}
	}
	return none
}

// type_word answers which word of the table a spelling word is, and none for a word
// the table does not have.
fn type_word(word string) ?TypeWord {
	return type_word_span(word, 0, word.len)
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
	// other_is_bitint says the last word the table had no flag for was a _BitInt
	// width, which is the only unknown word kind reads. It is a flag of its own
	// because a caller holding a spelling does not copy the word unless it is one.
	other_is_bitint bool
}

// add reads one word of the run and answers whether the run can hold it. A word
// written twice is not a type, except for `long` and `int`, which are counted
// because the table allows each of them to be written twice.
fn (mut r SpecifierRun) add(word string) bool {
	return r.add_span(word, 0, word.len)
}

// add_span is add for a word that is still in the spelling it was read from,
// which is the form a caller that holds the text has. The bytes are compared
// where they lie, so no word is copied out of the spelling to be read.
fn (mut r SpecifierRun) add_span(written string, start int, end int) bool {
	if span_is(written, start, end, 'long') {
		r.longs++
		return true
	}
	if span_is(written, start, end, 'int') {
		r.ints++
		return true
	}
	marker := type_word_span(written, start, end) or {
		r.other_is_bitint = span_has_prefix(written, start, end, '_BitInt(')
		if r.other_is_bitint {
			r.other = written[start..end]
		} else {
			r.other = ''
		}
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
	bitint := r.other_is_bitint
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
	if bitint {
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
// rather than its words: `unsigned long`, `long double _Complex`. The words are
// compared where they lie in the string, so the run costs no allocation, and every
// piece between two spaces is a word, an empty piece included, because splitting
// the same string would produce one and the two answers have to be the same.
fn spelling_kind(written string) ?Kind {
	mut run := SpecifierRun{}
	mut start := 0
	for i := 0; i <= written.len; i++ {
		if i < written.len && written[i] != ` ` {
			continue
		}
		if !run.add_span(written, start, i) {
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
