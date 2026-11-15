module optimizer

import ast

// The optimizer sits between the parser and the emitter: `ast` in, `ast` out.
// It owns two things a compiler is expected to have: the `-O` levels, and the
// set of library functions whose value it may compute itself (`-fno-builtin`
// takes that back).
//
// Both are tables rather than branches. A pass names the level that turns it on
// and the function that applies it, so adding an optimization is a row in
// `passes` and a function beside it. A builtin names its arity and the function
// that computes its value, so adding `strlen` later is a row in `builtins`.
//
// The emitter never asks this module anything. It runs before codegen and hands
// over a tree, which keeps `codegen/` about one target's bytes and nothing else.

pub enum Level {
	o0
	o1
	o2
	o3
	os
}

// rank orders the levels by how much work they turn on. `-Os` sits with `-O2`,
// which is what it is: `-O2` without the passes that make code larger.
fn (l Level) rank() int {
	return match l {
		.o0 { 0 }
		.o1 { 1 }
		.o2 { 2 }
		.o3 { 3 }
		.os { 2 }
	}
}

pub fn (l Level) spelling() string {
	return match l {
		.o0 { '-O0' }
		.o1 { '-O1' }
		.o2 { '-O2' }
		.o3 { '-O3' }
		.os { '-Os' }
	}
}

// Options is the optimization state of one compile.
pub struct Options {
pub mut:
	level Level
	// builtins is on by default, as it is in gcc and clang: a call to a known
	// library function with constant arguments is computed at compile time.
	builtins bool
	// disabled holds the names `-fno-builtin-NAME` turned off.
	disabled []string
	// recorded keeps the flags as they were written, so a verbose mode can show
	// what the command line asked for rather than only what was honored.
	recorded []string
}

pub fn default_options() Options {
	return Options{
		builtins: true
	}
}

// accept_flag reads one command-line argument and reports whether the optimizer
// owns it. The command line parser calls this for every flag it does not know,
// so the list of optimization flags lives here and not in `cli/`.
//
// A level or a `-f...` spelling this stub does not implement is accepted and
// recorded rather than refused. V hands a compiler flags for work it expects to
// be done, and refusing one fails a build that was supposed to succeed.
pub fn (mut o Options) accept_flag(arg string) bool {
	if arg == '-O' {
		return o.record_level(arg, .o1)
	}
	if arg.starts_with('-O') && arg.len > 2 {
		rest := arg[2..]
		return match rest {
			'0' { o.record_level(arg, .o0) }
			'1' { o.record_level(arg, .o1) }
			'2' { o.record_level(arg, .o2) }
			'3' { o.record_level(arg, .o3) }
			// -Os is -O2 for size; -Og is -O1 without the optimizations that
			// make debugging harder; -Ofast is -O3 plus semantic loosenings this
			// stub does not implement, so it is the level and not the loosenings.
			's' { o.record_level(arg, .os) }
			'g' { o.record_level(arg, .o1) }
			'fast' { o.record_level(arg, .o3) }
			// Anything else is recorded and changes nothing.
			else {
				o.recorded << arg
				true
			}
		}
	}
	if arg == '-fno-builtin' {
		o.builtins = false
		o.recorded << arg
		return true
	}
	if arg == '-fbuiltin' {
		o.builtins = true
		o.recorded << arg
		return true
	}
	if arg.starts_with('-fno-builtin-') {
		o.disabled << arg[13..]
		o.recorded << arg
		return true
	}
	if arg.starts_with('-fbuiltin-') {
		o.enable_builtin(arg[10..])
		o.recorded << arg
		return true
	}
	return false
}

fn (mut o Options) record_level(arg string, level Level) bool {
	o.level = level
	o.recorded << arg
	return true
}

fn (mut o Options) enable_builtin(name string) {
	mut kept := []string{}
	for disabled in o.disabled {
		if disabled != name {
			kept << disabled
		}
	}
	o.disabled = kept
}

// folds_builtin says whether a call to this name may be replaced by its value.
//
// The reserved `__builtin_` spelling is an explicit request and survives
// -fno-builtin, which is how gcc treats it: -fno-builtin says "do not assume
// what a library function named abs does", and `__builtin_abs` is not a library
// function anyone else can redefine.
pub fn (o Options) folds_builtin(name string) bool {
	if name.starts_with('__builtin_') {
		return true
	}
	if !o.builtins {
		return false
	}
	return name !in o.disabled
}

// Pass is one rewrite with the level that turns it on. It is handed the arena
// the unit's expressions sit in, because the nodes it builds are nodes of the
// tree it hands back: a node built in an arena the caller never sees is a link
// into nothing, and a node built in a copy of the arena is in an array that
// stops growing the moment the pass returns.
struct Pass {
	name  string
	min   Level
	apply fn (unit ast.TranslationUnit, mut arena ast.Arena, opts Options) ast.TranslationUnit @[required]
}

// passes is the pipeline, in the order it runs. The only entry today folds a
// call whose value the compiler can compute; it is at -O1 because a call this
// stub cannot emit is a diagnostic at -O0, and turning that into a value is the
// optimization.
const passes = [
	Pass{
		name:  'fold-builtins'
		min:   .o1
		apply: fold_builtin_calls
	},
]

// Builtin is a library function the compiler knows the value of when its
// argument is a constant. arity is checked before `apply` is called, and the
// arena is passed because an argument is read out of it: the value of a literal
// is in its node and not in the eight bytes that point at it.
struct Builtin {
	name  string
	arity int
	apply fn (args []ast.Expr, arena &ast.Arena) ?i64 @[required]
}

// builtins is the table `fold-builtins` reads. The three abs spellings are the
// same function with different argument types in C, and the stub has one
// integer type, so they compute the same thing.
//
// `__builtin_constant_p` is deliberately absent: answering it correctly means
// folding a whole constant expression, and this module can only evaluate a
// literal. A wrong answer to that builtin is worse than no answer, so it waits
// for the constant folder to be shared with the emitter.
const builtins = [
	Builtin{
		name:  'abs'
		arity: 1
		apply: absolute_value
	},
	Builtin{
		name:  'labs'
		arity: 1
		apply: absolute_value
	},
	Builtin{
		name:  'llabs'
		arity: 1
		apply: absolute_value
	},
	Builtin{
		name:  '__builtin_abs'
		arity: 1
		apply: absolute_value
	},
	Builtin{
		name:  '__builtin_labs'
		arity: 1
		apply: absolute_value
	},
	Builtin{
		name:  '__builtin_llabs'
		arity: 1
		apply: absolute_value
	},
]

// max_rewrite_depth bounds how far into a nested expression the rewrite
// follows. The emitter has the same kind of bound and reports the nesting it
// will not fold, so returning the expression unchanged here leaves the
// diagnostic to the place that already owns it.
const max_rewrite_depth = 200

// pipeline names the passes that run at a level, in order.
pub fn pipeline(opts Options) []string {
	mut names := []string{}
	for pass in passes {
		if pass.min.rank() <= opts.level.rank() {
			names << pass.name
		}
	}
	return names
}

// optimize runs the pipeline over a translation unit and returns the tree the
// emitter gets. Every pass writes into the arena of the unit it is handed and
// hands it back with the tree, so the nodes a pass built are nodes the caller
// reads: the arena is the unit's, and a pass that grew its own copy would leave
// the links in the tree pointing into an array nothing holds any more.
pub fn optimize(unit ast.TranslationUnit, opts Options) ast.TranslationUnit {
	mut current := unit
	for pass in passes {
		if pass.min.rank() <= opts.level.rank() {
			current = pass.apply(current, mut current.arena, opts)
		}
	}
	return current
}

// summary is the one line `-vv` prints about the optimizer.
pub fn (o Options) summary() string {
	names := pipeline(o)
	state := if names.len == 0 { 'no passes' } else { names.join(', ') }
	builtins_state := if o.builtins { 'builtins on' } else { 'builtins off' }
	if o.disabled.len > 0 {
		return '${o.level.spelling()}: ${state}; ${builtins_state}; disabled ${o.disabled.join(', ')}'
	}
	return '${o.level.spelling()}: ${state}; ${builtins_state}'
}

fn fold_builtin_calls(unit ast.TranslationUnit, mut arena ast.Arena, opts Options) ast.TranslationUnit {
	mut decls := []ast.FnDecl{}
	for decl in unit.decls {
		// Every part of the declaration is carried over, because the pass
		// changes the body and nothing else and a field left out of the
		// rebuild is one nothing reports. A declaration without its parameters
		// is a function the back end cannot find, one without ret_type or
		// resolved is a declaration whose types read as unresolved, one
		// without nested or owner is a nested function separated from the
		// frame it reaches through the static chain, and one without static_
		// or weak is a symbol with a binding the source did not ask for, so
		// two units may no longer each define a static helper of the same
		// name at -O1 while they link at -O0.
		decls << ast.FnDecl{
			name:     decl.name
			ret:      decl.ret
			ret_type: decl.ret_type
			resolved: decl.resolved
			params:   decl.params
			defined:  decl.defined
			weak:     decl.weak
			static_:  decl.static_
			body:     rewrite_body(decl.body, mut arena, opts)
			nested:   decl.nested
			owner:    decl.owner
			line:     decl.line
			col:      decl.col
		}
	}
	return ast.TranslationUnit{
		decls:          decls
		globals:        unit.globals
		extern_objects: unit.extern_objects
		arena:          arena
	}
}

fn rewrite_body(body []ast.Stmt, mut arena ast.Arena, opts Options) []ast.Stmt {
	mut out := []ast.Stmt{}
	for stmt in body {
		// Every expression a statement carries is rewritten, and the
		// statements it carries are rewritten in turn. What the rebuild writes
		// is those expressions and every other field is the one that arrived,
		// because the emitter reads them and decides nothing here: the member
		// an assignment writes through and the operator a compound assignment
		// was written with are as much a part of the statement as its value is.
		mut expr := stmt.expr
		if !expr.is_none() {
			expr = rewrite(expr, mut arena, opts, 0)
		}
		mut cond := stmt.cond
		if !cond.is_none() {
			cond = rewrite(cond, mut arena, opts, 0)
		}
		// An element of an array is a place a value is read from as well as
		// written to, so the subscript is rewritten like every other expression.
		mut index := stmt.index
		if !index.is_none() {
			index = rewrite(index, mut arena, opts, 0)
		}
		// The expression an assignment writes through is a place as well as a
		// value: `*p = v` reads the pointer, so a builtin call inside it is
		// folded the same way. It lives in the extra part along with what this
		// pass does not change, and the part is rebuilt only when it holds an
		// expression to rewrite: the type and byte width a declaration
		// resolved to, the size and stride of an array, the element an
		// assignment writes, the cleanup a declaration names and the function
		// a nested_function statement defines are all read by the emitter, and
		// a statement rebuilt without them is refused or given the wrong
		// symbol at -O1 and up while it compiles at -O0. A part with no
		// expression in it is shared with the statement that arrived.
		mut extra := stmt.extra
		if present := stmt.extra {
			if !present.init.is_none() || !present.deref.is_none() || !present.goto_expr.is_none()
				|| present.step.len > 0 || present.then_body.len > 0 || present.else_body.len > 0 {
				mut init := present.init
				if !init.is_none() {
					init = rewrite(init, mut arena, opts, 0)
				}
				mut deref := present.deref
				if !deref.is_none() {
					deref = rewrite(deref, mut arena, opts, 0)
				}
				mut goto_expr := present.goto_expr
				if !goto_expr.is_none() {
					goto_expr = rewrite(goto_expr, mut arena, opts, 0)
				}
				extra = arena.box_extra(ast.StmtExtra{
					resolved:        present.resolved
					decl_name:       present.decl_name
					decl_type:       present.decl_type
					decl_count:      present.decl_count
					init:            init
					compound:        present.compound
					step:            rewrite_body(present.step, mut arena, opts)
					then_body:       rewrite_body(present.then_body, mut arena, opts)
					else_body:       rewrite_body(present.else_body, mut arena, opts)
					bytes:           present.bytes
					decl_vla_size:   present.decl_vla_size
					decl_stride:     present.decl_stride
					deref:           deref
					subscript:       present.subscript
					case_value:      present.case_value
					case_value_high: present.case_value_high
					case_is_range:   present.case_is_range
					label:           present.label
					goto_expr:       goto_expr
					assembly:        present.assembly
					cleanup:         present.cleanup
					nested_fn:       present.nested_fn
				})
			}
		}
		out << ast.Stmt{
			kind:   stmt.kind
			expr:   expr
			target: stmt.target
			index:  index
			field:  stmt.field
			extra:  extra
			cond:   cond
			body:   rewrite_body(stmt.body, mut arena, opts)
			line:   stmt.line
			col:    stmt.col
		}
	}
	return out
}

// rewrite returns the expression with every builtin call it can compute
// replaced by the value. The left spine of an operator chain is walked with a
// loop rather than with recursion: a chain of ten thousand terms is one level
// deep in the grammar and ten thousand nodes deep in the tree, and recursing
// over it is a stack overflow rather than an optimization.
//
// A node is read out of the arena into a copy before its children are rewritten,
// because building a node of the same shape moves the array the node came from:
// a payload pointer is good until the next put_* for its shape.
fn rewrite(expr ast.Expr, mut arena ast.Arena, opts Options, depth int) ast.Expr {
	if depth > max_rewrite_depth {
		return expr
	}
	mut spine := []ast.Binary{}
	mut node := expr
	for node.kind == .binary {
		binary := *arena.binary(node)
		spine << binary
		node = binary.left
	}
	mut rebuilt := rewrite_leaf(node, mut arena, opts, depth + 1)
	for i := spine.len - 1; i >= 0; i-- {
		binary := spine[i]
		// The step's own type travels with it. The emitter sizes an operand by
		// the type the reader resolved onto the node, so a step rebuilt without
		// one is an operand of unknown width: `x & (x - 1)` over two
		// unsigned long longs is then refused as a bitwise operation on a
		// pointer at -O1 and up while it compiles at -O0.
		rebuilt = arena.put_binary(ast.Binary{
			op:    binary.op
			left:  rebuilt
			right: rewrite_leaf(binary.right, mut arena, opts, depth + 1)
			typ:   binary.typ
			line:  binary.line
			col:   binary.col
		})
	}
	return rebuilt
}

fn rewrite_leaf(expr ast.Expr, mut arena ast.Arena, opts Options, depth int) ast.Expr {
	match expr.kind {
		.int_lit {
			return expr
		}
		.float_lit {
			// A floating constant is a value nothing in this file changes, like
			// the integer one beside it.
			return expr
		}
		.complex_lit {
			// An imaginary constant is a value too, and one no pass here folds:
			// its two components are written at emission, so there is nothing
			// for this file to compute.
			return expr
		}
		.ident {
			return expr
		}
		.str_lit {
			return expr
		}
		.field {
			// A member of an object is a place a value is read from, at an
			// offset the reader worked out from the layout. There is no
			// expression inside it to rewrite, so it is returned as it is: the
			// node it points at is in the arena and is not built again here.
			return expr
		}
		.index {
			// An element is a place a value is read from, and both the base
			// and the expression that says which element are rewritten like
			// any other. The node's own type and its run-time stride are not
			// decided here and travel with it: the emitter sizes the element
			// from the one and steps an array whose element size it cannot
			// fold by the other.
			node := *arena.index(expr)
			return arena.put_index(ast.Index{
				base:       rewrite(node.base, mut arena, opts, depth + 1)
				index:      rewrite(node.index, mut arena, opts, depth + 1)
				typ:        node.typ
				vla_stride: node.vla_stride
				line:       node.line
				col:        node.col
			})
		}
		.binary {
			return rewrite(expr, mut arena, opts, depth + 1)
		}
		.unary {
			node := *arena.unary(expr)
			return arena.put_unary(ast.Unary{
				op:   node.op
				expr: rewrite(node.expr, mut arena, opts, depth + 1)
				typ:  node.typ
				line: node.line
				col:  node.col
			})
		}
		.cast {
			// A conversion is not a call to a builtin, so the only thing inside
			// it to rewrite is its operand. The clause travels with it: what the
			// node is worth is the type converted to, and nothing in the operand
			// says which conversion this is.
			node := *arena.cast(expr)
			return arena.put_cast(ast.Cast{
				spelling: node.spelling
				expr:     rewrite(node.expr, mut arena, opts, depth + 1)
				typ:      node.typ
				line:     node.line
				col:      node.col
			})
		}
		.call {
			// The arguments are rewritten first, so `abs(abs(-3))` folds the
			// inner call and then has a constant to work with.
			node := *arena.call(expr)
			rewritten := ast.Call{
				name:   node.name
				// A callee that is an expression travels with the call: the
				// rewrite changes the arguments, not what the call calls.
				callee: node.callee
				args:   rewrite_arguments(node.args, mut arena, opts, depth + 1)
				// The type the reader resolved onto the call is the width its
				// value has when the unit declares no return type for the name,
				// so it travels with the call rather than being looked up again.
				typ:    node.typ
				line:   node.line
				col:    node.col
			}
			if folded := fold_call(rewritten, mut arena, opts) {
				return folded
			}
			return arena.put_call(rewritten)
		}
		.inc_dec {
			// The operand is an object, and an object holds no call to a
			// builtin - but its own subexpressions still come through here.
			node := *arena.inc_dec(expr)
			return arena.put_inc_dec(ast.IncDec{
				op:      node.op
				operand: rewrite(node.operand, mut arena, opts, depth + 1)
				postfix: node.postfix
				typ:     node.typ
				line:    node.line
				col:     node.col
			})
		}
		.assign {
			// Both operands are rewritten, and the clause travels with the
			// node: what the assignment is worth is the type of the object
			// written, which is what the reader resolved.
			node := *arena.assign(expr)
			return arena.put_assign(ast.Assign{
				op:     node.op
				target: rewrite(node.target, mut arena, opts, depth + 1)
				value:  rewrite(node.value, mut arena, opts, depth + 1)
				typ:    node.typ
				line:   node.line
				col:    node.col
			})
		}
		.comma {
			// The left operand is evaluated for what it does and the value is
			// the right one's, whose type the node carries.
			node := *arena.comma(expr)
			return arena.put_comma(ast.Comma{
				left:  rewrite(node.left, mut arena, opts, depth + 1)
				right: rewrite(node.right, mut arena, opts, depth + 1)
				typ:   node.typ
				line:  node.line
				col:   node.col
			})
		}
		.conditional {
			// All three operands are rewritten: a builtin call can sit in the
			// condition as much as in either arm. The clause travels with the
			// node, since which arm runs does not change the type they share.
			// `omitted_middle` travels with it too: rewriting the condition and
			// the middle operand separately would lose the fact that the source
			// wrote only one of them, and the emitter needs it to evaluate the
			// condition once.
			node := *arena.conditional(expr)
			return arena.put_conditional(ast.Conditional{
				cond:           rewrite(node.cond, mut arena, opts, depth + 1)
				then_expr:      rewrite(node.then_expr, mut arena, opts, depth + 1)
				else_expr:      rewrite(node.else_expr, mut arena, opts, depth + 1)
				typ:            node.typ
				omitted_middle: node.omitted_middle
				line:           node.line
				col:            node.col
			})
		}
		.stmt_expr {
			// The statements run in order and the value is the last
			// expression statement's, so both halves are rewritten: a builtin
			// call can sit in either. The clause travels with the node.
			node := *arena.stmt_expr(expr)
			mut value := node.value
			if !value.is_none() {
				value = rewrite(value, mut arena, opts, depth + 1)
			}
			return arena.put_stmt_expr(ast.StmtExpr{
				body:  rewrite_body(node.body, mut arena, opts)
				value: value
				typ:   node.typ
				line:  node.line
				col:   node.col
			})
		}
		.none {
			// An absent expression has no node behind it and nothing inside it
			// to rewrite.
			return expr
		}
	}
}

fn rewrite_arguments(args []ast.Expr, mut arena ast.Arena, opts Options, depth int) []ast.Expr {
	mut out := []ast.Expr{}
	for arg in args {
		out << rewrite(arg, mut arena, opts, depth)
	}
	return out
}

// fold_call computes a call to a builtin, or hands back nothing so the call
// stays in the tree and the emitter reports it. A name that is not in the table,
// an argument count that does not match, an argument that is not a constant, and
// a name the command line turned off all end the same way: leave it alone.
fn fold_call(call ast.Call, mut arena ast.Arena, opts Options) ?ast.Expr {
	if !opts.folds_builtin(call.name) {
		return none
	}
	for builtin in builtins {
		if builtin.name != call.name {
			continue
		}
		if call.args.len != builtin.arity {
			return none
		}
		value := builtin.apply(call.args, arena) or { return none }
		// The literal is the call's value and carries the call's type. A literal
		// built without one is a constant the emitter sizes as an int, which
		// refuses `x & llabs(-0x100000001)` at -O1 and up: a wide value has no
		// type to be written at, so the program is refused where the call at
		// -O0 compiles.
		return arena.put_int_lit(ast.IntLit{
			value: value
			text:  '${value}'
			typ:   call.typ
			line:  call.line
			col:   call.col
		})
	}
	return none
}

// constant_of evaluates what the stub calls a constant: a literal, or a literal
// with a sign or a complement in front of it. Folding `abs(1 + 2)` would mean a
// constant expression evaluator here, and the emitter already has one; until the
// two are one function, a builtin's argument has to be written out.
fn constant_of(expr ast.Expr, arena &ast.Arena, depth int) ?i64 {
	if depth > 8 {
		return none
	}
	match expr.kind {
		.int_lit {
			return arena.int_lit(expr).value
		}
		.unary {
			node := *arena.unary(expr)
			operand := constant_of(node.expr, arena, depth + 1) or { return none }
			return match node.op {
				'-' { wrap_sub(0, operand) }
				'+' { operand }
				'~' { ~operand }
				else { none }
			}
		}
		else {
			return none
		}
	}
}

fn absolute_value(args []ast.Expr, arena &ast.Arena) ?i64 {
	value := constant_of(args[0], arena, 0) or { return none }
	if value < 0 {
		// The one value with no positive counterpart wraps to itself, which is
		// what the emitter's arithmetic does with it too.
		return wrap_sub(0, value)
	}
	return value
}

// Wrapping arithmetic, for the same reason the emitter spells it out: V 0.5.2
// has no `+%`, and whether `-` traps depends on how this binary was built.
fn wrap_sub(a i64, b i64) i64 {
	return i64(u64(a) - u64(b))
}
