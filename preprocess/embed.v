module preprocess

import os
import standard
import tokenize

// embed is C23 6.10.3: a directive that names a file and stands for the bytes
// in it, so that a resource is a list of numbers in the program's own text:
//
//	const unsigned char data[] = {
//	#embed "data.bin"
//	};
//
// The directive expands to a comma-separated list of integer constants, one
// per byte, and it is spliced into the token stream where the line stands. The
// numbers are the byte values in decimal, unsigned, so no `0x` spelling and no
// suffix: gcc writes `1,2,3,4` for a file of four bytes and `255` for a byte
// that is 0xFF (measured), and a program that wanted hexadecimal can say so
// with `prefix` or by not asking for this at all.
//
// The file is found the way a header is, because that is what it is to the
// preprocessor: a quoted name is looked for beside the file that wrote the
// line, then in the -I directories, then in the standard ones, and an angled
// name skips the first step. The search matters more here than for a header:
// a program embeds a file from the directory it keeps its resources in, and
// the compiler is not necessarily started in that directory, so a name
// resolved against the working directory would find the wrong file or none.
//
// The four parameters are the standard's:
//
//	limit(N)      at most N bytes are read, and N is an integer constant
//	              expression, so a macro that stands for one is allowed.
//	prefix(...)   tokens put before the first number.
//	suffix(...)   tokens put after the last number.
//	if_empty(...) what the directive becomes when it offers no byte at all.
//
// A prefix and a suffix are not written around an empty list: when the file is
// empty, or the limit counts no bytes, the directive is the if_empty content
// and nothing else. Measured on gcc 16.2.1, `#embed "empty" if_empty(7)
// prefix(9,9)` is `7` and no `9`, and a file that is empty with no if_empty is
// nothing at all. Neither gcc 16.2.1 nor clang 23.1.4 diagnoses that emptiness
// (both compile the line and leave the initializer empty), so it is not
// diagnosed here either.
//
// `__has_embed` is not here. A compiler that does not offer it leaves the name
// undefined, which is what makes `#ifdef __has_embed` false and C's own rule
// for an undefined name in an `#if` turn the call into 0; a program written for
// C23 asks `#ifdef` first for exactly that reason. The three
// `__STDC_EMBED_*` macros are part of the same operator and are not defined.

// EmbedParameters is the parameters one #embed line wrote after the file name.
// The `_set` fields are the difference between a parameter that was not
// written and one that was written with nothing in it: `if_empty()` is an
// empty replacement, and a second `limit` is a mistake whatever its value.
struct EmbedParameters {
mut:
	limit_set    bool
	limit        u64
	prefix_set   bool
	prefix       []tokenize.Token
	suffix_set   bool
	suffix       []tokenize.Token
	if_empty_set bool
	if_empty     []tokenize.Token
}

// embed reads one #embed line: the file name, the parameters, the file, and
// what the directive stands for.
fn (mut p Processor) embed(tok tokenize.Token, args string) {
	// The arguments are read from the column they start at, so a parameter
	// that is wrong is reported where it was written rather than at the hash.
	tokens := tokenize.lex_fragment_at(args, tok.line, tok.col + (tok.text.len - args.len), standard.has_digraphs(p.opts.dialect))
	if tokens.len == 0 {
		p.problem(tok, '#embed names no file')
		return
	}
	mut name := ''
	mut angled := false
	mut at := 1
	if tokens[0].kind == .string {
		name = unquoted_name(tokens[0].text)
	} else if tokens[0].kind == .punct && tokens[0].text == '<' {
		angled = true
		// What is between the brackets is the name of the file, however many
		// tokens the lexer made of it, which is the rule the include directive
		// follows for the same spelling.
		for at < tokens.len && !(tokens[at].kind == .punct && tokens[at].text == '>') {
			name += tokens[at].text
			at++
		}
		if at >= tokens.len {
			p.problem(tok, '#embed has a < with no >')
			return
		}
		at++
	} else {
		p.problem(tok, '#embed wants a "file" or a <file>, not ${tokens[0].text}')
		return
	}
	if name == '' {
		p.problem(tok, '#embed names no file')
		return
	}
	// The mode's answer is the table's, and the line is refused nowhere: a
	// mode before C23 compiles the directive and is told under -pedantic that
	// the construct is newer than the standard it names, which is what gcc
	// 16.2.1 does with the same line.
	if !p.in_system_file() {
		site := tokenize.Token{
			kind: tok.kind
			text: tok.text
			line: tok.line
			col:  tok.col
			file: p.file_name(tok)
		}
		if message := standard.dialect_message('#embed', site, standard.Question{
			mode: p.opts.dialect
		}) {
			p.diagnostics << message
		}
	}
	mut parameters := EmbedParameters{}
	for at < tokens.len {
		parameter := tokens[at]
		if parameter.kind != .identifier {
			p.problem(parameter, '#embed wants a parameter name, not ${parameter.text}')
			return
		}
		if at + 1 >= tokens.len || tokens[at + 1].kind != .punct || tokens[at + 1].text != '(' {
			p.problem(parameter, '#embed parameter ${parameter.text} wants a ( after it')
			return
		}
		argument, after := parenthesised(tokens, at + 1)
		if after < 0 {
			p.problem(parameter, '#embed ${parameter.text}( has no closing )')
			return
		}
		at = after
		match parameter.text {
			'limit' {
				if parameters.limit_set {
					p.problem(parameter, '#embed has two limit parameters, and one limit is what the line can say')
					return
				}
				parameters.limit = p.embed_limit(parameter, argument) or { return }
				parameters.limit_set = true
			}
			'prefix' {
				if parameters.prefix_set {
					p.problem(parameter, '#embed has two prefix parameters')
					return
				}
				parameters.prefix = argument
				parameters.prefix_set = true
			}
			'suffix' {
				if parameters.suffix_set {
					p.problem(parameter, '#embed has two suffix parameters')
					return
				}
				parameters.suffix = argument
				parameters.suffix_set = true
			}
			'if_empty' {
				if parameters.if_empty_set {
					p.problem(parameter, '#embed has two if_empty parameters')
					return
				}
				parameters.if_empty = argument
				parameters.if_empty_set = true
			}
			else {
				p.problem(parameter, '#embed has no parameter called ${parameter.text}')
				return
			}
		}
	}
	from := p.frames.last().path
	located := p.find_include(name, angled, from, false) or {
		p.missing_file(tok, name, angled, from, false)
		return
	}
	content := os.read_file(located.path) or {
		p.problem(tok, 'cannot read ${located.path}')
		return
	}
	// The file is a dependency the way a header is: -M lists it, because the
	// program's bytes change when the file does.
	if !p.files.any(it.path == located.path) {
		p.files << SourceFile{
			path:   located.path
			system: located.system
		}
	}
	mut count := content.len
	if parameters.limit_set && parameters.limit < u64(count) {
		// A limit past the end of the file is the whole file: the parameter
		// says how many bytes are wanted at most, not how many there are.
		count = int(parameters.limit)
	}
	if count == 0 {
		for token in p.expand_all(parameters.if_empty) {
			p.emit(p.mapped(token))
		}
		return
	}
	for token in p.expand_all(parameters.prefix) {
		p.emit(p.mapped(token))
	}
	for i in 0 .. count {
		if i > 0 {
			p.emit(embed_token(tok, .punct, ','))
		}
		p.emit(embed_token(tok, .number, '${content[i]}'))
	}
	for token in p.expand_all(parameters.suffix) {
		p.emit(p.mapped(token))
	}
}

// embed_limit reads the limit parameter. The expression is expanded and read
// by the #if reader, because what C calls an integer constant expression is
// the same arithmetic in both places; the one difference is that a name which
// is not a macro is zero in an #if and a mistake in a limit, since an #if is a
// question and a limit is an instruction.
fn (mut p Processor) embed_limit(parameter tokenize.Token, argument []tokenize.Token) ?u64 {
	if argument.len == 0 {
		p.problem(parameter, '#embed limit has nothing to count')
		return none
	}
	expanded := p.expand_all(argument)
	for token in expanded {
		if token.kind == .identifier {
			p.problem(token, '#embed limit wants an integer constant, and ${token.text} is not one')
			return none
		}
	}
	mut condition := Condition{
		tokens: expanded
		file:   parameter.file
		line:   parameter.line
		col:    parameter.col
	}
	value := condition.parse()
	p.diagnostics << condition.diagnostics
	if parsed := value {
		if !parsed.is_unsigned && i64(parsed.bits) < 0 {
			p.problem(parameter, '#embed limit is negative, and a file has no byte before its first')
			return none
		}
		return parsed.bits
	}
	return none
}

// embed_token is one token the directive stands for. It carries the place the
// directive was written, which is where a complaint about what the numbers
// made of the initializer belongs.
fn embed_token(tok tokenize.Token, kind tokenize.Kind, text string) tokenize.Token {
	return tokenize.Token{
		kind: kind
		text: text
		line: tok.line
		col:  tok.col
		file: tok.file
	}
}
