module preprocess

import standard
import tokenize

// Expanding a macro with arguments is the part of the preprocessor that is
// rules rather than code: which tokens are the arguments, which of them are
// replaced before the substitution and which are not, what a # does to one and
// what a ## does to two, and what stops an expansion that would otherwise go on
// forever. There is one function here per rule, in roughly the order the
// standard states them.
//
// The rule that stops an expansion is kept on the tokens rather than in a stack
// of the names being expanded. The standard says a macro name that arrived
// while that macro's own replacement was being built is not replaced again, and
// that is a property of the token: it stays true however many times the token is
// read afterwards. A stack answers a different question — which macros are being
// expanded right now — and the two answers part company when an argument is
// expanded before it is put in place. By the time the whole replacement is read
// again the argument's own macro has left the stack, so a name the argument was
// meant to keep quiet becomes live a second time; and a name that second read
// produces while the outer macro is still on the stack is left standing as
// ordinary text. glibc's <tgmath.h> nests macros deeply enough to reach both.

// Piece is one preprocessing token together with the names it is hidden from:
// the macro whose replacement produced it, and the macros that hid the place it
// was produced. A name in that set is not a use of that macro, however often the
// token is read again.
struct Piece {
	tok  tokenize.Token
	hide []string
}

// expansion_pieces answers a list a run of pieces is expanded into. It is filled
// here, read once by the caller and freed there; nothing slices it while it grows,
// which is what lets the runtime free the buffer a growth copies from rather than
// leave it behind. A piece is a token with the list of names it is hidden from, so
// a run that doubles its way to a thousand of them leaves two hundred kilobytes.
fn expansion_pieces() []Piece {
	mut pieces := []Piece{}
	unsafe {
		pieces.flags.set(.noslices)
	}
	return pieces
}

// produced_from turns a token of a replacement into the text of the expansion
// that happened at `site`: moved there for a diagnostic, and hidden from the
// macro being expanded and from everything that hid the use itself. The second
// part is what carries hiding around a corner: `#define A B` beside
// `#define B A` terminates because the B that A produced is hidden from A, and
// the A that B produces is hidden from both.
fn produced_from(piece Piece, site Piece) Piece {
	mut hide := piece.hide.clone()
	for name in site.hide {
		if name !in hide {
			hide << name
		}
	}
	if site.tok.text !in hide {
		hide << site.tok.text
	}
	return Piece{
		tok:  at_use_site(piece.tok, site.tok)
		hide: hide
	}
}

// shared_hide is the names the two tokens around a ## have in common. The token
// they make is hidden from those and from no other: a name that hid only one of
// the two suppressed a token that is no longer there on its own, and holding it
// against the joined token would keep a name-built-out-of-two-pieces from ever
// being read as the name it spells.
fn shared_hide(left Piece, right Piece) []string {
	mut shared := []string{}
	for name in left.hide {
		if name in right.hide {
			shared << name
		}
	}
	return shared
}

// Arguments is one macro use after the name: the argument lists, and where the
// tokens after the call begin.
struct Arguments {
	// called is false when the name was not a call at all — a function-like
	// macro's name with no ( after it is just a name in the text.
	called bool
	lists  [][]Piece
	// seps[i] says a run of whitespace stood in front of the comma that
	// separates lists[i] from lists[i + 1]. The comma itself is not part of
	// either argument, so its spelling is kept here: stringizing __VA_ARGS__
	// writes those commas back between the arguments, and whether a space
	// stood before one is the source's answer and not this compiler's.
	seps []bool
	// next is the index of the first token after the call's closing ), or
	// where the reader already was when there was no call.
	next int
}

// ScanFrame is one list being rescanned and where the scan had reached in it
// when the scan inside it started. The tokens after that position are what the
// inner scan reads when its own list runs out, so the frames are the text after
// each replacement without copying any of it.
struct ScanFrame {
mut:
	tokens []Piece
	pos    int
}

// scan_total is the text a scan can read: the list it was given and, after it,
// the tokens the scans it is inside of had not reached yet.
fn (p Processor) scan_total(tokens []Piece) int {
	mut total := tokens.len
	// The topmost frame is the scan's own list, which is `tokens`; the frames
	// under it are the text after it. A frame whose scan reached past its own
	// list has already read that far into the frame under it, so its count is
	// negative and takes those tokens off the total.
	for k := p.scan_base; k < p.scans.len - 1; k++ {
		total += p.scans[k].tokens.len - p.scans[k].pos
	}
	return total
}

// scan_at reads one token of a scan. A position past the end of the list is a
// position in the text after it, which is the rest of the scan it is inside of
// and then the rest of that one, the sequence C99 6.10.3p4 rescans. A frame
// whose own scan reached past its list passes that reach on to the frame under
// it, which is what a frame position beyond the list says.
fn (p Processor) scan_at(tokens []Piece, index int) Piece {
	if index < tokens.len {
		return tokens[index]
	}
	mut at := index - tokens.len
	for k := p.scans.len - 2; k >= p.scan_base; k-- {
		frame := p.scans[k]
		left := frame.tokens.len - frame.pos
		if at < left {
			return frame.tokens[frame.pos + at]
		}
		at -= left
	}
	return Piece{}
}

// collect_arguments reads the argument list of a macro use starting at the
// token after the name. The tokens are read from the list and then from the
// text after it, in that order, because a use a replacement starts has its
// arguments in the file. Commas inside parentheses are part of an argument and
// commas at the top level separate them, which is the only kind of nesting C
// protects.
fn (mut p Processor) collect_arguments(tokens []Piece, from int, tok tokenize.Token) Arguments {
	total := p.scan_total(tokens)
	if from >= total {
		return Arguments{
			next: from
		}
	}
	open := p.scan_at(tokens, from)
	if open.tok.kind != .punct || open.tok.text != '(' {
		return Arguments{
			next: from
		}
	}
	mut lists := [][]Piece{}
	mut seps := []bool{}
	mut current := []Piece{}
	mut depth := 1
	mut i := from + 1
	for i < total {
		t := p.scan_at(tokens, i)
		if t.tok.kind == .punct {
			if t.tok.text == '(' {
				depth++
			} else if t.tok.text == ')' {
				depth--
				if depth == 0 {
					lists << current
					return Arguments{
						called: true
						lists:  lists
						seps:   seps
						next:   i + 1
					}
				}
			} else if t.tok.text == ',' && depth == 1 {
				lists << current
				seps << t.tok.space
				current = []Piece{}
				i++
				continue
			}
		}
		current << t
		i++
	}
	p.problem(tok, 'the arguments of ${tok.text} have no closing )')
	return Arguments{
		next: from
	}
}

// expand_all returns the tokens with every macro use in them expanded. A name
// that takes arguments is a call only when a ( follows it, and the arguments
// are read from the tokens after it in the same list — which is what a call in
// a file looks like, what a call inside a replacement looks like, and what a
// call in the controlling expression of an #if looks like.
//
// The list that comes out is the caller's: the expansion arrays this function
// and the ones under it build are freed here, so the tokens are copied into one
// list and that list is the whole cost of a run. The list it is given is spent:
// a run that expands is freed on the way out, and a run that cannot expand is
// handed back as it stands, without a copy, because it is the list it was given.
fn (mut p Processor) expand_all(tokens []tokenize.Token) []tokenize.Token {
	// A run with no name that could expand is handed back as it stands. Every
	// token of straight-line code would otherwise be copied into a Piece, read
	// again, and copied into a new token list, none of which can change it: the
	// copies are what a macro use costs, and a run without one should not pay
	// them. A file of ordinary code is almost entirely runs of this kind.
	if !p.may_expand(tokens) {
		return tokens
	}
	mut pieces := []Piece{cap: tokens.len}
	defer {
		unsafe { pieces.free() }
	}
	for t in tokens {
		pieces << Piece{
			tok: t
		}
	}
	// A run that holds a name which expands into more tokens grows this list, and
	// the buffer a growth copies from is freed here: nothing slices it before it
	// is done, and the caller frees the one that comes back. Without the flag
	// each of those copies stayed, at 102.8 MB of the compiler's own generated C
	// over the headers it reads.
	mut out := []tokenize.Token{cap: pieces.len}
	unsafe {
		out.flags.set(.noslices)
	}
	expanded, _ := p.expand_pieces(pieces)
	for piece in expanded {
		out << piece.tok
	}
	unsafe { expanded.free() }
	unsafe { tokens.free() }
	return out
}

// may_expand says whether any token of a run is a name the expander would act
// on: a macro the table knows, one of the names whose value depends on where it
// is used, or the _Pragma operator. A run with none of them expands to itself,
// which is what lets expand_all hand it back without copying it.
//
// The names are exactly the ones expand_pieces looks at. A name the program
// defined itself is in the macro table and so answers here too, which is what
// keeps a program that defines __LINE__ for itself on the slow path.
fn (p Processor) may_expand(tokens []tokenize.Token) bool {
	for t in tokens {
		if t.kind != .identifier {
			continue
		}
		if t.text in p.macros || t.text == '_Pragma' || is_dynamic_builtin_name(t.text) {
			return true
		}
	}
	return false
}

// expand_pieces is expand_all over tokens that carry what they are hidden from,
// which is the form the rules inside an expansion need.
//
// TODO: `out << piece` clones the piece, which is a copy of the hiding list and of
// every name in it, and the names are already one buffer each from the intern pool:
// this plus the clones expand_all makes came to 15 MB on the compiler's own generated
// C. The append that copies instead of cloning is the fix, and it shares the hiding
// list between the two pieces, so it waits for a caller that frees one. None does
// today, which is what makes it a change to a contract rather than a line.
fn (mut p Processor) expand_pieces(tokens []Piece) ([]Piece, int) {
	// Expansion is recursive, and the guard that stops a macro naming itself
	// stops the shapes a person writes. This limit is for the shapes nobody
	// writes: without it, one that slipped past the guard would be a crash
	// instead of a diagnostic. The list that comes back is the caller's to free
	// either way, so this way out answers a copy of the list it was given.
	if p.expansion_depth >= max_expansion_depth {
		if !p.expansion_reported && tokens.len > 0 {
			p.expansion_reported = true
			p.problem(tokens[0].tok, 'the expansion here is ${max_expansion_depth} levels deep and still going')
		}
		return tokens.clone(), 0
	}
	p.expansion_depth++
	p.scans << ScanFrame{
		tokens: tokens
	}
	defer {
		p.scans.delete(p.scans.len - 1)
		p.expansion_depth--
	}
	mut out := expansion_pieces()
	mut i := 0
	for i < tokens.len {
		piece := tokens[i]
		tok := piece.tok
		if tok.kind != .identifier {
			out << piece
			i++
			continue
		}
		if tok.text == '_Pragma' {
			// `_Pragma("...")` is how a macro says a pragma, which is why it is
			// an operator and not a directive: the tokens are already past the
			// line start by the time they exist. A pragma this compiler has
			// nothing to say about is nothing, so the shape is read and the
			// text is left out.
			if after := pragma_operator(tokens, i) {
				i = after
				continue
			}
		}
		if tok.text !in p.macros {
			// __LINE__ and __FILE__ are the macros whose value is where they
			// were written, and a program that defined one of them itself has
			// the macro table answering for it instead.
			if builtin := p.dynamic_builtin(tok) {
				for t in builtin {
					out << Piece{
						tok: t
					}
				}
				unsafe { builtin.free() }
				i++
				continue
			}
			out << piece
			i++
			continue
		}
		macro := p.macros[tok.text]
		if macro.takes_arguments() {
			if tok.text in piece.hide {
				// The name is hidden from its own replacement here, so this
				// occurrence is the text it stands for and not another
				// expansion. This is the same rule as for an object-like macro,
				// and it is what stops a replacement that calls the macro it
				// came from.
				out << piece
				i++
				continue
			}
			use_args := p.collect_arguments(tokens, i + 1, tok)
			if !use_args.called {
				// The name of a function-like macro with no ( after it is not
				// a use of it, and C says it stays where it is.
				out << piece
				i++
				continue
			}
			call, used := p.expand_call(macro, use_args, piece, use_args.next)
			produced := call.len
			out << call
			unsafe { call.free() }
			i = p.finish_use(mut out, produced, tokens, use_args.next + used)
			continue
		}
		if tok.text in piece.hide {
			// The name is hidden from the expansion it came out of, so this
			// occurrence is the text it stands for and not another expansion.
			// This is the rule that makes `#define A B` beside `#define B A`
			// terminate.
			out << piece
			i++
			continue
		}
		mut replacement := []Piece{cap: macro.body.len}
		for body_token in macro.body {
			replacement << produced_from(Piece{
				tok: body_token
			}, piece)
		}
		// C99 6.10.3p4 rescans a replacement together with the text after the
		// use, so a replacement that ends inside an argument list reads the
		// rest of that list from the file. The ( that opened it is the
		// replacement's, and its arguments are the tokens after the use.
		p.scans[p.scans.len - 1].pos = i + 1
		expanded, used := p.expand_pieces(replacement)
		unsafe { replacement.free() }
		produced := expanded.len
		out << expanded
		unsafe { expanded.free() }
		i = p.finish_use(mut out, produced, tokens, i + 1 + used)
	}
	used := if i > tokens.len { i - tokens.len } else { 0 }
	return out, used
}

// finish_use reads the rest of a use that the tokens just produced did not
// finish. C99 6.10.3p4 rescans a replacement together with the text after the
// use, so a name a macro produced at the end of its expansion can be the name
// of a function-like macro whose ( is the next token of the file:
//
//     #define F(x) ((x) + 1)
//     #define G F
//     G(1)              /* is F(1), and F(1) expands */
//
// A `(` the replacement itself produced is not this case: the scan of the
// replacement reads the tokens after the use through the frame it is inside of,
// so that list is already complete by the time the scan reaches it, and
// `#define A F(` needs nothing here. What is left is a name whose `(` is still
// in the file.
//
// `out` ends with the `produced` tokens the expansion made. Each call takes its
// name back off `out` and writes the call's own tokens there, so the loop also
// reads a call whose replacement again ends in a function-like name. A name
// hidden from itself is text here as it is everywhere else, which is what keeps
// `#define G G(x)` from being expanded a second time.
fn (mut p Processor) finish_use(mut out []Piece, produced int, tokens []Piece, from int) int {
	mut i := from
	mut tail := produced
	for tail > 0 {
		last := out.last()
		if last.tok.kind != .identifier || last.tok.text !in p.macros {
			break
		}
		macro := p.macros[last.tok.text]
		if !macro.takes_arguments() || last.tok.text in last.hide {
			break
		}
		use_args := p.collect_arguments(tokens, i, last.tok)
		if !use_args.called {
			break
		}
		call, used := p.expand_call(macro, use_args, last, use_args.next)
		out.delete(out.len - 1)
		out << call
		tail = call.len
		i = use_args.next + used
		unsafe { call.free() }
	}
	return i
}

// expand_call expands one use of a macro that takes arguments: the arguments go
// where the parameters are, and the result is read again for macro uses of its
// own.
//
// The arguments are expanded as if they stood on their own — `F(F(1))` is the
// inner F being replaced — and what each of them is hidden from travels with it
// into the replacement. That is what keeps a name the argument's own expansion
// left standing from becoming live again when the replacement is read, and it is
// also what keeps a name the replacement produces from being handed to the
// outer macro as if it were written here.
fn (mut p Processor) expand_call(macro Macro, use_args Arguments, site Piece, at int) ([]Piece, int) {
	replacement := p.substitute(macro, use_args, site)
	mut hidden := []Piece{cap: replacement.len}
	for piece in replacement {
		hidden << produced_from(piece, site)
	}
	unsafe { replacement.free() }
	// The replacement the call produces is rescanned with the text after the
	// call, which is where the scan of the use had got to: `#define F(x) G(`
	// makes one call's replacement open the next list, and the file closes it.
	p.scans[p.scans.len - 1].pos = at
	out, used := p.expand_pieces(hidden)
	unsafe { hidden.free() }
	return out, used
}

// expand_argument expands one argument as C99 6.10.3.1 asks: as if it formed
// the rest of the file on its own, so no other tokens are available to it. The
// frames the use it came from is inside of are hidden while it is read, which
// is what stops a name at the end of an argument from taking a `(` that belongs
// to the file as the start of its argument list.
fn (mut p Processor) expand_argument(tokens []Piece) []Piece {
	previous := p.scan_base
	p.scan_base = p.scans.len
	expanded, _ := p.expand_pieces(tokens)
	p.scan_base = previous
	return expanded
}

// substitute is the replacement itself: every parameter is replaced by its
// argument, # stringizes the argument it is in front of, ## joins the tokens
// around it into one, and the variadic name stands for the arguments after the
// named parameters. That name is __VA_ARGS__ under the standard `...` spelling,
// and whatever name the GNU `name...` spelling gave it under that one.
fn (mut p Processor) substitute(macro Macro, arguments Arguments, site Piece) []Piece {
	tok := site.tok
	// The variable arguments are written __VA_ARGS__ under the standard `...`
	// spelling and under whatever name a GNU `name...` parameter list gave them.
	// The replacement body writes the one or the other, and this is the name it
	// may write; it is also the name `, ##` looks for, so the two spellings take
	// the same road through the code below.
	va_name := if macro.variadic_name == '' { '__VA_ARGS__' } else { macro.variadic_name }
	mut lists := arguments.lists.clone()
	// `F()` is one empty argument to a macro that takes one, and no arguments
	// at all to a macro that takes none: the count is what tells the two
	// apart, and the count is what the standard says to read it by.
	if lists.len == 1 && lists[0].len == 0 && macro.params.len == 0 {
		lists.clear()
	}
	if macro.variadic {
		if lists.len < macro.params.len {
			p.problem(tok, '${tok.text} takes at least ${macro.params.len} ${argument_word(macro.params.len)} and ${lists.len} ${were_word(lists.len)} given')
			for lists.len < macro.params.len {
				lists << []Piece{}
			}
		}
	} else if lists.len != macro.params.len {
		p.problem(tok, '${tok.text} takes ${macro.params.len} ${argument_word(macro.params.len)} and ${lists.len} ${were_word(lists.len)} given')
		for lists.len < macro.params.len {
			lists << []Piece{}
		}
		lists = lists[..macro.params.len]
	}
	mut args := map[string][]Piece{}
	for index, param in macro.params {
		args[param] = if index < lists.len { lists[index] } else { []Piece{} }
	}
	mut va_nonempty := false
	if macro.variadic {
		// __VA_ARGS__ is every argument from the variadic one on, with the
		// commas between them, because that is what the caller wrote and that
		// is what the replacement has to say.
		mut rest := []Piece{}
		for index in macro.params.len .. lists.len {
			if index > macro.params.len {
				// The comma is put back with the spacing the source gave the
				// one it stands for, which is what stringizing __VA_ARGS__
				// writes out: `S(1, 2, 3)` is "1, 2, 3" and `S(1,2,3)` is
				// "1,2,3", which is gcc's answer and C99 6.10.3.2's.
				rest << Piece{
					tok: tokenize.Token{
						kind:  .punct
						text:  ','
						space: index - 1 < arguments.seps.len && arguments.seps[index - 1]
						line:  tok.line
						col:   tok.col
						file:  tok.file
					}
				}
			}
			rest << lists[index]
		}
		args[va_name] = rest
		// __VA_OPT__ asks whether __VA_ARGS__ holds a token, not whether an
		// argument was written: measured on gcc 16.2.1, `V("a")` and `V("a",)`
		// both expand the content to nothing, and `V("a", 1)` expands it.
		va_nonempty = rest.len > 0
	}
	body := if macro.has_va_opt {
		replacement_with_va_opt(macro.body, va_nonempty)
	} else {
		macro.body
	}
	mut out := expansion_pieces()
	mut i := 0
	for i < body.len {
		t := body[i]
		if t.kind == .punct && t.text == '#' {
			// # puts the argument in a string literal without expanding it,
			// which is what makes a macro turn a name into a message.
			if i + 1 < body.len && body[i + 1].kind == .identifier && body[i + 1].text in args {
				out << Piece{
					tok: stringized(args[body[i + 1].text], tok)
				}
				i += 2
				continue
			}
			p.problem(tok, 'the # in the replacement of ${tok.text} is not in front of one of its parameters')
			i++
			continue
		}
		if t.kind == .punct && t.text == '##' {
			if i + 1 >= body.len {
				p.problem(tok, 'the ## at the end of the replacement of ${tok.text} has nothing to join')
				i++
				continue
			}
			next := body[i + 1]
			right := if next.kind == .identifier && next.text in args {
				args[next.text]
			} else {
				[Piece{
					tok: at_use_site(next, tok)
				}]
			}
			if right.len == 0 {
				// An empty argument on the right of a ##: nothing is joined,
				// and the token on the left stands alone. `, ## __VA_ARGS__`
				// with no arguments after it is the reason the rule exists:
				// it is how a macro writes a comma that is only there when
				// something follows it.
				if macro.variadic && out.len > 0 && out.last().tok.kind == .punct && out.last().tok.text == ',' {
					out.delete(out.len - 1)
				}
				i += 2
				continue
			}
			if macro.variadic && next.text == va_name && out.len > 0 && out.last().tok.kind == .punct && out.last().tok.text == ',' {
				// With arguments, the same spelling writes the comma and the
				// tokens out as they are: a comma joined to the token after it
				// is not a paste anybody means.
				for u in right {
					out << u
				}
				i += 2
				continue
			}
			if out.len == 0 {
				for u in right {
					out << u
				}
				i += 2
				continue
			}
			left := out.last()
			out.delete(out.len - 1)
			for u in p.paste(left, right[0], tok) {
				out << u
			}
			for u in right[1..] {
				out << u
			}
			i += 2
			continue
		}
		if t.kind == .identifier && t.text in args {
			raw := args[t.text]
			// An argument is expanded before it is put in place — unless it
			// stands beside a # or a ##, where the tokens themselves are the
			// point and the expansion would lose them.
			beside_paste := (i + 1 < body.len && is_paste(body[i + 1])) || (i > 0 && is_paste(body[i - 1]))
			mut text := []Piece{cap: raw.len}
			for argument in raw {
				text << Piece{
					tok:  at_use_site(argument.tok, tok)
					hide: argument.hide.clone()
				}
			}
			if !beside_paste {
				expanded := p.expand_argument(text)
				unsafe { text.free() }
				for u in expanded {
					out << u
				}
				unsafe { expanded.free() }
				i++
				continue
			}
			for u in text {
				out << u
			}
			unsafe { text.free() }
			i++
			continue
		}
		out << Piece{
			tok: at_use_site(t, tok)
		}
		i++
	}
	return out
}

// replacement_with_va_opt is the replacement the rest of the substitution reads:
// every `__VA_OPT__( content )` is the content when the variable arguments hold
// at least one token and nothing when they do not. The content is spliced in
// before the body is walked, so a #, a ## and a parameter inside it do the work
// they would do anywhere else in the replacement, and the result is rescanned
// with the rest of it.
//
// `nonempty` is whether __VA_ARGS__ holds a token, not whether an argument was
// written. Measured on gcc 16.2.1, `V("a")` and `V("a",)` both expand the
// content to nothing while `V("a", 1)` expands it.
fn replacement_with_va_opt(body []tokenize.Token, nonempty bool) []tokenize.Token {
	mut out := []tokenize.Token{cap: body.len}
	mut i := 0
	for i < body.len {
		t := body[i]
		if t.kind != .identifier || t.text != '__VA_OPT__' || i + 1 >= body.len
			|| body[i + 1].kind != .punct || body[i + 1].text != '(' {
			out << t
			i++
			continue
		}
		mut depth := 0
		mut close := -1
		for j := i + 1; j < body.len; j++ {
			if body[j].kind != .punct {
				continue
			}
			if body[j].text == '(' {
				depth++
			} else if body[j].text == ')' {
				depth--
				if depth == 0 {
					close = j
					break
				}
			}
		}
		if close < 0 {
			// The shape was refused where the definition was read; keep the
			// token so the rest of the replacement still has an answer.
			out << t
			i++
			continue
		}
		if nonempty {
			for j := i + 2; j < close; j++ {
				out << body[j]
			}
		}
		i = close + 1
	}
	return out
}

// check_replacement refuses the __VA_OPT__ shapes the standard does not allow and
// asks the dialect table whether the selected mode takes the operator. It runs
// where a replacement list is read rather than where it is used, because the
// answer is a property of the definition: gcc 16.2.1 reports both the nested
// form and the non-variadic one on the #define line, whether or not the macro is
// ever called. Its answer says whether the body writes the operator at all, which
// the macro records so a use does not have to scan the body again.
fn (mut p Processor) check_replacement(at tokenize.Token, body []tokenize.Token, variadic bool) bool {
	mut writes_va_opt := false
	mut i := 0
	for i < body.len {
		t := body[i]
		if t.kind != .identifier || t.text != '__VA_OPT__' {
			i++
			continue
		}
		writes_va_opt = true
		if !variadic {
			p.problem(at, "'__VA_OPT__' may only appear in the replacement list of a variadic macro")
			i++
			continue
		}
		if i + 1 >= body.len || body[i + 1].kind != .punct || body[i + 1].text != '(' {
			p.problem(at, "'__VA_OPT__' is written as __VA_OPT__( content )")
			i++
			continue
		}
		mut depth := 0
		mut close := -1
		for j := i + 1; j < body.len; j++ {
			if body[j].kind != .punct {
				continue
			}
			if body[j].text == '(' {
				depth++
			} else if body[j].text == ')' {
				depth--
				if depth == 0 {
					close = j
					break
				}
			}
		}
		if close < 0 {
			p.problem(at, "'__VA_OPT__' has no closing )")
			break
		}
		for j := i + 2; j < close; j++ {
			if body[j].kind == .identifier && body[j].text == '__VA_OPT__' {
				p.problem(at, "'__VA_OPT__' may not appear inside a '__VA_OPT__'")
				break
			}
		}
		i = close + 1
	}
	if writes_va_opt && !p.in_system_file() {
		// A directive token carries no file of its own: where it is to be
		// reported is the frame's answer, the same one p.problem reads.
		site := tokenize.Token{
			kind: at.kind
			text: at.text
			line: at.line
			col:  at.col
			file: p.file_name(at)
		}
		if message := standard.dialect_message('__VA_OPT__', site, standard.Question{
			mode: p.opts.dialect
		}) {
			p.diagnostics << message
		}
	}
	return writes_va_opt
}

// paste joins two tokens into one by writing them together and reading the
// result back, which is what a preprocessor does with ##: `__GLIBC_USE_ ## F`
// is how a header builds one name out of two pieces.
//
// Two tokens that do not read back as one are not a paste. The standard leaves
// the answer undefined there, and both tokens are kept, because both of them
// are real and the one that is not real is the joined one.
fn (mut p Processor) paste(left Piece, right Piece, tok tokenize.Token) []Piece {
	joined := left.tok.text + right.tok.text
	lexed := tokenize.lex_fragment(joined, standard.has_digraphs(p.opts.dialect))
	if lexed.len == 1 {
		return [
			Piece{
				tok:  tokenize.Token{
					kind: lexed[0].kind
					text: lexed[0].text
					line: tok.line
					col:  tok.col
					file: tok.file
				}
				hide: shared_hide(left, right)
			},
		]
	}
	p.problem(tok, 'the ## in the replacement of ${tok.text} joins ${left.tok.text} and ${right.tok.text}, which do not make one token')
	return [left, right]
}

fn is_paste(t tokenize.Token) bool {
	return t.kind == .punct && t.text == '##'
}

// stringized writes an argument the way a # writes it: the tokens as they were
// spelled, a run of whitespace between two of them as one space and none at
// either end, quoted, and with the quotes and backslashes of the text escaped
// so the result is the string literal it says it is.
//
// The space goes in front of a token when the source put one there, which is
// C99 6.10.3.2 and not a space between every pair: `a + b` keeps its spaces and
// `a+b` has none, and a comma separating variadic arguments carries the
// argument's own spacing rather than a pair of spaces this compiler added.
fn stringized(tokens []Piece, tok tokenize.Token) tokenize.Token {
	mut spelling := ''
	for index, t in tokens {
		if index > 0 && t.tok.space {
			spelling += ' '
		}
		spelling += t.tok.text
	}
	mut quoted := '"'
	for i in 0 .. spelling.len {
		c := spelling[i]
		if c == `"` || c == `\\` {
			quoted += '\\'
		}
		quoted += c.ascii_str()
	}
	quoted += '"'
	return tokenize.Token{
		kind: .string
		text: quoted
		line: tok.line
		col:  tok.col
		file: tok.file
	}
}

// at_use_site moves a token of a replacement or of an argument to the place the
// macro was used: what the standard asks, and what makes a diagnostic inside an
// expansion point at something a person wrote. The spelling's own spacing stays
// with it, because it is still the token's: an argument is stringized where it
// was read, and moving it should not lose the space a # has to write back.
fn at_use_site(t tokenize.Token, use tokenize.Token) tokenize.Token {
	return tokenize.Token{
		kind:  t.kind
		text:  t.text
		space: t.space
		line:  use.line
		col:   use.col
		file:  use.file
	}
}

fn argument_word(count int) string {
	return if count == 1 { 'argument' } else { 'arguments' }
}

fn were_word(count int) string {
	return if count == 1 { 'was' } else { 'were' }
}

// pragma_operator reads `_Pragma ( "text" )` starting at the name and returns
// where the tokens after it start, or nothing when what follows is not that
// shape — in which case the name is a name and the caller writes it out. The
// operand has to be one string literal and nothing else, which is what makes the
// operator impossible to get wrong in the way a pragma spelled across lines is.
fn pragma_operator(tokens []Piece, at int) ?int {
	if at + 3 >= tokens.len {
		return none
	}
	if tokens[at + 1].tok.text != '(' || tokens[at + 2].tok.kind != .string || tokens[at + 3].tok.text != ')' {
		return none
	}
	return at + 4
}
