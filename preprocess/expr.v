module preprocess

import tokenize

// The controlling expression of an #if is read before anything else on the
// line matters, so it has its own reader and its own arithmetic. Macros in it
// are expanded, `defined` is answered from the macro table before that
// expansion, every name that is left over is zero, and the operators are C's
// with C's precedence, because what these expressions come from is headers
// written for a C compiler.
//
// Everything is read as 64 bits and whether those bits are an intmax_t or a
// uintmax_t, which is what C99 6.10.1p4 evaluates the controlling expression
// in. A literal answers that from its base and its suffix (6.4.4.1), the usual
// arithmetic conversions answer it for a binary operator, a comparison and a
// logical operator answer int, and a conditional is as unsigned as either of
// its two arms. The arithmetic wraps instead of trapping.

// Value is one #if operand: its bits, and whether C's conversions have made
// them a uintmax_t rather than an intmax_t. There is no other type in an #if,
// so those two fields are the whole of C's type system here, and every
// operator only has to decide which of the two it produces.
struct Value {
	bits        u64
	is_unsigned bool
}

fn signed_value(value i64) Value {
	return Value{
		bits:        u64(value)
		is_unsigned: false
	}
}

fn unsigned_value(value u64) Value {
	return Value{
		bits:        value
		is_unsigned: true
	}
}

// Condition is one #if expression: the tokens to read, where the reader is, and
// what it has to report.
struct Condition {
mut:
	tokens      []tokenize.Token
	pos         int
	diagnostics []tokenize.Diagnostic
	file        string
	line        int
	col         int
}

// parse reads the whole expression and refuses anything left over, so a token
// the evaluator did not understand is a diagnostic instead of a value that
// silently ignored it.
fn (mut c Condition) parse() ?Value {
	value := c.ternary(true) or { return none }
	if c.pos < c.tokens.len {
		c.problem('the #if expression has something this evaluator cannot read: ${c.tokens[c.pos].text}')
		return none
	}
	return value
}

fn (mut c Condition) ternary(evaluate bool) ?Value {
	condition := c.binary(1, evaluate)?
	if !c.at('?') {
		return condition
	}
	c.pos++
	taken := condition.bits != 0
	then_value := c.ternary(evaluate && taken)?
	if !c.at(':') {
		c.problem('the #if expression has a ? with no :')
		return none
	}
	c.pos++
	else_value := c.ternary(evaluate && !taken)?
	// The two arms are converted to a common type even though only one of them
	// has a value: `0 ? -1 : 0u` is uintmax_t, and comparing it with 0 is the
	// unsigned question.
	chosen := if taken { then_value } else { else_value }
	return Value{
		bits:        if evaluate { chosen.bits } else { u64(0) }
		is_unsigned: then_value.is_unsigned || else_value.is_unsigned
	}
}

// binary reads an expression by precedence, the way every C expression reader
// does. evaluate is false on the side of a && or || or ?: that is not taken:
// the tokens are still read, nothing is computed from them beyond the type the
// operator gives its result — which is what keeps `#if 0 && 1 / 0` from being a
// division by zero.
fn (mut c Condition) binary(min int, evaluate bool) ?Value {
	mut left := c.unary(evaluate)?
	for c.pos < c.tokens.len {
		t := c.tokens[c.pos]
		if t.kind != .punct {
			break
		}
		precedence := binary_precedence(t.text)
		if precedence == 0 || precedence < min {
			break
		}
		c.pos++
		if t.text == '&&' {
			right := c.binary(precedence + 1, evaluate && left.bits != 0)?
			left = signed_value(if left.bits != 0 && right.bits != 0 { i64(1) } else { i64(0) })
			continue
		}
		if t.text == '||' {
			right := c.binary(precedence + 1, evaluate && left.bits == 0)?
			left = signed_value(if left.bits != 0 || right.bits != 0 { i64(1) } else { i64(0) })
			continue
		}
		right := c.binary(precedence + 1, evaluate)?
		left = c.apply(t, left, right, evaluate)?
	}
	return left
}

fn (mut c Condition) unary(evaluate bool) ?Value {
	if c.pos >= c.tokens.len {
		c.problem('the #if expression ends where a value was expected')
		return none
	}
	t := c.tokens[c.pos]
	if t.kind == .punct && t.text in ['-', '+', '!', '~'] {
		c.pos++
		operand := c.unary(evaluate)?
		// A unary operator on an arithmetic type keeps the operand's type,
		// except `!`, which answers int.
		return match t.text {
			'-' { Value{ bits: u64(0) - operand.bits, is_unsigned: operand.is_unsigned } }
			'+' { operand }
			'!' { signed_value(if operand.bits == 0 { i64(1) } else { i64(0) }) }
			else { Value{ bits: ~operand.bits, is_unsigned: operand.is_unsigned } }
		}
	}
	return c.primary(evaluate)
}

fn (mut c Condition) primary(evaluate bool) ?Value {
	if c.pos >= c.tokens.len {
		c.problem('the #if expression ends where a value was expected')
		return none
	}
	t := c.tokens[c.pos]
	if t.kind == .punct && t.text == '(' {
		c.pos++
		value := c.ternary(evaluate)?
		if !c.at(')') {
			c.problem('the #if expression has a ( with no )')
			return none
		}
		c.pos++
		return value
	}
	if t.kind == .number {
		c.pos++
		return integer_literal_value(t.text) or {
			c.problem('${t.text} is not an integer constant the #if evaluator can read')
			return none
		}
	}
	if t.kind == .character {
		c.pos++
		value := character_value(t.text) or {
			c.problem('${t.text} is not a character constant the #if evaluator can read')
			return none
		}
		// A character constant has type int (6.4.4.4), which is intmax_t here.
		return signed_value(value)
	}
	if t.kind == .identifier {
		// A name that is still here after expansion is not defined, and C says
		// an undefined name in an #if is zero. `defined` was answered before
		// expansion, so it never reaches this arm as an operator.
		c.pos++
		return signed_value(0)
	}
	c.problem('the #if expression has a value where none can be read: ${t.text}')
	return none
}

// apply does the arithmetic of one operator. evaluate is false inside a branch
// that was not taken, where the answer is not used and the checks are not run,
// but the type is still worked out: an arm that is not taken still decides what
// type the conditional has.
fn (mut c Condition) apply(op tokenize.Token, left Value, right Value, evaluate bool) ?Value {
	// C's usual arithmetic conversions: intmax_t and uintmax_t have the same
	// rank, so one unsigned operand makes the result unsigned. A comparison
	// answers int, and a shift is the type of the operand it shifts.
	mut unsigned := left.is_unsigned || right.is_unsigned
	match op.text {
		'<', '>', '<=', '>=', '==', '!=' { unsigned = false }
		'<<', '>>' { unsigned = left.is_unsigned }
		else {}
	}
	if !evaluate {
		return Value{
			is_unsigned: unsigned
		}
	}
	if op.text in ['<', '>', '<=', '>=', '==', '!='] {
		return signed_value(if compare(op.text, left, right) { i64(1) } else { i64(0) })
	}
	return match op.text {
		'+' { Value{ bits: left.bits + right.bits, is_unsigned: unsigned } }
		'-' { Value{ bits: left.bits - right.bits, is_unsigned: unsigned } }
		'*' { Value{ bits: left.bits * right.bits, is_unsigned: unsigned } }
		'/' {
			if right.bits == 0 {
				c.problem('division by zero in a #if expression')
				return none
			}
			if unsigned {
				unsigned_value(left.bits / right.bits)
			} else {
				signed_value(i64(left.bits) / i64(right.bits))
			}
		}
		'%' {
			if right.bits == 0 {
				c.problem('division by zero in a #if expression')
				return none
			}
			if unsigned {
				unsigned_value(left.bits % right.bits)
			} else {
				signed_value(i64(left.bits) % i64(right.bits))
			}
		}
		'&' { Value{ bits: left.bits & right.bits, is_unsigned: unsigned } }
		'|' { Value{ bits: left.bits | right.bits, is_unsigned: unsigned } }
		'^' { Value{ bits: left.bits ^ right.bits, is_unsigned: unsigned } }
		'<<' {
			count := c.shift_count(right)?
			Value{ bits: left.bits << count, is_unsigned: left.is_unsigned }
		}
		'>>' {
			count := c.shift_count(right)?
			// An unsigned value shifts its zeroes in, a signed one its sign:
			// that is the one place the same bits answer differently.
			bits := if left.is_unsigned { left.bits >> count } else { u64(i64(left.bits) >> count) }
			Value{ bits: bits, is_unsigned: left.is_unsigned }
		}
		else {
			c.problem('the #if expression has an operator this evaluator cannot read: ${op.text}')
			return none
		}
	}
}

// shift_count is the distance a shift moves by. The right operand of a shift is
// converted on its own and nothing else comes of it, so it is read as a number:
// a count of 64 or more, or a negative one, is outside the width this evaluator
// works in and is reported rather than wrapped.
fn (mut c Condition) shift_count(right Value) ?u64 {
	if right.is_unsigned {
		if right.bits >= 64 {
			c.problem('the #if expression shifts by ${right.bits}, which is outside the 64 bits it is evaluated in')
			return none
		}
		return right.bits
	}
	count := i64(right.bits)
	if count < 0 || count >= 64 {
		c.problem('the #if expression shifts by ${count}, which is outside the 64 bits it is evaluated in')
		return none
	}
	return u64(count)
}

// compare answers one of the relational operators. The operands have already
// been converted to a common type, so when either of them is unsigned the
// comparison is the unsigned one: `-1 < 0u` is false.
fn compare(op string, left Value, right Value) bool {
	if left.is_unsigned || right.is_unsigned {
		return match op {
			'<' { left.bits < right.bits }
			'>' { left.bits > right.bits }
			'<=' { left.bits <= right.bits }
			'>=' { left.bits >= right.bits }
			'==' { left.bits == right.bits }
			else { left.bits != right.bits }
		}
	}
	return match op {
		'<' { i64(left.bits) < i64(right.bits) }
		'>' { i64(left.bits) > i64(right.bits) }
		'<=' { i64(left.bits) <= i64(right.bits) }
		'>=' { i64(left.bits) >= i64(right.bits) }
		'==' { i64(left.bits) == i64(right.bits) }
		else { i64(left.bits) != i64(right.bits) }
	}
}

fn binary_precedence(op string) int {
	return match op {
		'||' { 1 }
		'&&' { 2 }
		'|' { 3 }
		'^' { 4 }
		'&' { 5 }
		'==', '!=' { 6 }
		'<', '>', '<=', '>=' { 7 }
		'<<', '>>' { 8 }
		'+', '-' { 9 }
		'*', '/', '%' { 10 }
		else { 0 }
	}
}

fn (mut c Condition) at(text string) bool {
	if c.pos >= c.tokens.len {
		return false
	}
	t := c.tokens[c.pos]
	return t.kind == .punct && t.text == text
}

fn (mut c Condition) problem(msg string) {
	t := if c.pos < c.tokens.len {
		c.tokens[c.pos]
	} else {
		tokenize.Token{
			line: c.line
			col:  c.col
		}
	}
	c.diagnostics << tokenize.Diagnostic{
		line: t.line
		col:  t.col
		msg:  msg
		file: c.file
	}
}

// integer_literal_value reads a number the way an #if has to: decimal, octal,
// hexadecimal and the 0b form, with the suffixes a literal may wear. Anything
// else — a float, a value too large for 64 bits — is refused so the caller can
// say so.
//
// The value carries whether the literal is a uintmax_t, because C99 6.4.4.1
// picks the type from the base and the suffix: a `u` suffix is unsigned, and a
// hexadecimal or octal literal too large for intmax_t is unsigned too. A
// decimal one without the suffix has no unsigned type in that list; gcc reads
// one that is too large for intmax_t as unsigned and warns, and the value is
// the number the writer wrote either way, so it is read the same way here.
fn integer_literal_value(text string) ?Value {
	mut body := text
	mut base := 10
	if body.starts_with('0x') || body.starts_with('0X') {
		base = 16
		body = body[2..]
	} else if body.starts_with('0b') || body.starts_with('0B') {
		base = 2
		body = body[2..]
	} else if body.len > 1 && body[0] == `0` {
		// The leading zero is the base, not a digit that has to be removed:
		// `0u` is an octal zero wearing a suffix, and it has to keep its zero
		// to be read at all.
		base = 8
	}
	mut digits := ''
	for i in 0 .. body.len {
		c := body[i]
		if c == `u` || c == `U` || c == `l` || c == `L` {
			break
		}
		digits += c.ascii_str()
	}
	if digits == '' {
		return none
	}
	unsigned := literal_suffix(body[digits.len..]) or { return none }
	mut value := u64(0)
	for i in 0 .. digits.len {
		c := digits[i]
		digit := digit_value(c) or { return none }
		if digit >= base {
			return none
		}
		if value > (~u64(0) - u64(digit)) / u64(base) {
			return none
		}
		value = value * u64(base) + u64(digit)
	}
	if unsigned || value > u64(0x7fffffffffffffff) {
		return unsigned_value(value)
	}
	return signed_value(i64(value))
}

// literal_suffix reads what follows the digits of an integer literal: at most
// one `u` and at most one `l` or `ll`, in either order (6.4.4.1), and answers
// whether that suffix makes the literal unsigned. The long count does not
// change the type here, because intmax_t and uintmax_t are the only two types
// an #if has; it is still checked, so that a suffix the tokenizer let through is
// not silently ignored.
fn literal_suffix(text string) ?bool {
	mut unsigned := false
	mut long_suffix := false
	mut i := 0
	for i < text.len {
		c := text[i]
		if c == `u` || c == `U` {
			if unsigned {
				return none
			}
			unsigned = true
			i++
			continue
		}
		if c == `l` || c == `L` {
			if long_suffix {
				return none
			}
			long_suffix = true
			if i + 1 < text.len && (text[i + 1] == `l` || text[i + 1] == `L`) {
				i += 2
			} else {
				i++
			}
			continue
		}
		return none
	}
	return unsigned
}

fn digit_value(c u8) ?int {
	if c >= `0` && c <= `9` {
		return int(c - `0`)
	}
	if c >= `a` && c <= `f` {
		return int(c - `a`) + 10
	}
	if c >= `A` && c <= `F` {
		return int(c - `A`) + 10
	}
	return none
}

// character_value reads a character constant to the value it stands for. The
// escapes are the ones a C compiler has to know; a multi-character constant is
// C's implementation-defined case and is refused rather than guessed at.
fn character_value(text string) ?i64 {
	// C99 6.4.4.4 lets a character constant name the encoding of what it holds: `L` for
	// wchar_t, `u` for char16_t, `U` for char32_t. The #if evaluator wants the value, and
	// the prefix does not change it, so the prefix is dropped and the constant read the
	// same way either side of it. This is not a corner: glibc's <bits/wchar.h> asks
	// `#elif L'\0' - 1 > 0`, so a prefix refused here refuses every translation unit that
	// includes <wchar.h>.
	mut quoted := text
	for prefix in ['u8', 'L', 'u', 'U'] {
		if quoted.starts_with(prefix) {
			quoted = quoted[prefix.len..]
			break
		}
	}
	if quoted.len < 3 || quoted[0] != `'` || quoted[quoted.len - 1] != `'` {
		return none
	}
	body := quoted[1..quoted.len - 1]
	if body.len == 0 {
		return none
	}
	if body[0] == `\\` {
		if body.len < 2 {
			return none
		}
		escaped := body[1]
		return match escaped {
			`n` { i64(10) }
			`t` { i64(9) }
			`r` { i64(13) }
			`0` { i64(0) }
			`a` { i64(7) }
			`b` { i64(8) }
			`f` { i64(12) }
			`v` { i64(11) }
			`\\`, `'`, `"`, `?` { i64(escaped) }
			else { none }
		}
	}
	if body.len != 1 {
		return none
	}
	return i64(body[0])
}
