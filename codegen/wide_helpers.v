module codegen

import ast
import backend

// The runtime's helpers for the 128-bit operations.
//
// A value of 128 bits is two words, and the machine has an instruction for some
// of what can be done with a pair and not for the rest. gcc 16.2.1 on x86-64 at
// -O0 is what this split was read off: a multiplication of two pairs is written
// inline (two imulq for the cross products and a mulq for the low product), a
// shift is a shldq or a shrdq, and a division and a remainder are the only
// operations left as calls, `call __divti3` and `call __umodti3`. This back end
// keeps that shape: a division is always a call to the runtime, and the
// operations the machine has instructions for are written inline unless
// -fignore-natives asked for the runtime's copy of them anyway.
//
// The names and the signatures are libgcc's, because that is what libvcc.a
// defines. libvcc spells a pair as a structure of two words rather than as
// C's 128-bit type, and on x86-64 SysV such an argument travels in two
// consecutive integer registers, in rdi and rsi for the first and rdx and rcx
// for the second, and is returned in rax and rdx. That return is the pair the
// accumulator and the register above it already form, so the answer needs no
// move.

// wide_helper_name is the runtime helper a 128-bit operation is written as, or
// none for an operator the machine computes with its own instructions and no
// helper is named for.
fn wide_helper_name(op string, unsigned bool) ?string {
	match op {
		'/' {
			return if unsigned { '__udivti3' } else { '__divti3' }
		}
		'%' {
			return if unsigned { '__umodti3' } else { '__modti3' }
		}
		'*' {
			return '__multi3'
		}
		'<<' {
			return '__ashlti3'
		}
		'>>' {
			return if unsigned { '__lshrti3' } else { '__ashrti3' }
		}
		else {
			return none
		}
	}
}

// wide_helper_is_native says whether the machine computes the operation with
// its own instructions. A multiplication and a shift of a pair do; a division
// does not, which is why gcc leaves that one to the runtime at every level.
fn wide_helper_is_native(op string) bool {
	return op in ['*', '<<', '>>']
}

// emits_wide_helper says whether an operation is written as a call to the
// runtime. One the machine has no instruction for always is; one it has an
// instruction for is written inline unless -fignore-natives asked for the
// helper, which is how the runtime's own copy of the operation is reached.
fn (e Emitter) emits_wide_helper(op string) bool {
	return !wide_helper_is_native(op) || e.ignore_natives
}

// load_wide_helper_pair loads one pair of a helper call into the two integer
// registers that carry argument `position`. The pair is read out of its frame
// slot rather than out of the registers the operation was computed in, because
// the second argument's low word is the register the first argument's high word
// sits in: loading one pair from a register pair into the argument registers
// would overwrite the other half of the first.
fn (mut e Emitter) load_wide_helper_pair(slot Slot, position int, line int, col int) !void {
	registers := e.pair_argument_registers(position) or {
		e.diagnostics << problem(line, col, 'internal: the call to a 128-bit runtime helper needs two argument registers at position ${position}, and this machine has not got them')
		return error('no pair of argument registers')
	}
	frame := e.slot_base_register(slot, line, col)!
	word := e.target.word_size
	e.append(e.target.load_slot(frame, slot.offset, registers[0], word)!)
	e.append(e.target.load_slot(frame, slot.offset + word, registers[1], word)!)
}

// write_wide_helper_call writes the call itself. A name the unit defines is a
// direct call, which is what a runtime compiled by this compiler and a test
// that supplies its own helper get; otherwise the name is an import, and an
// object leaves it for a linker while a program reaches it through the slot the
// loader fills in.
fn (mut e Emitter) write_wide_helper_call(name string) {
	if name in e.program.defined {
		e.reference(e.target.call_near(0), .call_local, name, '')
		return
	}
	e.import_symbol(name)
	if e.compile_only {
		e.reference(e.target.call_near(0), .call_import, name, '')
	} else {
		e.reference(e.target.call_slot(0), .call_import, name, '')
	}
}

// emit_wide_binary_helper writes a 128-bit division, remainder or
// multiplication as the runtime's call. Both operands are already in their
// slots, and the call leaves its answer in the pair the accumulator and the
// register above it form.
fn (mut e Emitter) emit_wide_binary_helper(step ast.Binary, left Slot, right Slot, name string) !void {
	e.load_wide_helper_pair(left, 0, step.line, step.col)!
	e.load_wide_helper_pair(right, 2, step.line, step.col)!
	e.write_wide_helper_call(name)
}

// emit_wide_shift_helper writes a 128-bit shift by a constant count as the
// runtime's call. The count is an int rather than a pair, so it travels in the
// third integer argument register, after the pair's two.
fn (mut e Emitter) emit_wide_shift_helper_constant(step ast.Binary, left Slot, bits u8, name string) !void {
	count := e.shift_helper_count_register(step.line, step.col)!
	e.append(e.target.move_immediate32(count, u32(bits))!)
	e.load_wide_helper_pair(left, 0, step.line, step.col)!
	e.write_wide_helper_call(name)
}

// emit_wide_shift_helper_register is the same call with a count the program
// works out. The machine reads a shift count from one register, and the
// convention hands the third argument over in another, so the count is moved
// into the argument register before the pair is loaded: the pair's own load
// does not disturb it, because the two pairs of registers do not overlap.
fn (mut e Emitter) emit_wide_shift_helper_register(step ast.Binary, left Slot, count backend.Register, name string) !void {
	argument := e.shift_helper_count_register(step.line, step.col)!
	e.append(e.target.move_register32(argument, count)!)
	e.load_wide_helper_pair(left, 0, step.line, step.col)!
	e.write_wide_helper_call(name)
}

// shift_helper_count_register is where the third integer argument travels,
// which is where a shift helper reads its count.
fn (mut e Emitter) shift_helper_count_register(line int, col int) !backend.Register {
	return e.target.arg_reg(2) or {
		e.diagnostics << problem(line, col, 'internal: the call to a shift helper takes its count as the third argument, and this machine has no register for it')
		return error('no argument register for a shift count')
	}
}
