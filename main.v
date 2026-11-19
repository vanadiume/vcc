module main

import backend
import backend.os.linux
import cli
import codegen
import diagnostics
import extensions
import image as unit
import linking
import linking.archive
import linking.object
import linking.output
import optimizer
import os
import parser
import preprocess
import printer
import standard
import time
import tokenize

// vcc: read a command line, run the pipeline over one source file, write the
// image. The stages are the modules named after them, and this file is only the
// wiring between them.
fn main() {
	opts := cli.parse(os.args[1..]) or {
		eprintln('vcc: ${err.msg()}')
		eprintln('')
		eprintln(cli.usage(false))
		exit(1)
	}
	if opts.show_help_all {
		println(cli.usage(true))
		return
	}
	if opts.show_help {
		println(cli.usage(false))
		return
	}
	if opts.show_version {
		println(cli.version_line())
		return
	}
	if opts.show_paths {
		println(cli.version_line())
		target := backend.host() or {
			println('target: none')
			return
		}
		println('target: ${target.name}')
		println('optimize: ${opts.optimization.summary()}')
		println('standard: ${standard_line(opts)}')
		println('emulation: ${emulation_line(opts)}')
		println('extensions: ${extensions_line(opts.vcc_extensions)}')
		println('recorded: ${recorded_line(opts.ignored)}')
		if opts.include_dirs.len == 0 {
			println('include: (the -I directories, none given)')
		}
		for dir in opts.include_dirs {
			println('include: ${dir}')
		}
		if opts.nostdinc {
			println('include: (the standard directories, which -nostdinc turns off)')
		} else {
			for dir in standard_include_dirs() {
				println('include: ${dir} (standard)')
			}
		}
		return
	}
	if opts.verbose {
		verbose_print(verbose_header_lines(opts))
	}
	// A -print- flag asks a question and stops, so it needs no input file. That
	// is how a build system asks a compiler where its things are before it has
	// anything to compile: it reads the answer off the standard output and does
	// not want a file, an object or a diagnostic beside it.
	if opts.asks_query() {
		target := backend.resolve(opts.target) or {
			abort(err.msg())
			return
		}
		if opts.verbose {
			verbose_print(verbose_query_lines(opts, target))
		}
		println(query_answer(opts, target))
		return
	}
	if opts.inputs.len == 0 {
		eprintln('vcc: no input files')
		eprintln('')
		eprintln(cli.usage(false))
		exit(1)
	}
	// Two linkers on one command line is one of them dropped in silence, so the
	// pair is refused before either path is taken: -fuse-ld is dispatched below
	// and would otherwise answer for a link -flegacy-ld also asked for.
	if refusal := opts.linker_conflict_refusal() {
		abort(refusal)
	}
	// -fuse-ld is its own path: it links the inputs this compiler cannot
	// consume and is taken before the single-input refusals below, because those
	// refusals are what the flag exists to lift. A run that stops before a link
	// keeps to the ordinary path and the flag goes unused, the way a linker flag
	// that names a tool a run never reaches does anywhere else: it asks for
	// something the run does not do, and refusing the command line would make a
	// flag that decides nothing an error.
	if opts.fuse_ld != '' && opts.links() {
		fuse_ld_link(opts)
		return
	}
	// -shared and -static decide what a link writes, and the path with no linker
	// writes all three kinds of file: the container has a shape for each. Both
	// flags are therefore read here rather than refused. The one command line
	// that is refused is the pair asking for different files, because a link
	// that took one flag would drop the other without a word.
	if refusal := opts.link_kind_conflict_refusal() {
		abort(refusal)
	}
	// Every other link runs through the vlk library, which is the default now.
	// That path reads the whole command line as one link: it takes every input
	// the way the multi-input path does, whether the line named one file or
	// ten, because the library's merge is what writes the container. The
	// single-input path below writes that container from the one program its
	// emitter produced instead, and -flegacy-ld is the flag that asks for it.
	if opts.links() && !opts.legacy_ld {
		link_inputs(opts)
		return
	}
	// -flegacy-ld is the linker this tree carried before the library. It is
	// deprecated and gets no more work after this merge, and it is kept for one
	// release so a build that has to compare the two images can still ask for
	// it. The paths below are unchanged from before the library became the
	// default.
	//
	// More than one input is a link, and a link is the linker's job: every
	// input is compiled as one unit of it, the merge settles the references
	// between them, and the container writes the one program. The single-input
	// path below writes that container from the one program it emitted
	// instead, which is why the stub is a detail of its emitter there and a
	// unit of the link here. A run that stops before a link has no list of
	// units to hand over, and each of those options reads one file, so it is
	// refused by name rather than linked from a subset of what it was given.
	if opts.inputs.len > 1 {
		if !opts.links() {
			abort('more than one input is a link, and this run stops before one: -c, -E, -M and -print-ast each read one file, so name the inputs one command at a time')
			return
		}
		link_inputs(opts)
		return
	}
	// A -l name that resolves to an archive is a link input, and a .c input is
	// compiled as the object it produces at its own place on the command line.
	// `vcc main.c -lx` is therefore the same link as `vcc main.o -lx`, and it
	// takes the path that reads archives: the single-input path below writes a
	// program from one unit and has nowhere to put a member the link pulls. A
	// shared library is the other answer - the loader maps it and settles its
	// names when the program starts - so naming one keeps the single-input
	// path.
	if opts.links() && names_a_static_archive(opts) {
		link_inputs(opts)
		return
	}
	if opts.verbose {
		verbose_print(verbose_include_dir_lines(opts))
	}
	path := opts.inputs[0]
	source := read_source(path) or {
		abort('cannot read ${path}: ${err.msg()}')
		return
	}
	// What the input is decides whether it is read as source at all. An object
	// or an archive is an input to a link rather than a file to parse, and
	// reading one as source answers a wrong input kind with a parse error
	// raised from inside a binary file. The bytes are classified rather than the
	// path so that standard input, which cannot be read twice, is decided by the
	// same rule.
	//
	// A single object, archive or shared object is a link with one input, so a
	// run that writes a program hands it to the linker's path, which reads it
	// as the unit it holds or as a library it names. The options that read one
	// file stop before a link and are refused by name. A program is not a link
	// input at all.
	kind := cli.classify_input(source, path, opts.input_type)
	if kind != .source {
		if !opts.links()
			|| (kind != .object && kind != .archive && kind != .shared_object) {
			abort(cli.input_refusal(path, kind))
			return
		}
		if path == '-' {
			abort('standard input holds ${kind.describe()}, and a link reads its inputs from files')
			return
		}
		link_inputs(opts)
		return
	}
	// A static program is linked rather than written from one unit, because the
	// only static program that can reach a library is the one the library
	// itself starts. Which of the two a static link needs is decided once its
	// units are read, in the linker's path below, so every static link takes
	// that path and one rule decides it.
	if opts.links() && link_kind(opts) == .static_program {
		link_inputs(opts)
		return
	}
	mut phases := []cli.Phase{}
	mut started := time.now()
	// Lexing happens inside the preprocessor, which is the stage that knows
	// which file it is reading and what to do with the directives it finds.
	processed := preprocess.preprocess(source, path, read_options(opts))
	phases << cli.Phase{
		name:   'preprocess'
		micros: time.since(started).microseconds()
	}
	if opts.verbose {
		verbose_print(verbose_file_lines(processed.files))
	}
	// A warning is reported and the compile goes on; an error ends it, and so
	// does a warning the command line promoted. Which is which is asked of the
	// diagnostic and of the policy rather than counted, so that a stage which
	// hands back a warning is not mistaken for a stage that failed.
	//
	// A run that only asks what the file is made of — -M without -MD, -E, -dM —
	// has no compile for that promotion to stop, and its answer is the whole
	// point of the command: a build that passes a promotion flag to a dependency
	// step, which is harmless under gcc and was harmless here before these flags
	// existed, must still get its rule. Measured, gcc reports and writes in that
	// run: `gcc -M -std=c99 -Werror=cpp` over a file carrying a `#warning` exits
	// 0 with the rule and empty stderr, `-dM` exits 0 with the macros, and `-E`
	// writes the stream, where the same command line without a read-only switch
	// exits 1. So both stages of such a run — the preprocessor's own report here
	// and the dialect check below — are reported under the policy a read-only
	// run is reported under, which keeps a message a flag asked for printed and
	// takes its verdict back. A compile keeps the policy the command line gave,
	// so there a promotion still ends it.
	reading_only := (opts.deps && !opts.deps_compile) || opts.preprocess || opts.dump_macros
	policy := if reading_only { opts.warnings.without_promotion() } else { opts.warnings }
	if report(path, processed.diagnostics, policy) > 0 {
		exit(1)
	}
	// The dialect check runs over the stream the preprocessor produced, which is
	// the one place the whole program is in a single list. It reports the
	// constructs the selected mode does not allow and refuses nothing; a message
	// the flags promoted is the only way it can stop a compile. It is reported
	// under the same policy as the stage above, so the two stages of a read-only
	// run agree and neither of them can drop the answer.
	pedantic := dialect_messages(processed, opts)
	if report(path, pedantic, policy) > 0 {
		exit(1)
	}
	// -M and -dM answer a question about the read and stop there: a build tool
	// asking what a file is made of does not want an object file at the end of
	// its command line. -MD is the other half of that question — write the rule
	// and compile as well — and its rule goes beside the object unless -MF
	// says otherwise.
	if opts.deps && !opts.deps_compile {
		write_dependencies(path, processed.files, opts)
		return
	}
	if opts.deps {
		write_dependencies(path, processed.files, opts)
	}
	if opts.dump_macros {
		print_macros(processed.macros)
		return
	}
	if opts.preprocess {
		print_tokens(processed.tokens)
		return
	}
	started = time.now()
	// The front end needs the target as much as the emitter does: the width of a
	// pointer and of an int, the offset a member sits at, the type a constant is
	// given and the class an aggregate is handed over in are all the target's, and
	// a second target would make the host the wrong answer for every one of them.
	parsed := parser.parse_with(processed.tokens, parser_target(opts.target), opts.bracket_depth)
	phases << cli.Phase{
		name:   'parse'
		micros: time.since(started).microseconds()
	}
	if report(path, parsed.diagnostics, opts.warnings) > 0 {
		exit(1)
	}
	started = time.now()
	optimized := optimizer.optimize(parsed.unit, opts.optimization)
	phases << cli.Phase{
		name:   'opt'
		micros: time.since(started).microseconds()
	}
	if opts.print_ast {
		// The tree the emitter would be handed, which is the useful one to read
		// when a level is suspected of doing the wrong thing.
		println(printer.render(optimized))
		return
	}
	// The -Wl, options this run's link takes. They are the container's facts
	// and not the code's, so a run that stops before a link (-c) leaves them
	// unread, the way a linker flag on a compile-only command line does in any
	// other compiler. The refusal is here rather than in `parse` because parse
	// cannot know which linker will read the words.
	mut link_options := linux.LinkOptions{}
	if opts.links() {
		link_options = in_house_link_options(opts) or {
			abort(err.msg())
			return
		}
	}
	// The target this run builds for, resolved here as well as in the emitter
	// because the include search and the link flags both read it: a freestanding
	// target has no standard headers and no C library.
	run_target := target_of_run(opts)
	// The runtime archive's names, read before the unit is emitted: the import
	// check has to know which of the unit's names the link will answer from an
	// archive rather than from a library, and a program that reaches one of them
	// is handed to the link path below, which is the path that reads archives.
	//
	// A -l name that resolves to a static archive is the same kind of input. The
	// single-input path wraps its image in the emitter and reads no archive, so a
	// program that calls a member of one cannot be finished there: the name would
	// be reported undefined by a link that never opened the file. Reading the
	// members' names here is what hands the run to the link, which pulls them.
	mut archive_names := map[string]bool{}
	if !opts.compile_only && link_kind(opts) == .program {
		if opts.default_libraries() {
			archive_names = runtime_names(opts, run_target)
		}
		for name, _ in library_archive_names(opts, run_target) {
			archive_names[name] = true
		}
	}
	started = time.now()
	image := codegen.emit(optimized, codegen.Options{
		target:               opts.target
		entry:                'main'
		compile_only:         opts.compile_only
		pic:                  opts.pic
		ignore_natives:       opts.ignore_natives
		dialect:              opts.dialect
		bracket_depth:        opts.bracket_depth
		link_kind:            link_kind(opts)
		link_options:         link_options
		libraries:            opts.libraries
		library_dirs:         opts.library_dirs
		no_default_libraries: !default_libraries(opts, run_target)
		archive_names:        archive_names.keys()
	})
	phases << cli.Phase{
		name:   'emit'
		micros: time.since(started).microseconds()
	}
	if report(path, image.diagnostics, opts.warnings) > 0 {
		exit(1)
	}
	// A program that reaches a name the runtime archive answers is a link and not
	// a wrapping: the archive is an input, and the path that reads archives is the
	// linker's. The unit is compiled a second time there, and that is the price of
	// the ordinary path staying one pass over one file, which is the path almost
	// every program takes. The names come from the same read of the archive the
	// import check was given, so the two cannot disagree about what the link will
	// answer.
	//
	// A shared object is left out because its helper references are the loader's
	// to resolve, and a static program never arrives here: it takes the link path
	// above, where its archives are read.
	if archive_names.len > 0 && program_reaches_archive(image.program, archive_names) {
		link_inputs(opts)
		return
	}
	out_path := if opts.output != '' {
		opts.output
	} else if opts.compile_only {
		// The object keeps the source's name with .o where its last extension
		// was, which is where a build looks for it without being told.
		object_name(path, opts)
	} else if opts.run {
		temporary_path()
	} else {
		'a.out'
	}
	if opts.compile_only {
		// A relocatable file is read by a linker and never run, so it is written
		// without the execute bit an image gets.
		write_object(out_path, image.bytes) or {
			abort('cannot write ${out_path}: ${err.msg()}')
			return
		}
	} else {
		write_image(out_path, image.bytes) or {
			abort('cannot write ${out_path}: ${err.msg()}')
			return
		}
	}
	if opts.verbose {
		verbose_print(verbose_result_lines(opts, phases, image.bytes, out_path))
	}
	if opts.bench {
		for line in cli.bench_lines(phases) {
			eprintln(line)
		}
	}
	if opts.run {
		run_image(out_path, opts.run_args)
	}
}

// read_options is what every input is read with, whether it is the one file the
// ordinary path reads or one more unit of a link: the same -I, -D, -U, prelude
// and dialect, so that a link's units are read the way the same files read one
// command at a time would be.
fn read_options(opts cli.Options) preprocess.Options {
	return preprocess.Options{
		include_dirs:   opts.include_dirs
		defines:        language_defines(opts)
		actions:        opts.define_actions
		standard_dirs:  standard_include_dirs_for(opts)
		preludes:       opts.preludes
		undef_builtins: opts.undef_builtins
		hosted:         target_of_run(opts).hosted
		// The mode goes to the read as well as to the dialect check, because
		// phase 1 asks it a question before a token exists: whether a trigraph
		// is replaced.
		dialect:        opts.dialect
	}
}

// dialect_messages are the constructs the selected mode does not allow, read off
// the stream the preprocessor produced. It is the same check for one unit of a
// link as for the one file the ordinary path reads.
fn dialect_messages(processed preprocess.Result, opts cli.Options) []tokenize.Diagnostic {
	return standard.pedantic_messages(processed.tokens, standard.Question{
		mode:         opts.dialect
		extensions:   opts.vcc_extensions.enabled_names()
		system_files: system_files(processed.files)
	})
}

// provided_with adds one unit's definitions to a set of names a link already
// answers. A definition is a function this unit defines and an object whose
// storage it holds, which is a name in `globals` that is not a copy of a
// library's: a unit that only refers to an external object puts a slot in
// `globals` for it too. A name the unit gives internal linkage is no answer to
// another unit's reference (6.2.2p2), so it stays out.
fn provided_with(mut provided map[string]bool, entry unit.Program) {
	for name, _ in entry.defined {
		if name !in entry.internal {
			provided[name] = true
		}
	}
	for name, _ in entry.globals {
		if name !in entry.copy_objects && name !in entry.internal {
			provided[name] = true
		}
	}
}

// pull_members pulls from one archive the members that answer a name the link
// still needs, and goes round that archive again while a member it pulled opens
// a name the archive itself answers. The sweep stops there: a name a member
// leaves open is answered by an archive written later on the command line, and
// an archive written earlier has already had its turn. That is the order ld
// gives a command line, and it is why `-lb -la` and `-la -lb` are two different
// links: the second answers `alpha`'s call to `beta` and the first does not.
//
// The walk carries the link's two sets. `provided` is every name the units seen
// so far define, and `needed` is every name one of them uses. A member is read
// once: pulling it puts its definitions in `provided`, and the test below then
// skips it. `which` is the archive's place in the walk, so the key a member is
// remembered under cannot collide with another archive holding a member of the
// same name. The names are walked in sorted order rather than off the map so
// one command line always pulls the same members in the same order.
fn pull_members(which int, parts archive.Archive, target backend.Target, mut needed map[string]bool, mut provided map[string]bool, mut pulled map[string]bool) ![]unit.Program {
	mut out := []unit.Program{}
	mut again := true
	for again {
		again = false
		mut names := parts.index.keys()
		names.sort()
		for name in names {
			// A name no unit of the link defines yet is the only one a member
			// is pulled for. It is the rule ld follows, and what keeps the C
			// library's copy of a name the runtime's own crt1.o already
			// defines from joining the link: two definitions of one name are
			// what a link refuses.
			if !needed[name] || provided[name] {
				continue
			}
			index := parts.index[name]
			key := '${which}:${index}'
			if key in pulled {
				continue
			}
			pulled[key] = true
			member := parts.members[index]
			entry := object.read(member.bytes, target) or {
				return error('${member.name}: ${err.msg()}')
			}
			note_unit(mut provided, mut needed, entry)
			out << entry
			again = true
		}
	}
	return out
}

// note_unit adds one unit's definitions and open names to the sets a link walks
// its archives with. The definitions go in first, so a unit that imports a name
// it also defines does not open it again. A weak import is left out because an
// undefined weak symbol stands for zero, which is no archive's to answer.
fn note_unit(mut provided map[string]bool, mut needed map[string]bool, entry unit.Program) {
	provided_with(mut provided, entry)
	for symbol in entry.imports {
		if symbol !in provided && symbol !in entry.weak_imports {
			needed[symbol] = true
		}
	}
}

// pull_group searches a group of archives together: every archive in it is
// swept again while a sweep pulled a member, because the libraries a link adds
// for itself are one group rather than a sequence. That is what the gcc driver
// writes for a static link - `--start-group -lgcc -lgcc_eh -lc --end-group` -
// and it is not an optimization: libc.a reaches into libgcc.a for a soft-float
// routine and libgcc.a reaches back into libc.a for a thread primitive, so one
// pass in either order leaves one of the two open. The command line's own -l
// names are not a group: they are searched where they were written, by
// pull_members, and an archive written earlier does not answer a name opened by
// an archive written later.
fn pull_group(archives []archive.Archive, first int, target backend.Target, mut needed map[string]bool, mut provided map[string]bool, mut pulled map[string]bool) ![]unit.Program {
	mut out := []unit.Program{}
	mut again := true
	for again {
		again = false
		for a, parts in archives {
			members := pull_members(first + a, parts, target, mut needed, mut provided,
				mut pulled)!
			if members.len > 0 {
				out << members
				again = true
			}
		}
	}
	return out
}

// read_unit reads one file as the relocatable object a link merges. The start
// files of a link are objects of this compiler's own reading, so a link that
// puts the C library's startup around its program reads them the way it reads
// an object the command line named.
fn read_unit(path string, target backend.Target) !unit.Program {
	source := read_source(path)!
	return object.read(source.bytes(), target)
}

// has_constructors says whether any unit of the link carries a constructor or
// destructor table, which is what decides whether whoever starts the image has
// to run anything before `main`.
fn has_constructors(units []unit.Program) bool {
	for unit in units {
		if unit.init_array.count > 0 || unit.fini_array.count > 0 {
			return true
		}
	}
	return false
}

// has_tls says whether any unit of the link defines thread-local storage. A
// static program that holds one has to be started by the C library, which is
// what sets the thread pointer up: the loader does that for a dynamic program,
// and a program this compiler starts with its own stub has nothing to do it, so
// every read of a thread-local would read whatever the pointer happened to hold.
fn has_tls(units []unit.Program) bool {
	for unit in units {
		if unit.tls_size > 0 {
			return true
		}
	}
	return false
}

// needs_a_library says whether the units name a function or an object that none
// of them defines, which is what makes a link reach outside itself. The names a
// unit defines are collected first and the imports asked against them, because a
// name one unit imports and another defines is the link's own business and not a
// library's.
fn needs_a_library(units []unit.Program) bool {
	mut defined := map[string]bool{}
	for unit in units {
		for name, _ in unit.defined {
			defined[name] = true
		}
		for name, _ in unit.globals {
			defined[name] = true
		}
	}
	for unit in units {
		for name in unit.imports {
			if name !in defined {
				return true
			}
		}
	}
	return false
}

// link_inputs is the multi-input path. Every input is compiled as one unit of a
// link, the units are merged with the process stub, and the one program the link
// calls for is written. The stub is built here and placed first, because text
// offset zero is the stub and so the image's entry point is text offset zero
// whatever the units do with a `main` of their own; the single-input path has
// the emitter write that stub into the one image instead.
fn link_inputs(opts cli.Options) {
	if opts.verbose {
		verbose_print(verbose_include_dir_lines(opts))
	}
	// The -Wl, options are read before any input is, so an option this linker
	// cannot express names itself and stops the run before a whole compile has
	// produced objects for a link that would not have honored it.
	link_options := in_house_link_options(opts) or {
		abort(err.msg())
		return
	}
	target := backend.resolve(opts.target) or {
		abort(err.msg())
		return
	}
	// A shared object has no process stub: nothing starts it and the image's
	// entry point is zero. Every other kind of link starts at a stub this
	// compiler writes, unless the units bring an entry point of their own,
	// which is what the C library's start files do; that is decided below,
	// once the units are read, because it is the units that say whether the
	// link reaches a library.
	output_kind := link_kind(opts)
	mut units := []unit.Program{cap: opts.inputs.len + 1}
	// The shared objects the command line named as files. They are not units:
	// the link records them as libraries the image asks the loader for and
	// leaves the names they define to the loader, so they travel beside the
	// units rather than into the merge.
	mut shared := []linux.Library{}
	mut reading := i64(0)
	mut parsing := i64(0)
	mut optimizing := i64(0)
	mut emitting := i64(0)
	// The members pulled out of archives, in the order the archives were
	// reached. They are kept apart from the units the command line named until
	// the start files have been placed: whether the link is started by the C
	// library is a question about the named units, and a pulled member that
	// carries a constructor is refused below rather than started in silence.
	mut pulled := []unit.Program{}
	// The two sets the archives are asked with, built while the command line is
	// walked. `provided` is every name a unit so far defines and `needed` every
	// name one of them leaves open. A program's entry is open before the first
	// word, because the start file or the stub this link writes is what calls
	// it, and both stand in front of the command line's own inputs.
	mut provided := map[string]bool{}
	mut needed := map[string]bool{}
	if output_kind == .program {
		needed['main'] = true
	}
	// A member is remembered under the place its archive holds in the walk, so
	// two archives that each hold a member of one name are still two members
	// and the same archive named twice is searched at both places.
	mut member_keys := map[string]bool{}
	mut archive_count := 0
	for item in opts.link_items {
		if item.library {
			// A -l name is resolved where it sits on the line. A shared library
			// answers nothing here: the loader maps it and settles its names
			// when the program starts. An archive, and the archives a GNU ld
			// script names beside a shared object, are read now: after the
			// objects written before the name and before the objects written
			// after it.
			files := target.archive_libraries([item.value], opts.library_dirs, output_kind == .static_program) or {
				abort(err.msg())
				return
			}
			for file in files {
				source := read_source(file.path) or {
					abort('cannot read ${file.path}: ${err.msg()}')
					return
				}
				parts := archive.read(source.bytes()) or {
					abort('${file.path}: ${err.msg()}')
					return
				}
				members := pull_members(archive_count, parts, target, mut needed, mut provided,
					mut member_keys) or {
					abort(err.msg())
					return
				}
				pulled << members
				archive_count++
			}
			continue
		}
		path := item.value
		source := read_source(path) or {
			abort('cannot read ${path}: ${err.msg()}')
			return
		}
		// What the input is decides how it is read, by the rule the single-input
		// path uses: source is compiled into a unit, an object is read back into
		// the unit it holds, a shared object is read for the name the loader is
		// asked for, and an archive the command line named as a file is read
		// where it stands, the same way its -l spelling would be. A program is
		// an input this compiler does not read, and reading one as source would
		// answer a wrong input kind with a parse error raised from inside a
		// binary file.
		kind := cli.classify_input(source, path, opts.input_type)
		if kind == .shared_object {
			// A static program has no loader, so a library it cannot unpack
			// into itself has no way to answer a name when the program runs.
			// The refusal names the file rather than leaving the merge to
			// report a symbol, because the file is the thing that cannot be
			// used here.
			if output_kind == .static_program {
				abort('${path}: a shared object is not an input to a static link: a static program is started with no loader to map it')
				return
			}
			shared << linux.shared_library(path) or {
				abort('${path}: ${err.msg()}')
				return
			}
			continue
		}
		if kind == .object {
			read := object.read(source.bytes(), target) or {
				abort('${path}: ${err.msg()}')
				return
			}
			note_unit(mut provided, mut needed, read)
			units << read
			continue
		}
		if kind == .archive {
			parts := archive.read(source.bytes()) or {
				abort('${path}: ${err.msg()}')
				return
			}
			members := pull_members(archive_count, parts, target, mut needed, mut provided,
				mut member_keys) or {
				abort(err.msg())
				return
			}
			pulled << members
			archive_count++
			continue
		}
		if kind != .source {
			abort(cli.input_refusal(path, kind))
			return
		}
		mut started := time.now()
		processed := preprocess.preprocess(source, path, read_options(opts))
		reading += time.since(started).microseconds()
		if opts.verbose {
			verbose_print(verbose_file_lines(processed.files))
		}
		if report(path, processed.diagnostics, opts.warnings) > 0 {
			exit(1)
		}
		if report(path, dialect_messages(processed, opts), opts.warnings) > 0 {
			exit(1)
		}
		started = time.now()
		parsed := parser.parse_with(processed.tokens, parser_target(opts.target), opts.bracket_depth)
		parsing += time.since(started).microseconds()
		if report(path, parsed.diagnostics, opts.warnings) > 0 {
			exit(1)
		}
		started = time.now()
		optimized := optimizer.optimize(parsed.unit, opts.optimization)
		optimizing += time.since(started).microseconds()
		started = time.now()
		emitted := codegen.emit(optimized, codegen.Options{
			target:         opts.target
			link:           true
			link_kind:      output_kind
			ignore_natives: opts.ignore_natives
			dialect:        opts.dialect
			bracket_depth:  opts.bracket_depth
			libraries:      opts.libraries
			library_dirs:   opts.library_dirs
		})
		emitting += time.since(started).microseconds()
		if report(path, emitted.diagnostics, opts.warnings) > 0 {
			exit(1)
		}
		note_unit(mut provided, mut needed, emitted.program)
		units << emitted.program
	}
	// The C library is on every image whether or not a -l named it, and the
	// archives the ld script beside its shared object names are inputs of the
	// same kind. glibc keeps there the functions that cannot live in a shared
	// object at all, `atexit` among them, so a dynamic link that maps libc.so.6
	// and pulls no archive of its own still owes an answer for every object
	// that calls one. They come after the command line's own words, where a
	// linker's implicit libraries sit. A static link has them through
	// static_support_libraries, which is read where the start files are.
	//
	mut support := []string{}
	// -nostdlib and -nodefaultlibs are read here and not at the archive pull: a
	// link with no default libraries is one whose every library the command line
	// named, so the C library's archives and the runtime archive are not inputs
	// at all, and nothing is left for the pull to keep out.
	if default_libraries(opts, target) {
		if output_kind != .static_program && output_kind != .shared {
			for library in target.base_library_archives(opts.library_dirs) {
				support << library.path
			}
		}
		// The runtime is a program's. A shared object does not take one: its
		// helper references are what the loader resolves from whatever maps it,
		// and this compiler writes the runtime for a program. A static link
		// takes it through static_support_libraries, which is where the list of
		// archives it resolves against is written down.
		//
		// Which kind of input it is decides where it goes: an archive is read
		// for its members and its member answers the helper, and a shared
		// object is a name the loader is asked for, which is the list the
		// command line's own .so inputs are on.
		if output_kind == .program {
			if runtime := runtime_archive(opts, target) {
				if runtime.archive {
					support << runtime.path
				} else {
					shared << linux.shared_library(runtime.path) or {
						abort('${runtime.path}: ${err.msg()}')
						return
					}
				}
			}
		}
	}
	// A link that carries a constructor table is started by the C library's own
	// entry point rather than by a stub this compiler writes, and so is a static
	// link that reaches a library.
	//
	// The constructor table is the reason. glibc's loader runs the initializers
	// of every object it maps except the program itself: `call_init` returns
	// when the map has no name and is an executable, and the main program's name
	// is emptied as it is mapped. The initializers of the program are run by the
	// C library's startup instead, which walks `__init_array_start` to
	// `__init_array_end` - two names the linker answers for, because it is what
	// knows where the tables landed. A program this compiler starts with its own
	// stub calls `main` with its constructors never run, and a constructor that
	// does not run is a wrong answer rather than a missing feature.
	//
	// The start files come from the system's own description, resolved in the
	// directories a link searches, and they go around the units in the order a
	// link puts them: crt1.o holds the entry point, so it is what the merged
	// text begins with and what the image's entry point is.
	//
	// -nostdlib is the one flag that takes them away, and the test is at the
	// front because both halves of `reach` are reasons to put start files
	// around a link: a constructor table wants the C library's startup to walk
	// it, and a static link that reaches a library wants crt1.o to name it.
	reach := start_files(opts, target) && (has_constructors(units) || (output_kind == .static_program
		&& (needs_a_library(units) || has_tls(units))))
	mut entry := if output_kind == .shared { '' } else { 'main' }
	if reach {
		before, after := target.start_file_paths(output_kind, opts.library_dirs) or {
			abort(err.msg())
			return
		}
		// The start files go in front of the units, in the order a link places
		// them, so the last one is prepended first and crt1.o ends up at text
		// offset zero, where the container reads the entry point from.
		mut i := before.len
		for i > 0 {
			i--
			start := read_unit(before[i], target) or {
				abort('${before[i]}: ${err.msg()}')
				return
			}
			note_unit(mut provided, mut needed, start)
			units.prepend(start)
		}
		for path in after {
			start := read_unit(path, target) or {
				abort('${path}: ${err.msg()}')
				return
			}
			note_unit(mut provided, mut needed, start)
			units << start
		}
		// A static link resolves the library's own objects out of its archives, and
		// static_support_libraries is where its list is written down. A link with
		// no default libraries has no such list: the C library is not one of its
		// inputs, and neither is a runtime archive.
		if output_kind == .static_program && default_libraries(opts, target) {
			for path in target.static_support_libraries(opts.library_dirs, runtime_library_name(opts)) {
				support << path
			}
		}
		entry = '_start'
	} else if output_kind != .shared {
		stub := codegen.start_stub(entry, codegen.Options{
			target:               opts.target
			link_kind:            output_kind
			no_default_libraries: !default_libraries(opts, target)
		})
		// The stub is emitted from a constant entry name and the exit
		// sequence, so it has nothing to report; a diagnostic here is this
		// compiler failing rather than an input. It goes through the one place
		// a diagnostic becomes text, with no file to name because it has none.
		if report('', stub.diagnostics, opts.warnings) > 0 {
			exit(1)
		}
		units.prepend(stub.program)
		note_unit(mut provided, mut needed, stub.program)
		// The stub is the entry point, so crt1.o is the one start file this link
		// leaves out. The rest go around the units the way they do a link that takes
		// the C library's entry, and crtbegin.o is where __dso_handle is defined. A
		// program built without them links with an undefined __dso_handle the moment
		// the C library's non-shared archive is read, which is where atexit lives.
		//
		// There are none of them under -nostdlib: the flag takes the start files
		// away from every link, including the one whose entry point is this
		// compiler's own stub.
		if start_files(opts, target) {
			before, after := target.stub_start_file_paths(opts.library_dirs) or {
				abort(err.msg())
				return
			}
			mut i := before.len
			for i > 0 {
				i--
				start := read_unit(before[i], target) or {
					abort('${before[i]}: ${err.msg()}')
					return
				}
				note_unit(mut provided, mut needed, start)
				units.prepend(start)
			}
			for path in after {
				start := read_unit(path, target) or {
					abort('${path}: ${err.msg()}')
					return
				}
				note_unit(mut provided, mut needed, start)
				units << start
			}
		}
	}
	// The implicit archives are read now, after the command line's own words and
	// after the start files: the names those files open are the ones the C
	// library's archives were put there to answer. They are one group and are
	// swept together, because the C library and the runtime reach into each
	// other. A member whose symbols nothing refers to stays where it is, the
	// way a linker leaves it, so a library of many objects adds the ones the
	// program asks for.
	mut support_parts := []archive.Archive{}
	for path in support {
		source := read_source(path) or {
			abort('cannot read ${path}: ${err.msg()}')
			return
		}
		support_parts << archive.read(source.bytes()) or {
			abort('${path}: ${err.msg()}')
			return
		}
	}
	pulled << pull_group(support_parts, archive_count, target, mut needed, mut provided,
		mut member_keys) or {
		abort(err.msg())
		return
	}
	// A constructor table that arrived with a member pulled out of an archive is
	// one the program's own startup would have to walk, and this link is not
	// started by the library: the stub calls `main` and leaves, so the constructor
	// would be skipped in silence. Only the pulled members are asked, because the
	// start files carry constructors of their own - crtbegin.o registers a frame -
	// and those are the compiler's own startup rather than the program's.
	if !reach && output_kind != .shared && has_constructors(pulled) {
		abort('a member pulled out of an archive carries a constructor, and this link is not started by the C library: name the library with -l, or the constructor would never run')
		return
	}
	units << pulled
	mut started := time.now()
	merge_options := linking.Options{
		entry:                entry
		target:               target
		libraries:            opts.libraries
		library_dirs:         opts.library_dirs
		shared_libraries:     shared
		no_default_libraries: !default_libraries(opts, target)
	}
	// The two linkers take the same units and the same options, and they differ
	// in whose code performs the link. vlk's high entry does the merge, the
	// library check and the container in one call and answers the image's
	// bytes; the legacy path does the merge and hands the merged program to
	// the container. -flegacy-ld is the one place the two are chosen between,
	// so the phases below are measured over whichever ran.
	bytes := if opts.legacy_ld {
		merged := linking.link(units, merge_options) or {
			abort(err.msg())
			return
		}
		output.image(merged, target, link_kind(opts), link_options) or {
			abort(err.msg())
			return
		}
	} else {
		linking.link_vlk(units, merge_options, link_kind(opts), link_options) or {
			abort(err.msg())
			return
		}
	}
	linked := time.since(started).microseconds()
	// One line per phase for the whole command, because a build reading -bench
	// wants what the link cost rather than a row per input: each number is the
	// sum over the units and the last one is the merge and the container.
	mut phases := []cli.Phase{}
	phases << cli.Phase{
		name:   'preprocess'
		micros: reading
	}
	phases << cli.Phase{
		name:   'parse'
		micros: parsing
	}
	phases << cli.Phase{
		name:   'opt'
		micros: optimizing
	}
	phases << cli.Phase{
		name:   'emit'
		micros: emitting
	}
	phases << cli.Phase{
		name:   'link'
		micros: linked
	}
	out_path := if opts.output != '' {
		opts.output
	} else if opts.run {
		temporary_path()
	} else {
		'a.out'
	}
	write_image(out_path, bytes) or {
		abort('cannot write ${out_path}: ${err.msg()}')
		return
	}
	if opts.verbose {
		verbose_print(verbose_result_lines(opts, phases, bytes, out_path))
	}
	if opts.bench {
		for line in cli.bench_lines(phases) {
			eprintln(line)
		}
	}
	if opts.run {
		run_image(out_path, opts.run_args)
	}
}

// language_defines are the -D arguments the compiler hands the preprocessor: the
// ones that identify this compiler, the ones the selected mode adds, and the
// conformance claims the implementation makes about its types. They are applied
// before the command line, which is what makes a -D win over the mode and over
// the identity, the way it wins over a built-in in gcc: the command line's
// arguments arrive separately as cli.Options.define_actions and are applied
// after these, in the order they were written. -undef takes all of the
// compiler's own macros away with every other macro that describes the target.
fn language_defines(opts cli.Options) []string {
	if opts.undef_builtins {
		return []
	}
	mut out := []string{}
	out << preprocess.identity_defines(cli.version)
	out << preprocess.standard_defines(opts.dialect, opts.emulation)
	out << preprocess.conformance_defines(opts.dialect)
	return out
}

// system_files is the set of files the dialect check stays out of: the headers
// that came from the standard directories, which nobody in the build wrote and
// nobody in the build can fix.
fn system_files(files []preprocess.SourceFile) map[string]bool {
	mut out := map[string]bool{}
	for file in files {
		if file.system {
			out[file.path] = true
		}
	}
	return out
}

// standard_line is what -vv says about the dialect: the spelling the command line
// wrote and the mode it names, so that a build reading the output can tell what
// the flag bought.
fn standard_line(opts cli.Options) string {
	if opts.standard == '' {
		return 'no -std (mode ${standard.default_mode.spelling()}, ${standard.default_mode.standard_name()}): the default'
	}
	match opts.dialect {
		.other {
			return '${opts.standard} (a spelling this compiler does not implement; recorded, never refused)'
		}
		else {
			return '${opts.standard} (mode ${opts.dialect.spelling()}, ${opts.dialect.standard_name()})'
		}
	}
}

// parser_target is the target the front end resolves widths for: the one the
// command line names, or the machine this binary runs on when it names none.
//
// A name this compiler does not describe is passed on as the host rather than as
// no description at all. The refusal for an unknown target belongs to the
// emitter, which is the layer that reads what the flag means, and a parse that
// could answer no width at all would report the same bad command line as a page
// of refusals about the source, which sends the reader to the wrong file.
fn parser_target(name string) ?backend.Target {
	target := backend.resolve(name) or { return backend.host() }
	return target
}

// emulation_line is what -vv says about -femulation: the compiler whose identity
// macros the build asked for, or that it asked for none and this compiler's own
// are the answer.
fn emulation_line(opts cli.Options) string {
	if opts.emulation == .none {
		return '(none; this compiler reports its own identity)'
	}
	return '${opts.emulation.spelling()} (the identity macros of that compiler are defined)'
}

// extensions_line is what -vv says about the vendor extensions: which are on,
// what each one brings down, and which names exist, so that one command answers
// what -fvcc-exts= did. Every part of it comes from the extension column of the
// standard table, which is the only place an extension is named.
fn extensions_line(chosen extensions.Options) string {
	offered := extensions.names()
	enabled := chosen.enabled_names()
	if enabled.len == 0 {
		return 'none enabled (the names it has are ${offered.join(', ')})'
	}
	mut said := []string{}
	for name in enabled {
		said << '${name} brings down ${extensions.brings(name)}'
	}
	return '${said.join('; ')} (of ${offered.join(', ')})'
}

// recorded_line is what -vv says about the flags the compiler accepted and did
// not act on. They are all there, so a build can see that a flag it passed was
// recorded rather than honored.
fn recorded_line(ignored []string) string {
	if ignored.len == 0 {
		return '(nothing: every flag was acted on)'
	}
	return ignored.join(' ')
}

// read_source takes the path or the source itself, so a pipeline that feeds the
// compiler on standard input works the way it does with tcc.
fn read_source(path string) !string {
	if path == '-' {
		return os.get_raw_stdin().bytestr()
	}
	return os.read_file(path)
}

// write_image writes an image, and gives it the execute bit only when the output
// is a regular file. A path naming a device node or a fifo is written to and left
// alone: /dev/null is how a build asks whether a source compiles, and chmod there
// fails for an unprivileged user and changes a device node for root.
//
// The stat follows a symlink, because the write does: an image written through a
// link lands in the file the link names, and that file is the one to run.
fn write_image(path string, bytes []u8) ! {
	os.write_file_array(path, bytes)!
	info := os.stat(path)!
	if (info.mode & os.s_ifmt) == os.s_ifreg && (info.mode & os.s_ixusr) == 0 {
		os.chmod(path, 0o755)!
	}
}

// write_object writes a relocatable file. It is the same bytes as an image and
// not the same kind of file: a linker reads it rather than the kernel running
// it, so it gets no execute bit.
fn write_object(path string, bytes []u8) ! {
	os.write_file_array(path, bytes)!
}

// run_image runs what was just compiled and leaves with its exit status, which is
// what `-run` means: the compiler becomes the program it produced.
//
// The program is given the terminal rather than a pipe, because its output is
// the whole reason for running it: a captured stream would arrive after the
// program had finished, on the wrong one of the two, and in one lump. The
// arguments travel as an array and reach the program as separate words, so
// nothing in one of them is read again as syntax. A name with no directory in it
// is given one first: `-o prog` names the file this compiler just wrote, while
// the call below looks a bare word up on PATH, which is not where that file is.
fn run_image(path string, args []string) {
	program := if path.contains(os.path_separator) { path } else { './${path}' }
	mut invocation := [program]
	invocation << args
	status := os.system_args(invocation)
	if status == -1 {
		eprintln('vcc: cannot run ${path}: no such file, or it is not executable')
		exit(127)
	}
	exit(status)
}

fn temporary_path() string {
	return os.join_path(os.temp_dir(), 'vcc-run-${os.getpid()}')
}

// print_tokens is what `-E` does: the stream the parser would be handed, one
// token per line, with the file and the position each token was written at.
fn print_tokens(tokens []tokenize.Token) {
	for tok in tokens {
		println('${tok.file}:${tok.line}:${tok.col}\t${tok.kind}\t${tok.text}')
	}
}

// write_dependencies is what `-M` does: the make rule that says what the file
// is made of. It is printed, or written where -MF says, and the compile stops
// there — make reads the rule to decide whether to run the compile at all, and
// running it as well would be doing the work twice.
//
// -MM leaves the headers that came from the standard directories out of the
// rule: a build that already knows where the C library is does not need to be
// told again, and a rule naming /usr/include changes whenever the machine does.
fn write_dependencies(source string, files []preprocess.SourceFile, opts cli.Options) {
	mut words := []string{}
	for file in files {
		if !opts.deps_system && file.system {
			continue
		}
		words << escape_for_make(file.path)
	}
	rule := '${escape_for_make(dependency_target(source, opts))}: ${words.join(' ')}'
	to := dependency_file(source, opts)
	if to == '' {
		// With -M and no -MF the rule goes to the standard output, which is
		// where a build that asked for it reads it from.
		println(rule)
		return
	}
	os.write_file(to, '${rule}\n') or {
		abort('cannot write ${to}: ${err.msg()}')
		return
	}
}

// dependency_file is where the rule is written: the file -MF names, or for
// -MD and -MMD the object's name with .d in place of its extension, which is
// where a build looks for it without being told. It is the object's name and not
// the rule's target: -MT decides what the rule says and not what file it is said
// in. With -M and no -MF there is no file and the rule is printed.
fn dependency_file(source string, opts cli.Options) string {
	if opts.deps_file != '' {
		return opts.deps_file
	}
	if !opts.deps_compile {
		return ''
	}
	base := object_name(source, opts)
	dot := base.last_index('.') or { return '${base}.d' }
	return '${base[..dot]}.d'
}

// dependency_target is what the rule is for: the name -MT or -MQ gives it, or
// the object the compile writes, which is the file make would look for.
fn dependency_target(source string, opts cli.Options) string {
	if opts.deps_target != '' {
		return opts.deps_target
	}
	return object_name(source, opts)
}

// object_name is the file the compile produces: the one named with -o when
// there is one, and the source with its last extension changed to .o otherwise.
fn object_name(source string, opts cli.Options) string {
	if opts.output != '' {
		return opts.output
	}
	dot := source.last_index('.') or { return '${source}.o' }
	return '${source[..dot]}.o'
}

// escape_for_make writes a path so that make reads it as one word with nothing
// read into it: a space ends a word, a `#` starts a comment and a `$` starts a
// variable, so a file whose name has one has to say so.
fn escape_for_make(path string) string {
	return path.replace(' ', '\\ ').replace('#', '\\#').replace('$', '$$')
}

// print_macros is what `-dM` does: what is defined when the read ends, one
// definition per line, in the shape the program itself would have written it.
// It is how a build checks what a compiler believes about the target before it
// relies on it, and how a person asks why a branch was not taken.
fn print_macros(macros []preprocess.Macro) {
	for macro in macros {
		mut texts := []string{}
		for token in macro.body {
			texts << token.text
		}
		mut head := '#define ${macro.name}'
		if macro.takes_arguments() {
			mut params := macro.params.clone()
			if macro.variadic {
				// The standard spelling writes `...`; the GNU spelling that named
				// its variable arguments writes the name back before the dots,
				// which is how gcc's -dM prints a macro defined that way.
				params << if macro.variadic_name == '' {
					'...'
				} else {
					macro.variadic_name + '...'
				}
			}
			head += '(${params.join(', ')})'
		}
		body := texts.join(' ')
		if body == '' {
			println(head)
			continue
		}
		println('${head} ${body}')
	}
}

// severity_of is where a diagnostic meets the command line. An error is an error
// whatever the flags say, because nothing silences something that is wrong, and
// a warning carries its class, which is what the policy answers for.
fn severity_of(diagnostic tokenize.Diagnostic, policy diagnostics.Policy) diagnostics.Severity {
	if !diagnostic.warning {
		return .error
	}
	return policy.severity(diagnostic.class)
}

// report prints the diagnostics a stage handed back and answers how many of them
// are errors: a diagnostic that is wrong on its own, and a warning the command
// line promoted to one. What is not printed is a class the flags silenced, which
// is a warning the compiler still counted and a compile that still succeeded.
fn report(path string, raised []tokenize.Diagnostic, policy diagnostics.Policy) int {
	mut errors := 0
	for diagnostic in raised {
		severity := severity_of(diagnostic, policy)
		if severity == .silent {
			continue
		}
		// A diagnostic raised inside an included file names that file; the one
		// the compiler was handed is the fallback for everything else.
		where := if diagnostic.file != '' { diagnostic.file } else { path }
		eprintln(diagnostics.render(where, diagnostic.line, diagnostic.col, severity, diagnostic.msg))
		if diagnostic.note != '' {
			eprintln(diagnostics.render_note(where, diagnostic.line, diagnostic.col, diagnostic.note))
		}
		if severity == .error {
			errors++
		}
	}
	return errors
}

fn abort(message string) {
	eprintln('vcc: ${message}')
	exit(1)
}

// runtime_library_name is the file a link takes for the helpers the machine has
// no instruction for: this compiler's own libvcc, or the toolchain's libgcc when
// --link-libgcc asked for it, and that one's shared form when -shared-libvcc or
// -shared-libgcc asked for a library the loader maps. The two runtimes define the
// same helper names, so a link takes one of them and never both, and the command
// line is not allowed to name both: runtime_conflict_refusal is where the pairs
// that would mean nothing are refused.
fn runtime_library_name(opts cli.Options) string {
	if opts.link_libgcc {
		if opts.shared_libgcc {
			return linux.libgcc_shared_library
		}
		return linux.libgcc_library
	}
	if opts.shared_libvcc {
		return linux.runtime_shared_library
	}
	return linux.runtime_library
}

// runtime_archive is the runtime archive a link takes, or none when it has none
// to take. --link-libgcc is a request and libgcc.a is not implicit in anything,
// so a search that answers nothing is the flag failing rather than a link made
// without the library it named. libvcc is implicit, so a tree that has none is a
// link that takes one archive less, and a program that needed a helper is
// refused by the name of the helper it called.
fn runtime_archive(opts cli.Options, target backend.Target) ?backend.Library {
	name := runtime_library_name(opts)
	// libgcc_s is not a file this compiler keeps or a name it knows a directory
	// for: it lives beside the toolchain that built it, which is the answer the
	// search a -l name goes through gives. So it is resolved as that name rather
	// than searched for as a file, and the answer carries the name the loader is
	// asked for.
	if opts.link_libgcc && opts.shared_libgcc {
		libraries := target.resolve_libraries([linux.libgcc_shared_flag], opts.library_dirs,
			false) or { []backend.Library{} }
		if libraries.len > 0 {
			return libraries[0]
		}
	} else if library := target.runtime_archive(name, opts.library_dirs, install_dir()) {
		return library
	}
	if opts.link_libgcc {
		abort('--link-libgcc needs ${name}, and no directory this system searches has it: name the directory that holds it with -L')
	}
	return none
}

// runtime_names are the names the runtime answers, which is the set the
// single-input path hands its import check and the set it asks the emitted unit
// against. The file is read rather than guessed at: an archive answers through
// its symbol index, and a shared object through the dynamic symbol table it is
// loaded by, which is the same reader a -l name that resolved to a shared object
// is checked with. A run with no runtime answers nothing, and a link with no
// libvcc is a program refused by the name of the helper it called.
fn runtime_names(opts cli.Options, target backend.Target) map[string]bool {
	mut out := map[string]bool{}
	runtime := runtime_archive(opts, target) or { return out }
	if runtime.archive {
		bytes := read_source(runtime.path) or { return out }
		parts := archive.read(bytes.bytes()) or { return out }
		for name, _ in parts.index {
			out[name] = true
		}
		return out
	}
	symbols := linux.library_symbols(runtime.path) or { return out }
	for name, _ in symbols {
		out[name] = true
	}
	return out
}

// library_archive_names is the names the archives behind the command line's -l
// flags answer, read from the files the search resolved to. They are the members
// a -l name brings to a link that reads archives, and the single-input path asks
// this so a program that calls one is handed to the link rather than finished in
// the emitter, which reads no archive.
//
// The list is empty for a -l name that resolved to a shared object, which is the
// usual answer, and for a name the search does not have: that refusal is the
// emitter's to report, with the flag that asked for it.
fn library_archive_names(opts cli.Options, target backend.Target) map[string]bool {
	mut out := map[string]bool{}
	if opts.libraries.len == 0 {
		return out
	}
	for library in target.archive_libraries(opts.libraries, opts.library_dirs, false) or {
		[]backend.Library{}
	} {
		bytes := read_source(library.path) or { continue }
		parts := archive.read(bytes.bytes()) or { continue }
		for name, _ in parts.index {
			out[name] = true
		}
	}
	return out
}

// program_reaches_archive says whether a program the single-input path emitted
// reaches a name the runtime archive answers. The single-input path wraps its
// image in the emitter and never reads an archive, so a program that calls a
// helper cannot be finished there: this is the question whose answer hands the
// run to the link, and the link pulls the member the name lives in.
fn program_reaches_archive(program unit.Program, names map[string]bool) bool {
	for name in program.imports {
		if name in names {
			return true
		}
	}
	return false
}

// target_of_run is the target the run was asked for, or the host when the name is
// one this compiler does not describe. The refusal for that name belongs to the
// emitter, which is where a target description is read, and a caller that needed
// the answer earlier than that asks this.
fn target_of_run(opts cli.Options) backend.Target {
	return backend.resolve(opts.target) or { backend.host() or { backend.Target{} } }
}

// default_libraries is whether a link takes the system's default libraries: the
// command line's two flags and the target's own answer. A freestanding target has
// no C library, so the flags have nothing to take away and the runtime archive is
// not offered either.
fn default_libraries(opts cli.Options, target backend.Target) bool {
	return opts.default_libraries() && target.hosted
}

// start_files is whether a link takes the system's start files, for the same
// reason: they are the C library's startup, and a target with no C library has
// none of it to run.
fn start_files(opts cli.Options, target backend.Target) bool {
	return opts.start_files() && target.hosted
}

// standard_include_dirs_for is the standard header search for this run: the
// system's directories, or none when -nostdinc said so or the target has no C
// library. A freestanding translation unit may not include the host's headers,
// which is what makes `__STDC_HOSTED__` 0 mean something to a header that asks.
fn standard_include_dirs_for(opts cli.Options) []string {
	if opts.nostdinc {
		return []string{}
	}
	target := backend.resolve(opts.target) or { return standard_include_dirs() }
	if !target.hosted {
		return []string{}
	}
	return standard_include_dirs()
}

// link_kind is which link the command line asked for, read off the two flags
// that name one. Whether the two may both be given is decided where the run is
// refused and not here, so this answers and does not judge.
fn link_kind(opts cli.Options) linux.LinkKind {
	if opts.shared {
		return .shared
	}
	if opts.static_link {
		return .static_program
	}
	return .program
}

// names_a_static_archive says whether a -l name the command line gave resolves
// to a static archive. An archive is a link input this compiler has to read:
// its members are pulled into the program, which only the link path does, and a
// .c input is the object it produces at its own place on the line. A name that
// resolves to nothing is left to the path that links to report by name, and a
// name that resolves to a shared library is answered by the loader rather than
// by this compiler.
fn names_a_static_archive(opts cli.Options) bool {
	if opts.libraries.len == 0 {
		return false
	}
	target := backend.resolve(opts.target) or { return false }
	dirs := target.library_dirs_for(opts.library_dirs)
	for given in opts.libraries {
		library := linux.resolve_library(given, dirs, link_kind(opts) == .static_program) or { continue }
		if library.archive {
			return true
		}
	}
	return false
}

// in_house_link_options reads the -Wl, options for this compiler's own linker.
// The parser keeps their payloads untouched because -fuse-ld hands them
// to another tool; here they are interpreted, and one the image cannot express
// is an error naming the flag rather than a line in a list nobody reads. The
// image writer is where the answer has to be true: an option that reached this
// function and changed no byte would be the silent no-op issue #64 reported.
fn in_house_link_options(opts cli.Options) !linux.LinkOptions {
	flags := cli.linker_options(opts.link_args)!
	return linux.LinkOptions{
		execstack:   flags.execstack
		noexecstack: flags.noexecstack
		bind_now:    flags.bind_now
		relro:       flags.relro
		soname:      flags.soname
	}
}

// fuse_ld_link performs the final link with the program -fuse-ld named.
//
// It is the one path that links more than one input and inputs that are not C:
// each .c input runs the same stages -c runs and becomes a relocatable object, a
// foreign object or an archive is passed to the linker as it stands, and the
// linker writes the program. Every failure is reported and ends the run
// non-zero. The in-house path is never taken in place of a link that was asked
// for: a link that quietly did nothing is the worst outcome this flag can have,
// and the reason the tool is resolved before any object is written. A run that
// stops before a link never arrives here; the caller asks `links()` first.
fn fuse_ld_link(opts cli.Options) {
	// Two kinds of link at once is one kind of link dropped in silence: the
	// linker would be given one of the two flags and the file would not be what
	// the other asked for.
	if refusal := opts.link_kind_conflict_refusal() {
		abort(refusal)
	}
	if refusal := cli.fuse_ld_refusal(opts.fuse_ld) {
		abort(refusal)
	}
	if link_kind(opts) == .static_program {
		if refusal := cli.fuse_ld_static_refusal(opts.fuse_ld) {
			abort(refusal)
			return
		}
	}
	program := cli.fuse_ld_path(opts.fuse_ld) or {
		abort('cannot find ${opts.fuse_ld}: -fuse-ld names a linker the system must have on PATH')
		return
	}
	target := backend.resolve(opts.target) or {
		abort(err.msg())
		return
	}
	mut objects := []string{}
	mut all_source := true
	for index, input in opts.inputs {
		// The input is read once and classified from its bytes, the same rule
		// the single-input path uses; a classification by name alone would read
		// a foreign object as source.
		source := read_source(input) or {
			abort('cannot read ${input}: ${err.msg()}')
			return
		}
		match cli.classify_input(source, input, opts.input_type) {
			.source {
				bytes := compile_source_object(input, source, opts) or {
					abort('${input}: ${err.msg()}')
					return
				}
				object_path := link_object_path(index)
				write_object(object_path, bytes) or {
					abort('cannot write ${object_path}: ${err.msg()}')
					return
				}
				objects << object_path
			}
			.object, .shared_object, .archive {
				all_source = false
				objects << input
			}
			.program {
				abort('${input}: a program is not an input to a link')
				return
			}
		}
	}
	out_path := if opts.output != '' {
		opts.output
	} else if opts.run {
		temporary_path()
	} else {
		'a.out'
	}
	// The three library flags reach the external link as the same facts the
	// in-house link reads: whether the start files go around the objects, whether
	// the C library is named, and which runtime archive is in the group. The
	// archive is resolved here because a linker given the name `vcc` would not
	// find a file this compiler keeps beside itself.
	mut runtime_path := ''
	if default_libraries(opts, target) && link_kind(opts) != .shared {
		if runtime := runtime_archive(opts, target) {
			runtime_path = runtime.path
		}
	}
	link_options := linux.LinkOptions{
		start_files:       start_files(opts, target)
		default_libraries: default_libraries(opts, target)
		runtime:           runtime_path
	}
	args := target.external_link_arguments(link_kind(opts), objects, opts.library_dirs, opts.libraries, out_path,
		link_options) or {
		abort(err.msg())
		return
	}
	// A tool whose name does not say which linker it is gets its own word first
	// (lld's `-flavor gnu`); everything else gets nothing before the link. The
	// -Wl, options follow untouched: what they mean is the linker's business,
	// and a comma between them is the separator gcc gives the tool, so
	// -Wl,-z,now reaches it as the two words `-z now`.
	mut invocation := cli.fuse_ld_prefix(opts.fuse_ld)
	invocation << cli.fuse_ld_arguments(opts.link_args)
	invocation << args
	// A file an earlier link left is not allowed to stand in for one this run
	// did not write: the run reports a failure and the output has to agree.
	os.rm(out_path) or {}
	// What happened is said rather than left to be inferred. Every input being C
	// this compiler could link itself is the case that must not look like the
	// in-house path was taken quietly, so it says which tool did the link.
	if all_source {
		eprintln('vcc: every input is C this compiler could link itself; the link is handed to ${opts.fuse_ld} because -fuse-ld was given')
	} else {
		eprintln('vcc: the link is handed to ${opts.fuse_ld} (-fuse-ld)')
	}
	// What runs is the argument array and not one string a shell would read
	// again, so a path or an argument holding a space stays one word. The line
	// -verbose prints is the readable form of the same words.
	if opts.verbose {
		eprintln('link: ${link_command_line(program, invocation)}')
	}
	mut argv := [program]
	argv << invocation
	status := os.system_args(argv)
	if status != 0 {
		// The linker's own stderr reached the terminal as it ran; the status is
		// carried out rather than replaced, so a failed link is a failed compile
		// to whatever started it.
		os.rm(out_path) or {}
		exit(status)
	}
	if opts.run {
		run_image(out_path, opts.run_args)
	}
}

// compile_source_object runs the stages -c runs over one source and answers the
// bytes of the relocatable object they produce. It states the sequence main()
// runs for a source because that sequence reports through the command line's
// warning policy and stops at the first stage that fails; the external link
// needs the same stages with the object as their product, and sharing the whole
// sequence would make it carry the verbose hooks and the early modes as well.
//
// The emitter is asked for the -c product: a relocatable container, no entry
// point required, and no import checked, because a linker resolves the symbols
// of an object and the linker here is the one the flag named.
fn compile_source_object(path string, source string, opts cli.Options) ![]u8 {
	processed := preprocess.preprocess(source, path, preprocess.Options{
		include_dirs:   opts.include_dirs
		defines:        language_defines(opts)
		actions:        opts.define_actions
		standard_dirs:  standard_include_dirs_for(opts)
		preludes:       opts.preludes
		undef_builtins: opts.undef_builtins
		hosted:         target_of_run(opts).hosted
		dialect:        opts.dialect
	})
	if report(path, processed.diagnostics, opts.warnings) > 0 {
		return error('the compile stopped at a diagnostic')
	}
	pedantic := standard.pedantic_messages(processed.tokens, standard.Question{
		mode:         opts.dialect
		extensions:   opts.vcc_extensions.enabled_names()
		system_files: system_files(processed.files)
	})
	if report(path, pedantic, opts.warnings) > 0 {
		return error('the compile stopped at a diagnostic')
	}
	parsed := parser.parse_with(processed.tokens, parser_target(opts.target), opts.bracket_depth)
	if report(path, parsed.diagnostics, opts.warnings) > 0 {
		return error('the compile stopped at a diagnostic')
	}
	optimized := optimizer.optimize(parsed.unit, opts.optimization)
	image := codegen.emit(optimized, codegen.Options{
		target:         opts.target
		entry:          'main'
		compile_only:   true
		pic:            opts.pic
		ignore_natives: opts.ignore_natives
		dialect:        opts.dialect
		bracket_depth:  opts.bracket_depth
		libraries:      opts.libraries
		library_dirs:   opts.library_dirs
	})
	if report(path, image.diagnostics, opts.warnings) > 0 {
		return error('the compile stopped at a diagnostic')
	}
	return image.bytes
}

// link_object_path is where one input's relocatable object is written on its
// way to the linker. It is named after the process and the input's place on the
// command line so that a run over many inputs does not write one over another.
fn link_object_path(index int) string {
	return os.join_path(os.temp_dir(), 'vcc-extlink-${os.getpid()}-${index}.o')
}

// link_command_line renders the linker invocation the way it would be typed,
// with every word quoted so a path with a space reads as one word. It is the
// line -verbose prints; what runs is the argument array beside it.
fn link_command_line(program string, args []string) string {
	mut command := os.quoted_path(program)
	for arg in args {
		command += ' ' + os.quoted_path(arg)
	}
	return command
}

// standard_include_dirs are the directories searched for <stdio.h> after the -I
// ones, unless -nostdinc says not to search any. They are the host's, because
// this compiler brings no headers of its own: what it compiles against is the C
// library the machine already has, and the headers that describe it.
//
// The compiler's own headers live with the GCC that ships them — stddef.h and
// stdarg.h, which every standard header expects to find — one directory per
// version, and the newest one is the one meant to be read. A machine can carry
// headers for more than one target side by side there (a cross compiler, a
// mingw toolchain); only the directories whose names describe the target being
// compiled for are read, so a cross compiler's stddef.h is never picked up
// because its name happens to sort last.
fn standard_include_dirs() []string {
	target := backend.host() or { return []string{} }
	mut dirs := []string{}
	dirs << '/usr/local/include'
	mut gcc_dirs := []string{}
	for machine in os.ls('/usr/lib/gcc') or { []string{} } {
		if !machine.contains(target.arch) || !machine.contains(target.os) {
			continue
		}
		for version in os.ls('/usr/lib/gcc/${machine}') or { []string{} } {
			candidate := '/usr/lib/gcc/${machine}/${version}/include'
			if os.is_dir(candidate) {
				gcc_dirs << candidate
			}
		}
	}
	gcc_dirs.sort()
	if gcc_dirs.len > 0 {
		dirs << gcc_dirs.last()
	}
	// Debian and its relatives keep the architecture's own headers in a
	// directory named after the target; on a machine that has no such split
	// this simply does not exist.
	arch_dir := '/usr/include/${target.arch}-${target.os}-gnu'
	if os.is_dir(arch_dir) {
		dirs << arch_dir
	}
	dirs << '/usr/include'
	return dirs
}

// query_answer answers the -print- question the command line asked. The answers
// are this compiler's own and come from the same description the compile uses: a
// file resolves through the linker's search, and the target's multiarch spelling
// is the one its own search lists are built from.
//
// gcc answers questions about its private tree - its install directory, its cc1
// and its as - which this compiler does not have, because it is one binary that
// runs no program and writes the container itself. Where that is the reason, the
// answer is the one gcc gives for a thing it cannot find, and the comment says so.
//
// When more than one query is written, the first of these in this order is the
// one answered, which is the order gcc's own answers come out in: a file query
// first, then the variant queries, then the sysroot.
fn query_answer(opts cli.Options, target backend.Target) string {
	if opts.print_file_name_given {
		// The file the linker's search finds, or the name back unchanged when it
		// finds none. An empty name is not a file and comes back empty, which is
		// the same rule and not gcc's special answer of its install directory.
		// It is answered here rather than left to the search, because the search
		// appends the name to the install directory and an empty name would come
		// back as that directory.
		if opts.print_file_name == '' {
			return ''
		}
		//
		// The runtime is the one file searched for a second way: libvcc.a and
		// libvcc.so are kept beside the compiler rather than in a directory the
		// linker's search has, so a name the -L directories do not answer is
		// asked of the install directory too. That is the search
		// runtime_archive makes, and the two answers agreeing is what makes
		// `-print-file-name=libvcc.a` name the file a link would take.
		//
		// The search is the link's own rather than the one a -l name goes
		// through: libgcc.a and crtbeginS.o are in the toolchain's directory,
		// which no -l name searches, and a query that stopped at the library
		// directories answered a bare name while the link read the file.
		return target.link_file(opts.print_file_name, opts.library_dirs) or {
			linux.find_runtime_library(opts.print_file_name, target.library_dirs_for(opts.library_dirs),
				install_dir()) or { opts.print_file_name }
		}
	}
	if opts.print_prog_name_given {
		// This compiler runs no external program: it emits the container
		// itself, so there is no name it could resolve to a path. gcc prints a
		// program name unchanged for one it cannot find, and every name is one
		// this compiler cannot find.
		return opts.print_prog_name
	}
	if opts.print_libgcc_file_name {
		// The file a --link-libgcc link reads, which is the resolution that
		// link makes rather than a search of the library directories: libgcc.a
		// lives in the toolchain's own directory, and on a machine that keeps
		// it there a search of the library directories has none and answered
		// the name back. A machine without it answers the name, which is gcc's
		// answer for a libgcc it does not have.
		if runtime := target.runtime_archive(linux.libgcc_library, opts.library_dirs, install_dir()) {
			return runtime.path
		}
		return linux.libgcc_library
	}
	if opts.print_multi_directory {
		// One compilation variant exists, and its directory is the default one.
		return '.'
	}
	if opts.print_multi_lib {
		// That one variant, named by the directory it lives in and no options.
		return '.;'
	}
	if opts.print_multi_os_directory {
		// There is no multilib tree to move through: the system's own library
		// directories are what the search looks in, so the relative directory
		// is the one this compiler is already in.
		return '.'
	}
	if opts.print_multiarch {
		// The target's multiarch spelling, which is the name this compiler
		// builds both of its search lists from. gcc here prints an empty line
		// because it is configured without multiarch.
		return '${target.arch}-${target.os}-gnu'
	}
	if opts.print_sysroot {
		// A sysroot is a tree to compile against instead of the running system,
		// and this compiler has none: its headers and libraries are the host's,
		// so the answer is empty and not a directory.
		return ''
	}
	if opts.print_sysroot_headers_suffix {
		// The suffix goes with the sysroot, and there is no sysroot. gcc makes
		// this a fatal error because it has no suffix to give; an empty answer
		// is the same fact in a form a build can use, so the run still exits 0.
		return ''
	}
	return cli.search_dirs_text(install_dir(), []string{}, target.library_dirs_for(opts.library_dirs))
}

// install_dir is the directory the running compiler is in. gcc names its private
// install tree here because that is where its own files are; this compiler is one
// binary with no tree beside it, so the directory holding the binary is the only
// "where the compiler is" there is.
fn install_dir() string {
	return os.dir(os.executable())
}

// The -verbose report. gcc's -v prints the cc1, as and collect2 command lines it
// runs; this compiler runs none of those, so what follows is what it can honestly
// report: which compiler and target this is, where headers and libraries are
// looked for, what was read, and what went into the file. Every line goes to
// stderr through verbose_print and nothing here changes what is compiled, so a
// -E stream or a -print- answer on the standard output is left alone.
//
// Each stage hands back its lines rather than printing them, so the stages can be
// read in a test and there is one place that writes them.

// verbose_header_lines names the compiler, the target and the dialect, the facts
// gcc's -v opens with.
fn verbose_header_lines(opts cli.Options) []string {
	mut out := []string{}
	out << 'vcc version ${cli.version} (pure V)'
	target := backend.resolve(opts.target) or {
		out << 'target: none (${err.msg()})'
		return out
	}
	out << 'target: ${target.name}'
	out << 'standard: ${standard_line(opts)}'
	return out
}

// verbose_query_lines shows the search a query answer came from, which is the
// detail gcc's -v prints beside a -print- answer.
fn verbose_query_lines(opts cli.Options, target backend.Target) []string {
	return ['libraries: =${target.library_dirs_for(opts.library_dirs).join(':')}']
}

// verbose_include_dir_lines is where a header is looked for, in the order it is
// searched, which is what a person reads to see why a header resolved where it
// did.
fn verbose_include_dir_lines(opts cli.Options) []string {
	mut out := []string{}
	for dir in opts.include_dirs {
		out << 'include: ${dir}'
	}
	if opts.nostdinc {
		out << 'include: (the standard directories, which -nostdinc turns off)'
		return out
	}
	for dir in standard_include_dirs() {
		out << 'include: ${dir} (standard)'
	}
	return out
}

// verbose_file_lines is what the read opened: the source and every header that was
// included, which is the list -M writes as a rule.
fn verbose_file_lines(files []preprocess.SourceFile) []string {
	mut out := []string{}
	for file in files {
		kind := if file.system { ' (system)' } else { '' }
		out << 'read: ${file.path}${kind}'
	}
	return out
}

// verbose_result_lines closes the report with what performed the link and what
// the image carries, which is the part of gcc's -v a build reads to see what
// got linked. The link itself is in-process either way, so there is no command
// line to show; the line says which of the two linkers wrote the bytes.
fn verbose_result_lines(opts cli.Options, phases []cli.Phase, bytes []u8, out_path string) []string {
	mut out := []string{}
	for phase in phases {
		out << 'phase: ${phase.name} ${phase.micros}us'
	}
	target := backend.resolve(opts.target) or { return out }
	if opts.legacy_ld {
		out << 'link: the legacy linker wrote the container (deprecated)'
	} else {
		out << 'link: the vlk library wrote the container'
	}
	out << '  interpreter: ${target.interpreter}'
	out << '  library: ${target.base_library()} (the C library every image names)'
	for library in target.resolve_libraries(opts.libraries, opts.library_dirs, link_kind(opts) == .static_program) or {
		[]backend.Library{}
	} {
		out << '  library: ${library.soname} (${library.path})'
	}
	out << '  written: ${out_path} (${bytes.len} bytes)'
	return out
}

// verbose_print is the one place -verbose reaches a stream: stderr, so that the
// standard output stays whatever the command was asked for.
fn verbose_print(lines []string) {
	for line in lines {
		eprintln(line)
	}
}
