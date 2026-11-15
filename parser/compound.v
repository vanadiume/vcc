module parser

import ast
import tokenize
import types

// This file reads a compound literal, C99 6.5.2.5: a type name in parentheses
// followed by a brace list, `(int[]){10, 20, 30}`. The construct names an
// unnamed object whose lifetime is the enclosing block, so it is an lvalue, and
// an array one decays to a pointer to its first element wherever an array does.
//
// The object is not a shape the back end has a node for, and it does not need
// one: the tree already places a brace initializer against a named object in a
// body, one store per scalar subobject, and an object of an aggregate type has
// an address, a member and an element wherever those are wanted. So the literal
// is read as what it is - a declaration of an object with no name, followed by
// the stores that initialize it - and the expression the literal is worth is a
// use of that name. Everything after that is the code that was already there:
// `arr[1] = 21` writes through the name, `&(P){3, 4}` takes its address, and
// passing one to a function reads it the way passing a named object does.
//
// The declaration of the object is put in front of the statement the literal
// was written in, which is where the object has to be created before the
// expression that reads it runs. `parse_statement` opens one list per statement
// for this to be appended to.
//
// 6.5.2.5p7 makes that one object for a whole scope and re-initializes it every
// time the literal is evaluated. For a literal written somewhere the statement
// describes a single evaluation of, the stores go in front of the statement with
// the declaration and that is the one evaluation. For a literal written inside a
// condition, a loop step, a short-circuited operand or an arm of `?:`, the
// statement may evaluate it a number of times, so the stores are wrapped in a
// statement expression at the literal's own position: they run each time the
// literal is evaluated, and the comma makes the expression worth the object they
// wrote. The declaration still goes in front of the statement, so the object is
// one for the scope rather than one per evaluation.

// brace_list_is_constant says whether a brace list initializes its object
// without running anything: every element is a written constant - a number, a
// character or an address - rather than an expression the program evaluates,
// and a nested list is constant the same way. An object built from such a list
// holds the same bytes wherever it is built, so building it at the start of the
// statement is the object the literal would have built in place.
fn brace_list_is_constant(elements []BraceElement) bool {
	for element in elements {
		if element.expr != none {
			return false
		}
		if list := element.list {
			if !brace_list_is_constant(list.elements) {
				return false
			}
		}
	}
	return true
}

fn (mut p Parser) parse_compound_literal(spec DeclSpec, d Declarator, at tokenize.Token) !ast.Expr {
	list := p.parse_brace_initializer(true) or {
		return error('compound literal initializer')
	}
	return p.build_compound_literal(spec, d, at, list)
}

// build_compound_literal builds the object a type name and an initializer name,
// and answers the use of it. The list is what the file wrote for a literal, and
// a list the reader built itself for a construct that means the same object
// written another way: a cast to a union type is an object of the union with one
// member initialized, which is a brace list with a designated element, so the
// two arrive here as one shape rather than two.
fn (mut p Parser) build_compound_literal(spec DeclSpec, d Declarator, at tokenize.Token, list BraceList) !ast.Expr {
	if p.compound_pending.len == 0 {
		// A compound literal outside a statement is one whose object lives in
		// the image rather than in a frame. The one shape this reader builds
		// there is a pointer initialized by an array literal, which the
		// file-scope reader recognizes before it gets here.
		p.error_at(at, 'unsupported: a compound literal here is not one this compiler builds')
		return error('compound literal outside a statement')
	}
	name := p.compound_name()
	target, stmts := p.compound_literal_object(name, spec, d, at, list)
	// The stores the object is initialized with are copied into the list of the
	// statement the literal is written in, and the list they were built in is
	// this reader's own: nothing else keeps it, so the buffer it holds is freed
	// here. It is the whole of what the literals in a program allocated, 70 MB
	// of the compiler's own generated C, and with no collector a list nobody
	// frees stays.
	defer {
		unsafe { stmts.free() }
	}
	if p.compound_unstable > 0 && !brace_list_is_constant(list.elements) {
		// The literal is written where the statement may evaluate it more than
		// once and the initializer is not constant, so 6.5.2.5p7's "the object
		// is initialized each time the literal is evaluated" is observable: the
		// stores have to run at the evaluation and not once in front of the
		// statement. Only the declaration stays in front, so the object is one
		// for the scope; the stores are wrapped in a statement expression at the
		// literal's position and the comma is worth the object they wrote.
		p.compound_pending[p.compound_pending.len - 1] << stmts[0..1]
		return ast.Expr(ast.Comma{
			left:  ast.Expr(ast.StmtExpr{
				body: stmts[1..].clone()
				typ:  types.void_type()
				line: at.line
				col:  at.col
			})
			right: ast.Expr(ast.Ident{
				name: name
				typ:  target
				line: at.line
				col:  at.col
			})
			typ:   target
			line:  at.line
			col:   at.col
		})
	}
	p.compound_pending[p.compound_pending.len - 1] << stmts
	return ast.Expr(ast.Ident{
		name: name
		typ:  target
		line: at.line
		col:  at.col
	})
}

// cast_to_union reads a cast whose destination is a union type and whose operand
// is not already an object of it. GCC 6.2.7 makes such a cast a value of the
// union with the member whose type matches the operand's initialized to the
// operand, so the construct is the object a compound literal names with a
// designated element: `(union value)42` is `(union value){.i = 42}` and the two
// are one tree, built by the reader that already builds the literal.
//
// The member is chosen by type and not by position. `(union value)1.5f` writes
// the float member, which is not the first member of the union, so a list
// written positionally would write the int member and the program would read a
// wrong value. Measured on gcc 16.2.1: `(union value)42` writes the int member,
// `(union value)1.5f` the float member, and an operand whose type is no member's
// is a constraint violation - `cast to union type from type not present in
// union`, refused here by name with the location.
fn (mut p Parser) cast_to_union(at tokenize.Token, spec DeclSpec, d Declarator, destination types.Type, operand ast.Expr) !ast.Expr {
	union_type := p.tagged_type(destination)
	source := types.unqualified(p.value_type(operand))
	mut member := ''
	for candidate in union_type.members() {
		if types.unqualified(candidate.typ).compatible(source) {
			member = candidate.name
			break
		}
	}
	if member == '' {
		p.error_at(at, 'a constraint violation: a cast to ${union_type.describe()} writes the member whose type matches the operand, and no member of ${union_type.describe()} has the type ${source.describe()}')
		return error('no member of the union has the operand type')
	}
	list := BraceList{
		elements: [
			BraceElement{
				designators: [
					BraceDesignator{
						member: member
						at:     at
					},
				]
				expr:        operand
			},
		]
		at:       at
	}
	return p.build_compound_literal(spec, d, at, list)
}

// compound_name is the name of the unnamed object a compound literal declares.
// It is in the namespace the implementation reserves for itself, so no source
// text can write it, and the serial makes each literal's object its own.
fn (mut p Parser) compound_name() string {
	name := '__vcc_compound_${p.compound_serial}'
	p.compound_serial++
	return name
}

// compound_literal_object builds the declaration of the compound literal's
// object and the stores that initialize it, and answers the object's type and
// the statements. The type is the type name with a size an unsized array's
// brackets take from the list, which is the size a later `sizeof` or subscript
// reads: `(int[]){1, 2, 3}` is an int[3].
//
// The initialization is the same walk a body's brace initializer makes: every
// scalar subobject is stored zero first, because the frame slot starts as
// whatever was there and 6.7.8p21 makes the subobjects the list did not reach
// hold zero, and then each value the list wrote is stored over it. That is what
// makes a flat list, a nested list, a designator and an element that is any
// expression all one path here.
fn (mut p Parser) compound_literal_object(name string, spec DeclSpec, d Declarator, at tokenize.Token, list BraceList) (types.Type, []ast.Stmt) {
	declared := p.declared_type(spec.clause, d)
	mut target := declared
	mut count := d.array_count()
	if declared.is_array() && count <= 0 {
		// An array whose brackets named no size takes it from the list, the way
		// a declaration's does: the objects the list reaches are how many the
		// array turned out to be.
		named := brace_array_count(list.elements)
		if named > 0 {
			count = named
			target = types.array_of(declared.element() or { declared }, named)
		}
	}
	p.declare_name(name, target, at, false)
	stride := declaration_stride(target, p.representation)
	bytes := p.aggregate_bytes(declared)
	array := target.kind == .array
	element := if array { target.element() or { target } } else { target }
	element_width := p.representation.size_of(element) or { 0 }
	mut writes := brace_writes()
	defer {
		unsafe { writes.free() }
	}
	p.fill_brace(target, list.elements, 0, 0, mut writes)
	mut leaves := brace_writes()
	defer {
		unsafe { leaves.free() }
	}
	p.collect_leaves(target, 0, mut leaves)
	// The declaration comes first and a store follows for every scalar leaf and
	// every value the list wrote, so the list is that long: it is sized once,
	// which is what keeps it from doubling its way there. A growth copies the
	// stores made so far, and with no collector the copy it grew from stays.
	mut stmts := []ast.Stmt{cap: leaves.len + writes.len + 1}
	stmts << ast.Stmt{
		kind:  .var_decl
		extra: &ast.StmtExtra{
			decl_name:   name
			decl_type:   p.spelling_of(spec, d.pointer_count())
			decl_count:  count
			decl_stride: stride
			bytes:       bytes
		}
		line:  at.line
		col:   at.col
	}
	for leaf in leaves {
		stmts << p.store_a_leaf(name, at, leaf, zero_initializer(at), array, bytes, element_width,
			target)
	}
	for write in writes {
		value := if expression := write.element.expr {
			expression
		} else if number := write.element.number {
			p.constant_expr(number)
		} else {
			zero_initializer(at)
		}
		stmts << p.store_a_leaf(name, at, write, value, array, bytes, element_width, target)
	}
	return target, stmts
}

// compound_literal_size answers the size of the object a compound literal names
// without building it, which is what `sizeof (int[]){1, 2, 3}` asks: 6.5.3.4
// makes a `sizeof` operand's value a constant and its operand unevaluated, so
// the brace list is read only for the size an unsized array's brackets take
// from it, and nothing is stored.
fn (mut p Parser) compound_literal_size(spec DeclSpec, d Declarator, list BraceList) ?int {
	declared := p.declared_type(spec.clause, d)
	mut target := declared
	if declared.is_array() && d.array_count() <= 0 {
		named := brace_array_count(list.elements)
		if named > 0 {
			target = types.array_of(declared.element() or { declared }, named)
		}
	}
	return p.representation.size_of(target)
}

// looks_like_compound_literal says whether the tokens at the cursor are a
// compound literal written where only a brace list after the closing
// parenthesis can tell it from a conversion. The parenthesis are matched
// without reading anything, because the answer decides which reader runs and a
// reader that guessed would have to be undone.
fn (p Parser) looks_like_compound_literal() bool {
	if !p.at_punct('(') || !p.starts_type_name(p.peek_at(1)) {
		return false
	}
	mut depth := 0
	mut i := p.pos
	for i < p.tokens.len {
		t := p.tokens[i]
		if t.kind == .punct {
			if t.text == '(' {
				depth++
			} else if t.text == ')' {
				depth--
				if depth == 0 {
					next := i + 1
					return next < p.tokens.len && p.tokens[next].kind == .punct
						&& p.tokens[next].text == '{'
				}
			}
		}
		i++
	}
	return false
}

// file_scope_compound_object reads the type name and list of a compound literal
// written at file scope, defines the unnamed object it names, and answers that
// object's address. The object is a definition in the image like any other
// top-level object, with a name of the reader's own.
//
// `explicit` says the ampersand was written: `&(struct S){1, 2}` is the address
// whatever the object holds, while a bare `(int[]){1, 2, 3}` is an array and the
// address answered for it is the decay 6.3.2.1p3 gives an array in a value
// position. A bare literal of any other type is the object itself and not an
// address, which is the value an aggregate initializer holds and the shape
// `compound_literal_list` reads, so it is refused here by name.
//
// The initialization is the reader a named object of the same scope takes, which
// is what makes the two one shape: an array of a scalar element is a run of
// constants, and an aggregate, an array of aggregates or a scalar is the walk
// the file-scope brace initializer already places.
fn (mut p Parser) file_scope_compound_object(explicit bool) ?ast.AddressInit {
	at := p.peek()
	name := p.compound_name()
	p.next() // (
	spec, d, _ := p.parse_type_name_parts(1) or { return none }
	if !p.expect_punct(')') {
		return none
	}
	list := p.parse_brace_initializer(false) or { return none }
	declared := p.declared_type(spec.clause, d)
	if !explicit && !declared.is_array() {
		p.error_at(at, 'unsupported: a compound literal at file scope is a value of its own type, and this one is of the type ${declared.describe()}; the address of one is an address constant, and it is written with &')
		return none
	}
	written := p.spelling_of(spec, 0)
	if declared.is_array() && !(declared.element() or { declared }).kind.is_aggregate() {
		mut count := d.array_count()
		if count <= 0 {
			count = list.elements.len
		}
		element := declared.element() or { return none }
		inits, init_floats := p.initializer_list_for(written, list.elements, name, at)
		p.declared[name] = true
		p.globals << ast.Global{
			name:        name
			typ:         written
			resolved:    types.array_of(element, count)
			count:       count
			inits:       inits
			init_floats: init_floats
			line:        at.line
			col:         at.col
		}
	} else if declared.is_array() || declared.kind in [types.Kind.struct_, .union_] {
		// An object with subobjects, `&(struct S){1, 2}` or `&(int[2]){1, 2}`:
		// the list is walked against the object's own type, and each value
		// reaches the byte the layout gives the member or element it writes.
		general := p.file_scope_general_initializer(spec, d, list, name) or { return none }
		p.declared[name] = true
		p.globals << ast.Global{
			name:         name
			typ:          written
			resolved:     general.resolved
			count:        general.count
			bytes:        general.bytes
			member_inits: general.members
			line:         at.line
			col:          at.col
		}
	} else {
		// A scalar, `&(int){5}`: the object is one value, which is the list's
		// one element converted the way the object's type converts it. 6.7.8p13
		// gives a scalar initializer list at most one element, so a longer list
		// is the constraint gcc 16.2.1 reports as `excess elements in scalar
		// initializer` rather than the extra values dropped.
		if list.elements.len != 1 {
			p.error_at(at, 'a constraint violation: a compound literal of the type ${declared.describe()} is one value, and its list writes ${list.elements.len}')
			return none
		}
		element := list.elements[0]
		number := element.number or {
			p.error_at(at, 'unsupported: a compound literal of the type ${declared.describe()} is initialized with something that is not a written constant here')
			return none
		}
		init, init_float := initializer_for(written, number.number.integer, number.number.floating)
		p.declared[name] = true
		p.globals << ast.Global{
			name:       name
			typ:        written
			resolved:   declared
			init:       init
			init_float: init_float
			line:       at.line
			col:        at.col
		}
	}
	return ast.AddressInit{
		name:     name
		explicit: explicit
		line:     at.line
		col:      at.col
	}
}

// file_scope_compound_literal reads a compound literal written as the initializer
// of a pointer at file scope, where the unnamed object it names has static
// storage duration rather than the enclosing block's. The value the literal is
// worth is that object's address: `int *p = (int[]){1, 2, 3};` defines an int[3]
// holding 1, 2 and 3 and initializes p with the address of its first element,
// which is what decays an array to a pointer.
fn (mut p Parser) file_scope_compound_literal() ?ast.AddressInit {
	return p.file_scope_compound_object(false)
}

// file_scope_compound_address reads a compound literal whose address is written,
// `struct S *s = &(struct S){1, 2};`. 6.5.2.5p5 gives a literal outside the body
// of a function static storage duration, and 6.6p9 makes the address of an
// object with static storage duration an address constant, so the initializer is
// one a file-scope pointer may hold. The object is the same unnamed definition
// the decay case builds, and the ampersand is the address of it rather than a
// decay from an array.
fn (mut p Parser) file_scope_compound_address() ?ast.AddressInit {
	return p.file_scope_compound_object(true)
}
