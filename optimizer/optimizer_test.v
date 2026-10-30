module optimizer

import ast
import parser
import tokenize
import types

// The optimizer has no file of its own in the pipeline, so these tests reach
// into the parser for input and check the tree that comes out the other side.

fn options(args []string) Options {
	mut opts := default_options()
	for arg in args {
		assert opts.accept_flag(arg)
	}
	return opts
}

fn source(text string) ast.TranslationUnit {
	lexed := tokenize.lex(text)
	assert lexed.diagnostics.len == 0
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 0
	return parsed.unit
}

fn optimize_source(text string, opts Options) ast.TranslationUnit {
	return optimize(source(text), opts)
}

// returned_fold is the value of the first statement of the first function, when
// it is a constant by the time the optimizer has finished.
fn returned_fold(unit ast.TranslationUnit) ?i64 {
	for decl in unit.decls {
		if decl.body.len == 0 {
			continue
		}
		expr := decl.body[0].expr or { return none }
		if expr is ast.IntLit {
			return (expr as ast.IntLit).value
		}
		return none
	}
	return none
}

fn first_expression(unit ast.TranslationUnit) ast.Expr {
	for decl in unit.decls {
		if decl.body.len > 0 {
			return decl.body[0].expr or { panic('the statement has no expression') }
		}
	}
	panic('no declaration in the unit has a body')
}

fn test_no_pass_runs_at_the_default_level() {
	opts := default_options()
	assert opts.level == .o0
	assert pipeline(opts).len == 0
}

fn test_a_level_turns_on_the_passes_it_has() {
	for level in ['-O1', '-O2', '-O3', '-Os'] {
		opts := options([level])
		assert pipeline(opts) == ['fold-builtins']
	}
}

fn test_the_level_spellings_are_recognized() {
	assert options(['-O']).level == .o1
	assert options(['-O0']).level == .o0
	assert options(['-O3']).level == .o3
	assert options(['-Os']).level == .os
}

fn test_a_level_this_stub_does_not_implement_is_recorded_and_ignored() {
	opts := options(['-O9'])
	assert opts.level == .o0
	assert '-O9' in opts.recorded
	// A flag belonging to someone else is not the optimizer's, and a flag that
	// looks like a level but is not one is not an error either.
	mut other := default_options()
	assert !other.accept_flag('-std=gnu11')
	assert !other.accept_flag('-fwrapv')
	assert !other.accept_flag('-g')
}

fn test_a_builtin_call_folds_to_its_value() {
	opts := options(['-O2'])
	folded := optimize_source('int abs(int n);\nint main() { return abs(-7); }', opts)
	value := returned_fold(folded) or { -1 }
	assert value == 7
}

fn test_the_three_absolute_value_spellings_agree() {
	opts := options(['-O2'])
	for name in ['abs', 'labs', 'llabs'] {
		folded := optimize_source('int ${name}(int n);\nint main() { return ${name}(-12); }', opts)
		value := returned_fold(folded) or { -1 }
		assert value == 12
	}
}

fn test_a_call_around_a_non_constant_stays_a_call() {
	opts := options(['-O2'])
	expr := first_expression(optimize_source('int x;\nint abs(int n);\nint main() { return abs(x); }', opts))
	assert expr is ast.Call
}

fn test_a_call_with_the_wrong_number_of_arguments_stays_a_call() {
	opts := options(['-O2'])
	expr := first_expression(optimize_source('int abs();\nint main() { return abs(1, 2); }', opts))
	assert expr is ast.Call
}

fn test_an_unknown_name_stays_a_call() {
	opts := options(['-O2'])
	expr := first_expression(optimize_source('int strlen(char *s);\nint main() { return strlen(0); }', opts))
	assert expr is ast.Call
}

fn test_fno_builtin_leaves_every_library_name_alone() {
	opts := options(['-O2', '-fno-builtin'])
	assert !opts.folds_builtin('abs')
	expr := first_expression(optimize_source('int abs(int n);\nint main() { return abs(-7); }', opts))
	assert expr is ast.Call
}

fn test_fno_builtin_name_turns_off_one_name() {
	opts := options(['-O2', '-fno-builtin-abs'])
	assert !opts.folds_builtin('abs')
	assert opts.folds_builtin('labs')
	expr := first_expression(optimize_source('int abs(int n);\nint labs(int n);\nint main() { return abs(-7) + labs(-9); }', opts))
	assert expr is ast.Binary
	binary := expr as ast.Binary
	assert binary.left is ast.Call
	folded_right := binary.right
	assert folded_right is ast.IntLit
	assert (folded_right as ast.IntLit).value == 9
}

fn test_the_reserved_spelling_survives_fno_builtin() {
	opts := options(['-O2', '-fno-builtin'])
	assert opts.folds_builtin('__builtin_abs')
	folded := optimize_source('int __builtin_abs(int n);\nint main() { return __builtin_abs(-7); }', opts)
	value := returned_fold(folded) or { -1 }
	assert value == 7
}

fn test_a_later_flag_turns_a_name_back_on() {
	opts := options(['-O2', '-fno-builtin-abs', '-fbuiltin-abs'])
	assert opts.folds_builtin('abs')
	// -fbuiltin after -fno-builtin turns the whole set back on.
	reversed := options(['-fno-builtin', '-fbuiltin'])
	assert reversed.builtins
}

fn test_a_positive_literal_is_left_alone_by_the_absolute_value() {
	opts := options(['-O2'])
	folded := optimize_source('int abs(int n);\nint main() { return abs(9); }', opts)
	value := returned_fold(folded) or { -1 }
	assert value == 9
}

fn test_a_call_inside_a_call_is_reached() {
	opts := options(['-O2'])
	folded := optimize_source('int abs(int n);\nint main() { return abs(abs(-3)); }', opts)
	value := returned_fold(folded) or { -1 }
	assert value == 3
}

fn test_a_return_without_a_value_is_untouched() {
	opts := options(['-O2'])
	unit := optimize_source('int main() { return; }', opts)
	assert unit.decls[0].body.len == 1
	assert unit.decls[0].body[0].expr == none
}

fn test_the_summary_names_what_runs() {
	assert default_options().summary() == '-O0: no passes; builtins on'
	off := options(['-O2', '-fno-builtin-abs'])
	assert off.summary() == '-O2: fold-builtins; builtins on; disabled abs'
}

fn test_a_declaration_keeps_its_parameters_through_the_rewrite() {
	// The pass rebuilds every declaration it rewrites, and a parameter left out
	// of the rebuild is one the back end cannot find: at -O1 and up a body that
	// reads its own parameter was diagnosed as reading something that is not a
	// local of this function, while the same program compiled at -O0.
	optimized := optimize(source('int add(int a, int b) { return a + b; }'), options(['-O2']))
	assert optimized.decls.len == 1
	assert optimized.decls[0].params.len == 2
	assert optimized.decls[0].params[0].name == 'a'
	assert optimized.decls[0].params[1].name == 'b'
}

fn test_the_debug_and_fast_spellings_map_to_the_level_they_mean() {
	// -Og is -O1 without the passes that make debugging harder and -Ofast is -O3
	// plus semantic loosenings, so each is the level and not the loosenings this
	// stub does not implement.
	assert options(['-Og']).level == .o1
	assert options(['-Ofast']).level == .o3
	// A bare -O is -O1, which is what gcc makes of it.
	assert options(['-O']).level == .o1
}

fn test_the_size_level_runs_what_o2_runs() {
	// -Os is -O2 without the passes that make code larger, which is the rank it
	// was given: the two pipelines name the same passes while nothing in this
	// stub makes code larger.
	assert options(['-Os']).level == .os
	assert pipeline(options(['-Os'])) == pipeline(options(['-O2']))
}

fn test_a_spelling_that_is_not_a_level_is_recorded_and_changes_nothing() {
	opts := options(['-Oz'])
	assert opts.level == .o0
	assert opts.recorded == ['-Oz']
}

fn test_the_recorded_flags_keep_the_order_they_were_written_in() {
	opts := options(['-O2', '-fno-builtin-abs', '-O1'])
	// The flags are kept as they were written, and the level is the last one
	// written rather than the highest.
	assert opts.recorded == ['-O2', '-fno-builtin-abs', '-O1']
	assert opts.level == .o1
}

fn test_a_disabled_name_is_kept_as_the_flag_wrote_it() {
	opts := options(['-fno-builtin-labs'])
	assert opts.disabled == ['labs']
	assert !opts.folds_builtin('labs')
	assert opts.folds_builtin('abs')
	// -fbuiltin-NAME is the only thing that shortens the list, and it takes the
	// name back on.
	back := options(['-fno-builtin-labs', '-fbuiltin-labs'])
	assert back.disabled == []
	assert back.folds_builtin('labs')
}

fn test_a_builtin_argument_written_with_a_sign_is_still_a_constant() {
	// The constant reader takes a literal with a sign or a complement in front
	// of it, which is what makes `abs(-7)` a value here.
	opts := options(['-O2'])
	plus := optimize_source('int abs(int n);\nint main() { return abs(+7); }', opts)
	assert (returned_fold(plus) or { -1 }) == 7
	complement := optimize_source('int abs(int n);\nint main() { return abs(~0); }', opts)
	assert (returned_fold(complement) or { -1 }) == 1
}

fn test_a_builtin_argument_that_is_a_sum_stays_a_call() {
	// Folding `abs(1 + 2)` would mean a constant expression evaluator here, and
	// the emitter already has one; until the two are one function, the argument
	// has to be written out.
	opts := options(['-O2'])
	expr := first_expression(optimize_source('int abs(int n);\nint main() { return abs(1 + 2); }', opts))
	assert expr is ast.Call
}

fn test_a_folded_value_is_written_as_the_literal_it_became() {
	opts := options(['-O2'])
	expr := first_expression(optimize_source('int abs(int n);\nint main() { return abs(-7); }', opts))
	assert expr is ast.IntLit
	folded := expr as ast.IntLit
	assert folded.value == 7
	assert folded.text == '7'
	// The location is the call's, so a diagnostic about what the value became
	// points at the expression a person wrote.
	assert folded.line == 2
	assert folded.col > 0
}

fn test_the_argument_count_in_the_table_is_checked_before_the_value() {
	// abs takes one argument, so a call written with none has no operand to
	// compute and is left for the emitter to report.
	opts := options(['-O2'])
	expr := first_expression(optimize_source('int abs();\nint main() { return abs(); }', opts))
	assert expr is ast.Call
}

fn test_the_reserved_spellings_are_in_the_table_too() {
	opts := options(['-O2'])
	for name in ['__builtin_abs', '__builtin_labs', '__builtin_llabs'] {
		folded := optimize_source('int ${name}(int n);\nint main() { return ${name}(-5); }', opts)
		assert (returned_fold(folded) or { -1 }) == 5, name
	}
}

fn test_a_call_nested_in_an_element_is_reached() {
	opts := options(['-O2'])
	unit := optimize_source('int abs(int n);\nint main() { int a[3]; return a[abs(-1)]; }', opts)
	body := unit.decls[1].body
	assert body.len == 2
	expr := body[1].expr or {
		assert false
		return
	}
	assert expr is ast.Index
	index := (expr as ast.Index).index
	assert index is ast.IntLit
	assert (index as ast.IntLit).value == 1
}

fn test_a_builtin_call_in_a_condition_is_folded_and_the_branches_survive() {
	opts := options(['-O2'])
	unit := optimize_source('int abs(int n);\nint main() { if (abs(-2)) { return 1; } return 0; }', opts)
	stmt := unit.decls[1].body[0]
	cond := stmt.cond or {
		assert false
		return
	}
	assert cond is ast.IntLit
	assert (cond as ast.IntLit).value == 2
	// The statement is carried over whole: the rewrite changes the condition and
	// not the branches or the kind.
	assert stmt.kind == .if_stmt
	assert stmt.then_body.len == 1
}

// The pass rebuilds every node it walks, and a field left out of a rebuild is a
// field that reads as its zero value at every level above -O0 and as itself at
// -O0. These tests pin the fields a rebuild has dropped before: the type the
// reader resolved onto a step or an element, the part of a statement the emitter
// sizes an object by, the member an assignment writes and the operator a
// compound assignment was written with, and the linkage and types of a
// definition.

fn type_name(t types.Type) string {
	return t.describe()
}

fn test_a_step_keeps_the_type_the_reader_resolved_for_it() {
	// `x & (x - 1)` over two unsigned long longs was refused at -O1 and up as a
	// bitwise operation on a pointer: the step had no type of its own, so the
	// emitter sized the operand it computes at the width of an address.
	expr := first_expression(optimize_source('unsigned long long f(unsigned long long x) { return x & (x - 1); }',
		options(['-O2'])))
	assert expr is ast.Binary
	step := expr as ast.Binary
	assert step.op == '&'
	assert type_name(step.typ) == 'unsigned long long'
	assert step.right is ast.Binary
	assert type_name((step.right as ast.Binary).typ) == 'unsigned long long'
}

fn test_an_element_keeps_the_type_the_reader_resolved_for_it() {
	unit := optimize_source('int main(void) { int a[3]; return a[1]; }', options(['-O2']))
	stmt := unit.decls[0].body[1]
	expr := stmt.expr or {
		assert false
		return
	}
	assert expr is ast.Index
	assert type_name((expr as ast.Index).typ) == 'int'
}

fn test_a_declaration_keeps_the_part_the_emitter_sizes_it_by() {
	// The resolved type, the byte count and the stride of an array are read by
	// the emitter and are fields of the statement's extra part: a VLA lost its
	// size and was refused at -O1 as an element of something that is not an
	// array, while the same program compiled at -O0.
	unit := optimize_source('int main(void) { int a[3]; return 0; }', options(['-O2']))
	decl := unit.decls[0].body[0]
	assert decl.resolved().is_array()
	assert decl.decl_stride() == 4
}

fn test_a_member_store_keeps_the_member_it_writes() {
	unit := optimize_source('struct P { int a; int b; };\nint main(void) { struct P p; p.a = 1; return 0; }',
		options(['-O2']))
	store := unit.decls[0].body[1]
	object := unit.decls[0].body[0]
	// A struct's byte count is a fact the layout gave the reader, not a
	// spelling the back end can size.
	assert object.bytes() == 8
	assert store.field != none
	field := store.field or {
		assert false
		return
	}
	assert field.member == 'a'
}

fn test_a_compound_assignment_keeps_the_operator_it_was_written_with() {
	// A compound assignment to an element or through an address is emitted from
	// the operator and the value, so that the address is computed once; without
	// the operator the emitter reads the expanded assignment instead and
	// evaluates the index twice.
	unit := optimize_source('int main(void) { int a[2]; int i = 0; a[i++] += 5; return i; }', options(['-O2']))
	stmt := unit.decls[0].body[2]
	assert stmt.compound == '+'
}

fn test_a_definition_keeps_its_linkage_and_its_types() {
	// A static helper is a name two units may each define. Rebuilt without the
	// flag it became a global symbol and the link refused the second definition,
	// which is a program that compiles at -O0.
	// A static definition nothing names is not read at all, so the helper here
	// is called: what this test is about is a definition that reaches the back
	// end.
	unit := optimize_source('static int helper(void) { return 1; }\nint main(void) { return helper(); }',
		options(['-O2']))
	decl := unit.decls[0]
	assert decl.static_
	assert decl.ret == 'int'
	assert type_name(decl.ret_type) == 'int'
	assert decl.resolved.is_function()
	assert decl.defined
}

fn test_a_folded_value_carries_the_type_of_the_call_it_replaces() {
	// A folded literal is the call's value, so it is the call's type as well.
	// Without one it is a constant the emitter writes as an int, and a value
	// wider than that has no type to be written at: `x & llabs(-0x100000001)`
	// was refused at -O1 and up while the call compiled at -O0.
	expr := first_expression(optimize_source('long long llabs(long long n);\nint main(void) { return llabs(-5); }',
		options(['-O2'])))
	assert expr is ast.IntLit
	literal := expr as ast.IntLit
	assert literal.value == 5
	assert type_name(literal.typ) == 'long long'
}
