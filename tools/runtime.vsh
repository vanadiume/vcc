#!/usr/bin/env -S v run

// Where the runtime archive a corpus needs comes from.
//
// A program this compiler builds reaches libvcc for a helper the machine has no
// instruction for, and since the complex product and quotient became calls, a
// corpus that multiplies two complex values needs an archive that answers them.
// The archive is not part of this tree, so a run of the corpus has to find one
// or build one.
//
// The order is the one a person would try:
//
//  1. a runtime the machine already has, which is used only when it answers the
//     six complex helpers -- the installed /usr/local/lib/libvcc.a from before
//     the complex work answers none of them, so existence is not the test;
//  2. a libvcc checkout beside this tree, or the directory named with --libvcc
//     or $LIBVCC_DIR;
//  3. a clone of the repository at the pinned commit, in a cache directory
//     outside the tree, built with the compiler this run is using.
//
// The answer is one line on stdout: the directory to hand the compiler with -L.
// Everything a person reads goes to stderr, so a caller can capture stdout
// without filtering it. A run that cannot provision exits non-zero and says
// which of the three failed.
//
//   v run tools/runtime.vsh --compiler /tmp/vcc --root .
//   v run tools/runtime.vsh --compiler /tmp/vcc --root . --libvcc ../libvcc
//
// A tree a run has to download is pinned to a commit, not to a branch: a corpus
// result is worth nothing if the runtime under it moves between two runs. The
// commit can be named with $LIBVCC_COMMIT, which is how CI carries the same pin
// the release workflow uses.

import os

const runtime_repo = 'https://github.com/vanadiume/libvcc'
const runtime_commit = '0f457bf8618faa8f5799764081655fecd880cd0e'
const runtime_archive = 'libvcc.a'

// The helpers a corpus program can reach. A runtime that answers fewer than
// these is one from before the complex work, and using it would fail every
// program that multiplies a complex value.
const required_helpers = ['__muldc3', '__divdc3', '__mulsc3', '__divsc3', '__mulxc3', '__divxc3']

// A program that needs all six helpers and reads one answer back, so a runtime
// is accepted only when it links and runs. gcc's arithmetic for the product of
// (1+2i) and (3+4i) is -5+10i, and the check is on the real part because that is
// the component a wrong return placement would corrupt.
const probe_source = 'double _Complex __muldc3(double, double, double, double);
double _Complex __divdc3(double, double, double, double);
float _Complex __mulsc3(float, float, float, float);
float _Complex __divsc3(float, float, float, float);
long double _Complex __mulxc3(long double, long double, long double, long double);
long double _Complex __divxc3(long double, long double, long double, long double);
int main(void) {
    double _Complex p = __muldc3(1.0, 2.0, 3.0, 4.0);
    double _Complex q = __divdc3(1.0, 2.0, 3.0, 4.0);
    float _Complex fp = __mulsc3(1.0f, 2.0f, 3.0f, 4.0f);
    float _Complex fq = __divsc3(1.0f, 2.0f, 3.0f, 4.0f);
    long double _Complex xp = __mulxc3(1.0L, 2.0L, 3.0L, 4.0L);
    long double _Complex xq = __divxc3(1.0L, 2.0L, 3.0L, 4.0L);
    if (__real__ p != -5.0 || __imag__ p != 10.0) { return 1; }
    if (__real__ q < 0.43 || __real__ q > 0.45) { return 2; }
    if (__real__ fp != -5.0f || __imag__ fp != 10.0f) { return 3; }
    if (__real__ fq < 0.43f || __real__ fq > 0.45f) { return 4; }
    if (__real__ xp != -5.0L || __imag__ xp != 10.0L) { return 5; }
    if (__real__ xq < 0.43L || __real__ xq > 0.45L) { return 6; }
    return 0;
}
'

struct Options {
mut:
	compiler string
	root     string
	tree     string
	verbose  bool
}

fn main() {
	opts := parse(os.args[1..]) or {
		usage()
		exit(2)
	}
	scratch := os.join_path(os.temp_dir(), 'vcc-runtime-${os.getpid()}')
	os.mkdir_all(scratch) or {
		eprintln('runtime: cannot make ${scratch}: ${err}')
		exit(1)
	}
	defer {
		os.rmdir_all(scratch) or {}
	}
	probe := os.join_path(scratch, 'probe.c')
	os.write_file(probe, probe_source) or {
		eprintln('runtime: cannot write the probe: ${err}')
		exit(1)
	}
	if dir := find_system(opts, probe, scratch) {
		eprintln('runtime: the machine has one, ${dir}')
		println(dir)
		return
	}
	if dir := find_tree(opts, probe, scratch) {
		println(dir)
		return
	}
	if dir := find_clone(opts, probe, scratch) {
		println(dir)
		return
	}
	eprintln('runtime: no libvcc answers ${required_helpers.join(', ')}')
	eprintln('runtime: the machine has none, ${opts.root}/../libvcc was not usable, and the clone of ${runtime_repo} did not build one')
	eprintln('runtime: name a tree with --libvcc DIR or $LIBVCC_DIR')
	exit(1)
}

fn usage() {
	eprintln('runtime: v run tools/runtime.vsh --compiler PATH --root DIR [--libvcc DIR]')
}

fn parse(raw []string) ?Options {
	mut opts := Options{}
	mut i := 0
	for i < raw.len {
		arg := raw[i]
		if arg == '--compiler' || arg == '--root' || arg == '--libvcc' {
			if i + 1 >= raw.len {
				eprintln('runtime: ${arg} needs a value')
				return none
			}
			match arg {
				'--compiler' { opts.compiler = raw[i + 1] }
				'--root' { opts.root = raw[i + 1] }
				else { opts.tree = raw[i + 1] }
			}
			i += 2
			continue
		}
		if arg.starts_with('--compiler=') {
			opts.compiler = arg.all_after('--compiler=')
		} else if arg.starts_with('--root=') {
			opts.root = arg.all_after('--root=')
		} else if arg.starts_with('--libvcc=') {
			opts.tree = arg.all_after('--libvcc=')
		} else if arg == '-v' || arg == '--verbose' {
			opts.verbose = true
		} else {
			eprintln('runtime: unknown argument ${arg}')
			return none
		}
		i++
	}
	if opts.compiler == '' || opts.root == '' {
		eprintln('runtime: --compiler and --root are both required')
		return none
	}
	if opts.tree == '' {
		opts.tree = os.getenv_opt('LIBVCC_DIR') or { '' }
	}
	return opts
}

// find_system is the runtime the machine already has: the archive the compiler's
// own search answers, accepted only when the probe links and runs against it.
// `-print-file-name` answers the name unchanged when the search has nothing, so
// an absolute path that is there is the first half of the test and the probe is
// the second.
fn find_system(opts Options, probe string, scratch string) ?string {
	result := os.execute('${os.quoted_path(opts.compiler)} -print-file-name=${runtime_archive}')
	if result.exit_code != 0 {
		return none
	}
	path := result.output.trim_space()
	if path == '' || !os.is_abs_path(path) || !os.exists(path) {
		return none
	}
	place := os.dir(path)
	if accepts(opts, place, probe, scratch) {
		return place
	}
	eprintln('runtime: ${path} is there and does not answer the helpers, so it is not used')
	return none
}

// find_tree is a checkout beside this one. It is built with the compiler under
// test before it is used, because a tree someone edited yesterday is not the
// archive this run is measuring.
fn find_tree(opts Options, probe string, scratch string) ?string {
	mut candidates := []string{}
	if opts.tree != '' {
		candidates << opts.tree
	}
	candidates << os.join_path(os.dir(opts.root), 'libvcc')
	candidates << os.join_path(opts.root, 'libvcc')
	for candidate in candidates {
		if !os.exists(os.join_path(candidate, 'build.vsh')) {
			continue
		}
		built := build_tree(opts, candidate, scratch) or {
			eprintln('runtime: could not build ${candidate}')
			continue
		}
		if accepts(opts, built, probe, scratch) {
			eprintln('runtime: built ${candidate}')
			return built
		}
		eprintln('runtime: ${candidate} built an archive that does not answer the helpers')
	}
	return none
}

// find_clone is the repository at the pinned commit, in a cache directory keyed
// by that commit so a second run clones nothing. The clone is reused only when
// its archive still answers the probe.
fn find_clone(opts Options, probe string, scratch string) ?string {
	commit := os.getenv_opt('LIBVCC_COMMIT') or { runtime_commit }
	cache := os.getenv_opt('XDG_CACHE_HOME') or { os.join_path(os.home_dir(), '.cache') }
	tree := os.join_path(cache, 'vcc', 'libvcc-${commit}')
	if stored := archive_dir(tree) {
		if accepts(opts, stored, probe, scratch) {
			eprintln('runtime: reused ${tree}')
			return stored
		}
	}
	eprintln('runtime: cloning ${runtime_repo} at ${commit}')
	os.rmdir_all(tree) or {}
	os.mkdir_all(os.dir(tree)) or {
		eprintln('runtime: cannot make ${os.dir(tree)}: ${err}')
		return none
	}
	clone := os.execute('git clone --quiet ${runtime_repo} ${os.quoted_path(tree)}')
	if clone.exit_code != 0 {
		eprintln('runtime: clone failed: ${clone.output.trim_space()}')
		return none
	}
	pin := os.execute('git -C ${os.quoted_path(tree)} checkout --quiet ${commit}')
	if pin.exit_code != 0 {
		eprintln('runtime: there is no commit ${commit} in the clone')
		return none
	}
	built := build_tree(opts, tree, scratch) or {
		eprintln('runtime: the clone did not build')
		return none
	}
	if accepts(opts, built, probe, scratch) {
		return built
	}
	eprintln('runtime: the clone at ${commit} answers fewer than the six helpers; the pin has to move to a commit that has them')
	return none
}

// archive_dir is where a built libvcc tree keeps the archive the compiler lane
// wrote, or nothing when it has not been built.
fn archive_dir(tree string) ?string {
	where := os.join_path(tree, 'target', 'vcc')
	if os.exists(os.join_path(where, runtime_archive)) {
		return where
	}
	return none
}

// build_tree builds one libvcc tree with the compiler under test: the archive is
// the runtime for the code this compiler emits, so it is built by this compiler.
fn build_tree(opts Options, tree string, scratch string) ?string {
	runner := os.join_path(tree, 'build.vsh')
	if !os.exists(runner) {
		return none
	}
	log_path := os.join_path(scratch, 'libvcc-build.log')
	command := 'cd ${os.quoted_path(tree)} && VCC=${os.quoted_path(opts.compiler)} v run build.vsh build --cc vcc > ${os.quoted_path(log_path)} 2>&1'
	if opts.verbose {
		eprintln('runtime: ${command}')
	}
	built := os.execute(command)
	if built.exit_code != 0 {
		lines := (os.read_file(log_path) or { '' }).split_into_lines()
		tail := if lines.len > 6 { lines[lines.len - 6..] } else { lines }
		eprintln('runtime: ${tree} did not build')
		for line in tail {
			eprintln('  ${line}')
		}
		return none
	}
	return archive_dir(tree)
}

// accepts links the probe against a directory and runs it. It is the whole test:
// a name in an index is not the same thing as a helper that answers.
fn accepts(opts Options, dir string, probe string, scratch string) bool {
	exe := os.join_path(scratch, 'probe')
	build := os.execute('${os.quoted_path(opts.compiler)} ${os.quoted_path(probe)} -L ${os.quoted_path(dir)} -o ${os.quoted_path(exe)} 2>&1')
	if build.exit_code != 0 {
		if opts.verbose {
			eprintln('runtime: probe against ${dir} did not link: ${build.output.trim_space()}')
		}
		return false
	}
	ran := os.execute(os.quoted_path(exe))
	if ran.exit_code != 0 {
		if opts.verbose {
			eprintln('runtime: probe against ${dir} answered ${ran.exit_code}')
		}
		return false
	}
	os.rm(exe) or {}
	return true
}
