module interning

// A Pool keeps one copy of each byte string it is handed, so a spelling the
// program reads a hundred thousand times costs one buffer instead of a hundred
// thousand. The compiler runs without a collector, which is what makes the
// sharing worth a lookup: a string copied per token is never freed, and the
// copies of a name like `int` or a punctuator like `(` are most of the text a
// translation unit allocates.
//
// Text handed in may be a slice of a buffer its owner is free to release, so a
// miss copies the bytes and the table keeps that copy. A hit returns the copy
// already kept and allocates nothing, which is the point of asking: what the
// caller gets back has bytes that live as long as the pool does.
//
// A pool is heap-allocated on purpose: it is made in one stage and used by every
// file that stage opens, so a reference to it outlives the call that made it.
@[heap]
pub struct Pool {
mut:
	entries map[string]string
}

// new makes an empty pool. One pool belongs to one translation unit's read, so
// the names that file shares with itself are the ones that get deduplicated.
pub fn new() &Pool {
	return &Pool{
		entries: map[string]string{}
	}
}

// count is how many distinct strings the pool holds, which is what a test reads
// to tell a repeat that was a hit from a second copy.
pub fn (p &Pool) count() int {
	return p.entries.len
}

// intern answers the pool's one copy of text, keeping a copy of text the first
// time it is asked.
pub fn (mut p Pool) intern(text string) string {
	if kept := p.entries[text] {
		return kept
	}
	return p.keep(text)
}

// intern_bytes is intern for bytes the caller holds no string over: the text of
// a token collected into a byte buffer, which would otherwise have to be copied
// out with bytestr before anyone could look at it. The bytes are hashed where
// they lie and only a miss copies them, so a caller whose buffer is reused or
// freed after the call still gets a string it can keep.
pub fn (mut p Pool) intern_bytes(bytes &u8, len int) string {
	if len <= 0 {
		return ''
	}
	borrowed := unsafe { tos(bytes, len) }
	if kept := p.entries[borrowed] {
		return kept
	}
	return p.keep(borrowed)
}

// keep copies text into the table and answers the copy. The key and the value
// are the same string, so a later lookup hashes a buffer the pool owns and not
// the caller's, which may be gone by then.
fn (mut p Pool) keep(text string) string {
	kept := text.clone()
	p.entries[kept] = kept
	return kept
}
