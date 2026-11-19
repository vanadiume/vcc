module codegen

import ast
import types

// The runtime's helpers for the complex product and the complex quotient.
//
// gcc 16.2.1 emits a call for both operators on all three complex types, at -O0
// and at -O2: `__muldc3` and `__divdc3` for `double _Complex`, `__mulsc3` and
// `__divsc3` for `float _Complex`, and `__mulxc3` and `__divxc3` for `long
// double _Complex`. A sum and a difference are one instruction per component and
// stay inline, which is what gcc does with them too.
//
// The reason the two operators are calls is the boundary C99's Annex G
// describes: a product or a quotient whose partial results overflow or underflow
// even though the answer does not needs an operand scaled before the arithmetic,
// and a recovery at the end for an operand that is an infinity or a zero. That is
// the arithmetic the helpers carry, and a formula written inline is wrong where
// they are not the same thing. Measured on gcc 16.2.1 at -O0 -fno-builtin, `a /
// (0.0 + 0.0i)` for `a = 1e308 + 1e308i` prints `inf inf`, and the inline formula
// this back end used to emit printed `-nan -nan`.
//
// The names and the signatures are the runtime's, which is libvcc, and libvcc
// answers them with libgcc's arithmetic. The argument lists are what gcc's own
// builtins take: four scalars, the left operand's real and imaginary parts and
// then the right operand's. Measured from gcc 16.2.1 on x86-64:
//
//	double _Complex __muldc3(double a, double b, double c, double d) with the four
//	arguments in xmm0 to xmm3 and the answer in xmm0 (real) and xmm1 (imaginary);
//	float _Complex __mulsc3(float, float, float, float) with the four arguments in
//	xmm0 to xmm3 and the answer packed into xmm0; and
//	long double _Complex __mulxc3(long double, long double, long double, long
//	double) with the four arguments on the stack, sixteen bytes each, and the
//	answer on the x87 stack, st0 the real part and st1 the imaginary one.
//
// So the components are read out of the two complex slots and placed as ordinary
// scalar arguments, and the answer is written into the destination the way the
// value of a call is written, which is what emit_complex_call already does for a
// complex return.

// complex_helper_name is the runtime helper one complex operator is a call to, or
// none for an operator this back end writes inline.
fn complex_helper_name(op string, kind types.Kind) ?string {
	if op != '*' && op != '/' {
		return none
	}
	product := op == '*'
	match kind {
		.complex_float {
			return if product { '__mulsc3' } else { '__divsc3' }
		}
		.complex_double {
			return if product { '__muldc3' } else { '__divdc3' }
		}
		.complex_long_double {
			return if product { '__mulxc3' } else { '__divxc3' }
		}
		else {
			return none
		}
	}
}

// emit_complex_helper writes a product or a quotient of two register-width
// complex values as the runtime's call. The four components are loaded into the
// four floating-point argument registers in the order the helper's parameters
// name them, and each is loaded straight out of its operand's slot: nothing goes
// through the scratch register, which is where half of the answer comes back.
fn (mut e Emitter) emit_complex_helper(dest Slot, step ast.Binary, left Slot, right Slot, name string) !void {
	line := step.line
	col := step.col
	frame := e.frame_pointer(line, col)!
	single := complex_component_single(step.typ)
	width := complex_component_width(step.typ)
	mut position := 0
	for slot in [left, right] {
		mut component := 0
		for component < 2 {
			register := e.target.float_arg_reg(position) or {
				e.diagnostics << problem(line, col, 'unsupported: the call to ${name} hands over ${position + 1} floating-point arguments, and this machine has not got that many argument registers')
				return error('no floating argument register')
			}
			e.load_complex_component(frame, register, slot.offset + component * width, single)!
			position++
			component++
		}
	}
	e.write_runtime_helper_call(name, line, col)
	return e.store_complex_helper_result(dest, single, line, col)
}

// store_complex_helper_result writes the value a helper answered into the
// destination slot. A `float _Complex` is one eightbyte with the two floats
// packed into it, which is the eight bytes of the register the answer arrives in;
// a `double _Complex` is two, one per floating-point register.
fn (mut e Emitter) store_complex_helper_result(dest Slot, single bool, line int, col int) !void {
	frame := e.frame_pointer(line, col)!
	base := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(dest.offset), base))
	e.store_return_eightbyte(base, 0, 8, true, line, col)!
	if single {
		return
	}
	e.append(e.target.add_immediate(base, 8))
	return e.store_return_eightbyte(base, 1, 8, true, line, col)
}

// emit_long_double_complex_helper is the same call for `long double _Complex`,
// whose components travel in memory rather than in the floating-point file.
//
// The four arguments are pushed from the last to the first and, within one, from
// its high word to its low, so the first argument ends at the lowest address and
// the callee reads the four in the order its parameters name them. The four make
// eight eight-byte words, so the call is made with the stack aligned the way the
// convention wants it without a padding word. The answer comes back on the x87
// stack with the real part on top, so it is popped into the destination in that
// order.
fn (mut e Emitter) emit_long_double_complex_helper(dest Slot, step ast.Binary, left Slot, right Slot, name string) !void {
	line := step.line
	col := step.col
	frame := e.frame_pointer(line, col)!
	component := complex_long_double_component
	entry := e.stack_pushed
	mut argument := 3
	for argument >= 0 {
		offset := if argument < 2 {
			left.offset + argument * component
		} else {
			right.offset + (argument - 2) * component
		}
		mut word := 1
		for word >= 0 {
			address := e.accumulator(line, col)!
			e.append(e.target.address_of_slot(frame, i32(offset + word * 8), address))
			value := e.scratch(line, col)!
			e.append(e.target.load_indirect(address, value, 8)!)
			e.append(e.target.push_register(value))
			e.stack_pushed += 8
			word--
		}
		argument--
	}
	e.write_runtime_helper_call(name, line, col)
	e.release_call_stack(entry)
	e.pop_extended_component(frame, dest.offset, line, col)!
	return e.pop_extended_component(frame, dest.offset + component, line, col)
}
