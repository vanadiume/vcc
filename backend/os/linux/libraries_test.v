module linux

import backend
import os

// The library reader. A `-l` name becomes a file, and the name the image
// carries is read out of that file rather than guessed from the flag, so these
// tests are about the shapes that file comes in on this machine.
//
// They followed the reader out of the emitter when it moved here. The subject is
// this system's libraries and this system's linker scripts, which is what makes
// them tests of the system rather than of the emitter that happens to ask.

// A directory of its own per test, so two of them running at once do not write
// over each other's libraries.
fn library_dir(name string) string {
	dir := os.join_path(os.temp_dir(), 'vcc_libraries_${os.getpid()}_${name}')
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

// `libm.so` on this machine is a GNU ld script rather than an object file, and
// what the script names is the library it stands for. The path inside the script
// is the one this machine keeps the library in, found the way the search finds
// libraries: written out as `/usr/lib/libm.so.6` the fixture would assert the
// layout of the machine it was written on, and the same library lives in
// `/usr/lib/x86_64-linux-gnu` on a Debian-derived system.
fn test_a_library_script_names_the_library_behind_it() {
	dir := library_dir('script')
	defer {
		os.rmdir_all(dir) or {}
	}
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	target := find_system_library(system_dirs, 'libm.so.6') or {
		panic('this test needs a libm.so.6 on the machine it runs on')
	}
	os.write_file(os.join_path(dir, 'libprobe.so'),
		'/* GNU ld script\nOUTPUT_FORMAT(elf64-x86-64)\nGROUP ( ${target} ) */\n') or {
		panic(err)
	}
	resolved := resolve_libraries(['probe'], [dir], false) or { panic(err) }
	assert resolved == ['libm.so.6']
}

// An archive is a library a link reads members out of, not one the loader maps:
// a `-l` name that resolves to one comes back marked as an archive with its own
// file name, it is left out of the names the image carries, and
// archive_libraries answers the file so the link can read its members.
fn test_an_archive_resolves_and_is_left_out_of_the_loader_names() {
	dir := library_dir('archive')
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'libprobe.a')
	os.write_file(path, '!<arch>\n') or { panic(err) }
	resolved := resolve_library('probe', [dir], false) or { panic(err) }
	assert resolved.archive
	assert resolved.path == path
	assert resolved.soname == 'libprobe.a'
	// A static archive is not a file the loader maps, so the image carries no
	// name for it.
	assert resolve_libraries(['probe'], [dir], false) or { panic(err) } == []string{}
	archives := archive_libraries(['probe'], [dir], false) or { panic(err) }
	assert archives.len == 1
	assert archives[0].path == path
	assert archives[0].soname == 'libprobe.a'
	assert archives[0].archive
	// A path is not repeated when a name resolves to the same archive twice.
	assert archive_libraries(['probe', 'probe'], [dir], false) or { panic(err) }.len == 1
}

// A shared library and an archive under the same stem: find_library prefers the
// shared one, and it is the one the image carries a name for. The archive beside
// it is still reachable by its own name and is what `-lprobe` does not resolve
// to.
fn test_a_shared_library_beside_an_archive_is_the_one_the_search_finds() {
	dir := library_dir('prefer_shared')
	defer {
		os.rmdir_all(dir) or {}
	}
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	shared := find_system_library(system_dirs, 'libm.so.6') or { return }
	copy_bytes(shared, os.join_path(dir, 'libprobe.so'))
	os.write_file(os.join_path(dir, 'libprobe.a'), '!<arch>\n') or { panic(err) }
	found := resolve_library('probe', [dir], false) or { panic(err) }
	assert !found.archive
	assert found.soname == 'libm.so.6'
	assert resolve_libraries(['probe'], [dir], false) or { panic(err) } == ['libm.so.6']
	// The name resolved to the shared library, so no archive is reported for it.
	assert archive_libraries(['probe'], [dir], false) or { panic(err) }.len == 0
	// The archive is reachable by the `-l:` form, which names the file itself.
	named := resolve_library(':libprobe.a', [dir], false) or { panic(err) }
	assert named.archive
	assert named.path == os.join_path(dir, 'libprobe.a')
	assert named.soname == 'libprobe.a'
}

// The rule ld uses, and the one this search got wrong: the -L directories are
// asked in order, and the first one that holds the library in any form answers.
// A directory holding only the archive is therefore what `-L first -L second`
// links, even though the second holds a shared object, where a search that
// looked for every shared object before any archive took the second directory's
// file. The other order has the shared object first and names it in the image.
fn test_the_first_directory_that_holds_the_library_answers() {
	first := library_dir('order_archive_first')
	second := library_dir('order_shared_second')
	defer {
		os.rmdir_all(first) or {}
		os.rmdir_all(second) or {}
	}
	archive := os.join_path(first, 'libprobe.a')
	os.write_file(archive, '!<arch>\n') or { panic(err) }
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	shared := find_system_library(system_dirs, 'libm.so.6') or { return }
	copy_bytes(shared, os.join_path(second, 'libprobe.so'))
	assert resolve_libraries(['probe'], [first, second], false) or { panic(err) } == []string{}
	archives := archive_libraries(['probe'], [first, second], false) or { panic(err) }
	assert archives.len == 1
	assert archives[0].path == archive
	assert resolve_libraries(['probe'], [second, first], false) or { panic(err) } == ['libm.so.6']
	assert archive_libraries(['probe'], [second, first], false) or { panic(err) }.len == 0
}

// A static link resolves every library into the file it writes, so it takes the
// archive and never the shared object: the directory holding only the shared
// object is passed over and the next one is asked. This is the pair that made a
// static link report the program's own call unresolved, because the shared
// object it picked was left to a loader the image does not name.
fn test_a_static_link_takes_the_archive_from_a_later_directory() {
	shared_dir := library_dir('static_shared_first')
	archive_dir := library_dir('static_archive_second')
	defer {
		os.rmdir_all(shared_dir) or {}
		os.rmdir_all(archive_dir) or {}
	}
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	shared := find_system_library(system_dirs, 'libm.so.6') or { return }
	copy_bytes(shared, os.join_path(shared_dir, 'libprobe.so'))
	archive := os.join_path(archive_dir, 'libprobe.a')
	os.write_file(archive, '!<arch>\n') or { panic(err) }
	assert resolve_libraries(['probe'], [shared_dir, archive_dir], true) or { panic(err) } == []string{}
	archives := archive_libraries(['probe'], [shared_dir, archive_dir], true) or { panic(err) }
	assert archives.len == 1
	assert archives[0].path == archive
}

// Within one directory the preference is still the shared object's, except for a
// static link, where the archive beside it is the one that answers.
fn test_a_static_link_prefers_the_archive_beside_the_shared_object() {
	dir := library_dir('static_prefer_archive')
	defer {
		os.rmdir_all(dir) or {}
	}
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	shared := find_system_library(system_dirs, 'libm.so.6') or { return }
	copy_bytes(shared, os.join_path(dir, 'libprobe.so'))
	archive := os.join_path(dir, 'libprobe.a')
	os.write_file(archive, '!<arch>\n') or { panic(err) }
	found := resolve_library('probe', [dir], true) or { panic(err) }
	assert found.archive
	assert found.path == archive
	assert found.soname == 'libprobe.a'
}

// A static link that finds no archive anywhere does not fall back to the shared
// object: ld with -static never opens one, and the name is what cannot be found
// rather than a symbol the image cannot resolve.
fn test_a_static_link_does_not_take_a_shared_object() {
	dir := library_dir('static_shared_only')
	defer {
		os.rmdir_all(dir) or {}
	}
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	shared := find_system_library(system_dirs, 'libm.so.6') or { return }
	copy_bytes(shared, os.join_path(dir, 'libprobe.so'))
	if resolved := resolve_library('probe', [dir], true) {
		assert false, 'a static link has nowhere to put ${resolved.path}'
	} else {
		assert err.msg().contains('-lprobe')
		assert err.msg().contains(dir)
	}
}

// `-l:filename` names the file itself, with no `lib` prefix and no `.so`/`.a`
// suffix searched for, and the name is looked for in the -L directories in
// order. A static link reads a literal archive the same way and refuses a
// literal shared object by the name that asked for it.
fn test_a_literal_file_name_is_searched_as_written() {
	first := library_dir('literal_first')
	second := library_dir('literal_second')
	defer {
		os.rmdir_all(first) or {}
		os.rmdir_all(second) or {}
	}
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	shared := find_system_library(system_dirs, 'libm.so.6') or { return }
	copy_bytes(shared, os.join_path(first, 'libprobe.so'))
	archive := os.join_path(second, 'libprobe.a')
	os.write_file(archive, '!<arch>\n') or { panic(err) }
	named := resolve_library(':libprobe.a', [first, second], false) or { panic(err) }
	assert named.archive
	assert named.path == archive
	assert (resolve_library(':libprobe.a', [first, second], true) or { panic(err) }).path == archive
	if _ := resolve_library(':libprobe.so', [first, second], true) {
		assert false, 'a static link has nowhere to put a shared object'
	} else {
		assert err.msg().contains('-l:libprobe.so')
		assert err.msg().contains('not an archive')
	}
}

// The per-directory rule holds for a name with no unversioned file too: the
// first directory holding any version answers, and the versions are compared
// with the ones beside them rather than with every version on the search. The
// first directory's `.2` is what the first order takes even though the second
// holds a `.10`.
fn test_the_first_directory_answers_for_a_versioned_library_too() {
	first := library_dir('versioned_order_first')
	second := library_dir('versioned_order_second')
	defer {
		os.rmdir_all(first) or {}
		os.rmdir_all(second) or {}
	}
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	older := find_system_library(system_dirs, 'libm.so.6') or { return }
	newer := find_system_library(system_dirs, 'libdl.so.2') or { return }
	copy_bytes(older, os.join_path(first, 'libprobe.so.2'))
	copy_bytes(newer, os.join_path(second, 'libprobe.so.10'))
	assert resolve_libraries(['probe'], [first, second], false) or { panic(err) } == ['libm.so.6']
	assert resolve_libraries(['probe'], [second, first], false) or { panic(err) } == ['libdl.so.2']
}

// A GNU ld script that names an archive beside its shared object brings that archive
// to the link. This is the shape /usr/lib/libc.so has, and libc_nonshared.a is where
// glibc keeps the functions that cannot live in a shared object at all, `atexit`
// among them. Reading only the first name a script gives leaves those undefined.
fn test_a_script_that_names_an_archive_brings_it_to_the_link() {
	dir := library_dir('script_archive')
	defer {
		os.rmdir_all(dir) or {}
	}
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	shared := find_system_library(system_dirs, 'libm.so.6') or { return }
	copy_bytes(shared, os.join_path(dir, 'libprobe.so.6'))
	os.write_file(os.join_path(dir, 'libprobe_nonshared.a'), '!<arch>\n') or { panic(err) }
	os.write_file(os.join_path(dir, 'libprobe.so'), '/* GNU ld script\nGROUP ( libprobe.so.6  libprobe_nonshared.a  AS_NEEDED ( libprobe.so.6 ) ) */\n') or {
		panic(err)
	}
	found := resolve_library('probe', [dir], false) or { panic(err) }
	assert !found.archive
	assert found.soname == 'libm.so.6'
	archives := archive_libraries(['probe'], [dir], false) or { panic(err) }
	assert archives.len == 1
	assert archives[0].path == os.join_path(dir, 'libprobe_nonshared.a')
	assert archives[0].soname == 'libprobe_nonshared.a'
	assert archives[0].archive
}

// A name that resolved to nothing is the search's own refusal, and
// archive_libraries propagates it rather than answering an empty list.
fn test_archive_libraries_propagates_a_name_the_search_does_not_have() {
	dir := library_dir('archive_missing')
	defer {
		os.rmdir_all(dir) or {}
	}
	if _ := archive_libraries(['nosuch'], [dir], false) {
		assert false, 'a name the search does not have has to be an error'
	} else {
		assert err.msg().contains('nosuch')
		assert err.msg().contains(dir)
	}
}

// The import check reads every resolved library's dynamic symbol table, and an
// archive is not an object it can read. It has to contribute no symbols rather
// than crash or error, which it does by answering none for a file that is not
// an ELF object, the same answer it gives a library it cannot read.
fn test_an_archive_without_an_object_beside_it_does_not_break_the_import_check() {
	dir := library_dir('archive_imports')
	defer {
		os.rmdir_all(dir) or {}
	}
	os.write_file(os.join_path(dir, 'libprobe.a'), '!<arch>\n') or { panic(err) }
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	// `exit` is in the C library the check always reads, so the only question
	// here is whether the archive beside the -L directory stops the check.
	assert unresolved_imports(['exit'], ['probe'], search_dirs([dir], system_dirs), true) == []string{}
}

// A library with no unversioned name is still found: glibc 2.44 ships
// `libdl.so.2` and no `libdl.so`, so a search that stopped at the unversioned
// name would fail `-ldl` on V's own command line. The version is compared as
// numbers, because sorting the file names as text puts `.10` before `.2`.
fn test_a_versioned_library_is_found_and_the_newest_version_wins() {
	dir := library_dir('versioned')
	defer {
		os.rmdir_all(dir) or {}
	}
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	older := find_system_library(system_dirs, 'libm.so.6') or { return }
	newer := find_system_library(system_dirs, 'libdl.so.2') or { return }
	copy_bytes(older, os.join_path(dir, 'libprobe.so.2'))
	copy_bytes(newer, os.join_path(dir, 'libprobe.so.10'))
	resolved := resolve_libraries(['probe'], [dir], false) or { panic(err) }
	assert resolved == ['libdl.so.2']
}

fn find_system_library(dirs []string, name string) ?string {
	for dir in dirs {
		path := os.join_path(dir, name)
		if os.is_file(path) {
			return path
		}
	}
	return none
}

// The symbol reader: a library the search finds answers the names it defines.
// That is what lets a caller tell an import that will resolve when the loader
// runs from one that will not.
fn test_a_library_answers_the_symbols_it_defines() {
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	libc := find_system_library(system_dirs, 'libc.so.6') or { return }
	symbols := library_symbols(libc) or { panic('the C library should read as one') }
	assert 'exit' in symbols
	assert 'printf' in symbols
	assert 'nowhere' !in symbols
}

// `libm.so` on this machine is a GNU ld script, so the reader has to follow it
// to `libm.so.6` to find the names it defines. fetestexcept is in libm and not
// in the C library, so it is the name that proves the script was followed.
fn test_a_library_behind_a_script_answers_its_symbols() {
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	script := find_system_library(system_dirs, 'libm.so') or { return }
	symbols := library_symbols(script) or { panic('a library script should name a library that reads') }
	assert 'fetestexcept' in symbols
	assert 'sqrt' in symbols
	assert 'nowhere' !in symbols
}

// The question the caller asks: which imports no library the image names
// provides. A symbol in the C library resolves, a symbol only in libm resolves
// when -lm is on the command line, and a name in neither is reported.
fn test_an_import_no_library_provides_is_reported() {
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	assert unresolved_imports(['exit', 'nowhere'], [], system_dirs, true) == ['nowhere']
	if find_system_library(system_dirs, 'libm.so') != none {
		assert unresolved_imports(['fetestexcept'], ['m'], system_dirs, true).len == 0
		assert unresolved_imports(['fetestexcept'], [], system_dirs, true) == ['fetestexcept']
	}
}

// An image that names no C library cannot be answered by one. The name the C
// library defines is reported when the base library is not one of the image's,
// and naming the C library with -l puts it back: that is the pair a run with no
// default libraries turns on, where the command line answers for the names and a
// name it does not answer is still unresolved.
fn test_the_c_library_answers_nothing_when_the_image_names_none() {
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	assert unresolved_imports(['exit'], [], system_dirs, false) == ['exit']
	assert unresolved_imports(['exit'], ['c'], system_dirs, false) == []string{}
	// A name libc does not define is reported either way.
	assert unresolved_imports(['nowhere'], [], system_dirs, false) == ['nowhere']
}

fn copy_bytes(from string, to string) {
	bytes := os.read_bytes(from) or { panic(err) }
	os.write_file_array(to, bytes) or { panic(err) }
}
