module cli

import os
import preprocess
import v.vmod

fn test_an_input_and_an_output() {
	opts := parse(['seven.c', '-o', 'seven'])!
	assert opts.inputs == ['seven.c']
	assert opts.output == 'seven'
	assert opts.compile_only == false
}

fn test_a_joined_output_value_works_too() {
	opts := parse(['-oseven', 'seven.c'])!
	assert opts.output == 'seven'
	assert opts.inputs == ['seven.c']
}

fn test_joined_and_separate_paths_are_the_same_flag() {
	joined := parse(['-I/usr/include', '-DN=7', '-L/usr/lib', '-lm', 'x.c'])!
	separate := parse(['-I', '/usr/include', '-D', 'N=7', '-L', '/usr/lib', '-l', 'm', 'x.c'])!
	assert joined.include_dirs == separate.include_dirs
	assert joined.defines == separate.defines
	assert joined.library_dirs == separate.library_dirs
	assert joined.libraries == separate.libraries
	assert joined.include_dirs == ['/usr/include']
	assert joined.defines == ['N=7']
}

fn test_the_optimizer_owns_its_flags() {
	opts := parse(['-O2', '-fno-builtin', '-fno-builtin-abs', 'src.c', '-o', 'out'])!
	// Recognized by the optimizer, so not in the ignored list, and not refused.
	assert !opts.ignored.contains('-O2')
	assert !opts.ignored.contains('-fno-builtin')
	assert opts.optimization.level == .o2
	assert !opts.optimization.builtins
	assert opts.optimization.recorded == ['-O2', '-fno-builtin', '-fno-builtin-abs']
	assert opts.optimization.disabled == ['abs']
}

fn test_a_level_this_stub_does_not_implement_is_still_not_refused() {
	opts := parse(['-O9', 'src.c', '-o', 'out'])!
	assert opts.optimization.level == .o0
	assert opts.optimization.recorded == ['-O9']
	assert opts.inputs == ['src.c']
}

fn test_compile_only_and_print_ast_are_their_own_modes() {
	only := parse(['-c', 'src.c', '-o', 'src.o'])!
	assert only.compile_only
	assert only.output == 'src.o'
	assert !only.print_ast
	printed := parse(['-print-ast', 'src.c'])!
	assert printed.print_ast
	assert !printed.compile_only
	assert !printed.ignored.contains('-print-ast')
	// Reading the tree is not a reason to stop reading the command line.
	both := parse(['-O2', '-print-ast', 'src.c'])!
	assert both.print_ast
	assert both.optimization.level == .o2
}

fn test_what_v_passes_is_accepted_rather_than_refused() {
	// The flag set read off the V tree: a compiler that errors on one of these
	// fails a build it was supposed to serve.
	opts := parse(['-std=gnu11', '-w', '-fwrapv', '-bt25', '-B/opt/tcc/lib/tcc', '-g',
		'-Werror=implicit-function-declaration', '-Wl,-rpath,/opt/v', '-DGC_THREADS=1',
		'-DTHREAD_LOCAL_ALLOC=1', '-I/opt/libgc/include', '/opt/libgc.a', 'src.c', '-o', 'out'])!
	assert opts.inputs == ['/opt/libgc.a', 'src.c']
	assert opts.standard == 'gnu11'
	assert opts.defines == ['GC_THREADS=1', 'THREAD_LOCAL_ALLOC=1']
	assert opts.include_dirs == ['/opt/libgc/include']
	assert opts.inhibit_warnings
	assert opts.ignored.contains('-bt25')
	assert opts.link_args == ['-rpath,/opt/v']
	assert opts.ignored.contains('-B/opt/tcc/lib/tcc')
}

// -fPIC, -fpic, -fPIE and -fpie are the spellings gcc offers for
// position-independent code, and -fno-pic, -fno-PIC, -fno-pie and -fno-PIE take
// the addressing back. The flag is read rather than recorded: it decides the
// form of every reference to a top-level object another unit may define, and a
// build that passes it and is told nothing is a build that has been told
// nothing.
fn test_the_position_independent_flag_is_read_from_either_spelling() {
	upper := parse(['-fPIC', 'src.c'])!
	assert upper.pic
	lower := parse(['-fpic', 'src.c'])!
	assert lower.pic
	executable_upper := parse(['-fPIE', 'src.c'])!
	assert executable_upper.pic
	assert !executable_upper.ignored.contains('-fPIE')
	executable_lower := parse(['-fpie', 'src.c'])!
	assert executable_lower.pic
	off := parse(['-fPIC', '-fno-pic', 'src.c'])!
	assert !off.pic
	executable_off := parse(['-fPIE', '-fno-pie', 'src.c'])!
	assert !executable_off.pic
	absent := parse(['src.c'])!
	assert !absent.pic
}

// -pie is the link flag for a position-independent executable. It asks for the
// kind and for position-independent code in the same run, because a one-shot
// command line compiles and links in one go; -no-pie asks for the fixed-base
// program again.
fn test_pie_asks_for_both_the_kind_and_the_code() {
	asked := parse(['-pie', 'src.c'])!
	assert asked.pie
	assert asked.pic
	off := parse(['-pie', '-no-pie', 'src.c'])!
	assert !off.pie
	assert !parse(['src.c'])!.pie
}

fn test_static_pie_is_refused_by_name() {
	parse(['-static-pie', 'src.c']) or {
		assert err.msg().contains('-static-pie')
		return
	}
	assert false, '-static-pie was accepted'
}

fn test_pie_and_the_legacy_linker_are_refused_together() {
	opts := parse(['-pie', '-flegacy-ld', 'src.c'])!
	refusal := opts.link_kind_conflict_refusal() or { panic('a pie has no legacy link') }
	assert refusal.contains('-pie')
	assert refusal.contains('-flegacy-ld')
}

// -fignore-natives asks the back end for the runtime's copy of a 128-bit
// operation the machine has instructions for. It is a feature of the code the
// compiler writes, so it is read rather than recorded, and its negative spelling
// turns it back off for a build that appends one flag to another.
fn test_the_ignore_natives_flag_is_read_and_can_be_turned_off() {
	asked := parse(['-fignore-natives', 'src.c'])!
	assert asked.ignore_natives
	assert !asked.ignored.contains('-fignore-natives')
	absent := parse(['src.c'])!
	assert !absent.ignore_natives
	off := parse(['-fignore-natives', '-fno-ignore-natives', 'src.c'])!
	assert !off.ignore_natives
	assert usage(false).contains('-fignore-natives')
}

// -fbracket-depth bounds how deep a construct may nest, and the three answers it
// has are three different kinds of value: a depth, no limit (0), and a refusal.
// The default is the 256 clang documents for its flag of the same name.
fn test_the_bracket_depth_is_read_from_either_spelling() {
	joined := parse(['-fbracket-depth=512', 'src.c'])!
	separate := parse(['-fbracket-depth', '512', 'src.c'])!
	assert joined.bracket_depth == 512
	assert separate.bracket_depth == 512
	assert joined.inputs == ['src.c']
	assert separate.inputs == ['src.c']
	assert parse(['src.c'])!.bracket_depth == 256
	assert usage(false).contains('-fbracket-depth=N')
}

fn test_a_bracket_depth_of_zero_is_no_limit() {
	assert parse(['-fbracket-depth=0', 'src.c'])!.bracket_depth == 0
}

fn test_a_negative_bracket_depth_is_refused() {
	if _ := parse(['-fbracket-depth=-1', 'src.c']) {
		assert false, 'a negative depth names no nesting and should be refused'
	} else {
		assert err.msg().contains('non-negative')
	}
}

fn test_a_bracket_depth_that_is_not_a_number_is_refused() {
	if _ := parse(['-fbracket-depth=three', 'src.c']) {
		assert false, 'a word is not a depth and should be refused'
	} else {
		assert err.msg().contains('takes a number')
	}
}

fn test_the_standard_is_recorded_from_either_spelling() {
	// V passes -std=gnu11 and a person types -std gnu11. The second one has to
	// be read as a value, or the version name becomes an input file and the
	// failure is about linking rather than about standards.
	joined := parse(['-std=gnu11', 'src.c'])!
	separate := parse(['-std', 'c99', 'src.c'])!
	assert joined.standard == 'gnu11'
	assert separate.standard == 'c99'
	assert joined.inputs == ['src.c']
	assert separate.inputs == ['src.c']
	assert !joined.ignored.contains('-std=gnu11')
	assert !separate.ignored.contains('-std')
}

fn test_the_standard_needs_a_value() {
	if _ := parse(['src.c', '-std']) {
		assert false, '-std with nothing after it should be an error'
	}
}

fn test_run_mode_splits_the_source_from_the_program_arguments() {
	opts := parse(['-run', 'prog.c', 'one', 'two'])!
	assert opts.run
	assert opts.inputs == ['prog.c']
	assert opts.run_args == ['one', 'two']
}

fn test_a_double_dash_puts_everything_after_it_in_the_program_arguments() {
	opts := parse(['-run', 'prog.c', '--', '-o', 'weird'])!
	assert opts.inputs == ['prog.c']
	assert opts.run_args == ['-o', 'weird']
}

fn test_standard_input_is_an_input() {
	opts := parse(['-', '-o', 'out'])!
	assert opts.inputs == ['-']
}

fn test_a_missing_value_is_an_error() {
	if _ := parse(['-o']) {
		assert false, '-o with nothing after it should be an error'
	} else {
		assert true
	}
}

fn test_a_list_file_is_spliced_in_place() {
	path := os.join_path(os.temp_dir(), 'vcc_cli_test_${os.getpid()}.txt')
	os.write_file(path, '-std=gnu11	-bt25\n-o out\nsrc.c\n')!
	opts := parse(['@${path}'])!
	os.rm(path) or {}
	assert opts.output == 'out'
	assert opts.inputs == ['src.c']
	assert opts.standard == 'gnu11'
	assert opts.ignored == ['-bt25']
}

fn test_an_unknown_flag_is_recorded_not_refused() {
	opts := parse(['-something-new', 'x.c'])!
	assert opts.inputs == ['x.c']
	assert opts.ignored == ['-something-new']
}

fn test_the_target_can_be_named() {
	assert parse(['-target', 'x86_64-linux', 'x.c'])!.target == 'x86_64-linux'
}

fn test_the_emulation_can_be_named() {
	assert parse(['-femulation=gcc', 'x.c'])!.emulation == .gcc
	assert parse(['-femulation', 'clang', 'x.c'])!.emulation == .clang
	assert parse(['-femulation=tcc', 'x.c'])!.emulation == .tcc
	assert parse(['x.c'])!.emulation == .none
}

fn test_an_unknown_emulation_is_refused() {
	if _ := parse(['-femulation=msvc', 'x.c']) {
		assert false, 'a compiler this one cannot present itself as should be refused'
	} else {
		assert err.msg().contains('gcc, clang and tcc')
	}
}

fn test_bench_lines_carry_the_phase_and_the_time() {
	lines := bench_lines([Phase{
		name:   'lex'
		micros: 41
	}])
	assert lines == ['bench lex: 41us']
}

fn test_usage_mentions_the_output_and_the_version_flags() {
	text := usage(true)
	assert text.contains('-o outfile')
	assert text.contains('--version')
	assert text.contains('libgc.a')
	assert text.contains('-std version')
}

fn test_undef_and_dm_are_their_own_modes() {
	opts := parse(['-undef', '-dM', 'x.c'])!
	assert opts.undef_builtins
	assert opts.dump_macros
}

fn test_the_two_dependency_modes_differ_by_the_system_headers() {
	full := parse(['-M', 'x.c'])!
	assert full.deps && full.deps_system
	user := parse(['-MM', 'x.c'])!
	assert user.deps && !user.deps_system
}

fn test_the_dependency_file_can_be_joined_or_separate() {
	joined := parse(['-MM', '-MFout.d', 'x.c'])!
	assert joined.deps_file == 'out.d'
	separate := parse(['-MM', '-MF', 'out.d', 'x.c'])!
	assert separate.deps_file == 'out.d'
}

fn test_a_prelude_keeps_the_order_it_was_given_in() {
	opts := parse(['-imacros', 'macros.h', '-include', 'pre.h', 'x.c'])!
	assert opts.preludes.len == 2
	assert opts.preludes[0].path == 'macros.h'
	assert opts.preludes[0].macros_only
	assert opts.preludes[1].path == 'pre.h'
	assert opts.preludes[1].macros_only == false
}

fn test_the_dependency_modes_that_also_compile() {
	full := parse(['-MD', 'x.c'])!
	assert full.deps && full.deps_system && full.deps_compile
	user := parse(['-MMD', 'x.c'])!
	assert user.deps && !user.deps_system && user.deps_compile
	stopping := parse(['-M', 'x.c'])!
	assert stopping.deps && !stopping.deps_compile
}

fn test_the_rule_can_be_given_a_target() {
	assert parse(['-MD', '-MT', 'build/seven.o', 'x.c'])!.deps_target == 'build/seven.o'
	assert parse(['-MD', '-MQ', 'a b.o', 'x.c'])!.deps_target == 'a b.o'
}

// The -print- family asks a question and stops. Each flag is read rather than
// recorded, because a flag the driver never looks at would be answered as an
// ordinary compile with no input file, which is the one thing a build tool
// asking these questions does not have.
fn test_every_query_flag_is_read_as_a_question() {
	options := [
		'-print-search-dirs',
		'-print-libgcc-file-name',
		'-print-file-name=libc.so',
		'-print-prog-name=ld',
		'-print-multiarch',
		'-print-multi-directory',
		'-print-multi-lib',
		'-print-multi-os-directory',
		'-print-sysroot',
		'-print-sysroot-headers-suffix',
	]
	for flag in options {
		opts := parse([flag])!
		assert opts.asks_query(), '${flag} was not read as a query'
		assert !opts.ignored.contains(flag), '${flag} was recorded as ignored'
		assert opts.inputs.len == 0
	}
}

fn test_a_file_name_query_keeps_its_value_and_the_empty_one() {
	joined := parse(['-print-file-name=libc.so'])!
	assert joined.print_file_name == 'libc.so'
	assert joined.print_file_name_given
	// An empty name is a question too, so "was it given" cannot be read off the
	// value.
	empty := parse(['-print-file-name='])!
	assert empty.print_file_name == ''
	assert empty.print_file_name_given
	assert empty.asks_query()
}

fn test_a_prog_name_query_keeps_its_value() {
	opts := parse(['-print-prog-name=ld'])!
	assert opts.print_prog_name == 'ld'
	assert opts.print_prog_name_given
	assert !opts.ignored.contains('-print-prog-name=ld')
}

fn test_a_query_is_usable_with_a_standard_and_an_empty_command_line() {
	opts := parse(['-std=gnu11', '-print-multi-directory'])!
	assert opts.standard == 'gnu11'
	assert opts.print_multi_directory
	assert opts.asks_query()
}

fn test_an_ordinary_command_line_is_not_a_query() {
	opts := parse(['-std=gnu11', 'src.c', '-o', 'out'])!
	assert !opts.asks_query()
}

fn test_verbose_is_its_own_flag_and_the_version_stays_v() {
	opts := parse(['-verbose', 'x.c'])!
	assert opts.verbose
	assert !opts.ignored.contains('-verbose')
	// -v is the version, the tcc spelling this command line keeps, so the two
	// do not collide.
	printed := parse(['-v'])!
	assert printed.show_version
	assert !printed.verbose
}

fn test_the_search_dirs_text_has_the_shape_gcc_uses() {
	text := search_dirs_text('/opt/vcc', []string{}, ['/usr/local/lib', '/usr/lib'])
	lines := text.split('\n')
	assert lines.len == 3
	assert lines[0] == 'install: /opt/vcc'
	assert lines[1] == 'programs: ='
	assert lines[2] == 'libraries: =/usr/local/lib:/usr/lib'
	// Program directories are the caller's: the same shape with some.
	with_programs := search_dirs_text('/opt/vcc', ['/opt/vcc/bin'], ['/usr/lib']).split('\n')
	assert with_programs[1] == 'programs: =/opt/vcc/bin'
}

fn test_the_usage_lists_the_query_flags() {
	text := usage(false)
	assert text.contains('-print-search-dirs')
	assert text.contains('-print-file-name=NAME')
	assert text.contains('-print-prog-name=NAME')
	assert text.contains('-print-multi-lib')
	assert text.contains('-print-sysroot-headers-suffix')
	assert text.contains('-verbose')
}

// elf_of is the beginning of an ELF64 file of one e_type: the magic, the class
// and data bytes, and the two bytes of the type at offset 16. Classification
// reads no more than this, so a file this long is a file it decides.
fn elf_of(kind u16) string {
	mut bytes := [u8(0x7f), `E`, `L`, `F`, u8(2), u8(1), u8(1), u8(0)]
	bytes << []u8{len: 8}
	bytes << u8(kind & 0xff)
	bytes << u8((kind >> 8) & 0xff)
	return bytes.bytestr()
}

fn input_scratch(name string) string {
	return os.join_path(os.temp_dir(), 'vcc_cli_input_${os.getpid()}_${name}')
}

// An object and an archive are link inputs and not source, and the kind is read
// off the bytes rather than off the name. Reading an object as source is the bug
// this pins: it reported an unexpected character from inside the ELF header,
// which is a wrong reading of a file fed to the wrong stage.
//
// The bytes classified here are the ones the driver hands over, and the last
// case reads a real file back so that what a file's own contents come to is
// covered and not only what the helper writes.
fn test_an_object_or_an_archive_is_classified_and_named() {
	object := elf_of(1)
	assert classify_input(object, 'from_vcc.o', '') == .object
	said := input_refusal('from_vcc.o', .object)
	assert said.contains('from_vcc.o')
	assert said.contains('relocatable object')

	archive := '!<arch>\n'
	assert classify_input(archive, 'libgc.a', '') == .archive
	assert input_refusal('libgc.a', .archive).contains('archive')

	// The other two containers an ELF can be, so that a program or a shared
	// object handed to the compiler is named as itself and not as an object.
	assert classify_input(elf_of(3), 'libm.so', '') == .shared_object
	assert classify_input(elf_of(2), 'a.out', '') == .program
	// A shared object is a link input like an object and an archive, so a run
	// that stops before a link refuses it as one, and the refusal does not
	// claim the file is something this compiler cannot read at all.
	said_shared := input_refusal('libx.so', .shared_object)
	assert said_shared.contains('libx.so')
	assert said_shared.contains('shared object')
	assert said_shared.contains('an input to a link')

	path := input_scratch('real_object.o')
	os.write_file_array(path, object.bytes()) or { panic(err) }
	on_disk := os.read_file(path) or { panic(err) }
	assert classify_input(on_disk, path, '') == .object
	os.rm(path) or {}
}

// The name is the fallback for bytes that are not a container this reader knows,
// which is a truncated object or a linker script carrying a library's name, and
// what is left is source: a source file, an empty file, and standard input,
// which has no name to fall back on either.
fn test_the_name_decides_what_the_bytes_do_not() {
	assert classify_input('not an elf at all\n', 'cache.tmp.c.o', '') == .object
	assert classify_input('GROUP ( /lib/libdl.so.2 )\n', 'libdl.so', '') == .shared_object
	assert classify_input('int main(void) { return 0; }\n', 'seven.c', '') == .source
	assert classify_input('', 'empty.c', '') == .source
	assert classify_input('int main(void) { return 0; }\n', '-', '') == .source
}

// A -x naming a C language says the input is C whatever the bytes are, which is
// how gcc reads `-x c foo.o`. -x none is gcc's way of cancelling an earlier -x
// and declares nothing, and a -x this compiler has no reader for is left to the
// bytes rather than taken for a promise.
fn test_x_naming_c_overrides_the_bytes() {
	object := elf_of(1)
	assert classify_input(object, 'forced.o', 'c') == .source
	assert classify_input(object, 'forced.o', 'c-header') == .source
	assert classify_input(object, 'forced.o', 'cpp-output') == .source
	assert classify_input(object, 'forced.o', 'none') == .object
	assert classify_input(object, 'forced.o', '') == .object
	assert classify_input(object, 'forced.o', 'assembler') == .object
}

// -fuse-ld names the program that performs the final link. Both
// spellings work, the joined one and the separated one, and the value is read
// rather than recorded: a build that passes the flag and finds the in-house path
// taken anyway has been told nothing. The spelling is gcc's and clang's, which
// is why it carries -f even though it is not a language feature.
fn test_fuse_ld_can_be_named_in_both_spellings() {
	joined := parse(['-fuse-ld=ld', 'a.c', 'b.c', '-o', 'out'])!
	separate := parse(['-fuse-ld', 'ld', 'a.c', 'b.c', '-o', 'out'])!
	assert joined.fuse_ld == 'ld'
	assert separate.fuse_ld == 'ld'
	assert joined.inputs == ['a.c', 'b.c']
	assert separate.inputs == ['a.c', 'b.c']
	assert !joined.ignored.contains('-fuse-ld=ld')
	assert !separate.ignored.contains('-fuse-ld')
	assert parse(['a.c', '-o', 'out'])!.fuse_ld == ''
}

// A command line with no -std reads gnu11. V passes that spelling to the C
// compiler it builds with, and a program written for that command line should
// not have to write the flag again; the spelling stays empty because no -std
// was written, and a -std that is written overrides the default.
fn test_no_std_selects_gnu11() {
	plain := parse(['a.c'])!
	assert plain.dialect == .gnu11
	assert plain.standard == ''
	assert parse(['-std=c99', 'a.c'])!.dialect == .c99
	assert parse(['-std', 'gnu99', 'a.c'])!.dialect == .gnu99
	// A spelling this compiler does not implement stays its own answer.
	assert parse(['-std=c++20', 'a.c'])!.dialect == .other
}

fn test_fuse_ld_needs_a_value() {
	if _ := parse(['a.c', '-fuse-ld']) {
		assert false, '-fuse-ld with nothing after it should be an error'
	}
}

// The spelling this flag replaced is refused rather than recorded as ignored.
// A build that still passes it asked for a link another program performs, and
// the in-house link it would get instead is a different answer to that request.
fn test_the_spelling_fuse_ld_replaced_is_refused() {
	for args in [['a.c', '-external-linker=ld'], ['a.c', '-external-linker', 'ld']] {
		if _ := parse(args) {
			assert false, '${args} should name -fuse-ld'
		} else {
			assert err.msg().contains('-fuse-ld=NAME')
		}
	}
}

// A C compiler may not be the linker -fuse-ld names. vcc compiles C itself, so
// a C compiler finishing the job would be circular, and the refusal names the
// flag and points at a linker instead.
fn test_a_c_compiler_may_not_be_the_linker_fuse_ld_names() {
	for name in ['gcc', 'cc', 'clang', 'c++', 'tcc'] {
		said := fuse_ld_refusal(name) or {
			assert false, '${name} is a C compiler and must be refused'
			''
		}
		assert said.contains('-fuse-ld=${name}')
		assert said.contains('a C compiler is not a linker')
		assert said.contains('ld')
		assert said.contains('lld')
	}
	// The versioned and target-prefixed spellings are the same driver.
	assert fuse_ld_refusal('gcc-16') != none
	assert fuse_ld_refusal('clang-15') != none
	assert fuse_ld_refusal('x86_64-linux-gnu-gcc') != none
	// A program whose name merely starts with a driver's is a different
	// program: clangd is a language server, not a compiler.
	assert fuse_ld_refusal('ld') == none
	assert fuse_ld_refusal('lld') == none
	assert fuse_ld_refusal('ld.lld') == none
	assert fuse_ld_refusal('ld.gold') == none
	assert fuse_ld_refusal('clangd') == none
	// vvd is the frontend over the vlk library this tree links through, so it
	// is a linker and not a compiler driver.
	assert fuse_ld_refusal('vvd') == none
}

// lld is the LLVM linkers' generic driver: invoked as `lld` it cannot choose a
// linker and wants `-flavor gnu` first. Every other name gets nothing before the
// link, because the GNU linkers would reject the word.
fn test_an_lld_name_gets_its_flavor_and_others_get_nothing() {
	assert fuse_ld_prefix('lld') == ['-flavor', 'gnu']
	assert fuse_ld_prefix('ld') == []
	assert fuse_ld_prefix('ld.lld') == []
	assert fuse_ld_prefix('ld.gold') == []
}

fn test_fuse_ld_is_in_the_help() {
	assert usage(false).contains('-fuse-ld=NAME')
	assert usage(true).contains('-fuse-ld')
}

// -flegacy-ld asks for the linker this tree carried before the vlk library,
// which is the default. It is a flag with no value and it is not recorded as
// ignored, and a command line that also names a linker program is refused: a
// link has one linker.
fn test_legacy_ld_is_read_and_refused_beside_a_named_linker() {
	asked := parse(['-flegacy-ld', 'a.c'])!
	assert asked.legacy_ld
	assert asked.fuse_ld == ''
	assert !asked.ignored.contains('-flegacy-ld')
	assert parse(['a.c'])!.legacy_ld == false
	// A run that stops before a link has nothing for the flag to do, which is
	// the answer -fuse-ld gets as well: the flag is read and not refused.
	assert parse(['-c', '-flegacy-ld', 'a.c'])!.legacy_ld
	both := parse(['-flegacy-ld', '-fuse-ld=ld', 'a.c'])!.linker_conflict_refusal() or {
		assert false, '-flegacy-ld beside -fuse-ld should be refused'
		''
	}
	assert both.contains('-flegacy-ld')
	assert both.contains('-fuse-ld=ld')
	assert parse(['-flegacy-ld', 'a.c'])!.linker_conflict_refusal() == none
}

// -fuse-vlk was the flag that asked for the library, and the library is the
// default now. The old spelling is refused by name so a build that still passes
// it is told where the other path went.
fn test_fuse_vlk_is_refused_and_names_the_legacy_flag() {
	if _ := parse(['-fuse-vlk', 'a.c']) {
		assert false, '-fuse-vlk is the default and should be refused by name'
	} else {
		assert err.msg().contains('-flegacy-ld')
		assert err.msg().contains('default')
	}
}

fn test_legacy_ld_is_in_the_help() {
	assert usage(false).contains('-flegacy-ld')
	assert usage(true).contains('-flegacy-ld')
	assert usage(false).contains('Deprecated')
}

// The two flags that name a kind of link are read and not recorded: a build that
// passes one and is told nothing has been told the flag was passed over, and
// what it asked for is the file that comes out.
fn test_a_kind_of_link_is_read_rather_than_recorded() {
	shared := parse(['-shared', 'x.c'])!
	assert shared.shared
	assert !shared.static_link
	assert shared.ignored.len == 0
	st := parse(['-static', 'x.c'])!
	assert st.static_link
	assert !st.shared
	assert st.ignored.len == 0
	// Both together are read here and decided where a run uses them: whether the
	// two can be combined is a question about the link, not about the spelling.
	both := parse(['-shared', '-static', 'x.c'])!
	assert both.shared && both.static_link
}

// Whether a run reaches a link is one fact, and it is the flags that decide it:
// the kind a link flag names has nothing to decide when the run stops before
// there is one.
fn test_a_run_that_stops_before_a_link_says_so() {
	assert parse(['x.c'])!.links()
	assert parse(['-shared', 'x.c'])!.links()
	assert parse(['-static', '-o', 'out', 'x.c'])!.links()
	assert !parse(['-c', 'x.c'])!.links()
	assert !parse(['-E', 'x.c'])!.links()
	assert !parse(['-M', 'x.c'])!.links()
	assert !parse(['-dM', 'x.c'])!.links()
	assert !parse(['-print-ast', 'x.c'])!.links()
	assert !parse(['-print-multiarch'])!.links()
	// A linker named on a run that stops before a link is a flag with nothing to
	// do rather than an error: the name is read and kept, the run keeps to the
	// ordinary path, and no linker is resolved for it. What the flag would have
	// done is not lost either, because the flag and the run disagree about
	// whether there is a link at all, and the run is the one that decides.
	stopped := parse(['-c', '-fuse-ld=ld', 'x.c'])!
	assert stopped.fuse_ld == 'ld'
	assert !stopped.links()
	assert stopped.link_kind_conflict_refusal() == none
}

// The path with no linker writes all three kinds of file, so the two flags that
// name one are read rather than refused, and the only refusal left is the pair
// that disagree about which file comes out. A flag on a run that stops before a
// link decides nothing either way.
fn test_the_kind_of_link_is_read_and_only_the_pair_is_refused() {
	assert parse(['x.c'])!.link_kind_conflict_refusal() == none
	assert parse(['-c', '-shared', 'x.c'])!.link_kind_conflict_refusal() == none
	assert parse(['-E', '-static', 'x.c'])!.link_kind_conflict_refusal() == none
	assert parse(['-shared', 'x.c'])!.link_kind_conflict_refusal() == none
	assert parse(['-static', 'x.c'])!.link_kind_conflict_refusal() == none
	assert parse(['-pie', 'x.c'])!.link_kind_conflict_refusal() == none
	assert parse(['-shared', 'x.c'])!.shared
	assert parse(['-static', 'x.c'])!.static_link
	assert parse(['-pie', 'x.c'])!.pie
	both := parse(['-shared', '-static', 'x.c'])!.link_kind_conflict_refusal() or {
		panic('a shared object and a static program are different links')
	}
	assert both.contains('-shared') && both.contains('-static')
	for pair in [['-pie', '-shared'], ['-pie', '-static']] {
		refusal := parse([pair[0], pair[1], 'x.c'])!.link_kind_conflict_refusal() or {
			panic('${pair[0]} and ${pair[1]} are different links')
		}
		assert refusal.contains(pair[0]) && refusal.contains(pair[1])
	}
}

// Both flags at once are refused on either path. A linker given the two takes one
// of them, so the file would be what one flag asked for and the other would be
// gone without a word, which is the outcome the whole flag surface exists to
// avoid.
fn test_two_kinds_of_link_at_once_are_refused() {
	assert parse(['-shared', 'x.c'])!.link_kind_conflict_refusal() == none
	assert parse(['-static', 'x.c'])!.link_kind_conflict_refusal() == none
	conflict := parse(['-shared', '-static', 'x.c'])!.link_kind_conflict_refusal() or {
		panic('a shared object and a static program are two different files')
	}
	assert conflict.contains('-shared') && conflict.contains('-static')
}

fn test_the_kind_of_link_is_in_the_help() {
	assert usage(false).contains('-shared')
	assert usage(false).contains('-pie')
	assert usage(false).contains('-static')
}

// -nostdlib is gcc's -nostartfiles and -nodefaultlibs on one command line, and
// -nodefaultlibs is the second half alone. The two questions a link asks of the
// flags are what separates them: the start files, and the default libraries. A
// program the link names no default library for runs against what the command
// line named and nothing else.
fn test_the_library_flags_answer_the_two_questions_a_link_asks() {
	plain := parse(['a.c'])!
	assert plain.default_libraries()
	assert plain.start_files()
	assert !plain.nostdlib
	assert !plain.nodefaultlibs
	without_libraries := parse(['-nodefaultlibs', 'a.c'])!
	assert !without_libraries.default_libraries()
	assert without_libraries.start_files()
	without_std := parse(['-nostdlib', 'a.c'])!
	assert !without_std.default_libraries()
	assert !without_std.start_files()
	// Both are read rather than recorded: a build that names one and is told
	// nothing has been told the flag was passed over.
	assert !without_libraries.ignored.contains('-nodefaultlibs')
	assert !without_std.ignored.contains('-nostdlib')
}

fn test_the_library_flags_are_in_the_help() {
	assert usage(false).contains('-nostdlib')
	assert usage(false).contains('-nodefaultlibs')
	assert usage(false).contains('--link-libgcc')
}

// --link-libgcc is read by every binary this tree builds: it selects the
// toolchain's runtime in place of libvcc, which is a choice about the link and
// not about what this binary carries.
fn test_link_libgcc_is_read() {
	assert parse(['--link-libgcc', 'a.c'])!.link_libgcc
	assert parse(['-link-libgcc', 'a.c'])!.link_libgcc
	assert !parse(['a.c'])!.link_libgcc
	// Read rather than recorded: a run told nothing has not been told the flag
	// was passed over.
	assert !parse(['--link-libgcc', 'a.c'])!.ignored.contains('--link-libgcc')
}

// -shared-libvcc is this compiler's own runtime in its shared form, which every
// binary this tree builds can name.
//
// The pairs it cannot mean are refused by naming both flags. A program links one
// runtime, so -shared-libvcc with --link-libgcc or with -shared-libgcc would take
// one of the two and drop the other, and -static writes a program with no loader
// in it, so a library the loader maps has nowhere to come from. The pair is
// judged before either flag's own rule, so a line naming both is told about the
// pair.
fn test_shared_libvcc_is_read_and_its_conflicts_are_refused() {
	assert parse(['-shared-libvcc', 'a.c'])!.shared_libvcc
	assert parse(['--shared-libvcc', 'a.c'])!.shared_libvcc
	assert !parse(['a.c'])!.shared_libvcc
	both := parse(['-shared-libvcc', '-static', 'a.c']) or {
		assert err.msg().contains('-shared-libvcc')
		assert err.msg().contains('-static')
		return
	}
	_ = both
	assert false, '-shared-libvcc with -static was accepted'
}

// The two shared runtimes on one line is the pair that is refused first, so the
// answer names them and not the runtime either one selects.
fn test_the_two_shared_runtimes_are_refused_by_name() {
	parsed := parse(['-shared-libvcc', '-shared-libgcc', 'a.c']) or {
		assert err.msg().contains('-shared-libvcc')
		assert err.msg().contains('-shared-libgcc')
		return
	}
	_ = parsed
	assert false, '-shared-libvcc with -shared-libgcc was accepted'
	// The same pair with the flag that selects the libgcc runtime is the same
	// answer, because the two shared flags are asked about first.
	asked := parse(['-shared-libvcc', '--link-libgcc', '-shared-libgcc', 'a.c']) or {
		assert err.msg().contains('-shared-libvcc')
		assert err.msg().contains('-shared-libgcc')
		return
	}
	_ = asked
	assert false, '-shared-libvcc with --link-libgcc and -shared-libgcc was accepted'
}

// -shared-libgcc is the shared form of the runtime --link-libgcc selects, so it
// needs that flag: alone it names nothing a link could take.
fn test_shared_libgcc_needs_the_link_libgcc_flag() {
	assert parse(['--link-libgcc', '-shared-libgcc', 'a.c'])!.shared_libgcc
	assert parse(['--link-libgcc', '-shared-libgcc', 'a.c'])!.runtime_conflict_refusal() == none
	says := parse(['-shared-libgcc', 'a.c']) or {
		assert err.msg().contains('-shared-libgcc')
		assert err.msg().contains('--link-libgcc')
		return
	}
	_ = says
	assert false, '-shared-libgcc without --link-libgcc was accepted'
}

// With no flags at all the command line still has to answer: every list empty,
// every switch off, and the optimizer at the level it runs when nothing says
// otherwise. This is the baseline a later flag is a change from.
fn test_no_flags_leaves_the_defaults_in_place() {
	opts := parse(['x.c'])!
	assert opts.inputs == ['x.c']
	assert opts.output == ''
	assert opts.include_dirs.len == 0
	assert opts.defines.len == 0
	assert opts.undefines.len == 0
	assert opts.library_dirs.len == 0
	assert opts.libraries.len == 0
	assert opts.preludes.len == 0
	assert opts.ignored.len == 0
	assert opts.target == ''
	assert opts.standard == ''
	assert opts.input_type == ''
	assert opts.emulation == .none
	assert !opts.compile_only
	assert !opts.preprocess
	assert !opts.print_ast
	assert !opts.run
	assert !opts.shared
	assert !opts.static_link
	assert !opts.pic
	assert !opts.verbose
	assert !opts.inhibit_warnings
	assert !opts.undef_builtins
	assert !opts.dump_macros
	assert opts.optimization.level == .o0
	// A command line with no input at all is empty rather than an error; the
	// driver is the one that refuses it, with the usage text.
	assert parse([])!.inputs.len == 0
}

// The output is empty until -o names it. The a.out default is the driver's and
// the usage text says so; this field only ever holds what the command line
// wrote, so a caller can tell "not named" from "named a.out".
fn test_the_output_stays_empty_until_the_flag_names_it() {
	assert parse(['x.c'])!.output == ''
	assert parse(['-o', 'a.out', 'x.c'])!.output == 'a.out'
	assert usage(false).contains('default a.out')
}

// -U, -x and -B are value flags the joined spellings elsewhere do not cover:
// -U has both spellings, and -x and -B only take the next word. -B records the
// flag and its value together, because the recorded list is what a verbose run
// prints and the value is half of what was passed over.
fn test_the_naming_flags_read_their_own_arguments() {
	joined := parse(['-UFOO', '-D', 'BAR', 'x.c'])!
	assert joined.undefines == ['FOO']
	assert joined.defines == ['BAR']
	separate := parse(['-U', 'FOO', 'x.c'])!
	assert separate.undefines == ['FOO']
	assert parse(['-x', 'c', 'x.c'])!.input_type == 'c'
	assert parse(['-B', '/dir', 'x.c'])!.ignored == ['-B /dir']
	assert parse(['-B/dir', 'x.c'])!.ignored == ['-B/dir']
}

// -D and -U are applied in the order they were written, so the reader keeps
// that order as well as the per-flag lists. `-D A=1 -U A -D A=2` ends with A
// defined as 2; applying every -D before every -U, which is what the two flat
// lists do, ends with it undefined.
fn test_the_define_and_undefine_arguments_keep_the_order_they_were_written() {
	opts := parse(['-D', 'A=1', '-UA', '-D', 'A=2', 'x.c'])!
	expected := [
		preprocess.DefineAction{ name: 'A=1' },
		preprocess.DefineAction{ name: 'A', undefine: true },
		preprocess.DefineAction{ name: 'A=2' },
	]
	assert opts.define_actions == expected
	// The lists sorted by flag still hold what each flag named, which is what
	// the existing readers ask for.
	assert opts.defines == ['A=1', 'A=2']
	assert opts.undefines == ['A']
	assert parse(['x.c'])!.define_actions.len == 0
}

// A flag that names a path or a name is given once per directory, header and
// library, so repeating it adds to the list rather than replacing what came
// before. The order is the command line's, which a search reads.
fn test_a_repeated_value_flag_accumulates_in_order() {
	opts := parse(['-I', 'a', '-Ib', '-D', 'ONE', '-DTWO', '-Lx', '-L', 'y', '-lm', '-l', 'pthread',
		'x.c'])!
	assert opts.include_dirs == ['a', 'b']
	assert opts.defines == ['ONE', 'TWO']
	assert opts.library_dirs == ['x', 'y']
	assert opts.libraries == ['m', 'pthread']
}

// A link searches a library after the objects written before it and before the
// objects written after it, so the order between the inputs and the -l names is
// part of the command line, and the two lists beside this one cannot say it.
// The joined and separate spellings of -l hold the same place, because they are
// the same flag.
fn test_the_link_keeps_the_order_inputs_and_libraries_were_written_in() {
	opts := parse(['main.c', '-L.', '-lx', 'other.c', '-lm'])!
	assert opts.inputs == ['main.c', 'other.c']
	assert opts.libraries == ['x', 'm']
	assert opts.link_items.len == 4
	assert opts.link_items[0].value == 'main.c' && !opts.link_items[0].library
	assert opts.link_items[1].value == 'x' && opts.link_items[1].library
	assert opts.link_items[2].value == 'other.c' && !opts.link_items[2].library
	assert opts.link_items[3].value == 'm' && opts.link_items[3].library
	// The same two words in the other order are two more links, and the list
	// says which is which.
	first := parse(['-lx', 'main.c'])!
	assert first.link_items.len == 2
	assert first.link_items[0].value == 'x' && first.link_items[0].library
	assert first.link_items[1].value == 'main.c' && !first.link_items[1].library
	// -l x and -lx are one flag and one place on the line.
	joined := parse(['-l', 'x', 'main.c'])!
	separate := parse(['-lx', 'main.c'])!
	assert joined.link_items == separate.link_items
}

// In a run the words after the source are the program's own arguments, so they
// are not link inputs: only the first input keeps its place, and every -l name
// stays where it was written.
fn test_a_run_keeps_the_first_input_and_every_library_on_the_link() {
	opts := parse(['-run', 'main.c', '-lx', 'arg'])!
	assert opts.inputs == ['main.c']
	assert opts.run_args == ['arg']
	assert opts.link_items.len == 2
	assert opts.link_items[0].value == 'main.c' && !opts.link_items[0].library
	assert opts.link_items[1].value == 'x' && opts.link_items[1].library
}

// A boolean flag that can also be turned off is decided by the last spelling on
// the line, which is what lets a build append -fno-pic to a line that already
// had -fPIC. A flag with no negative spelling stays on however often it is
// written.
fn test_a_repeated_boolean_flag_is_decided_by_the_last_spelling() {
	assert parse(['-fPIC', '-fno-pic', 'x.c'])!.pic == false
	assert parse(['-fno-pic', '-fPIC', 'x.c'])!.pic
	assert parse(['-fno-PIC', '-fpic', 'x.c'])!.pic
	assert parse(['-c', '-c', 'x.c'])!.compile_only
}

// The ignored list is the promise the flag surface makes: what was accepted and
// not acted on is recorded rather than refused, so a verbose run can say what
// it passed over. A flag this compiler reads is not in it. -Wl, options are
// read as a family and are kept in `link_args`, not here: the link that reads
// them applies or refuses them.
fn test_the_ignored_list_holds_the_flags_that_were_passed_over() {
	opts := parse(['-bt25', '-Wl,-rpath,/opt/v', '-fwrapv', '-fPIE', '-B/some/dir', 'x.c', '-o',
		'out'])!
	for flag in ['-bt25', '-fwrapv', '-B/some/dir'] {
		assert opts.ignored.contains(flag), '${flag} should be recorded, not refused'
	}
	assert !opts.ignored.contains('-fPIE'), '-fPIE is read and not recorded'
	for read_flag in ['-o', 'out', '-c', '-w', '-verbose', '-print-search-dirs', '-shared',
		'-Wl,-rpath,/opt/v'] {
		assert !opts.ignored.contains(read_flag), '${read_flag} is read and not recorded'
	}
}

// The recorded list keeps the order the flags were written in, so the verbose
// output reads the way the command line did.
fn test_the_ignored_list_keeps_the_command_line_order() {
	opts := parse(['-bt25', '-fwrapv', '-Wl,-z,now', 'x.c'])!
	assert opts.ignored == ['-bt25', '-fwrapv']
	assert opts.link_args == ['-z,now']
}

// -v is the version, -vv is the paths, and -verbose is the long spelling of the
// detailed report. They are three switches on three fields, so a build that
// asks for one is not answered with another.
fn test_the_version_paths_and_verbose_switches_are_separate() {
	version_flag := parse(['-v'])!
	assert version_flag.show_version
	assert !version_flag.show_paths
	assert !version_flag.verbose
	assert parse(['--version'])!.show_version
	paths := parse(['-vv'])!
	assert paths.show_paths
	assert !paths.show_version
	assert !paths.verbose
	verbose := parse(['-verbose', 'x.c'])!
	assert verbose.verbose
	assert !verbose.show_version
	assert !verbose.show_paths
}

// -h and -hh are the two help flags, and they name the two texts main.v prints:
// -h the short usage and -hh the section on compiler flags as well. They can be
// given together, which is what a command line appending -hh to -h does.
fn test_the_two_help_flags_select_the_two_texts() {
	short := parse(['-h'])!
	assert short.show_help
	assert !short.show_help_all
	all := parse(['-hh'])!
	assert all.show_help_all
	assert !all.show_help
	both := parse(['-h', '-hh'])!
	assert both.show_help && both.show_help_all
}

// -E is a switch of its own and not just "a run that does not link": it says
// the token stream is what comes out, which is a fact the driver reads before
// it decides what to write.
fn test_the_preprocess_flag_is_its_own_switch() {
	opts := parse(['-E', 'x.c'])!
	assert opts.preprocess
	assert !opts.compile_only
	assert !opts.print_ast
	assert !opts.links()
}

// - is an input, and it is the one input with no name to read a kind from. The
// -- marker ends the flags, so a - after it is an input too and the word after
// it is an input rather than a flag.
fn test_standard_input_and_the_end_of_flags_marker() {
	assert parse(['-', '-o', 'out'])!.inputs == ['-']
	assert parse(['--', '-', 'x.c'])!.inputs == ['-', 'x.c']
	assert parse(['--', '-o'])!.inputs == ['-o']
}

// The version line and the usage text both name the binary, because both are
// read by a build tool that has to know which compiler answered.
fn test_the_version_line_and_the_usage_name_the_binary() {
	line := version_line()
	assert line.contains('vcc')
	assert line.contains(version)
	text := usage(false)
	assert text.starts_with('Usage: vcc')
	assert text.contains('vcc')
}

// version is not written in cli.v: it is the version field v.mod names, and this
// pins the two together so a bump to v.mod cannot leave a stale number behind.
fn test_the_version_is_the_one_vmod_names() {
	manifest := vmod.decode(@VMOD_FILE) or { panic(err) }
	assert manifest.version != ''
	assert version == manifest.version
}

// The short usage and the full help differ by the section on what a build
// system passes a C compiler. The short text stops before it, and the short
// text is the one an error prints.
fn test_the_full_help_adds_the_compatibility_section() {
	short := usage(false)
	all := usage(true)
	assert short.contains('-print-search-dirs')
	assert !short.contains('What a build system passes a C compiler')
	assert all.contains('What a build system passes a C compiler')
	assert all.len > short.len
	assert all.contains(short)
}

// The value of a flag is the next word whatever it starts with: -D -foo is a
// define named -foo, and a value is not scanned for flags. A joined value is
// the same string without the flag in front of it.
fn test_a_value_that_looks_like_a_flag_is_still_a_value() {
	opts := parse(['-D', '-foo', '-o', '-weird', 'x.c'])!
	assert opts.defines == ['-foo']
	assert opts.output == '-weird'
	assert opts.inputs == ['x.c']
}

// -Wl, options are kept as written at parse time, because which linker reads
// them is not known yet: -fuse-ld may name another tool further down
// the same command line. The option is applied or refused where the link
// happens, and it is never in the ignored list, which is what a build reads to
// learn that something was passed over.
fn test_the_wl_options_are_kept_for_the_link_that_reads_them() {
	opts := parse(['-Wl,-z,execstack', '-Wl,-rpath,/opt/v', 'x.c'])!
	assert opts.link_args == ['-z,execstack', '-rpath,/opt/v']
	assert !opts.ignored.contains('-Wl,-z,execstack')
	assert !opts.ignored.contains('-Wl,-rpath,/opt/v')
	assert parse(['-Wl,-z,now', '-Wl,-z,relro', 'x.c'])!.link_args == ['-z,now', '-z,relro']
	// The spelling with no comma names no option, and a run that kept it would
	// be a run told a link option was given when none was.
	if _ := parse(['-Wl', 'x.c']) {
		assert false, '-Wl with no comma should be an error'
	}
}

// The -z options the image can express, and their negative spellings, are read
// in order: the last mention of a pair wins, the way a repeated command-line
// flag does.
fn test_the_linker_reads_the_z_options_the_image_can_express() {
	assert linker_options(['-z,execstack'])!.execstack
	assert linker_options(['-z,noexecstack'])!.noexecstack
	assert linker_options(['-z,now'])!.bind_now
	assert linker_options(['-z,relro'])!.relro
	assert !linker_options(['-z,relro,-z,norelro'])!.relro
	assert !linker_options(['-z,now,-z,lazy'])!.bind_now
	assert !linker_options(['-z,execstack,-z,noexecstack'])!.execstack
	assert !linker_options([])!.relro
}

// -Wl,-soname,NAME is the one -Wl, option here that takes a string rather than a
// keyword, because the name it gives is the shared object's own. A payload that
// names the option with no name after it is refused the way a -z with no keyword
// is: a recorded option nobody could apply is worse than an error.
fn test_the_linker_reads_the_soname_option() {
	assert linker_options(['-soname,libt.so.0'])!.soname == 'libt.so.0'
	assert linker_options(['-z,now,-soname,libvcc.so.0'])!.soname == 'libvcc.so.0'
	assert linker_options(['-z,now'])!.soname == ''
	assert link_option_refusal('-soname').contains('-soname needs a name')
	assert link_option_refusal('-soname,').contains('-soname needs a name')
}

// link_option_refusal is the diagnostic a payload is refused with, or an empty
// string when the linker reads it. The refusal tests read the message rather
// than only the failure, because the message is what tells a build which option
// stopped it.
fn link_option_refusal(payload string) string {
	linker_options([payload]) or { return err.msg() }
	return ''
}

// An option the in-house linker cannot express is refused by name rather than
// accepted and dropped. Each of these is an option a build system really
// passes, so the diagnostic has to make the option recognisable and say it was
// not implemented.
fn test_a_link_option_the_image_cannot_express_is_refused_by_name() {
	for option in ['--gc-sections', '-rpath,/x', '--as-needed', '-z,origin'] {
		said := link_option_refusal(option)
		assert said.contains('-Wl,${option}'), '${option} was not named in: ${said}'
		assert said.contains('does not implement'), '${option} was not refused: ${said}'
	}
	assert link_option_refusal('').contains('names no linker option')
	assert link_option_refusal('-z').contains('-z needs an argument')
}

// The other linker gets the payloads as its own words: a comma between the
// options inside one -Wl, word is the separator gcc uses, and nothing here
// interprets or refuses what it forwards.
fn test_fuse_ld_gets_the_wl_options_as_its_own_words() {
	assert fuse_ld_arguments(['-z,now']) == ['-z', 'now']
	assert fuse_ld_arguments(['-rpath,/x', '--gc-sections']) == ['-rpath', '/x', '--gc-sections']
	assert fuse_ld_arguments([]).len == 0
}
