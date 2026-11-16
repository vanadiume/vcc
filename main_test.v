module main

import os

// write_image writes the image and then decides what to do about the execute
// bit. These tests drive the three kinds of output path that decision turns on:
// a fresh regular file, an existing one, and the device node `-o /dev/null`
// names. The last is the regression: the write succeeds, and a chmod on a device
// node is neither needed nor permitted for an unprivileged user.
//
// The fourth test covers the failure path: when the write itself fails, that is
// the error the caller sees, not a chmod attempted on a path nothing created.

fn image_scratch(name string) string {
	return os.join_path(os.temp_dir(), 'vcc_image_test_${os.getpid()}_${name}')
}

fn test_write_image_makes_a_fresh_file_executable() {
	path := image_scratch('fresh')
	os.rm(path) or {}
	defer {
		os.rm(path) or {}
	}
	bytes := [u8(0x7f), `E`, `L`, `F`]
	write_image(path, bytes) or { panic(err) }
	info := os.stat(path) or { panic(err) }
	assert (info.mode & os.s_ifmt) == os.s_ifreg
	assert info.mode & 0o777 == 0o755
	assert (os.read_bytes(path) or { panic(err) }) == bytes
}

// gcc leaves an existing regular file at 0755 too: it creates the output afresh
// rather than keeping the mode a previous file happened to have.
fn test_write_image_gives_an_existing_regular_file_the_execute_bit() {
	path := image_scratch('existing')
	defer {
		os.rm(path) or {}
	}
	os.write_file(path, 'stale') or { panic(err) }
	os.chmod(path, 0o600) or { panic(err) }
	write_image(path, [u8(1), 2, 3]) or { panic(err) }
	info := os.stat(path) or { panic(err) }
	assert info.mode & 0o777 == 0o755
}

fn test_write_image_leaves_a_device_node_alone() {
	if !os.exists('/dev/null') {
		return
	}
	if os.inode('/dev/null').typ != .character_device {
		return
	}
	write_image('/dev/null', [u8(0x7f), `E`, `L`, `F`]) or { panic(err) }
}

fn test_write_image_failure_is_the_write_error() {
	if os.getuid() == 0 {
		// Root can write into a directory whose mode denies everyone else, so
		// there is no failure to report when this test runs as root.
		return
	}
	dir := image_scratch('read_only_dir')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.chmod(dir, 0o755) or {}
		os.rmdir_all(dir) or {}
	}
	os.chmod(dir, 0o555) or { panic(err) }
	mut message := ''
	write_image(os.join_path(dir, 'image'), [u8(1), 2, 3]) or { message = err.msg() }
	assert message != '', 'writing into a read-only directory must fail'
	assert !message.contains('chmod'), 'the failure must be the write: ${message}'
}
