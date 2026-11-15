module ast

import types

// The arena holds every node the parser builds, and the tree refers to a node by
// where it sits in it rather than by a box of its own.
//
// An expression is eight bytes: the shape it is and its position in the arena. A
// boxed sum type was sixteen bytes plus a malloc for the payload, and a child
// link was one of those boxes.
//
// The position is a byte offset into one stream of chunks. The stream is what
// makes the tree flat: nodes sit in the order they were built, the address of a
// node never changes, and nothing is copied when the arena grows because a new
// chunk is a new allocation. A per-shape array would have to double its buffer
// and copy what it held, which is the copy this avoids and the slack it leaves
// behind.
//
// A chunk is a []voidptr rather than a []u8 on purpose: a byte array in this V is
// allocated with a non-scanned flag, so a pointer written into it would not be
// traced by the collector. An array of pointers is scanned, and the payloads
// store strings and pointers of their own.
pub struct Arena {
mut:
	// state is shared by every copy of the arena. A copy made before a pass
	// built more nodes still sees the chunks that pass added, which a copied
	// value would not: the unit the emitter reads and the parser that is still
	// building are two handles on one stream.
	state &ArenaState = unsafe { nil }
}

// ArenaState is the stream itself: the chunks and how much of the last one is
// handed out. It sits behind the Arena handle so that copying an arena copies a
// pointer and not the bookkeeping.
pub struct ArenaState {
mut:
	// chunks are full, and cur is the one being filled. Both are kept for the
	// life of the arena, so an offset into either is still valid at the end of
	// the compile.
	chunks [][]voidptr
	cur    []voidptr
	// used is how many words of cur have been handed out.
	used int
}

// chunk_words is the size of one chunk in words, a megabyte's worth. It is a
// power of two so that an offset becomes a chunk number and a word inside it
// with a division the compiler folds to a shift.
const chunk_words = 131_072

// chunk_bytes is that same size in bytes, the divisor an offset is read with.
const chunk_bytes = chunk_words * 8

// max_arena_bytes is the most of the stream a position can name. An Expr carries
// its position in a u32, so a tree past this would wrap the position and read the
// wrong node; the check in `alloc` turns that into a refusal instead.
const max_arena_bytes = i64(4_294_967_040)

// new_chunk is one zeroed chunk. The unsafe is what says the array of pointers
// is written before anything reads it, which is true: every word comes from a
// payload copied over it.
fn new_chunk() []voidptr {
	return unsafe { []voidptr{len: chunk_words} }
}

// new_arena is an arena with its first chunk ready.
pub fn new_arena() Arena {
	return Arena{
		state: &ArenaState{
			cur: new_chunk()
		}
	}
}

// alloc hands out size bytes of the stream, sixteen-byte aligned, and answers the
// offset it starts at. A node the current chunk cannot hold starts a new one, so
// an address handed out earlier never moves.
fn (mut a Arena) alloc(size int) u32 {
	mut words := (size + 15) / 16 * 2
	if words < 2 {
		words = 2
	}
	if a.state.used + words > chunk_words {
		// The header goes in, not the chunk: appending the slice as a value
		// clones the megabyte it names, and the chunk is the one allocation
		// this arena must not copy.
		unsafe {
			a.state.chunks.push_many(&a.state.cur, 1)
		}
		a.state.cur = new_chunk()
		a.state.used = 0
	}
	total := (a.state.chunks.len * chunk_words + a.state.used) * 8
	if total > max_arena_bytes {
		panic('the arena holds more than four gigabytes of nodes, which a position cannot name')
	}
	offset := u32(total)
	a.state.used += words
	return offset
}

// at is the address an offset names.
@[inline]
fn (a &Arena) at(offset u32) &u8 {
	if isnil(a.state) {
		panic('the tree was read with no arena: a unit built by hand has to carry the one its nodes were put in')
	}
	chunk := int(offset) / chunk_bytes
	within := int(offset) % chunk_bytes
	if chunk < a.state.chunks.len {
		return unsafe { &u8(&a.state.chunks[chunk][within >> 3]) }
	}
	return unsafe { &u8(&a.state.cur[within >> 3]) }
}

// at_mut is the same address with a mutable receiver, which is what writing a
// node into the stream needs.
@[inline]
fn (mut a Arena) at_mut(offset u32) &u8 {
	if isnil(a.state) {
		panic('the tree was built with no arena: a unit built by hand has to carry the one its nodes are put in')
	}
	chunk := int(offset) / chunk_bytes
	within := int(offset) % chunk_bytes
	if chunk < a.state.chunks.len {
		return unsafe { &u8(&a.state.chunks[chunk][within >> 3]) }
	}
	return unsafe { &u8(&a.state.cur[within >> 3]) }
}

// box_extra writes a statement's extra part into the stream and answers the
// pointer the statement holds.
pub fn (mut a Arena) box_extra(extra StmtExtra) &StmtExtra {
	offset := a.alloc(int(sizeof(StmtExtra)))
	unsafe {
		*(&StmtExtra(a.at_mut(offset))) = extra
	}
	return unsafe { &StmtExtra(a.at(offset)) }
}

// box_field writes the member an assignment writes through into the stream.
pub fn (mut a Arena) box_field(field Field) &Field {
	offset := a.alloc(int(sizeof(Field)))
	unsafe {
		*(&Field(a.at_mut(offset))) = field
	}
	return unsafe { &Field(a.at(offset)) }
}

// box_function writes a nested function's declaration into the stream.
pub fn (mut a Arena) box_function(decl FnDecl) &FnDecl {
	offset := a.alloc(int(sizeof(FnDecl)))
	unsafe {
		*(&FnDecl(a.at_mut(offset))) = decl
	}
	return unsafe { &FnDecl(a.at(offset)) }
}

@[inline]
pub fn (mut a Arena) put_binary(node Binary) Expr {
	offset := a.alloc(int(sizeof(Binary)))
	unsafe {
		*(&Binary(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .binary
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) binary(e Expr) &Binary {
	return unsafe { &Binary(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_unary(node Unary) Expr {
	offset := a.alloc(int(sizeof(Unary)))
	unsafe {
		*(&Unary(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .unary
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) unary(e Expr) &Unary {
	return unsafe { &Unary(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_cast(node Cast) Expr {
	offset := a.alloc(int(sizeof(Cast)))
	unsafe {
		*(&Cast(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .cast
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) cast(e Expr) &Cast {
	return unsafe { &Cast(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_int_lit(node IntLit) Expr {
	offset := a.alloc(int(sizeof(IntLit)))
	unsafe {
		*(&IntLit(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .int_lit
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) int_lit(e Expr) &IntLit {
	return unsafe { &IntLit(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_float_lit(node FloatLit) Expr {
	offset := a.alloc(int(sizeof(FloatLit)))
	unsafe {
		*(&FloatLit(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .float_lit
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) float_lit(e Expr) &FloatLit {
	return unsafe { &FloatLit(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_complex_lit(node ComplexLit) Expr {
	offset := a.alloc(int(sizeof(ComplexLit)))
	unsafe {
		*(&ComplexLit(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .complex_lit
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) complex_lit(e Expr) &ComplexLit {
	return unsafe { &ComplexLit(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_ident(node Ident) Expr {
	offset := a.alloc(int(sizeof(Ident)))
	unsafe {
		*(&Ident(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .ident
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) ident(e Expr) &Ident {
	return unsafe { &Ident(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_call(node Call) Expr {
	offset := a.alloc(int(sizeof(Call)))
	unsafe {
		*(&Call(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .call
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) call(e Expr) &Call {
	return unsafe { &Call(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_str_lit(node StrLit) Expr {
	offset := a.alloc(int(sizeof(StrLit)))
	unsafe {
		*(&StrLit(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .str_lit
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) str_lit(e Expr) &StrLit {
	return unsafe { &StrLit(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_index(node Index) Expr {
	offset := a.alloc(int(sizeof(Index)))
	unsafe {
		*(&Index(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .index
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) index(e Expr) &Index {
	return unsafe { &Index(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_field(node Field) Expr {
	offset := a.alloc(int(sizeof(Field)))
	unsafe {
		*(&Field(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .field
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) field(e Expr) &Field {
	return unsafe { &Field(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_inc_dec(node IncDec) Expr {
	offset := a.alloc(int(sizeof(IncDec)))
	unsafe {
		*(&IncDec(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .inc_dec
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) inc_dec(e Expr) &IncDec {
	return unsafe { &IncDec(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_conditional(node Conditional) Expr {
	offset := a.alloc(int(sizeof(Conditional)))
	unsafe {
		*(&Conditional(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .conditional
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) conditional(e Expr) &Conditional {
	return unsafe { &Conditional(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_assign(node Assign) Expr {
	offset := a.alloc(int(sizeof(Assign)))
	unsafe {
		*(&Assign(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .assign
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) assign(e Expr) &Assign {
	return unsafe { &Assign(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_comma(node Comma) Expr {
	offset := a.alloc(int(sizeof(Comma)))
	unsafe {
		*(&Comma(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .comma
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) comma(e Expr) &Comma {
	return unsafe { &Comma(a.at(e.idx)) }
}

@[inline]
pub fn (mut a Arena) put_stmt_expr(node StmtExpr) Expr {
	offset := a.alloc(int(sizeof(StmtExpr)))
	unsafe {
		*(&StmtExpr(a.at_mut(offset))) = node
	}
	return Expr{
		kind: .stmt_expr
		idx:  offset
	}
}

@[inline]
pub fn (a &Arena) stmt_expr(e Expr) &StmtExpr {
	return unsafe { &StmtExpr(a.at(e.idx)) }
}

// typ is the type clause of an expression, whichever shape it is. Every payload
// struct carries one and a reader that only wants the clause should not have to
// know which shape the node is; the zero type is what an absent expression
// answers, which is the unresolved clause a node the model could not type has.
pub fn (a &Arena) typ(e Expr) types.Type {
	return match e.kind {
		.binary { a.binary(e).typ }
		.unary { a.unary(e).typ }
		.cast { a.cast(e).typ }
		.int_lit { a.int_lit(e).typ }
		.float_lit { a.float_lit(e).typ }
		.complex_lit { a.complex_lit(e).typ }
		.ident { a.ident(e).typ }
		.call { a.call(e).typ }
		.str_lit { a.str_lit(e).typ }
		.index { a.index(e).typ }
		.field { a.field(e).typ }
		.inc_dec { a.inc_dec(e).typ }
		.conditional { a.conditional(e).typ }
		.assign { a.assign(e).typ }
		.comma { a.comma(e).typ }
		.stmt_expr { a.stmt_expr(e).typ }
		.none { types.Type{} }
	}
}

// Span is where an expression was written: the line and the column a diagnostic
// about it names.
pub struct Span {
pub:
	line int
	col  int
}

// span is where an expression was written, whichever shape it is.
pub fn (a &Arena) span(e Expr) Span {
	return match e.kind {
		.binary {
			node := a.binary(e)
			Span{node.line, node.col}
		}
		.unary {
			node := a.unary(e)
			Span{node.line, node.col}
		}
		.cast {
			node := a.cast(e)
			Span{node.line, node.col}
		}
		.int_lit {
			node := a.int_lit(e)
			Span{node.line, node.col}
		}
		.float_lit {
			node := a.float_lit(e)
			Span{node.line, node.col}
		}
		.complex_lit {
			node := a.complex_lit(e)
			Span{node.line, node.col}
		}
		.ident {
			node := a.ident(e)
			Span{node.line, node.col}
		}
		.call {
			node := a.call(e)
			Span{node.line, node.col}
		}
		.str_lit {
			node := a.str_lit(e)
			Span{node.line, node.col}
		}
		.index {
			node := a.index(e)
			Span{node.line, node.col}
		}
		.field {
			node := a.field(e)
			Span{node.line, node.col}
		}
		.inc_dec {
			node := a.inc_dec(e)
			Span{node.line, node.col}
		}
		.conditional {
			node := a.conditional(e)
			Span{node.line, node.col}
		}
		.assign {
			node := a.assign(e)
			Span{node.line, node.col}
		}
		.comma {
			node := a.comma(e)
			Span{node.line, node.col}
		}
		.stmt_expr {
			node := a.stmt_expr(e)
			Span{node.line, node.col}
		}
		.none { Span{0, 0} }
	}
}
