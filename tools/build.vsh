#!/usr/bin/env -S v run

// The front door over the work this tree asks a person to run: build the
// compiler and its runtime archive, the gate, the two C corpora, the benchmark,
// the image, and the version report. Every step calls the runner that already
// owns it, so no count or floor lives here to drift; --list names the steps.
//
// The compiler is built under the temp directory for the steps that only need
// one to run cases, and `build -o PATH` puts it where a person wants it. `all`
// runs every step even when one fails, and exits non-zero if any failed. A step
// whose tool is missing is skipped, and fails only when asked for by name.
//
// `install` is the one step that writes outside the tree, so it is not part of
// the default run or of `all`: it copies the compiler and the runtime archive
// into a prefix and proves they work as a pair.

import os
import time

// The default run: the compiler, then its runtime archive, then the gate, then
// both corpora. The gate runs `v -nocache test .` itself, so the suite is not a
// step of its own here.
const default_steps = ['build', 'libvcc', 'gate', 'compliance', 'regress']

// The compiler is built without a garbage collector. Every stage frees what it
// allocated before the next one runs, so there is nothing left for a collector
// to find, and the binary carries none.
const gc_flag = '-gc none'

// What `all` runs, each step once; `corpora` is those two runners together.
const every_step = ['build', 'gate', 'test', 'compliance', 'regress', 'bench', 'libvcc', 'docker',
	'version']

// A step that is named and never run by default, because it writes outside the
// tree or because its whole point is to be asked for.
const named_steps = ['install']

struct Context {
mut:
	root     string
	scratch  string
	compiler string
}

struct Outcome {
mut:
	verdict Verdict
	name    string
	detail  string
	seconds f64
}

// Runtime is the archive a run built, or why it could not.
struct Runtime {
	archive string
	error   string
}

enum Verdict {
	passed
	failed
	skipped
}

fn main() {
	mut ctx := Context{
		root:    os.dir(os.dir(@FILE))
		scratch: os.join_path(os.temp_dir(), 'vcc-build-${os.getpid()}')
	}
	args := os.args[1..]
	if args.len == 0 {
		finish(mut ctx, run_all(mut ctx, default_steps, []), false)
		return
	}
	step := args[0]
	if step in ['-h', '--help', '--list', '-l'] {
		usage()
		return
	}
	if step == 'all' {
		finish(mut ctx, run_all(mut ctx, every_step, []), false)
		return
	}
	if step != 'corpora' && step !in every_step && step !in named_steps {
		eprintln('build: unknown step ${step}')
		usage()
		exit(1)
	}
	finish(mut ctx, run_all(mut ctx, [step], args[1..]), true)
}

// run_all prints each verdict as it lands; a failure does not stop the rest.
fn run_all(mut ctx Context, names []string, args []string) []Outcome {
	mut outcomes := []Outcome{}
	for name in names {
		outcome := run_step(mut ctx, name, args)
		print_outcome(outcome)
		outcomes << outcome
	}
	return outcomes
}

fn run_step(mut ctx Context, name string, args []string) Outcome {
	started := time.now()
	mut outcome := Outcome{ name: name }
	match name {
		'build' { outcome = step_build(mut ctx, args) }
		'test' { outcome = step_runner(mut ctx, 'test', 'v -nocache test .', args) }
		'gate' { outcome = step_runner(mut ctx, 'gate', 'v run tools/gate.vsh', args) }
		'bench' { outcome = step_runner(mut ctx, 'bench', 'v run tools/bench.vsh', args) }
		'libvcc' { outcome = step_libvcc(mut ctx) }
		'install' { outcome = step_install(mut ctx, args) }
		'compliance' { outcome = step_corpus(mut ctx, 'compliance', 'v run tools/compliance.vsh') }
		'regress' { outcome = step_corpus(mut ctx, 'regress', 'v run tools/regress.vsh') }
		'corpora' { outcome = step_corpora(mut ctx) }
		'docker' { outcome = step_docker(mut ctx) }
		'version' { outcome = step_version(mut ctx) }
		else {}
	}
	outcome.seconds = time.since(started).seconds()
	return outcome
}

// step_build is the one place a binary is asked for by name. With -o it lands
// where the caller said, otherwise under the temp directory for the runners.
// --prod is the build the image makes: V's warnings become errors, so a
// deprecation that the plain build carries on past stops this one, and the
// generated C is compiled without debug information.
fn step_build(mut ctx Context, args []string) Outcome {
	mut path := os.join_path(ctx.scratch, 'vcc')
	mut production := ''
	mut rest := []string{}
	for arg in args {
		if arg == '--prod' {
			production = '-prod'
			continue
		}
		rest << arg
	}
	if rest.len > 0 {
		if rest[0] != '-o' || rest.len < 2 {
			return failed('build', 'only -o PATH and --prod are taken here')
		}
		path = rest[1]
	}
	os.mkdir_all(os.dir(path)) or {}
	if run_in(ctx.root, 'v ${gc_flag} ${production} -o ${os.quoted_path(path)} .') != 0 {
		return failed('build', 'the compiler did not build')
	}
	ctx.compiler = path
	mut detail := if rest.len > 0 { path } else { 'scratch binary' }
	if production != '' {
		detail += ', production'
	}
	return Outcome{ verdict: .passed, name: 'build', detail: detail }
}

// step_libvcc builds the runtime library with the compiler this tree just built,
// then links a program against that archive and runs it. The archive is libvcc,
// and the program reaches into it for a helper this compiler's image cannot
// define for itself: a link that pulls the member is the proof the archive is
// found and read, and its exit status is the proof of what it computed.
//
// The tree comes from the libvcc repository at the commit the release workflow
// pins, cloned into the user's cache, so a checkout with no sibling tree builds
// the same runtime a release carries. LIBVCC_COMMIT names another commit for a
// probe.
fn step_libvcc(mut ctx Context) Outcome {
	runtime := provision_runtime(mut ctx, '')
	if runtime.error != '' {
		return failed('libvcc', runtime.error)
	}
	problem := probe_archive(mut ctx, ctx.compiler, runtime.archive)
	if problem != '' {
		return failed('libvcc', problem)
	}
	return Outcome{ verdict: .passed, name: 'libvcc', detail: runtime.archive }
}

// provision_runtime builds libvcc with the compiler this run built and answers
// the archive it wrote. A named tree is used as it is; with no name the
// repository is cloned at the commit release.yml pins, into the cache directory
// tools/runtime.vsh uses for the same commit, so the two scripts share one clone
// and neither trusts a tree that has moved.
fn provision_runtime(mut ctx Context, tree string) Runtime {
	mut where := tree
	if where == '' {
		where = libvcc_tree(ctx.root) or {
			return Runtime{ error: 'no libvcc: ${err}' }
		}
	} else if !os.exists(os.join_path(where, 'build.vsh')) {
		return Runtime{ error: 'no ${os.join_path(where, 'build.vsh')}' }
	}
	compiler := ensure_compiler(mut ctx)
	if compiler == '' {
		return Runtime{ error: 'the compiler did not build' }
	}
	// libvcc's own build looks for vcc through $VCC before PATH, which is how it
	// is handed the binary this step just built rather than whichever one a
	// shell would find.
	os.setenv('VCC', compiler, true)
	if run_in(where, 'v run build.vsh build --cc vcc') != 0 {
		return Runtime{ error: 'libvcc did not build with the compiler' }
	}
	archive := os.join_path(where, 'target', 'vcc', 'libvcc.a')
	if !os.exists(archive) {
		return Runtime{ error: 'the build at ${where} wrote no ${archive}' }
	}
	return Runtime{ archive: archive }
}

// libvcc_tree is the clone a run builds: the repository and commit release.yml
// names, in the cache directory keyed by the commit. Reading the pin out of the
// release workflow keeps the build step and the tarball on one commit.
fn libvcc_tree(root string) !string {
	workflows := os.join_path(root, '.github', 'workflows')
	repo := read_named(workflows, 'release.yml', 'LIBVCC_REPO:')
	commit := os.getenv_opt('LIBVCC_COMMIT') or {
		read_named(workflows, 'release.yml', 'LIBVCC_COMMIT:')
	}
	if repo == '' || commit == '' {
		return error('release.yml names no LIBVCC_REPO or LIBVCC_COMMIT')
	}
	cache := os.getenv_opt('XDG_CACHE_HOME') or { os.join_path(os.home_dir(), '.cache') }
	tree := os.join_path(cache, 'vcc', 'libvcc-${commit}')
	if os.exists(os.join_path(tree, 'build.vsh')) {
		head := capture('git -C ${os.quoted_path(tree)} rev-parse HEAD').trim_space()
		if head == commit {
			return tree
		}
	}
	os.rmdir_all(tree) or {}
	os.mkdir_all(os.dir(tree)) or { return error('cannot make ${os.dir(tree)}: ${err}') }
	clone := os.exec(['git', 'clone', '--quiet', repo, tree])
	if clone.exit_code != 0 {
		return error('could not clone ${repo} (git exited ${clone.exit_code})')
	}
	pin := os.exec(['git', '-C', tree, 'checkout', '--quiet', commit])
	if pin.exit_code != 0 {
		return error('there is no commit ${commit} in ${repo}')
	}
	return tree
}

// probe_archive links a program against one archive and runs it. The program
// calls __divdi3, which only a runtime answers, and exits with the quotient of
// 84 by 2.
fn probe_archive(mut ctx Context, compiler string, archive string) string {
	os.mkdir_all(ctx.scratch) or {}
	program := os.join_path(ctx.scratch, 'runtime_helper.c')
	binary := os.join_path(ctx.scratch, 'runtime_helper')
	body := 'long long __divdi3(long long a, long long b);\nint main(void) { return (int)__divdi3(84, 2); }\n'
	os.write_file(program, body) or { return 'could not write a program: ${err}' }
	if run_in('', '${os.quoted_path(compiler)} ${os.quoted_path(program)} -L ${os.quoted_path(os.dir(archive))} -o ${os.quoted_path(binary)}') != 0 {
		return 'the compiler could not link a program against ${archive}'
	}
	status := run_in('', os.quoted_path(binary))
	if status != 42 {
		return 'the program answered ${status}, and the helper it called divides 84 by 2'
	}
	return ''
}

// step_install puts the compiler and the runtime archive where a user's link
// finds them: PREFIX/bin/vcc and PREFIX/lib/libvcc.a, /usr/local by default. The
// archive is not optional, because a program that reaches one of its helpers is
// refused by that helper's name when the archive is missing, so a run that
// cannot provide libvcc fails here rather than installing half a compiler.
//
// The compiler is built from this tree and libvcc comes from its repository at
// the commit release.yml pins, unless --libvcc names a tree to build instead.
// What is left behind is then proved as a pair: a program that calls a helper
// only the archive defines is compiled by the installed binary and run.
fn step_install(mut ctx Context, args []string) Outcome {
	mut prefix := '/usr/local'
	mut tree := ''
	mut i := 0
	for i < args.len {
		arg := args[i]
		if arg == '--prefix' || arg == '--libvcc' {
			if i + 1 >= args.len {
				return failed('install', '${arg} needs a directory')
			}
			if arg == '--prefix' {
				prefix = args[i + 1]
			} else {
				tree = args[i + 1]
			}
			i += 2
			continue
		}
		if arg.starts_with('--prefix=') {
			prefix = arg.all_after('--prefix=')
		} else if arg.starts_with('--libvcc=') {
			tree = arg.all_after('--libvcc=')
		} else {
			return failed('install', 'install takes --prefix DIR and --libvcc DIR, and not ${arg}')
		}
		i++
	}
	runtime := provision_runtime(mut ctx, tree)
	if runtime.error != '' {
		return failed('install', runtime.error)
	}
	compiler := ctx.compiler
	archive := runtime.archive
	// The shared runtime is part of the pair. A program linked with
	// -shared-libvcc records the .so's own name, so the install carries the
	// chain of names the library was written with: the versioned file and the
	// two symlinks beside it. A tree that built only the archive fails here
	// rather than installing half a runtime.
	shared := os.join_path(os.dir(archive), 'libvcc.so')
	if !os.exists(shared) {
		return failed('install', 'the build wrote no ${shared}, and -shared-libvcc links against it')
	}
	binary := os.join_path(prefix, 'bin', 'vcc')
	library := os.join_path(prefix, 'lib', 'libvcc.a')
	// A prefix the user cannot write is the normal case for /usr/local, and a
	// build script that stops there sends a person to retype the run under sudo.
	// The copies go through it instead, and the line says which they were.
	escalate := !writable(prefix)
	if escalate {
		println('install: ${prefix} is not writable, so the copies run under sudo')
	}
	if !place(compiler, binary, '755', escalate) {
		return failed('install', 'could not write ${binary}')
	}
	if !place(archive, library, '644', escalate) {
		return failed('install', 'could not write ${library}')
	}
	shared_dir := os.join_path(prefix, 'lib')
	real := os.real_path(shared)
	if !place(real, os.join_path(shared_dir, os.base(real)), '755', escalate) {
		return failed('install', 'could not write ${os.join_path(shared_dir, os.base(real))}')
	}
	// Every other name in the lane directory is a symlink the library was
	// written with, and the loader asks for the soname rather than for the
	// versioned file. Reproduce them rather than hardcoding the chain, because
	// the version in the names comes from libvcc's own VERSION file.
	for entry in os.ls(os.dir(archive)) or { []string{} } {
		if entry == os.base(real) || !entry.starts_with('libvcc.so') {
			continue
		}
		rel := os.readlink(os.join_path(os.dir(archive), entry)) or { '' }
		if rel == '' {
			continue
		}
		if !make_link(rel, os.join_path(shared_dir, entry), escalate) {
			return failed('install', 'could not link ${os.join_path(shared_dir, entry)} to ${rel}')
		}
	}
	os.mkdir_all(ctx.scratch) or {}
	program := os.join_path(ctx.scratch, 'runtime_helper.c')
	exe := os.join_path(ctx.scratch, 'runtime_helper')
	body := 'long long __divdi3(long long a, long long b);\nint main(void) { return (int)__divdi3(84, 2); }\n'
	os.write_file(program, body) or { return failed('install', 'could not write a program: ${err}') }
	// The compiler searches the system's library directories and then its own,
	// so a prefix that is one of those needs no flag; a staging prefix (the
	// release tarball's tree) is in no search list and is given one. Either way
	// the archive the run reads is the one just installed.
	search := if prefix == '/usr' || prefix == '/usr/local' {
		''
	} else {
		'-L ${os.quoted_path(os.join_path(prefix, 'lib'))}'
	}
	if run_in('', '${os.quoted_path(binary)} ${os.quoted_path(program)} ${search} -o ${os.quoted_path(exe)}') != 0 {
		return failed('install', 'the installed compiler could not link a program against ${library}')
	}
	status := run_in('', os.quoted_path(exe))
	if status != 42 {
		return failed('install', 'the program answered ${status}, and the helper it called divides 84 by 2')
	}
	// And the shared runtime, which is the other half of what the tarball
	// carries: a program that calls a complex helper, linked with -shared-libvcc
	// so the image names the .so, run with the installed directory on the
	// loader's path. It exits with the real part plus 5, which is 0.
	shared_program := os.join_path(ctx.scratch, 'shared_helper.c')
	shared_exe := os.join_path(ctx.scratch, 'shared_helper')
	shared_body := 'double _Complex __muldc3(double, double, double, double);\nint main(void) { double _Complex z = __muldc3(1.0, 2.0, 3.0, 4.0); return (int)__real__ z + 5; }\n'
	os.write_file(shared_program, shared_body) or {
		return failed('install', 'could not write a program: ${err}')
	}
	if run_in('', '${os.quoted_path(binary)} ${os.quoted_path(shared_program)} ${search} -shared-libvcc -o ${os.quoted_path(shared_exe)}') != 0 {
		return failed('install', 'the installed compiler could not link a program with -shared-libvcc')
	}
	shared_status := run_in('', 'LD_LIBRARY_PATH=${os.quoted_path(shared_dir)} ${os.quoted_path(shared_exe)}')
	if shared_status != 0 {
		return failed('install', 'the -shared-libvcc program answered ${shared_status}, and the helper it called multiplies (1+2i)(3+4i), whose real part is -5')
	}
	return Outcome{
		verdict: .passed
		name:    'install'
		detail:  '${binary}, ${library}, ${os.join_path(shared_dir, os.base(real))}'
	}
}

// writable says whether a run by this user can create a file under a directory
// that may not exist yet. The walk stops at the nearest directory that is there,
// because that is the one a file would be created in.
fn writable(dir string) bool {
	mut existing := dir
	for !os.exists(existing) {
		parent := os.dir(existing)
		if parent == existing {
			return false
		}
		existing = parent
	}
	probe := os.join_path(existing, '.vcc-install-${os.getpid()}')
	os.write_file(probe, '') or { return false }
	os.rm(probe) or {}
	return true
}

// place copies one file into a prefix with the mode it needs, through sudo when
// the prefix is not the user's to write.
// make_link points one name in the installed directory at another, through sudo
// when the prefix is not the user's to write.
fn make_link(target string, link string, escalate bool) bool {
	if escalate {
		return os.system_args(['sudo', 'ln', '-sf', target, link]) == 0
	}
	return os.system_args(['ln', '-sf', target, link]) == 0
}

fn place(source string, target string, mode string, escalate bool) bool {
	if escalate {
		return os.system_args(['sudo', 'install', '-D', '-m', mode, source, target]) == 0
	}
	return os.system_args(['install', '-D', '-m', mode, source, target]) == 0
}

fn step_runner(mut ctx Context, name string, command string, args []string) Outcome {
	mut full := command
	for arg in args {
		full += ' ${os.quoted_path(arg)}'
	}
	if run_in(ctx.root, full) != 0 {
		return failed(name, 'exit non-zero')
	}
	return Outcome{ verdict: .passed, name: name }
}

// ensure_compiler builds the tree once into the scratch directory, so the two
// corpus runners do not each build it again.
fn ensure_compiler(mut ctx Context) string {
	if ctx.compiler != '' {
		return ctx.compiler
	}
	os.mkdir_all(ctx.scratch) or {}
	path := os.join_path(ctx.scratch, 'vcc')
	if run_in(ctx.root, 'v ${gc_flag} -o ${os.quoted_path(path)} .') != 0 {
		return ''
	}
	ctx.compiler = path
	return path
}

// step_corpus hands the runner a compiler and lets it keep its own floors.
fn step_corpus(mut ctx Context, name string, command string) Outcome {
	compiler := ensure_compiler(mut ctx)
	if compiler == '' {
		return failed(name, 'the compiler did not build')
	}
	if run_in(ctx.root, '${command} --compiler ${os.quoted_path(compiler)}') != 0 {
		return failed(name, 'exit non-zero')
	}
	return Outcome{ verdict: .passed, name: name }
}

// step_corpora runs both runners even if the first fails, so both answers land.
fn step_corpora(mut ctx Context) Outcome {
	mut broken := []string{}
	if step_corpus(mut ctx, 'compliance', 'v run tools/compliance.vsh').verdict != .passed {
		broken << 'compliance'
	}
	if step_corpus(mut ctx, 'regress', 'v run tools/regress.vsh').verdict != .passed {
		broken << 'regress'
	}
	if broken.len > 0 {
		return failed('corpora', '${broken.join(' and ')} failed')
	}
	return Outcome{ verdict: .passed, name: 'corpora' }
}

// step_docker builds the image from the committed Dockerfile, copies the binary
// out of a container, asks its version, and hands it a program to compile and
// run. The build clones V at the pinned commit, so the line before it warns.
fn step_docker(mut ctx Context) Outcome {
	if (os.find_abs_path_of_executable('docker') or { '' }) == '' {
		return Outcome{ verdict: .skipped, name: 'docker', detail: 'docker is not on PATH' }
	}
	os.mkdir_all(ctx.scratch) or {}
	image := 'vcc-build-${os.getpid()}'
	println('docker: building ${image} from the Dockerfile, which clones V at the pinned commit and builds it; this takes minutes')
	if run_in(ctx.root, 'docker build -t ${image} .') != 0 {
		docker_cleanup('', image)
		return failed('docker', 'docker build exited non-zero')
	}
	id := capture('docker create ${image}').trim_space()
	binary := os.join_path(ctx.scratch, 'vcc-docker')
	if id == '' || run_in('', 'docker cp ${id}:/vcc ${os.quoted_path(binary)}') != 0 {
		docker_cleanup(id, image)
		return failed('docker', 'the container gave up no /vcc')
	}
	answer := capture('${os.quoted_path(binary)} --version').trim_space()
	program := os.join_path(ctx.scratch, 'seven.c')
	exe := os.join_path(ctx.scratch, 'seven')
	os.write_file(program, 'int main(void) { return 7; }\n') or {
		docker_cleanup(id, image)
		return failed('docker', 'could not write a test program: ${err}')
	}
	if run_in(ctx.scratch, '${os.quoted_path(binary)} ${os.quoted_path(program)} -o ${os.quoted_path(exe)}') != 0 {
		docker_cleanup(id, image)
		return failed('docker', 'the copied binary could not compile a program')
	}
	status := run_in(ctx.scratch, os.quoted_path(exe))
	docker_cleanup(id, image)
	if answer == '' {
		return failed('docker', 'the copied binary did not answer --version')
	}
	if status != 7 {
		return failed('docker', 'the compiled program exited ${status}, and its source says 7')
	}
	return Outcome{ verdict: .passed, name: 'docker', detail: answer }
}

// step_version prints the three facts that drift: the binary, v.mod, ci.yml.
fn step_version(mut ctx Context) Outcome {
	root := ctx.root
	mut binary := os.join_path(root, 'vcc')
	built := !os.exists(binary)
	if built {
		binary = ensure_compiler(mut ctx)
		if binary == '' {
			return failed('version', 'the compiler did not build')
		}
	}
	answer := capture('${os.quoted_path(binary)} --version').trim_space()
	named := read_named(root, 'v.mod', 'version:')
	pin := read_named(os.join_path(root, '.github', 'workflows'), 'ci.yml', 'V_COMMIT:')
	println('binary:  ${answer}${if built { ' (built for this run)' } else { '' }}')
	println('v.mod:   ${named}')
	println('V pin:   ${pin} (.github/workflows/ci.yml)')
	if named != '' && answer != '' && !answer.contains(named) {
		println('drift:   the binary and v.mod name different versions')
	}
	if answer == '' || named == '' || pin == '' {
		return failed('version', 'a fact is missing: binary "${answer}", v.mod "${named}", ci.yml "${pin}"')
	}
	return Outcome{ verdict: .passed, name: 'version' }
}

// finish cleans the scratch directory and says which steps failed or skipped.
fn finish(mut ctx Context, outcomes []Outcome, named bool) {
	os.rmdir_all(ctx.scratch) or {}
	mut failed_steps := []string{}
	mut skipped_steps := []string{}
	for outcome in outcomes {
		match outcome.verdict {
			.failed { failed_steps << outcome.name }
			.skipped { skipped_steps << outcome.name }
			.passed {}
		}
	}
	println('')
	if skipped_steps.len > 0 {
		println('build: skipped ${skipped_steps.join(', ')}')
	}
	if failed_steps.len > 0 {
		eprintln('build: ${failed_steps.len} step(s) failed: ${failed_steps.join(', ')}')
		exit(1)
	}
	if named && skipped_steps.len > 0 {
		eprintln('build: ${skipped_steps.join(', ')} was asked for and could not run')
		exit(1)
	}
	println('build: everything passes')
}

fn print_outcome(outcome Outcome) {
	detail := if outcome.detail != '' { '  ${outcome.detail}' } else { '' }
	println('  ${outcome.name}: ${outcome.verdict} (${outcome.seconds:.1f}s)${detail}')
}

// read_named reads one `key: value` line, so neither fact is copied into here.
fn read_named(root string, file string, key string) string {
	text := os.read_file(os.join_path(root, file)) or { return '' }
	for line in text.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with(key) {
			return trimmed.all_after(key).trim_space().trim("'")
		}
	}
	return ''
}

fn docker_cleanup(id string, image string) {
	if id != '' {
		os.system('docker rm -f ${id} >/dev/null 2>&1')
	}
	os.system('docker rmi -f ${image} >/dev/null 2>&1')
}

fn run_in(root string, command string) int {
	if root == '' {
		return os.system(command)
	}
	return os.system('cd ${os.quoted_path(root)} && ${command}')
}

// capture is stdout alone. V's os.execute folds stderr into the same stream, so a
// warning beside the value would land in it; stderr is sent away before reading.
fn capture(command string) string {
	return os.execute('${command} 2>/dev/null').output
}

fn failed(name string, detail string) Outcome {
	return Outcome{ verdict: .failed, name: name, detail: detail }
}

fn usage() {
	println('usage: v run tools/build.vsh [STEP] [args]')
	println('  build [-o PATH] [--prod]  build the compiler only')
	println('  test              the unit suite, `v -nocache test .`')
	println('  gate              tools/gate.vsh')
	println('  compliance        the corpus under compliance/, a directory per standard')
	println('  regress           the regression and golden corpora')
	println('  corpora           compliance and regress together')
	println('  bench [args]      tools/bench.vsh, args passed through')
	println('  libvcc            build ../libvcc with this compiler, then link and run a')
	println('                    program against the archive it writes')
	println('  install [--prefix DIR] [--libvcc DIR]')
	println('                    build both, copy them to DIR/bin/vcc and DIR/lib/libvcc.a')
	println('                    (/usr/local), then link and run a program with them')
	println('  docker            build the image, then run the binary in it')
	println('  version           the binary, v.mod, and the pinned V commit')
	println('  all               every step but install, then a summary')
	println('with no step: the compiler, libvcc, the gate, then both corpora')
}
