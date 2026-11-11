module interning

// A repeat is one entry and one buffer, which is the whole point of the table:
// the second ask for a spelling must not allocate a second copy.
fn test_a_repeat_is_one_copy() {
	mut pool := new()
	first := pool.intern('int')
	second := pool.intern('int')
	assert first == second
	assert first.str == second.str
	assert pool.count() == 1
}

// Two spellings that differ by one byte are two entries, so the table is keyed by
// the text and not by its length or its first byte.
fn test_distinct_spellings_are_distinct() {
	mut pool := new()
	assert pool.intern('int') != pool.intern('unsigned int')
	assert pool.intern('int') != pool.intern('unsigned int')
	assert pool.count() == 2
}

// The bytes are copied on the way in, so a caller that frees the buffer it read
// from still holds a string whose text is intact. This is the ownership the
// lexer depends on: a token's text is read out of a byte buffer that is reused
// for the next token.
fn test_borrowed_bytes_are_copied() {
	mut source := []u8{len: 3}
	source[0] = `a`
	source[1] = `b`
	source[2] = `c`
	mut pool := new()
	kept := pool.intern_bytes(&u8(source.data), source.len)
	source[0] = `x`
	assert kept == 'abc'
	assert pool.intern_bytes(&u8(source.data), source.len) == 'xbc'
	assert pool.count() == 2
	unsafe { source.free() }
}

// A string is interned the same way, and what comes back is the pool's copy: a
// caller can free the string it asked about and the answer still reads.
fn test_a_string_is_kept_not_borrowed() {
	mut pool := new()
	text := 'return'.clone()
	kept := pool.intern(text)
	unsafe { text.free() }
	assert kept == 'return'
	assert pool.count() == 1
}

// An empty span is the empty string and holds no entry: nothing in C is spelled
// with no bytes, and an empty key would be one more thing for a lookup to find.
fn test_an_empty_span_is_empty() {
	mut pool := new()
	bytes := []u8{}
	assert pool.intern_bytes(&u8(bytes.data), 0) == ''
	assert pool.count() == 0
}
