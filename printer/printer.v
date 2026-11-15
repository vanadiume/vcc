module printer

import ast
import types

// The printer turns a translation unit into text. It is what `-print-ast` runs,
// and it exists as its own module because `ast/` is node types only: the shape
// of a node and the way it reads are different jobs, and a tree that can print
// itself grows a print method on every node.
//
// The output is deterministic — same tree, same text — because it is read by
// people comparing two runs, and a dump that reorders its own lines is a dump
// nobody can diff.
//
// Every node the parser gave a type to carries it, written after the location it
// came from: `int 42 at 1:17 : int`. The clause is the model's answer and not the
// spelling, which is the point of printing it — a reader comparing the two sees
// where a declaration was read and where it was resolved. A node the model could
// not answer for says `: unresolved`, so that a missing clause means the printer
// had none to print and never that the reader has no answer.

// max_indent is where indentation stops growing. A chain of twenty thousand terms
// is twenty thousand levels deep, and growing the indent all the way down would
// print two spaces for every level of every line: hundreds of megabytes of
// whitespace for a file with one expression in it. Past this depth the levels
// are simply level with each other, and the order still reads.
const max_indent = 32

// render turns a unit into an indented tree, one node per line, with the
// location each node came from.
//
// Not named `dump`: V has a `dump()` builtin that wins over a function of the
// same name inside its own module, so the call would compile into the builtin's
// behavior with no diagnostic at the call site.
pub fn render(unit ast.TranslationUnit) string {
	mut out := []string{}
	for global in unit.globals {
		mut line := 'global ${global.name} ${global.typ}'
		if global.count > 0 {
			line += '[${global.count}]'
		}
		if init := global.init {
			line += ' = ${init}'
		} else {
			line += ' (zeroed)'
		}
		out << '${line} at ${global.line}:${global.col}${typed(global.resolved)}'
	}
	if unit.decls.len == 0 {
		out << '(no declarations)'
	}
	for decl in unit.decls {
		out << 'fn ${decl.name}() ${decl.ret} at ${decl.line}:${decl.col}${typed(decl.resolved)}'
		if !decl.defined {
			out << '  (declaration without a definition)'
			continue
		}
		dump_statements(decl.body, 1, &unit.arena, mut out)
	}
	return out.join('\n')
}

// typed is the type clause of a node, written after the location it came from. A
// node with no answer carries the zero type, whose kind is unknown, and says so:
// the alternative - printing nothing - would read the same as a node this printer
// has no clause for.
fn typed(typ types.Type) string {
	if typ.kind == .unknown {
		return ' : unresolved'
	}
	return ' : ${typ.describe()}'
}

fn indent_of(depth int) string {
	level := if depth > max_indent { max_indent } else { depth }
	return '  '.repeat(level)
}

fn dump_statements(body []ast.Stmt, depth int, arena &ast.Arena, mut out []string) {
	for stmt in body {
		indent := indent_of(depth)
		match stmt.kind {
			.return_stmt {
				out << '${indent}return at ${stmt.line}:${stmt.col}'
			}
			.block {
				out << '${indent}block at ${stmt.line}:${stmt.col}'
			}
			.empty {
				out << '${indent}empty statement at ${stmt.line}:${stmt.col}'
			}
			.expr_stmt {
				out << '${indent}expression statement at ${stmt.line}:${stmt.col}'
			}
			.var_decl {
				elements := if stmt.decl_count() > 0 { '[${stmt.decl_count()}]' } else { '' }
				out << '${indent}declaration of ${stmt.decl_type()} ${stmt.decl_name()}${elements} at ${stmt.line}:${stmt.col}${typed(stmt.resolved())}'
			}
			.assign {
				if stmt.deref().is_none() {
					out << '${indent}assignment to ${stmt.target} at ${stmt.line}:${stmt.col}'
				} else {
					out << '${indent}assignment through a dereference at ${stmt.line}:${stmt.col}'
				}
			}
			.if_stmt {
				out << '${indent}if at ${stmt.line}:${stmt.col}'
			}
			.while_stmt {
				out << '${indent}while at ${stmt.line}:${stmt.col}'
			}
			.do_while_stmt {
				out << '${indent}do at ${stmt.line}:${stmt.col}'
			}
			.break_stmt {
				out << '${indent}break at ${stmt.line}:${stmt.col}'
			}
			.continue_stmt {
				out << '${indent}continue at ${stmt.line}:${stmt.col}'
			}
			.switch_stmt {
				out << '${indent}switch at ${stmt.line}:${stmt.col}'
			}
			.case_stmt {
				if stmt.case_is_range() {
					out << '${indent}case ${stmt.case_value()} ... ${stmt.case_value_high()} at ${stmt.line}:${stmt.col}'
				} else {
					out << '${indent}case ${stmt.case_value()} at ${stmt.line}:${stmt.col}'
				}
			}
			.default_stmt {
				out << '${indent}default at ${stmt.line}:${stmt.col}'
			}
			.label_stmt {
				out << '${indent}label ${stmt.label()} at ${stmt.line}:${stmt.col}'
			}
			.goto_stmt {
				if stmt.goto_expr().is_none() {
					out << '${indent}goto ${stmt.label()} at ${stmt.line}:${stmt.col}'
				} else {
					out << '${indent}computed goto at ${stmt.line}:${stmt.col}'
					dump_expression(stmt.goto_expr(), depth + 1, arena, mut out)
				}
			}
			.asm_stmt {
				out << '${indent}asm statement ${stmt.asm_spelling()} at ${stmt.line}:${stmt.col}'
				// An asm goto carries the labels its template may jump to,
				// which name places in this function the way a goto's target
				// does, so the printer names them beside the template.
				labels := stmt.asm_goto_labels()
				if stmt.asm_is_goto() || labels.len > 0 {
					out << '${indent}jumping to ${labels.join(', ')}'
				}
			}
			.nested_function {
				fn_decl := stmt.nested_fn() or { ast.FnDecl{} }
				out << '${indent}nested function ${fn_decl.name} of ${fn_decl.owner} at ${stmt.line}:${stmt.col}'
			}
		}
		if !stmt.expr.is_none() {
			dump_expression(stmt.expr, depth + 1, arena, mut out)
		}
		if !stmt.index.is_none() {
			out << '${indent}subscript'
			dump_expression(stmt.index, depth + 1, arena, mut out)
		}
		if !stmt.deref().is_none() {
			out << '${indent}through'
			dump_expression(stmt.deref(), depth + 1, arena, mut out)
		}
		if !stmt.initializer().is_none() {
			out << '${indent}initializer'
			dump_expression(stmt.initializer(), depth + 1, arena, mut out)
		}
		if !stmt.cond.is_none() {
			out << '${indent}condition'
			dump_expression(stmt.cond, depth + 1, arena, mut out)
		}
		dump_statements(stmt.body, depth + 1, arena, mut out)
		dump_statements(stmt.then_body(), depth + 1, arena, mut out)
		dump_statements(stmt.else_body(), depth + 1, arena, mut out)
		if stmt.step().len > 0 {
			// The step of a loop is written under its own heading, because it
			// is a part of the loop and not a part of the body.
			out << '${indent}step'
			dump_statements(stmt.step(), depth + 1, arena, mut out)
		}
	}
}

// dump_expression prints an expression. The left spine of an operator chain is
// walked with a loop for the same reason the folder and the optimizer walk it
// that way: a chain of ten thousand terms is one node deep in the grammar and
// ten thousand deep in the tree, and recursion over it runs the stack out on a
// file that is only doing what generated code does.
//
// The spine prints outermost first, its operands after it, so `6 * 7 + 1` reads
// as the tree it is:
//
//	binary + at ...
//	  binary * at ...
//	    int 6 at ...
//	    int 7 at ...
//	  int 1 at ...
fn dump_expression(expr ast.Expr, depth int, arena &ast.Arena, mut out []string) {
	mut spine := []ast.Expr{}
	mut node := expr
	for node.kind == .binary {
		spine << node
		node = arena.binary(node).left
	}
	mut current := depth
	for step in spine {
		binary := arena.binary(step)
		out << '${indent_of(current)}binary ${binary.op} at ${binary.line}:${binary.col}${typed(binary.typ)}'
		current++
	}
	dump_leaf(node, current, arena, mut out)
	// The right sides come after the left spine, innermost first, which is the
	// order they were written in.
	for i := spine.len - 1; i >= 0; i-- {
		dump_expression(arena.binary(spine[i]).right, depth + i + 1, arena, mut out)
	}
}

fn dump_leaf(expr ast.Expr, depth int, arena &ast.Arena, mut out []string) {
	indent := indent_of(depth)
	span := arena.span(expr)
	typ := arena.typ(expr)
	match expr.kind {
		.int_lit {
			node := arena.int_lit(expr)
			out << '${indent}int ${node.value} at ${span.line}:${span.col}${typed(typ)}'
		}
		.float_lit {
			// The value is printed as a double rather than as the spelling it
			// was written with, because what the emitter reads is the value.
			// A decimal constant is not a double and its double field is
			// zero, so it prints the value it does hold, which is the digits
			// and the power of ten, in the form the standard's conversion
			// writes them.
			node := arena.float_lit(expr)
			if typ.kind.is_decimal() {
				out << '${indent}decimal ${node.decimal_value.text()} at ${span.line}:${span.col}${typed(typ)}'
			} else {
				out << '${indent}double ${node.value} at ${span.line}:${span.col}${typed(typ)}'
			}
		}
		.complex_lit {
			// The imaginary constant's value is its imaginary part, and the
			// real part is the zero 6.4.4.2 leaves it.
			node := arena.complex_lit(expr)
			out << '${indent}imaginary ${node.value} at ${span.line}:${span.col}${typed(typ)}'
		}
		.ident {
			node := arena.ident(expr)
			out << '${indent}ident ${node.name} at ${span.line}:${span.col}${typed(typ)}'
		}
		.unary {
			node := arena.unary(expr)
			out << '${indent}unary ${node.op} at ${span.line}:${span.col}${typed(typ)}'
			dump_expression(node.expr, depth + 1, arena, mut out)
		}
		.binary {
			// The spine loop leaves no Binary for this function to see; the arm
			// is here because the match covers every node the tree can hold.
			dump_expression(expr, depth, arena, mut out)
		}
		.call {
			node := arena.call(expr)
			if node.callee.is_none() {
				out << '${indent}call ${node.name} with ${node.args.len} argument(s) at ${span.line}:${span.col}${typed(typ)}'
			} else {
				// A call written to an expression prints the expression, since
				// the name it would otherwise print is the one thing it is not.
				out << '${indent}call through an expression with ${node.args.len} argument(s) at ${span.line}:${span.col}${typed(typ)}'
				dump_expression(node.callee, depth + 1, arena, mut out)
			}
			for arg in node.args {
				dump_expression(arg, depth + 1, arena, mut out)
			}
		}
		.str_lit {
			node := arena.str_lit(expr)
			out << '${indent}string ${node.text} at ${span.line}:${span.col}${typed(typ)}'
		}
		.index {
			node := arena.index(expr)
			out << '${indent}element[] at ${span.line}:${span.col}${typed(typ)}'
			dump_expression(node.base, depth + 1, arena, mut out)
			dump_expression(node.index, depth + 1, arena, mut out)
		}
		.field {
			// The offset is printed because it is the part of the node the
			// source does not say: `x.b` is where the layout put b, and that
			// number is what the emitter reads.
			node := arena.field(expr)
			object := if node.index.is_none() { node.name } else { '${node.name}[...]' }
			out << '${indent}member ${object}.${node.member} at +${node.offset} bytes, ${node.spelling}, at ${span.line}:${span.col}${typed(typ)}'
		}
		.cast {
			node := arena.cast(expr)
			out << '${indent}cast to ${node.spelling} at ${span.line}:${span.col}${typed(typ)}'
			dump_expression(node.expr, depth + 1, arena, mut out)
		}
		.inc_dec {
			// The form is printed beside the operator because `x++` and `++x`
			// are the same step and differ only in the value they are worth.
			node := arena.inc_dec(expr)
			form := if node.postfix { 'postfix' } else { 'prefix' }
			out << '${indent}${form} ${node.op} at ${span.line}:${span.col}${typed(typ)}'
			dump_expression(node.operand, depth + 1, arena, mut out)
		}
		.conditional {
			// The three operands are printed in the order they were written,
			// which is what makes the branch the emitter builds readable. The
			// middle one is marked when the source left it out: the node holds
			// the condition there as well, and a dump that printed it without a
			// word would read as one the program wrote.
			node := arena.conditional(expr)
			omitted := if node.omitted_middle { ' middle omitted' } else { '' }
			out << '${indent}conditional at ${span.line}:${span.col}${typed(typ)}${omitted}'
			dump_expression(node.cond, depth + 1, arena, mut out)
			dump_expression(node.then_expr, depth + 1, arena, mut out)
			dump_expression(node.else_expr, depth + 1, arena, mut out)
		}
		.assign {
			// The target is printed before the value, which is the order they
			// are written in and the order the store runs them in.
			node := arena.assign(expr)
			out << '${indent}assign ${node.op} at ${span.line}:${span.col}${typed(typ)}'
			dump_expression(node.target, depth + 1, arena, mut out)
			dump_expression(node.value, depth + 1, arena, mut out)
		}
		.comma {
			node := arena.comma(expr)
			out << '${indent}comma at ${span.line}:${span.col}${typed(typ)}'
			dump_expression(node.left, depth + 1, arena, mut out)
			dump_expression(node.right, depth + 1, arena, mut out)
		}
		.stmt_expr {
			// The statements are printed first, in the order they run, and the
			// value expression after them, which is the order the emitter
			// produces for this node.
			node := arena.stmt_expr(expr)
			out << '${indent}statement expression at ${span.line}:${span.col}${typed(typ)}'
			dump_statements(node.body, depth + 1, arena, mut out)
			if !node.value.is_none() {
				dump_expression(node.value, depth + 1, arena, mut out)
			}
		}
		.none {}
	}
}
