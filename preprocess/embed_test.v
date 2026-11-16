module preprocess

import os

// The embed tests write a payload file, because the directive's whole job is
// the bytes of one. Every test that names a payload names it from a source
// file somewhere other than the working directory, so a name resolved against
// the directory the test was started in would be found, or missed, by accident
// rather than by the rule.

// The include fixtures in preprocess_test.v are that file's own: V builds each
// _test.v as a program of its own, so a test file cannot call another one's
// helpers. This is the same small tree, under a name of its own.
fn embed_fixture_directory() string {
	dir := os.join_path(os.temp_dir(), 'vcc-embed-test-${os.getpid()}')
	os.mkdir_all(dir) or {}
	return dir
}

fn embed_result(source string, dir string) Result {
	return preprocess(source, os.join_path(dir, 'main.c'), Options{})
}

fn test_embed_is_the_bytes_of_a_file_as_numbers() {
	dir := embed_fixture_directory()
	os.write_file(os.join_path(dir, 'bytes.bin'), '\x01\x02\x03\x04') or {}
	result := embed_result('#embed "bytes.bin"\n', dir)
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['1', ',', '2', ',', '3', ',', '4']
	// The numbers stand where the directive stood: the line and the file that
	// wrote it are where a complaint about them belongs.
	assert result.tokens[0].line == 1
	assert result.tokens[0].file == os.join_path(dir, 'main.c')
}

fn test_embed_resolves_its_name_beside_the_file_that_wrote_it() {
	dir := embed_fixture_directory()
	nested := os.join_path(dir, 'nested')
	resources := os.join_path(nested, 'resources')
	os.mkdir_all(resources) or {}
	os.write_file(os.join_path(resources, 'bytes.bin'), '\x07\x08') or {}
	result := preprocess('#embed "resources/bytes.bin"\n', os.join_path(nested, 'main.c'), Options{})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['7', ',', '8']
}

fn test_embed_limit_stops_after_that_many_bytes() {
	// The limit is an integer constant expression, so a macro that stands for
	// one counts, and a limit past the end of the file is the whole file.
	dir := embed_fixture_directory()
	os.write_file(os.join_path(dir, 'four.bin'), '\x01\x02\x03\x04') or {}
	sources := ['#define N 2\n#embed "four.bin" limit(N)\n', '#embed "four.bin" limit(100)\n',
		'#embed "four.bin" limit(2 + 1)\n']
	wants := [['1', ',', '2'], ['1', ',', '2', ',', '3', ',', '4'], ['1', ',', '2', ',', '3']]
	for i in 0 .. sources.len {
		result := embed_result(sources[i], dir)
		assert result.diagnostics.len == 0
		assert result.tokens.map(it.text) == wants[i]
	}
}

fn test_embed_prefix_and_suffix_frame_the_numbers() {
	dir := embed_fixture_directory()
	os.write_file(os.join_path(dir, 'four.bin'), '\x01\x02\x03\x04') or {}
	result := embed_result('#embed "four.bin" prefix(0xFF, ) suffix(, 0xEE)\n', dir)
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['0xFF', ',', '1', ',', '2', ',', '3', ',', '4', ',',
		'0xEE']
}

fn test_embed_if_empty_is_what_a_file_with_no_bytes_becomes() {
	// One empty file and one emptied by its limit, because both leave the
	// directive with nothing to list.
	dir := embed_fixture_directory()
	os.write_file(os.join_path(dir, 'none.bin'), '') or {}
	os.write_file(os.join_path(dir, 'four.bin'), '\x01\x02\x03\x04') or {}
	empty := embed_result('#embed "none.bin" if_empty(0xAB, 0xCD)\n', dir)
	assert empty.diagnostics.len == 0
	assert empty.tokens.map(it.text) == ['0xAB', ',', '0xCD']
	limited := embed_result('#embed "four.bin" limit(0) if_empty(7)\n', dir)
	assert limited.diagnostics.len == 0
	assert limited.tokens.map(it.text) == ['7']
}

fn test_embed_leaves_the_prefix_and_suffix_out_of_an_empty_list() {
	// A prefix and a suffix belong to the list they frame; with no list there
	// is nothing for them to frame, and the if_empty content is the whole of
	// what the directive stands for. Measured on gcc 16.2.1.
	dir := embed_fixture_directory()
	os.write_file(os.join_path(dir, 'four.bin'), '\x01\x02\x03\x04') or {}
	result := embed_result('#embed "four.bin" limit(0) prefix(9, 9) suffix(8, 8) if_empty(7)\n', dir)
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['7']
}

fn test_embed_of_an_empty_file_with_no_if_empty_writes_no_tokens() {
	// gcc 16.2.1 and clang 23.1.4 both compile this and leave the initializer
	// empty, so an empty file is not a diagnostic here either.
	dir := embed_fixture_directory()
	os.write_file(os.join_path(dir, 'none.bin'), '') or {}
	result := embed_result('#embed "none.bin"\n', dir)
	assert result.diagnostics.len == 0
	assert result.tokens.len == 0
}

fn test_an_embed_of_a_file_that_is_not_there_is_diagnosed_by_name() {
	dir := embed_fixture_directory()
	result := embed_result('#embed "no-such-payload.bin"\n', dir)
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('no-such-payload.bin')
	assert result.diagnostics[0].msg.contains('looked in')
	assert result.tokens.len == 0
}

fn test_an_embed_parameter_the_standard_does_not_have_is_diagnosed() {
	dir := embed_fixture_directory()
	os.write_file(os.join_path(dir, 'four.bin'), '\x01\x02\x03\x04') or {}
	result := embed_result('#embed "four.bin" offset(1)\n', dir)
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('offset')
}

fn test_a_second_limit_parameter_is_diagnosed() {
	dir := embed_fixture_directory()
	os.write_file(os.join_path(dir, 'four.bin'), '\x01\x02\x03\x04') or {}
	result := embed_result('#embed "four.bin" limit(1) limit(2)\n', dir)
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('two limit parameters')
}

fn test_an_embed_limit_that_is_negative_is_diagnosed() {
	dir := embed_fixture_directory()
	os.write_file(os.join_path(dir, 'four.bin'), '\x01\x02\x03\x04') or {}
	result := embed_result('#embed "four.bin" limit(-1)\n', dir)
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('negative')
}

fn test_an_embed_inside_a_branch_that_was_not_taken_reads_nothing() {
	// A payload that is not there is not a mistake when the line is not read.
	result := embed_result('#if 0\n#embed "no-such-payload.bin"\n#endif\nint x;\n', embed_fixture_directory())
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['int', 'x', ';']
}

fn test_embed_is_a_c23_construct_a_mode_before_c23_is_told_about() {
	// Measured on gcc 16.2.1: every mode before C23 compiles the directive and
	// refuses it under -pedantic-errors, gnu17 included. The reader asks the
	// dialect table for that answer, and the line is compiled either way.
	dir := embed_fixture_directory()
	os.write_file(os.join_path(dir, 'four.bin'), '\x01\x02\x03\x04') or {}
	source := '#embed "four.bin"\n'
	main_path := os.join_path(dir, 'main.c')
	c99 := preprocess(source, main_path, Options{
		dialect: .c99
	})
	assert c99.diagnostics.len == 1
	assert c99.diagnostics[0].msg == 'ISO C99 forbids the #embed directive'
	assert c99.tokens.len == 7
	c23 := preprocess(source, main_path, Options{
		dialect: .c23
	})
	assert c23.diagnostics.len == 0
	assert c23.tokens.len == 7
}
