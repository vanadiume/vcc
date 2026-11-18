module linking

import backend
import backend.os.linux
import image
import linking.output
import os
import vanadiume.vlk.unit as vunit

// The link through the vlk library is checked against the same link performed
// here: the two are handed the same units and the same options, and the bytes
// they write are compared. An image that runs proves the link happened; two
// images that agree prove it is the same link, which is the claim a flag that
// swaps an implementation has to earn.

fn machine() backend.Target {
	return backend.lookup('x86_64-linux') or { panic('the link tests need the x86_64-linux target') }
}

fn link_options(entry string) Options {
	return Options{
		entry:  entry
		target: machine()
	}
}

// exporting builds a unit that defines one function at the start of its text.
fn exporting(name string, code []u8) image.Program {
	mut part := image.Program{}
	part.text = code
	part.defined[name] = true
	part.labels[name] = 0
	return part
}

fn vlk_scratch(name string) string {
	dir := os.join_path(os.temp_dir(), 'vcc_linking_vlk_${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	return os.join_path(dir, name)
}

fn run_image(path string) int {
	os.chmod(path, 0o755) or { panic(err) }
	return os.exec([path]).exit_code
}

// calling_an_import is a unit whose entry zeroes its argument, calls a library
// function and stops if the call returns. The call is the six-byte branch
// through a global offset table slot, which is the instruction this compiler
// writes for an import, and the slot is what the link fills in.
fn calling_an_import() image.Program {
	mut part := image.Program{
		text: [
			u8(0x31),
			u8(0xff), // xor edi, edi
			u8(0xff),
			u8(0x15),
			u8(0),
			u8(0),
			u8(0),
			u8(0), // call [rip + exit]
			u8(0x0f),
			u8(0x0b), // ud2
		]
	}
	part.defined['main'] = true
	part.labels['main'] = 0
	part.imports << 'exit'
	part.fixups << image.Fixup{
		start:  2
		length: 6
		kind:   .call_import
		name:   'exit'
	}
	return part
}

// exiting is a unit that stops the process with a syscall, so a static link of
// it needs no library at all: `mov edi, code`, `mov eax, 60`, `syscall`.
fn exiting(code u8) image.Program {
	mut part := image.Program{
		text: [u8(0xbf), code, u8(0), u8(0), u8(0), u8(0xb8), u8(60), u8(0), u8(0), u8(0), u8(0x0f),
			u8(0x05)]
	}
	part.defined['main'] = true
	part.labels['main'] = 0
	return part
}

// A program that reaches a library: the merge resolves the import to a stub, the
// container writes the stub and the slot, and the image names the loader and the
// C library. Both linkers answer with the same bytes, and the image runs.
fn test_a_program_link_through_the_library_is_the_same_image() {
	units := [calling_an_import()]
	merged := link(units, link_options('main')) or { panic('the in-house link failed: ${err.msg()}') }
	expected := output.image(merged, machine(), linux.LinkKind.program, linux.LinkOptions{}) or {
		panic('the in-house container failed: ${err.msg()}')
	}
	got := link_vlk(units, link_options('main'), linux.LinkKind.program, linux.LinkOptions{}) or {
		panic('the link through the library failed: ${err.msg()}')
	}
	assert got == expected
	path := vlk_scratch('program')
	os.write_file_array(path, got) or { panic(err) }
	assert run_image(path) == 0
}

// A static link resolves everything into the image, so it exercises the layout
// and the container without a loader or a library named in it. The two linkers
// write the same bytes and the program exits with the status its own code asked
// for.
fn test_a_static_link_through_the_library_is_the_same_image() {
	units := [exiting(42)]
	merged := link(units, link_options('main')) or { panic('the in-house link failed: ${err.msg()}') }
	expected := output.image(merged, machine(), linux.LinkKind.static_program, linux.LinkOptions{}) or {
		panic('the in-house container failed: ${err.msg()}')
	}
	got := link_vlk(units, link_options('main'), linux.LinkKind.static_program, linux.LinkOptions{}) or {
		panic('the link through the library failed: ${err.msg()}')
	}
	assert got == expected
	path := vlk_scratch('static')
	os.write_file_array(path, got) or { panic(err) }
	assert run_image(path) == 42
}

// A shared object has no entry point and no loader, and the header says so: the
// link is a different container shape rather than a program with another field.
fn test_a_shared_link_through_the_library_is_the_same_image() {
	units := [exporting('exported', []u8{len: 8, init: u8(0x90)})]
	merged := link(units, link_options('')) or { panic('the in-house link failed: ${err.msg()}') }
	expected := output.image(merged, machine(), linux.LinkKind.shared, linux.LinkOptions{}) or {
		panic('the in-house container failed: ${err.msg()}')
	}
	got := link_vlk(units, link_options(''), linux.LinkKind.shared, linux.LinkOptions{}) or {
		panic('the link through the library failed: ${err.msg()}')
	}
	assert got == expected
}

// The container options are the -Wl, flags, and they reach the library's own
// container: an image asked for eager binding says so in its dynamic table
// whichever linker wrote it.
fn test_the_container_options_reach_the_library() {
	units := [calling_an_import()]
	eager := linux.LinkOptions{
		bind_now: true
	}
	merged := link(units, link_options('main')) or { panic('the in-house link failed: ${err.msg()}') }
	expected := output.image(merged, machine(), linux.LinkKind.program, eager) or {
		panic('the in-house container failed: ${err.msg()}')
	}
	got := link_vlk(units, link_options('main'), linux.LinkKind.program, eager) or {
		panic('the link through the library failed: ${err.msg()}')
	}
	assert got == expected
	// DT_FLAGS carries DF_BIND_NOW, and DT_FLAGS_1 carries DF_1_NOW. The bytes
	// are read back rather than trusted: the tag is the number 30 and the flag
	// is its one bit.
	assert dynamic_flag(got, 30) & 8 != 0
	assert dynamic_flag(got, 0x6ffffffb) & 1 != 0
}

// dynamic_flag reads one dynamic table entry's value out of an image. The table
// is found through the program headers, which is the only place the file says
// where it is; a kind of image that has none answers zero.
fn dynamic_flag(image_bytes []u8, tag u64) u64 {
	phoff := read_u64(image_bytes, 32)
	phentsize := int(read_u16(image_bytes, 54))
	phnum := int(read_u16(image_bytes, 56))
	mut i := 0
	for i < phnum {
		at := int(phoff) + i * phentsize
		if read_u32(image_bytes, at) == 2 {
			offset := read_u64(image_bytes, at + 8)
			filesz := read_u64(image_bytes, at + 32)
			mut j := u64(0)
			for j + 16 <= filesz {
				entry_tag := read_u64(image_bytes, int(offset + j))
				if entry_tag == tag {
					return read_u64(image_bytes, int(offset + j + 8))
				}
				j += 16
			}
		}
		i++
	}
	return 0
}

fn read_u16(bytes []u8, at int) u16 {
	return u16(bytes[at]) | (u16(bytes[at + 1]) << 8)
}

fn read_u32(bytes []u8, at int) u32 {
	mut value := u32(0)
	mut i := 0
	for i < 4 {
		value |= u32(bytes[at + i]) << (8 * i)
		i++
	}
	return value
}

fn read_u64(bytes []u8, at int) u64 {
	mut value := u64(0)
	mut i := 0
	for i < 8 {
		value |= u64(bytes[at + i]) << (8 * i)
		i++
	}
	return value
}

// A target the library describes no instruction set for is refused by name
// rather than linked with empty encoders, which would write an image full of
// zeros for every stub.
fn test_a_machine_the_library_describes_none_for_is_refused() {
	mut other := machine()
	other.elf_machine = 183
	link_vlk([exiting(0)], Options{
		entry:  'main'
		target: other
	}, linux.LinkKind.program, linux.LinkOptions{}) or {
		assert err.msg().contains('vlk describes no link')
		return
	}
	assert false, 'a machine the library writes no image for was accepted'
}

// The unit's fields and the enumerations the conversions name are the same on
// both sides, checked without a list that could go stale: the trees copy each
// other, and a field one side adds is a conversion that stopped carrying it.
fn test_the_two_trees_carry_the_same_unit() {
	mut ours := []string{}
	$for field in image.Program.fields {
		ours << field.name
	}
	mut theirs := []string{}
	$for field in vunit.Program.fields {
		theirs << field.name
	}
	assert ours == theirs
}

// The conversions answer the member with the same name, which is checked name
// for name: an enum value is its position, so a mapping that slid one member
// still compiles and still answers something, just not the thing asked for.
fn test_every_conversion_answers_the_member_of_the_same_name() {
	for kind in [image.FixupKind.call_local, image.FixupKind.call_import, image.FixupKind.take_address,
		image.FixupKind.take_wide_address, image.FixupKind.jump_local, image.FixupKind.branch_zero,
		image.FixupKind.branch_nonzero, image.FixupKind.global_address, image.FixupKind.got_address,
		image.FixupKind.function_address, image.FixupKind.import_address,
		image.FixupKind.float_constant, image.FixupKind.single_constant,
		image.FixupKind.section_address] {
		assert vlk_fixup_kind(kind).str() == kind.str()
	}
	for place in [image.RelocationPlace.text, image.RelocationPlace.read_only,
		image.RelocationPlace.tls, image.RelocationPlace.data] {
		assert vlk_place(place).str() == place.str()
	}
	for kind in [image.RelocationKind.direct, image.RelocationKind.got, image.RelocationKind.absolute,
		image.RelocationKind.tpoff] {
		assert vlk_relocation_kind(kind).str() == kind.str()
	}
	for width in [image.RelocationWidth.narrow, image.RelocationWidth.wide] {
		assert vlk_width(width).str() == width.str()
	}
}
