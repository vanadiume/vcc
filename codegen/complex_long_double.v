module codegen

import backend
import types
import ast

// `long double _Complex` is the extended type's complex form: two sixteen-byte
// components, the real part first, thirty-two bytes in all and aligned sixteen.
// The model already sizes it (types/object.v), and this file is what carries a
// value of it through the back end.
//
// A value travels the way a complex value does and the way a long double does at
// once: an expression of the type is worth the address of its bytes rather than
// a value in a register, because no register is thirty-two bytes wide. A
// component is read and written with the x87 moves the scalar type already uses,
// and the arithmetic is the x87 stack's.
//
// The convention, measured with gcc 16.2.1 at -O0: an argument is thirty-two
// bytes in memory, real part at the lower address; a return leaves st(0) the
// real part and st(1) the imaginary one, so a caller pops the real part first.

// complex_long_double_component is one component: the extended format's sixteen
// bytes, which is what fldt and fstpt move.
const complex_long_double_component = long_double_bytes

// complex_long_double_bytes is the whole object: two components.
const complex_long_double_bytes = 2 * complex_long_double_component

// is_long_double_complex says whether a type is the extended complex type.
fn (e Emitter) is_long_double_complex(t types.Type) bool {
	return t.kind == .complex_long_double
}

// returns_a_complex_long_double says whether a call hands a value of the
// extended complex type back: the type the reader resolved onto the call says
// so, and the return type a declaration this file read says so where the reader
// left the call's own type unresolved.
fn (e Emitter) returns_a_complex_long_double(call ast.Call) bool {
	if call.typ.kind == .complex_long_double {
		return true
	}
	return e.complex_long_double_returns[call.name]
}

// complex_long_double_parameter says whether parameter `position` of a call is
// the extended complex type: the declaration's parameter list says so, whether
// or not this file wrote the body, and none of the two tables a call reads for a
// parameter type names it as a system this back end can carry alone.
fn (e Emitter) complex_long_double_parameter(call ast.Call, position int) bool {
	if parameter := e.call_parameter(call, position) {
		return parameter.kind == .complex_long_double
	}
	if kinds := e.complex_long_double_params[call.name] {
		if position < kinds.len {
			return kinds[position]
		}
	}
	return false
}

// complex_long_double_argument says whether argument `position` is handed over
// as a thirty-two byte object in memory, which is a parameter of the extended
// complex type or, where nothing declares it, an argument that is itself one.
// It is the same question long_double_argument asks of the scalar type: a value
// this type is never carried by a register, so a call has to hand the bytes over
// rather than the address of them.
fn (e Emitter) complex_long_double_argument(call ast.Call, position int, arg ast.Expr) bool {
	if e.complex_long_double_parameter(call, position) {
		return true
	}
	if parameter := e.call_parameter(call, position) {
		// The callee names its parameters and none of them is this type, so the
		// argument is converted to whatever the parameter is and not handed over
		// as an extended complex value.
		_ = parameter
		return false
	}
	if kinds := e.complex_long_double_params[call.name] {
		if position < kinds.len {
			return kinds[position]
		}
	}
	return e.expr_type(arg).kind == .complex_long_double
}

// complex_long_double_argument_address leaves in the accumulator the address of
// the thirty-two bytes an argument of the extended complex type is handed over
// as. An argument that already is one is its own storage; a real one is turned
// into a complex value with a zero imaginary part first, which is 6.3.2.2 and
// what makes `csqrtl(4.0L)` hand over `4.0L + 0.0Li`.
fn (mut e Emitter) complex_long_double_argument_address(arg ast.Expr, depth int) !void {
	line := e.expr_line(arg)
	col := e.expr_col(arg)
	destination := types.complex_long_double_type()
	object := e.complex_object_as(arg, destination, depth)!
	frame := e.frame_pointer(line, col)!
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(object.offset), register))
}

// emit_long_double_complex_into writes the value of an expression into an object
// of the extended complex type. It is emit_complex_into_type for this one type,
// whose components are the extended format and whose arithmetic is the x87
// stack's rather than one instruction per component in the floating file.
fn (mut e Emitter) emit_long_double_complex_into(dest Slot, expr ast.Expr, depth int) !void {
	line := e.expr_line(expr)
	col := e.expr_col(expr)
	typ := e.expr_type(expr)
	if typ.is_arithmetic() && !typ.kind.is_complex() {
		return e.emit_real_into_complex_long_double(dest, expr, depth)
	}
	if !typ.kind.is_complex() {
		e.diagnostics << problem(line, col, 'unsupported: a value of type ${typ.describe()} is not converted to ${types.complex_long_double_type().describe()}')
		return error('not a complex conversion')
	}
	if typ.kind != .complex_long_double {
		// A complex value of the other width converted to this one: each
		// component is widened to the extended format on the x87 stack.
		source := e.complex_object_as(expr, typ, depth + 1)!
		return e.convert_complex_to_extended(dest, source, typ, line, col)
	}
	if expr.kind == .ident {
		if local := e.lookup(e.unit.arena.ident(expr).name) {
			if local.complex {
				return e.copy_complex_frame(local, dest, dest.width, line, col)
			}
		}
	}
	if expr.kind == .binary {
		return e.emit_long_double_complex_arithmetic(dest, *e.unit.arena.binary(expr), depth)
	}
	if expr.kind == .call {
		return e.emit_complex_call(dest, *e.unit.arena.call(expr), depth)
	}
	if expr.kind == .cast {
		return e.emit_long_double_complex_into(dest, e.unit.arena.cast(expr).expr, depth)
	}
	if expr.kind == .unary {
		node := e.unit.arena.unary(expr)
		if node.op == '-' {
			return e.emit_long_double_complex_negation(dest, *node, depth)
		}
		if node.op == '+' {
			source := e.complex_object(node.expr, depth + 1)!
			return e.copy_complex_frame(source, dest, dest.width, line, col)
		}
	}
	if expr.kind == .ident || expr.kind == .field || expr.kind == .index {
		e.address_of_object(expr, depth + 1)!
		source_address := e.value_slot(depth + 1)
		e.store_accumulator(source_address, line, col)!
		frame := e.frame_pointer(line, col)!
		register := e.accumulator(line, col)!
		e.append(e.target.address_of_slot(frame, i32(dest.offset), register))
		destination_address := e.value_slot(depth)
		e.store_accumulator(destination_address, line, col)!
		return e.copy_address_object(source_address, destination_address, complex_long_double_bytes,
			line, col)
	}
	if expr.kind == .complex_lit {
		// An imaginary constant of this type: the real part is a zero of the
		// extended format and the coefficient is the component above it.
		return e.store_long_double_imaginary_constant(dest, *e.unit.arena.complex_lit(expr))
	}
	e.diagnostics << problem(line, col, 'unsupported: a value of type ${types.complex_long_double_type().describe()} written as this expression is not one this back end computes')
	return error('unsupported long double complex value')
}

// store_long_double_imaginary_constant writes an imaginary constant whose
// component is the extended format, which is the constant 6.4.4.2 makes:
// thirty-two bytes with the real part a zero and the coefficient the imaginary
// part. The zero is written rather than left alone, because the object is
// storage that may have held something else.
fn (mut e Emitter) store_long_double_imaginary_constant(dest Slot, expr ast.ComplexLit) !void {
	value := expr.long_value or {
		e.diagnostics << problem(expr.line, expr.col, 'internal: a long double imaginary constant reached the emitter with no value of the extended type')
		return error('long double imaginary constant without a value')
	}
	frame := e.frame_pointer(expr.line, expr.col)!
	register := e.accumulator(expr.line, expr.col)!
	e.append(e.target.address_of_slot(frame, i32(dest.offset), register))
	e.append(e.target.extended_zero())
	e.append(e.target.store_extended(register)!)
	imaginary := Slot{
		offset: dest.offset + complex_long_double_component
		width:  complex_long_double_component
	}
	e.put_extended(imaginary, value, expr.line, expr.col)!
}

// emit_real_into_complex_long_double writes a real value into an extended
// complex object: the real part is the value converted to the extended format
// and the imaginary part is +0.0 of it. The zero is written rather than left
// alone, because the object is storage that may have held something else.
fn (mut e Emitter) emit_real_into_complex_long_double(dest Slot, expr ast.Expr, depth int) !void {
	line := e.expr_line(expr)
	col := e.expr_col(expr)
	if e.is_a_pointer(expr) {
		e.diagnostics << problem(line, col, 'unsupported: a pointer is not converted to ${types.complex_long_double_type().describe()}')
		return error('pointer to complex')
	}
	real := Slot{
		offset: dest.offset
		width:  complex_long_double_component
	}
	e.store_long_double(real, expr, line, col, depth)!
	frame := e.frame_pointer(line, col)!
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(dest.offset + complex_long_double_component), register))
	e.append(e.target.extended_zero())
	e.append(e.target.store_extended(register)!)
}

// convert_complex_to_extended widens a `float _Complex` or `double _Complex`
// value to the extended complex type, one component at a time: the component is
// read at its own width, rounded to a double where it is a float, and written
// through the x87 stack as the extended format.
fn (mut e Emitter) convert_complex_to_extended(dest Slot, source Slot, source_type types.Type, line int,
	col int) !void {
	frame := e.frame_pointer(line, col)!
	value := e.float_accumulator(line, col)!
	single := complex_component_single(source_type)
	step := complex_component_width(source_type)
	mut which := 0
	for which < 2 {
		from := source.offset + which * step
		to := dest.offset + which * complex_long_double_component
		if single {
			e.append(e.target.load_float_slot(frame, i32(from), value)!)
			e.append(e.target.float_to_double(value, value)!)
		} else {
			e.append(e.target.load_double_slot(frame, i32(from), value)!)
		}
		temporary := e.reserve(8)
		e.append(e.target.store_double_slot(frame, i32(temporary.offset), value)!)
		register := e.accumulator(line, col)!
		e.append(e.target.address_of_slot(frame, i32(temporary.offset), register))
		e.append(e.target.load_double_extended(register)!)
		e.append(e.target.address_of_slot(frame, i32(to), register))
		e.append(e.target.store_extended(register)!)
		which++
	}
}

// convert_extended_to_complex narrows a `long double _Complex` value to one of
// the two register widths, one component at a time. An extended component is
// sixteen bytes in memory and not a value in a floating-point register, so it
// cannot be read by the component instruction the two narrow types use: the
// component is loaded onto the x87 stack, stored back as a double, and rounded
// once more to a float where the destination's components are four bytes. The
// roundings are the ones 6.3.1.6 asks for, one per component, and the double
// step in the middle is exact for every value the extended format holds at a
// float's precision.
fn (mut e Emitter) convert_extended_to_complex(dest Slot, destination types.Type, source Slot, line int,
	col int) !void {
	frame := e.frame_pointer(line, col)!
	value := e.float_accumulator(line, col)!
	single := complex_component_single(destination)
	mut which := 0
	for which < 2 {
		from := source.offset + which * complex_long_double_component
		to := dest.offset + complex_component_offset(destination, which)
		temporary := e.reserve(8)
		register := e.accumulator(line, col)!
		e.append(e.target.address_of_slot(frame, i32(from), register))
		e.append(e.target.load_extended(register)!)
		e.append(e.target.address_of_slot(frame, i32(temporary.offset), register))
		e.append(e.target.store_double_extended(register)!)
		e.append(e.target.load_double_slot(frame, i32(temporary.offset), value)!)
		if single {
			e.append(e.target.double_to_float(value, value)!)
		}
		e.store_complex_component(frame, value, to, single)!
		which++
	}
}

// emit_complex_long_double_return leaves a value of the extended complex type
// where a caller of this function finds it: on the x87 stack, st(0) the real
// part and st(1) the imaginary one. Measured on gcc 16.2.1, which returns one
// this way. The value is materialized into an object of this frame first, so a
// return of an expression that is not already an object - a sum, a product, a
// call - is computed once, and then its two components are pushed in the order
// the caller pops them: the imaginary part first, so the real part ends on top.
fn (mut e Emitter) emit_complex_long_double_return(expr ast.Expr, line int, col int) !void {
	object := e.complex_object_as(expr, types.complex_long_double_type(), 0)!
	frame := e.frame_pointer(line, col)!
	e.push_extended_component(frame, object.offset + complex_long_double_component, line, col)!
	e.push_extended_component(frame, object.offset, line, col)!
	e.append(e.target.frame_epilogue())
}

// push_extended_component loads the sixteen bytes of a component at a frame
// offset onto the x87 stack.
fn (mut e Emitter) push_extended_component(frame backend.Register, offset int, line int, col int) !void {
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(offset), register))
	e.append(e.target.load_extended(register)!)
}

// pop_extended_component writes the value at the top of the x87 stack into the
// sixteen bytes of a component at a frame offset, and pops it.
fn (mut e Emitter) pop_extended_component(frame backend.Register, offset int, line int, col int) !void {
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(offset), register))
	e.append(e.target.store_extended(register)!)
}

// extended_component_step computes one component of an arithmetic step: the left
// value is pushed first and the right one second, so the x87 instruction that
// combines the pair computes the left against the right, and the result is
// written into the destination component.
fn (mut e Emitter) extended_component_step(frame backend.Register, left_offset int, right_offset int, dest_offset int, op string, line int,
	col int) !void {
	e.push_extended_component(frame, left_offset, line, col)!
	e.push_extended_component(frame, right_offset, line, col)!
	e.append(e.target.extended_arithmetic(op)!)
	e.pop_extended_component(frame, dest_offset, line, col)!
}

// emit_long_double_complex_arithmetic writes an arithmetic step on two extended
// complex values. The four operators are the language's; two of them are one x87
// instruction per component, and a product and a quotient are the runtime's, the
// same way they are for the two register widths.
fn (mut e Emitter) emit_long_double_complex_arithmetic(dest Slot, binary ast.Binary, depth int) !void {
	left := e.complex_object_as(binary.left, binary.typ, depth + 1)!
	right := e.complex_object_as(binary.right, binary.typ, depth + 1)!
	match binary.op {
		'+', '-' {
			return e.emit_long_double_complex_sum(dest, binary, left, right)
		}
		'*', '/' {
			name := complex_helper_name(binary.op, binary.typ.kind) or {
				e.diagnostics << problem(binary.line, binary.col, 'unsupported: ${binary.op} is not an operator this back end computes ${types.complex_long_double_type().describe()} with')
				return error('unsupported long double complex operator')
			}
			return e.emit_long_double_complex_helper(dest, binary, left, right, name)
		}
		else {
			e.diagnostics << problem(binary.line, binary.col, 'unsupported: ${binary.op} is not an operator this back end computes ${types.complex_long_double_type().describe()} with')
			return error('unsupported long double complex operator')
		}
	}
}

// emit_long_double_complex_sum writes the sum or the difference of two extended
// complex values: the real part from the real parts and the imaginary part from
// the imaginary ones, each a single x87 instruction.
fn (mut e Emitter) emit_long_double_complex_sum(dest Slot, binary ast.Binary, left Slot, right Slot) !void {
	line := binary.line
	col := binary.col
	frame := e.frame_pointer(line, col)!
	step := complex_long_double_component
	mut which := 0
	for which < 2 {
		e.extended_component_step(frame, left.offset + which * step, right.offset + which * step,
			dest.offset + which * step, binary.op, line, col)!
		which++
	}
}

// emit_long_double_complex_negation writes the negation of an extended complex
// value: each component's sign is flipped where it sits on the x87 stack, with
// the same `fchs` the scalar extended type's negation uses. The instruction
// changes the sign bit and rounds nothing, so a component that is -0.0 becomes
// +0.0 and stays a different value from +0.0, a NaN keeps its payload and takes
// the other sign, and an infinity takes the opposite sign. gcc 16.2.1 emits the
// same `fchs` for each component at -O0, measured on
// `long double _Complex g(long double _Complex a) { return -a; }`.
fn (mut e Emitter) emit_long_double_complex_negation(dest Slot, unary ast.Unary, depth int) !void {
	line := unary.line
	col := unary.col
	source := e.complex_object(unary.expr, depth + 1)!
	frame := e.frame_pointer(line, col)!
	step := complex_long_double_component
	mut which := 0
	for which < 2 {
		e.push_extended_component(frame, source.offset + which * step, line, col)!
		e.append(e.target.extended_negate())
		e.pop_extended_component(frame, dest.offset + which * step, line, col)!
		which++
	}
}
