module codegen

import ast
import backend

// The memory and string builtins, emitted where they are written.
//
// Each of these names a library function, and gcc answers a call to one with a
// call to the other unless it expands it inline. This compiler cannot: a program
// built with -nostdlib has no library to call, and a program built for a target
// with no C library has none either, so a call left for the loader is a program
// that dies at its first byte. What is emitted instead is the function's own work,
// a byte at a time: a loop with a cursor per pointer and a count that counts down,
// which is what the library function does at its simplest.
//
// The bytes are read and written unsigned, because a string is compared and
// searched as `unsigned char` and a signed byte would make strcmp answer the wrong
// sign above 0x7f. A count is a word, and every count that arrives narrower was
// widened where the argument was evaluated.
//
// Slots in the frame hold the pointers and the count, and the three registers are
// loaded from them for one step and left free for the next. Nothing is kept in a
// register across a step that needs a register for something else, which is what
// keeps a loop body short enough to read.

// emit_memory_builtin answers one of the memory and string builtins by name. A
// name this dispatcher is handed is one the reader's own list routed here, so a
// name with no arm is this compiler's mistake rather than the program's.
fn (mut e Emitter) emit_memory_builtin(call ast.Call, depth int) !void {
	match call.name {
		'__builtin_memset' {
			return e.emit_memset(call, depth)
		}
		'__builtin_memcpy' {
			return e.emit_memcpy(call, depth)
		}
		'__builtin_memmove' {
			return e.emit_memmove(call, depth)
		}
		'__builtin_memcmp' {
			return e.emit_memcmp(call, depth)
		}
		'__builtin_memchr' {
			return e.emit_memchr(call, depth)
		}
		'__builtin_strlen' {
			return e.emit_strlen(call, depth)
		}
		'__builtin_strnlen' {
			return e.emit_strnlen(call, depth)
		}
		'__builtin_strcmp' {
			return e.emit_strcmp(call, depth)
		}
		'__builtin_strncmp' {
			return e.emit_strncmp(call, depth)
		}
		'__builtin_strcpy' {
			return e.emit_strcpy(call, depth)
		}
		'__builtin_strncpy' {
			return e.emit_strncpy(call, depth)
		}
		else {
			e.diagnostics << problem(call.line, call.col, 'internal: ${call.name} reached the memory builtins with no implementation')
			return error('no memory builtin implementation')
		}
	}
}

// builtin_argument evaluates one argument of a builtin and leaves it in a slot of
// the frame as a word. A pointer is a word already; an int is widened, so a count
// the program wrote as four bytes is read as the value it is and not with whatever
// the register held above it.
fn (mut e Emitter) builtin_argument(argument ast.Expr, depth int, line int, col int) !Slot {
	slot := e.reserve(e.target.word_size)
	e.emit_expr_at(argument, depth)!
	e.extend_operand_to_word(argument, line, col)!
	e.store_accumulator(slot, line, col)!
	return slot
}

// word_from and word_to move one slot of the frame through a register. Every
// pointer and count these loops keep lives in a slot, so a step reads the slot it
// needs, uses it, and puts it back.
fn (mut e Emitter) word_from(slot Slot, register backend.Register, line int, col int) !void {
	base := e.frame_pointer(line, col)!
	e.append(e.target.load_slot(base, i32(slot.offset), register, e.target.word_size)!)
}

fn (mut e Emitter) word_to(register backend.Register, slot Slot, line int, col int) !void {
	base := e.frame_pointer(line, col)!
	e.append(e.target.store_slot(base, i32(slot.offset), register, e.target.word_size)!)
}

// byte_from reads one unsigned byte at an address into a register, and byte_to
// writes a register's low byte at an address.
fn (mut e Emitter) byte_from(address backend.Register, dst backend.Register) !void {
	e.append(e.target.load_indirect_unsigned(address, dst, 1)!)
}

fn (mut e Emitter) byte_to(address backend.Register, src backend.Register) !void {
	e.append(e.target.store_indirect(address, src, 1)!)
}

// step_pointer moves one of these cursors by one byte, which is how every loop
// here walks the memory it was handed.
fn (mut e Emitter) step_pointer(slot Slot, line int, col int) !void {
	register := e.accumulator(line, col)!
	e.word_from(slot, register, line, col)!
	e.append(e.target.add_immediate(register, 1))
	e.word_to(register, slot, line, col)!
}

// step_pointer_back moves a cursor towards lower addresses, which is the direction
// an overlapping copy takes when the destination is above the source.
fn (mut e Emitter) step_pointer_back(slot Slot, line int, col int) !void {
	register := e.accumulator(line, col)!
	e.word_from(slot, register, line, col)!
	e.append(e.target.add_immediate(register, -1))
	e.word_to(register, slot, line, col)!
}

// countdown is the shape every loop here uses: it jumps to `done` when the count
// has reached zero and otherwise takes one off it. The count in the slot is always
// the number of bytes still to go, so one instruction both asks and steps.
fn (mut e Emitter) countdown(count Slot, done string, line int, col int) !void {
	register := e.accumulator(line, col)!
	e.word_from(count, register, line, col)!
	e.append(e.target.test_word(register)!)
	e.branch(.branch_zero, done, line, col)!
	e.append(e.target.add_immediate(register, -1))
	e.word_to(register, count, line, col)!
}

// copy_byte_at moves one byte from the source cursor to the destination cursor and
// steps neither, because the two directions step differently: a forward copy walks
// on and a backward copy walks back, and a step taken here would be taken twice by
// one of them.
fn (mut e Emitter) copy_byte_at(source Slot, destination Slot, line int, col int) !void {
	register := e.accumulator(line, col)!
	scratch := e.scratch(line, col)!
	e.word_from(source, register, line, col)!
	e.byte_from(register, scratch)!
	e.word_from(destination, register, line, col)!
	e.byte_to(register, scratch)!
}

// copy_byte is one byte copied and both cursors stepped forward, which is the body
// of memcpy, memmove's forward direction and strcpy's loop before its terminator
// stops it.
fn (mut e Emitter) copy_byte(source Slot, destination Slot, line int, col int) !void {
	e.copy_byte_at(source, destination, line, col)!
	e.step_pointer(source, line, col)!
	e.step_pointer(destination, line, col)!
}

// emit_memset is `memset`: the count bytes at the destination, each set to the low
// byte of the second argument. The byte is masked to eight bits because the
// parameter is an int and C stores its low byte.
fn (mut e Emitter) emit_memset(call ast.Call, depth int) !void {
	dst := e.builtin_argument(call.args[0], depth + 1, call.line, call.col)!
	byte := e.builtin_argument(call.args[1], depth + 2, call.line, call.col)!
	count := e.builtin_argument(call.args[2], depth + 3, call.line, call.col)!
	cursor := e.reserve(e.target.word_size)
	register := e.accumulator(call.line, call.col)!
	scratch := e.scratch(call.line, call.col)!
	e.word_from(dst, register, call.line, call.col)!
	e.word_to(register, cursor, call.line, call.col)!
	top := e.label()
	done := e.label()
	e.place(top)
	e.countdown(count, done, call.line, call.col)!
	e.word_from(cursor, register, call.line, call.col)!
	e.word_from(byte, scratch, call.line, call.col)!
	e.append(e.target.and_immediate(scratch, 0xff)!)
	e.byte_to(register, scratch)!
	e.step_pointer(cursor, call.line, call.col)!
	e.jump(top)!
	e.place(done)
	e.word_from(dst, register, call.line, call.col)!
}

// emit_memcpy is `memcpy`: the count bytes at the source copied to the
// destination, forwards, one at a time. A destination that overlaps the source
// from above is what memmove exists for, and this copies forwards regardless.
fn (mut e Emitter) emit_memcpy(call ast.Call, depth int) !void {
	dst := e.builtin_argument(call.args[0], depth + 1, call.line, call.col)!
	src := e.builtin_argument(call.args[1], depth + 2, call.line, call.col)!
	count := e.builtin_argument(call.args[2], depth + 3, call.line, call.col)!
	destination := e.reserve(e.target.word_size)
	source := e.reserve(e.target.word_size)
	register := e.accumulator(call.line, call.col)!
	e.word_from(dst, register, call.line, call.col)!
	e.word_to(register, destination, call.line, call.col)!
	e.word_from(src, register, call.line, call.col)!
	e.word_to(register, source, call.line, call.col)!
	top := e.label()
	done := e.label()
	e.place(top)
	e.countdown(count, done, call.line, call.col)!
	e.copy_byte(source, destination, call.line, call.col)!
	e.jump(top)!
	e.place(done)
	e.word_from(dst, register, call.line, call.col)!
}

// emit_memmove is `memcpy` that is allowed to overlap: the copy runs forwards when
// the destination is at or below the source, and backwards when it is above it,
// because that is the direction in which a byte is written only after it has been
// read. The test is C's own: a forward copy is correct while `dst <= src` or
// `src + n <= dst`, and only the case in between needs the other direction.
fn (mut e Emitter) emit_memmove(call ast.Call, depth int) !void {
	dst := e.builtin_argument(call.args[0], depth + 1, call.line, call.col)!
	src := e.builtin_argument(call.args[1], depth + 2, call.line, call.col)!
	count := e.builtin_argument(call.args[2], depth + 3, call.line, call.col)!
	destination := e.reserve(e.target.word_size)
	source := e.reserve(e.target.word_size)
	register := e.accumulator(call.line, call.col)!
	scratch := e.scratch(call.line, call.col)!
	remainder := e.remainder(call.line, call.col)!
	e.word_from(dst, register, call.line, call.col)!
	e.word_to(register, destination, call.line, call.col)!
	e.word_from(src, register, call.line, call.col)!
	e.word_to(register, source, call.line, call.col)!
	forward := e.label()
	done := e.label()
	// The distance between the two pointers decides the direction, and one
	// subtraction answers it for both cases. dst - src wraps around when the
	// destination is below the source, so the distance is then a number no count
	// can reach and the copy is forward; a destination at the source is forward
	// too, because there is nothing to overlap; and only a distance smaller than
	// the count means the two regions overlap with the destination above.
	e.word_from(dst, register, call.line, call.col)!
	e.word_from(src, scratch, call.line, call.col)!
	e.append(e.target.subtract_word(register, scratch)!)
	e.append(e.target.test_word(register)!)
	e.branch(.branch_zero, forward, call.line, call.col)!
	e.word_from(count, scratch, call.line, call.col)!
	e.append(e.target.subtract_word(scratch, register)!)
	e.append(e.target.set_condition(backend.Condition.below, remainder)!)
	e.append(e.target.widen_byte(remainder)!)
	e.append(e.target.test_word(remainder)!)
	e.branch(.branch_nonzero, forward, call.line, call.col)!
	// The backward direction: both cursors start at the last byte and walk down.
	e.word_from(destination, register, call.line, call.col)!
	e.word_from(count, scratch, call.line, call.col)!
	e.append(e.target.add_reg64(register, scratch))
	e.append(e.target.add_immediate(register, -1))
	e.word_to(register, destination, call.line, call.col)!
	e.word_from(source, register, call.line, call.col)!
	e.word_from(count, scratch, call.line, call.col)!
	e.append(e.target.add_reg64(register, scratch))
	e.append(e.target.add_immediate(register, -1))
	e.word_to(register, source, call.line, call.col)!
	back := e.label()
	e.place(back)
	e.countdown(count, done, call.line, call.col)!
	e.copy_byte_at(source, destination, call.line, call.col)!
	e.step_pointer_back(source, call.line, call.col)!
	e.step_pointer_back(destination, call.line, call.col)!
	e.jump(back)!
	e.place(forward)
	e.countdown(count, done, call.line, call.col)!
	e.copy_byte(source, destination, call.line, call.col)!
	e.jump(forward)!
	e.place(done)
	e.word_from(dst, register, call.line, call.col)!
}

// compare_bytes compares the two bytes the cursors are at: the flags are left as
// their unsigned difference and the value is that difference, so a caller that
// branches on the zero flag and a caller that returns it read the same subtraction.
fn (mut e Emitter) compare_bytes(source Slot, destination Slot, line int, col int) !void {
	register := e.accumulator(line, col)!
	scratch := e.scratch(line, col)!
	e.word_from(source, register, line, col)!
	e.byte_from(register, scratch)!
	remainder := e.remainder(line, col)!
	e.append(e.target.move_register64(remainder, scratch)!)
	e.word_from(destination, register, line, col)!
	e.byte_from(register, scratch)!
	e.append(e.target.move_register64(register, remainder)!)
	e.append(e.target.subtract_word(register, scratch)!)
}

// emit_memcmp is `memcmp`: the first pair of bytes that differ answers their
// unsigned difference, and the count running out answers zero.
fn (mut e Emitter) emit_memcmp(call ast.Call, depth int) !void {
	first := e.builtin_argument(call.args[0], depth + 1, call.line, call.col)!
	second := e.builtin_argument(call.args[1], depth + 2, call.line, call.col)!
	count := e.builtin_argument(call.args[2], depth + 3, call.line, call.col)!
	a := e.reserve(e.target.word_size)
	b := e.reserve(e.target.word_size)
	register := e.accumulator(call.line, call.col)!
	e.word_from(first, register, call.line, call.col)!
	e.word_to(register, a, call.line, call.col)!
	e.word_from(second, register, call.line, call.col)!
	e.word_to(register, b, call.line, call.col)!
	top := e.label()
	equal := e.label()
	different := e.label()
	end := e.label()
	e.place(top)
	e.countdown(count, equal, call.line, call.col)!
	e.compare_bytes(a, b, call.line, call.col)!
	e.branch(.branch_nonzero, different, call.line, call.col)!
	e.step_pointer(a, call.line, call.col)!
	e.step_pointer(b, call.line, call.col)!
	e.jump(top)!
	e.place(different)
	// The accumulator already holds the difference the branch read.
	e.jump(end)!
	e.place(equal)
	e.append(e.target.xor_word(register, register)!)
	e.place(end)
}

// emit_memchr is `memchr`: the address of the first byte equal to the second
// argument's low byte, or null when the count runs out first.
fn (mut e Emitter) emit_memchr(call ast.Call, depth int) !void {
	first := e.builtin_argument(call.args[0], depth + 1, call.line, call.col)!
	wanted := e.builtin_argument(call.args[1], depth + 2, call.line, call.col)!
	count := e.builtin_argument(call.args[2], depth + 3, call.line, call.col)!
	cursor := e.reserve(e.target.word_size)
	register := e.accumulator(call.line, call.col)!
	scratch := e.scratch(call.line, call.col)!
	e.word_from(first, register, call.line, call.col)!
	e.word_to(register, cursor, call.line, call.col)!
	top := e.label()
	found := e.label()
	missing := e.label()
	end := e.label()
	e.place(top)
	e.countdown(count, missing, call.line, call.col)!
	e.word_from(cursor, register, call.line, call.col)!
	e.byte_from(register, scratch)!
	e.word_from(wanted, register, call.line, call.col)!
	e.append(e.target.and_immediate(register, 0xff)!)
	e.append(e.target.subtract_word(scratch, register)!)
	e.append(e.target.test_word(scratch)!)
	e.branch(.branch_zero, found, call.line, call.col)!
	e.step_pointer(cursor, call.line, call.col)!
	e.jump(top)!
	e.place(found)
	e.word_from(cursor, register, call.line, call.col)!
	e.jump(end)!
	e.place(missing)
	e.append(e.target.xor_word(register, register)!)
	e.place(end)
}

// emit_strlen is `strlen`: a count that steps until the byte under the cursor is
// the terminator. The cursor and the count are two slots and one loop.
fn (mut e Emitter) emit_strlen(call ast.Call, depth int) !void {
	text := e.builtin_argument(call.args[0], depth + 1, call.line, call.col)!
	cursor := e.reserve(e.target.word_size)
	length := e.reserve(e.target.word_size)
	register := e.accumulator(call.line, call.col)!
	scratch := e.scratch(call.line, call.col)!
	e.word_from(text, register, call.line, call.col)!
	e.word_to(register, cursor, call.line, call.col)!
	e.append(e.target.xor_word(register, register)!)
	e.word_to(register, length, call.line, call.col)!
	top := e.label()
	done := e.label()
	e.place(top)
	e.word_from(cursor, register, call.line, call.col)!
	e.byte_from(register, scratch)!
	e.append(e.target.test_word(scratch)!)
	e.branch(.branch_zero, done, call.line, call.col)!
	e.step_pointer(cursor, call.line, call.col)!
	e.word_from(length, register, call.line, call.col)!
	e.append(e.target.add_immediate(register, 1))
	e.word_to(register, length, call.line, call.col)!
	e.jump(top)!
	e.place(done)
	e.word_from(length, register, call.line, call.col)!
}

// emit_strnlen is `strnlen`: `strlen` that stops at a count as well as at the
// terminator, so a string that is not terminated answers the count.
fn (mut e Emitter) emit_strnlen(call ast.Call, depth int) !void {
	text := e.builtin_argument(call.args[0], depth + 1, call.line, call.col)!
	count := e.builtin_argument(call.args[1], depth + 2, call.line, call.col)!
	cursor := e.reserve(e.target.word_size)
	length := e.reserve(e.target.word_size)
	register := e.accumulator(call.line, call.col)!
	scratch := e.scratch(call.line, call.col)!
	e.word_from(text, register, call.line, call.col)!
	e.word_to(register, cursor, call.line, call.col)!
	e.append(e.target.xor_word(register, register)!)
	e.word_to(register, length, call.line, call.col)!
	top := e.label()
	done := e.label()
	e.place(top)
	// The count is the limit on how far the walk may go, and the length is what it
	// has gone: they are two numbers because the byte that stops the walk is not
	// part of the answer.
	e.countdown(count, done, call.line, call.col)!
	e.word_from(cursor, register, call.line, call.col)!
	e.byte_from(register, scratch)!
	e.append(e.target.test_word(scratch)!)
	e.branch(.branch_zero, done, call.line, call.col)!
	e.step_pointer(cursor, call.line, call.col)!
	e.word_from(length, register, call.line, call.col)!
	e.append(e.target.add_immediate(register, 1))
	e.word_to(register, length, call.line, call.col)!
	e.jump(top)!
	e.place(done)
	e.word_from(length, register, call.line, call.col)!
}

// emit_strcmp is `strcmp`: the first pair of bytes that differ answers their
// unsigned difference, and a pair that are both the terminator answers zero.
fn (mut e Emitter) emit_strcmp(call ast.Call, depth int) !void {
	first := e.builtin_argument(call.args[0], depth + 1, call.line, call.col)!
	second := e.builtin_argument(call.args[1], depth + 2, call.line, call.col)!
	a := e.reserve(e.target.word_size)
	b := e.reserve(e.target.word_size)
	register := e.accumulator(call.line, call.col)!
	scratch := e.scratch(call.line, call.col)!
	e.word_from(first, register, call.line, call.col)!
	e.word_to(register, a, call.line, call.col)!
	e.word_from(second, register, call.line, call.col)!
	e.word_to(register, b, call.line, call.col)!
	top := e.label()
	different := e.label()
	equal := e.label()
	end := e.label()
	e.place(top)
	e.compare_bytes(a, b, call.line, call.col)!
	e.branch(.branch_nonzero, different, call.line, call.col)!
	// Equal so far: a terminator here is the end of both strings.
	e.word_from(a, register, call.line, call.col)!
	e.byte_from(register, scratch)!
	e.append(e.target.test_word(scratch)!)
	e.branch(.branch_zero, equal, call.line, call.col)!
	e.step_pointer(a, call.line, call.col)!
	e.step_pointer(b, call.line, call.col)!
	e.jump(top)!
	e.place(different)
	e.jump(end)!
	e.place(equal)
	e.append(e.target.xor_word(register, register)!)
	e.place(end)
}

// emit_strncmp is `strncmp`: `strcmp` that stops at a count, and a count that runs
// out before a difference answers zero.
fn (mut e Emitter) emit_strncmp(call ast.Call, depth int) !void {
	first := e.builtin_argument(call.args[0], depth + 1, call.line, call.col)!
	second := e.builtin_argument(call.args[1], depth + 2, call.line, call.col)!
	count := e.builtin_argument(call.args[2], depth + 3, call.line, call.col)!
	a := e.reserve(e.target.word_size)
	b := e.reserve(e.target.word_size)
	register := e.accumulator(call.line, call.col)!
	e.word_from(first, register, call.line, call.col)!
	e.word_to(register, a, call.line, call.col)!
	e.word_from(second, register, call.line, call.col)!
	e.word_to(register, b, call.line, call.col)!
	top := e.label()
	different := e.label()
	equal := e.label()
	end := e.label()
	e.place(top)
	e.countdown(count, equal, call.line, call.col)!
	e.compare_bytes(a, b, call.line, call.col)!
	e.branch(.branch_nonzero, different, call.line, call.col)!
	e.step_pointer(a, call.line, call.col)!
	e.step_pointer(b, call.line, call.col)!
	e.jump(top)!
	e.place(different)
	e.jump(end)!
	e.place(equal)
	e.append(e.target.xor_word(register, register)!)
	e.place(end)
}

// emit_strcpy is `strcpy`: bytes copied until one of them is the terminator, which
// is copied as well.
fn (mut e Emitter) emit_strcpy(call ast.Call, depth int) !void {
	dst := e.builtin_argument(call.args[0], depth + 1, call.line, call.col)!
	src := e.builtin_argument(call.args[1], depth + 2, call.line, call.col)!
	destination := e.reserve(e.target.word_size)
	source := e.reserve(e.target.word_size)
	register := e.accumulator(call.line, call.col)!
	scratch := e.scratch(call.line, call.col)!
	e.word_from(dst, register, call.line, call.col)!
	e.word_to(register, destination, call.line, call.col)!
	e.word_from(src, register, call.line, call.col)!
	e.word_to(register, source, call.line, call.col)!
	top := e.label()
	done := e.label()
	e.place(top)
	e.word_from(source, register, call.line, call.col)!
	e.byte_from(register, scratch)!
	e.word_from(destination, register, call.line, call.col)!
	e.byte_to(register, scratch)!
	e.append(e.target.test_word(scratch)!)
	e.branch(.branch_zero, done, call.line, call.col)!
	e.step_pointer(source, call.line, call.col)!
	e.step_pointer(destination, call.line, call.col)!
	e.jump(top)!
	e.place(done)
	e.word_from(dst, register, call.line, call.col)!
}

// emit_strncpy is `strncpy`: at most the count bytes copied from the source, and
// the rest of the count filled with the terminator once the source's is reached.
// The second loop is that fill, and it is entered only by a terminator.
fn (mut e Emitter) emit_strncpy(call ast.Call, depth int) !void {
	dst := e.builtin_argument(call.args[0], depth + 1, call.line, call.col)!
	src := e.builtin_argument(call.args[1], depth + 2, call.line, call.col)!
	count := e.builtin_argument(call.args[2], depth + 3, call.line, call.col)!
	destination := e.reserve(e.target.word_size)
	source := e.reserve(e.target.word_size)
	register := e.accumulator(call.line, call.col)!
	scratch := e.scratch(call.line, call.col)!
	e.word_from(dst, register, call.line, call.col)!
	e.word_to(register, destination, call.line, call.col)!
	e.word_from(src, register, call.line, call.col)!
	e.word_to(register, source, call.line, call.col)!
	top := e.label()
	fill := e.label()
	done := e.label()
	e.place(top)
	e.countdown(count, done, call.line, call.col)!
	e.word_from(source, register, call.line, call.col)!
	e.byte_from(register, scratch)!
	e.word_from(destination, register, call.line, call.col)!
	e.byte_to(register, scratch)!
	e.append(e.target.test_word(scratch)!)
	e.branch(.branch_zero, fill, call.line, call.col)!
	e.step_pointer(source, call.line, call.col)!
	e.step_pointer(destination, call.line, call.col)!
	e.jump(top)!
	e.place(fill)
	// The terminator is already written, so the fill starts after it and writes the
	// bytes the source did not have, which is the rest of the count.
	e.step_pointer(destination, call.line, call.col)!
	fill_top := e.label()
	e.place(fill_top)
	e.countdown(count, done, call.line, call.col)!
	e.word_from(destination, register, call.line, call.col)!
	e.append(e.target.xor_word(scratch, scratch)!)
	e.byte_to(register, scratch)!
	e.step_pointer(destination, call.line, call.col)!
	e.jump(fill_top)!
	e.place(done)
	e.word_from(dst, register, call.line, call.col)!
}
