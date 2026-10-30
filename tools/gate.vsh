#!/usr/bin/env -S v run

// The local gate: the checks a pull request has to pass, runnable before pushing
// so that CI never holds an opinion the author did not already know.
//
//   v run tools/gate.vsh                            # every step, the whole suite
//   v run tools/gate.vsh --without tests            # every step but the suite
//   v run tools/gate.vsh --only format,pure         # named steps only
//   v run tools/gate.vsh --only tests --shard 1/3   # one third of the suite
//
// Seven steps: formatting, the pure-V rule, the build, the production build, the
// test suite, the links between the documents at the root, and the workflows.
// Each one reports on its own line, and the exit status is zero only when all of
// them pass.
//
// The flags exist so a runner can take part of the gate, which is what `ci.yml`
// does with them: the gate job runs `--without tests` and three runners take a
// third of the suite each with `--shard`. `--without` is what the gate job names
// rather than `--only` with six names, so a step added to this file later runs in
// CI without the workflow being edited to include it. A run that took some of the
// steps says so on its last line rather than reporting the whole gate, because a
// partial run read as the whole one is the failure these flags exist not to
// cause.

import os

const c_source_extensions = ['.c', '.h', '.cc', '.cpp', '.hpp', '.S', '.s']

// The directories that may hold C, as input to the compiler rather than as part
// of it: the corpus under compliance/, one program per fixed bug under
// regression/, and the recorded-output programs under goldens/.
const test_c_directories = ['compliance/', 'regression/', 'goldens/']

// Step is one check of the gate: the name it reports with, the key `--only`
// names it by, and what runs it. The selection is handed to every check because
// the tests step is the one that reads it.
struct Step {
	name  string
	key   string
	check fn (string, Selection) []string @[required]
}

const steps = [
	Step{
		name:  'formatting'
		key:   'format'
		check: check_formatting
	},
	Step{
		name:  'pure V'
		key:   'pure'
		check: check_pure_v
	},
	Step{
		name:  'build'
		key:   'build'
		check: check_build
	},
	Step{
		name:  'prod build'
		key:   'prod'
		check: check_prod
	},
	Step{
		name:  'tests'
		key:   'tests'
		check: check_tests
	},
	Step{
		name:  'documents'
		key:   'docs'
		check: check_documents
	},
	Step{
		name:  'workflows'
		key:   'workflows'
		check: check_workflows
	},
]

// Selection is which steps this run takes and which slice of the test suite it
// runs. The zero value takes every step and the whole suite.
struct Selection {
mut:
	only     []string
	skip     []string
	shard    int
	shard_of int
}

fn (selection Selection) runs(key string) bool {
	if key in selection.skip {
		return false
	}
	if selection.only.len == 0 {
		return true
	}
	return key in selection.only
}

// parse_selection reads the flags and refuses the ones that would let a run mean
// less than it says. An unknown step name is refused rather than ignored, since
// `--only typo` would otherwise run nothing and exit zero.
fn parse_selection() !Selection {
	mut selection := Selection{}
	mut args := os.args[1..].clone()
	mut i := 0
	for i < args.len {
		arg := args[i]
		if arg == '--only' || arg == '--without' {
			if i + 1 >= args.len {
				return error('${arg} needs a list of step names')
			}
			names := step_names(args[i + 1])!
			if arg == '--only' {
				selection.only = names
			} else {
				selection.skip = names
			}
			i += 2
			continue
		}
		if arg.starts_with('--only=') || arg.starts_with('--without=') {
			is_only := arg.starts_with('--only=')
			names := step_names(arg[(if is_only { 7 } else { 10 })..])!
			if is_only {
				selection.only = names
			} else {
				selection.skip = names
			}
			i++
			continue
		}
		if arg == '--shard' {
			if i + 1 >= args.len {
				return error('--shard needs K/N')
			}
			parsed := parse_shard(args[i + 1])!
			selection.shard = parsed[0]
			selection.shard_of = parsed[1]
			i += 2
			continue
		}
		if arg.starts_with('--shard=') {
			parsed := parse_shard(arg[8..])!
			selection.shard = parsed[0]
			selection.shard_of = parsed[1]
			i++
			continue
		}
		return error('unknown argument ${arg}')
	}
	if selection.only.len > 0 && selection.skip.len > 0 {
		return error('--only and --without answer one question the same way; give one of them')
	}
	// A shard is a part of the suite and not a part of the gate: the other six
	// steps are not divisible, and a runner that took one of them would report a
	// gate it half ran.
	if selection.shard_of > 0 && (selection.only.len != 1 || selection.only[0] != 'tests') {
		return error('a shard is part of the tests step, so --shard needs --only tests')
	}
	return selection
}

// step_names reads one flag's comma-separated list and refuses a name the table
// does not have.
fn step_names(text string) ![]string {
	names := text.split(',').map(it.trim_space()).filter(it != '')
	for name in names {
		if name !in steps.map(it.key) {
			return error('${name}: the steps are ${steps.map(it.key).join(', ')}')
		}
	}
	return names
}

fn parse_shard(text string) ![]int {
	parts := text.split('/')
	if parts.len != 2 {
		return error('${text} is not K/N')
	}
	shard := parts[0].int()
	of := parts[1].int()
	if of < 1 || shard < 1 || shard > of {
		return error('${text} names no shard: K is between 1 and N')
	}
	return [shard, of]
}

fn main() {
	root := os.dir(os.dir(@FILE))
	selection := parse_selection() or {
		eprintln('gate: ${err}')
		exit(2)
	}
	println('gate: ${root}')
	if selection.shard_of > 0 {
		// The count is printed so the log of one runner says how much of the
		// suite it took: three numbers that add up to the tree's test files are
		// what reads as "the shards covered the suite".
		count := shard_paths(root, selection.shard, selection.shard_of).len
		println('gate: tests shard ${selection.shard} of ${selection.shard_of}, ${count} files')
	}
	mut failures := []string{}
	mut ran := 0
	for step in steps {
		if !selection.runs(step.key) {
			continue
		}
		report(step.name, step.check(root, selection), mut failures)
		ran++
	}
	if failures.len > 0 {
		eprintln('')
		eprintln('gate: ${failures.len} step(s) failed: ${failures.join(', ')}')
		exit(1)
	}
	println('')
	if ran < steps.len {
		println('gate: ${ran} of ${steps.len} steps, all pass')
		return
	}
	println('gate: everything passes')
}

// report prints one step's verdict and keeps its name for the summary, so a
// failure says which gate closed rather than only what it printed.
fn report(name string, problems []string, mut failures []string) {
	print('  ${name}: ')
	if problems.len == 0 {
		println('ok')
		return
	}
	println('failed')
	for problem in problems {
		eprintln('    ${problem}')
	}
	failures << name
}

// check_formatting asks `v fmt -verify`, the same formatter every contributor
// runs. A gate using a different one would be a second opinion nobody asked for.
fn check_formatting(root string, _ Selection) []string {
	result := run(root, 'v fmt -verify .')
	if result.exit_code == 0 {
		return []
	}
	mut problems := []string{}
	for line in result.output.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.contains('is not formatted') || trimmed.starts_with('diff ') {
			problems << trimmed
		}
	}
	if problems.len == 0 {
		problems << 'v fmt -verify failed: ${result.output.trim_space()}'
	}
	return problems
}

// check_pure_v enforces the first constraint by looking for what breaks it: C
// sources in the tree, and C interop in the compiler's own sources. A test
// directory holds C the compiler is handed rather than C the compiler is built
// from, so a C source there is the directory's purpose and not a break in the
// rule: compliance/ is the corpus, regression/ one program per bug that must
// not come back, goldens/ the programs whose output is compared against a
// recording. Everywhere else a C source is a failure. The interop scan below has
// no such exception for a test directory, because a .v file there is still this
// compiler's source; tools/ and .omh/ are the only places skipped there, since
// the scripts and the agent notes name these patterns on purpose.
fn check_pure_v(root string, _ Selection) []string {
	mut problems := []string{}
	for extension in c_source_extensions {
		for file in os.walk_ext(root, extension) {
			if is_c_input_directory(file, root) {
				continue
			}
			problems << '${file.replace('${root}/', '')}: C source in a tree that is V only'
		}
	}
	interop := ['#include ', '#flag ', 'C.']
	for file in os.walk_ext(root, '.v') {
		if file.contains('/tools/') || file.contains('/.omh/') {
			continue
		}
		relative := file.replace('${root}/', '')
		lines := os.read_lines(file) or { continue }
		for i, line in lines {
			trimmed := line.trim_space()
			if trimmed.starts_with('//') {
				continue
			}
			for pattern in interop {
				if trimmed.contains(pattern) {
					problems << '${relative}:${i + 1}: ${pattern.trim_space()} brings C into the compiler'
				}
			}
		}
	}
	return problems
}

// is_c_input_directory reports whether a path sits under one of the directories
// that hold C as input to the compiler rather than as part of it. The slash is
// part of the prefix, so a file named goldens-old.c at the root is not mistaken
// for one inside goldens/.
fn is_c_input_directory(file string, root string) bool {
	for directory in test_c_directories {
		if file.starts_with('${root}/${directory}') {
			return true
		}
	}
	return false
}

fn check_build(root string, _ Selection) []string {
	binary := os.join_path(os.temp_dir(), 'vcc-gate-${os.getpid()}')
	result := run(root, 'v -o ${os.quoted_path(binary)} .')
	os.rm(binary) or {}
	if result.exit_code != 0 {
		return ['the compiler did not build: ${result.output.trim_space()}']
	}
	return []
}

// check_prod builds the same source the way a release would, because -prod is
// not the plain build with optimizations on: it makes V's warnings into errors,
// so a deprecation the plain build reports and carries on past stops this one.
// That is how the tree stopped building at all once upstream marked `os.system`
// deprecated, which main.v used for the link and for -run.
//
// It is a build and not an artifact: the file is written under the temp
// directory and removed here, so a gate run leaves nothing in the tree.
fn check_prod(root string, _ Selection) []string {
	binary := os.join_path(os.temp_dir(), 'vcc-gate-prod-${os.getpid()}')
	result := run(root, 'v -prod -o ${os.quoted_path(binary)} .')
	os.rm(binary) or {}
	if result.exit_code != 0 {
		return ['the compiler did not build with -prod: ${result.output.trim_space()}']
	}
	return []
}

// shard_paths deals the tree's test files into `of` groups and hands back the
// ones in group `shard`, counting from one. The files are dealt in a snake (1, 2,
// 3, 3, 2, 1) rather than a round robin, because they arrive in directory order
// and a plain round robin leaves each directory's files bunched in the same
// groups; the deal is computed from the walk rather than kept in a table, so a
// test file added anywhere lands in exactly one group without anyone editing the
// gate to say so.
//
// Measured on this tree, 51 test files, the three groups took 165, 236 and 227
// seconds here (16 cores, -nocache) against 627 for the suite in one run. The
// slowest group is what CI waits for, and that spread is the price of not keeping
// a weight per file that would drift the moment a file moved.
fn shard_paths(root string, shard int, of int) []string {
	mut files := []string{}
	for file in os.walk_ext(root, '_test.v') {
		if file.contains('/.omh/') {
			continue
		}
		files << file.replace('${root}/', '')
	}
	files.sort()
	mut out := []string{}
	for i, file in files {
		position := i % (2 * of)
		group := if position < of { position } else { 2 * of - 1 - position }
		if group == shard - 1 {
			out << file
		}
	}
	return out
}

fn check_tests(root string, selection Selection) []string {
	// -nocache, not `v test .`. The module cache makes the suite depend on which C
	// compiler V uses for each file: V's implicit tcc cannot compile its own int128
	// C, so the files that need it fall back to cc, which links the objects the
	// earlier tcc pass cached and fails on a duplicate symbol, and V then retries
	// with its 0.5.2 fallback that rejects this tree's `shared`. A cold cache fails
	// 6 files that way on the runner; the same cache with -nocache passes 51 of 51.
	//
	// A shard names the files it runs rather than the directory the suite lives in,
	// so the three runners between them run every test file once and no file twice.
	paths := if selection.shard_of > 0 {
		shard_paths(root, selection.shard, selection.shard_of)
	} else {
		['.']
	}
	if paths.len == 0 {
		return ['shard ${selection.shard} of ${selection.shard_of} names no test file, so this run would have checked nothing']
	}
	command := 'v -nocache test ${paths.map(os.quoted_path(it)).join(' ')}'
	result := run(root, command)
	if result.exit_code == 0 {
		return []
	}
	// Which file failed is not the whole of what someone needs: V prints the failing
	// function and the assertion under the FAIL line, up to a rule of dashes, and
	// keeping only the FAIL lines made a CI failure say which file failed and never
	// why. Measured on V 0.5.2, the shape is
	//
	//   FAIL    10.405 ms /path/x_test.v
	//   /path/x_test.v:4: fn test_name
	//      > assert 1 == 2
	//        Left value (len: 1): `1`
	//   --------------------------------------------------------------------------
	//
	// and the reason is the lines between the first and the third.
	mut problems := []string{}
	mut under_failure := false
	for line in result.output.split_into_lines() {
		if line.starts_with('FAIL') {
			under_failure = true
			problems << line.trim_space()
			continue
		}
		if under_failure && line.starts_with('---') {
			under_failure = false
			continue
		}
		if line.contains('Summary for all V') {
			under_failure = false
			problems << line.trim_space()
			continue
		}
		if under_failure {
			problems << line.trim_space()
		}
	}
	if problems.len == 0 {
		problems << 'v test failed: ${result.output.trim_space()}'
	}
	return problems
}

// check_workflows reads the CI configuration for the two things the files cannot
// check about themselves: every workflow pins the same V commit, and every action
// is pinned to a version rather than to a branch that moves under it.
//
// Two workflows that pin different V commits would be testing two compilers and
// calling it one CI, and the failure would look like flakiness rather than like
// the disagreement it is.
fn check_workflows(root string, _ Selection) []string {
	mut problems := []string{}
	workflows := os.walk_ext(os.join_path(root, '.github', 'workflows'), '.yml')
	if workflows.len == 0 {
		problems << 'no workflows under .github/workflows'
		return problems
	}
	for file in workflows {
		name := os.file_name(file)
		for line in os.read_lines(file) or { continue } {
			trimmed := line.trim_space()
			if trimmed.starts_with('- uses:') || trimmed.starts_with('uses:') {
				target := value_after(trimmed, 'uses:')
				at := target.last_index('@') or { -1 }
				if at >= 0 && !target[at + 1..].starts_with('v') {
					problems << '${name}: ${target} is not pinned to a version'
				}
			}
		}
	}
	// The V this tree is built with and the snapshot its bootstrap comes from are
	// both pinned, and both have to agree across the workflows: a job built by
	// another compiler answers a question nobody asked.
	problems << check_one_pin(workflows, 'V_COMMIT')
	problems << check_one_pin(workflows, 'VC_COMMIT')
	return problems
}

// check_one_pin reads one commit variable out of every workflow, refuses a value
// that is not a commit hash, and reports the set when the workflows name more than
// one. A workflow with no value at all is a problem too: it would run against
// whatever its steps fetch, which is how a job comes to build with a compiler no
// other job used.
fn check_one_pin(workflows []string, variable string) []string {
	mut problems := []string{}
	mut pinned := map[string]string{}
	for file in workflows {
		name := os.file_name(file)
		mut commit := ''
		for line in os.read_lines(file) or { continue } {
			trimmed := line.trim_space()
			if trimmed.starts_with('${variable}:') {
				commit = value_after(trimmed, ':')
				if commit.len != 40 || !is_hex(commit) {
					problems << '${name}: ${variable} is not a 40-character commit hash'
				}
			}
		}
		if commit == '' {
			problems << '${name}: no ${variable}, so nothing says which commit its jobs build with'
			continue
		}
		pinned[name] = commit
	}
	mut by_commit := map[string][]string{}
	for name, commit in pinned {
		// The append has to go back into the map: appending to a missing map
		// value lands in a temporary and is dropped.
		mut names := by_commit[commit] or { []string{} }
		names << name
		by_commit[commit] = names
	}
	if by_commit.len > 1 {
		mut described := []string{}
		for commit, names in by_commit {
			described << '${commit[..8]} (${names.join(', ')})'
		}
		problems << 'the workflows pin different ${variable} commits: ${described.join('; ')}'
	}
	return problems
}

fn value_after(line string, separator string) string {
	at := line.index(separator) or { return '' }
	return line[at + separator.len..].trim_space()
}

fn is_hex(text string) bool {
	for character in text {
		if !(character >= `0` && character <= `9`) && !(character >= `a` && character <= `f`) {
			return false
		}
	}
	return true
}

// check_documents follows the relative links between the documents. One pointing
// at a file that moved is worse than no link at all.
fn check_documents(root string, _ Selection) []string {
	mut problems := []string{}
	for file in os.walk_ext(root, '.md') {
		if file.contains('/.omh/') {
			continue
		}
		relative := file.replace('${root}/', '')
		lines := os.read_lines(file) or { continue }
		for i, line in lines {
			for target in link_targets(line) {
				if target.starts_with('http') || target.starts_with('mailto')
					|| target.starts_with('#') {
					continue
				}
				path := target.split('#')[0]
				if path == '' {
					continue
				}
				resolved := if path.starts_with('/') {
					os.join_path(root, path[1..])
				} else {
					os.join_path(os.dir(file), path)
				}
				if !os.exists(resolved) {
					problems << '${relative}:${i + 1}: ${target} does not exist'
				}
			}
		}
	}
	return problems
}

// link_targets pulls the targets out of markdown links written on one line, which
// is how every link in these documents is written.
fn link_targets(line string) []string {
	mut out := []string{}
	mut rest := line
	for {
		start := rest.index('](') or { break }
		rest = rest[start + 2..]
		end := rest.index(')') or { break }
		out << rest[..end]
		rest = rest[end..]
	}
	return out
}

fn run(root string, command string) os.Result {
	return os.execute('cd ${os.quoted_path(root)} && ${command} 2>&1')
}
