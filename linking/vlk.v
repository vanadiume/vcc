module linking

import backend
import backend.os.linux
import image
import vanadiume.vlk
import vanadiume.vlk.library as vlibrary
import vanadiume.vlk.output as voutput
import vanadiume.vlk.target as vtarget
import vanadiume.vlk.unit as vunit

// The same link, performed by the vlk library instead of this module.
//
// `link` above merges the units into one program and hands it to the container.
// `link_vlk` does neither: it converts the units and the target into the
// library's own values, gives it the options the command line decided, and gets
// the image's bytes back. The merge, the library check and the container are
// then the library's code, which is the point of the flag that reaches here.
//
// The conversion exists because the two trees hold the same shapes as different
// types. `image.Program` and `vlk.unit.Program` were one file before the split,
// so every field is written out below, and a field either side adds later breaks
// this file instead of arriving as its zero value on the other.

// link_vlk is one link through the library: the units and the command line in,
// the bytes of the image out. No file is written here, because the caller owns
// the output path and the execute bit that goes with it.
pub fn link_vlk(units []image.Program, options Options, kind linux.LinkKind, container linux.LinkOptions) ![]u8 {
	mut parts := []vunit.Program{cap: units.len}
	for part in units {
		parts << vlk_unit(part)
	}
	mut shared := []vlibrary.Library{cap: options.shared_libraries.len}
	for known in options.shared_libraries {
		shared << vlibrary.Library{
			path:    known.path
			soname:  known.soname
			archive: known.archive
		}
	}
	return vlk.link(parts, vlk.Options{
		entry:                options.entry
		target:               vlk_target(options.target)!
		libraries:            options.libraries
		library_dirs:         options.library_dirs
		shared_libraries:     shared
		no_default_libraries: options.no_default_libraries
		kind:                 vlk_kind(kind)
		container:            voutput.Options{
			execstack:   container.execstack
			noexecstack: container.noexecstack
			bind_now:    container.bind_now
			relro:       container.relro
			soname:      container.soname
		}
	})
}

// vlk_target is this compiler's target as the library describes one. The
// machine's own tables, its registers and the instructions a container writes,
// come from the library, because they are the instruction set its container
// writes stubs with. The system facts come from this compiler, so -target, a
// loader the command line named and a freestanding build all reach the library
// as the caller wrote them. A machine the library writes no image for is refused
// by name rather than linked with empty encoders.
fn vlk_target(machine backend.Target) !vtarget.Target {
	host := vtarget.host() or { return error('vlk describes no target for the machine it runs on') }
	if machine.elf_machine != host.elf_machine {
		return error('vlk describes no link for ${machine.name}: it writes images for ${host.name}')
	}
	return vtarget.Target{
		name:                       machine.name
		word_size:                  machine.word_size
		elf_machine:                machine.elf_machine
		page_size:                  machine.page_size
		load_base:                  machine.load_base
		interpreter:                machine.interpreter
		base_library:               machine.base_library_name
		library_dirs:               machine.library_dirs
		registers:                  host.registers
		float_registers:            host.float_registers
		relocation_call:            machine.relocation_call
		relocation_pc_relative:     machine.relocation_pc_relative
		relocation_got_pc_relative: machine.relocation_got_pc_relative
		encoders:                   host.encoders
	}
}

// vlk_kind is which of the three containers the command line asked for. The
// names are the same three in both trees, and the conversion is written out so a
// kind one side adds later is a file that does not compile rather than an image
// written as a program.
fn vlk_kind(kind linux.LinkKind) voutput.Kind {
	match kind {
		.program { return voutput.Kind.program }
		.static_program { return voutput.Kind.static_program }
		.shared { return voutput.Kind.shared }
	}
}

// vlk_unit is one translation unit in the library's shape. Every field travels,
// including the ones this compiler's own emitter leaves zero: a unit read back
// from a relocatable object carries relocations, thread-local storage and
// constructor tables, and a link through the library has to see them.
fn vlk_unit(part image.Program) vunit.Program {
	mut fixups := []vunit.Fixup{cap: part.fixups.len}
	for fixup in part.fixups {
		fixups << vlk_fixup(fixup)
	}
	mut data_fixups := []vunit.DataFixup{cap: part.data_fixups.len}
	for fixup in part.data_fixups {
		data_fixups << vlk_data_fixup(fixup)
	}
	mut relocations := []vunit.Relocation{cap: part.relocations.len}
	for relocation in part.relocations {
		relocations << vlk_relocation(relocation)
	}
	mut function_runs := []vunit.CodeRun{cap: part.function_runs.len}
	for run in part.function_runs {
		function_runs << vlk_run(run)
	}
	return vunit.Program{
		text:                 part.text
		executable_stack:     part.executable_stack
		fixups:               fixups
		data_fixups:          data_fixups
		relocations:          relocations
		labels:               part.labels
		defined:              part.defined
		function_runs:        function_runs
		imports:              part.imports
		object_imports:       part.object_imports
		libraries:            part.libraries
		no_default_libraries: part.no_default_libraries
		string_blob:          part.string_blob
		strings:              part.strings
		wide_strings:         part.wide_strings
		doubles:              part.doubles
		globals_blob:         part.globals_blob
		globals:              vlk_slots(part.globals)
		read_only_globals:    vlk_slots(part.read_only_globals)
		globals_alignment:    part.globals_alignment
		init_run:             vlk_run(part.init_run)
		fini_run:             vlk_run(part.fini_run)
		stub:                 part.stub
		eh_frame_run:         vlk_run(part.eh_frame_run)
		entry_place:          part.entry_place
		read_only_alignment:  part.read_only_alignment
		copy_objects:         part.copy_objects
		weak:                 part.weak
		hidden:               part.hidden
		weak_imports:         part.weak_imports
		tls_slots:            part.tls_slots
		internal:             part.internal
		plts:                 part.plts
		bound:                vlk_bound(part.bound)
		tls_blob:             part.tls_blob
		tls_size:             part.tls_size
		tls_alignment:        part.tls_alignment
		tls_labels:           part.tls_labels
		init_array:           vlk_table(part.init_array)
		fini_array:           vlk_table(part.fini_array)
		ifuncs:               part.ifuncs
	}
}

fn vlk_fixup(fixup image.Fixup) vunit.Fixup {
	return vunit.Fixup{
		start:    fixup.start
		length:   fixup.length
		kind:     vlk_fixup_kind(fixup.kind)
		name:     fixup.name
		register: fixup.register
	}
}

fn vlk_data_fixup(fixup image.DataFixup) vunit.DataFixup {
	return vunit.DataFixup{
		offset: fixup.offset
		kind:   vlk_fixup_kind(fixup.kind)
		name:   fixup.name
		addend: fixup.addend
	}
}

fn vlk_relocation(relocation image.Relocation) vunit.Relocation {
	return vunit.Relocation{
		offset: relocation.offset
		place:  vlk_place(relocation.place)
		kind:   vlk_relocation_kind(relocation.kind)
		name:   relocation.name
		addend: relocation.addend
		width:  vlk_width(relocation.width)
	}
}

fn vlk_run(run image.CodeRun) vunit.CodeRun {
	return vunit.CodeRun{
		base:      run.base
		len:       run.len
		alignment: run.alignment
	}
}

fn vlk_slots(slots map[string]image.GlobalSlot) map[string]vunit.GlobalSlot {
	mut out := map[string]vunit.GlobalSlot{}
	for name, slot in slots {
		out[name] = vunit.GlobalSlot{
			offset:   slot.offset
			width:    slot.width
			count:    slot.count
			object:   slot.object
			floating: slot.floating
			single:   slot.single
			unsigned: slot.unsigned
		}
	}
	return out
}

fn vlk_bound(bound map[string]image.Definition) map[string]vunit.Definition {
	mut out := map[string]vunit.Definition{}
	for name, definition in bound {
		out[name] = vunit.Definition{
			offset:     definition.offset
			function:   definition.function
			tls:        definition.tls
			image_base: definition.image_base
		}
	}
	return out
}

fn vlk_table(table image.ConstructorTable) vunit.ConstructorTable {
	return vunit.ConstructorTable{
		offset: table.offset
		count:  table.count
	}
}

// The converters below are written out one member at a time. A cast would be
// shorter and would be wrong the day one side inserts a member: an enum value is
// its position, so a cast answers the member next door without a word. V refuses
// a module-qualified value as a match key across modules, so the keys are the
// shorthand and the answers name the library's member in full.

fn vlk_fixup_kind(kind image.FixupKind) vunit.FixupKind {
	match kind {
		.call_local { return vunit.FixupKind.call_local }
		.call_import { return vunit.FixupKind.call_import }
		.take_address { return vunit.FixupKind.take_address }
		.take_wide_address { return vunit.FixupKind.take_wide_address }
		.jump_local { return vunit.FixupKind.jump_local }
		.branch_zero { return vunit.FixupKind.branch_zero }
		.branch_nonzero { return vunit.FixupKind.branch_nonzero }
		.global_address { return vunit.FixupKind.global_address }
		.got_address { return vunit.FixupKind.got_address }
		.function_address { return vunit.FixupKind.function_address }
		.import_address { return vunit.FixupKind.import_address }
		.float_constant { return vunit.FixupKind.float_constant }
		.single_constant { return vunit.FixupKind.single_constant }
		.section_address { return vunit.FixupKind.section_address }
	}
}

fn vlk_place(place image.RelocationPlace) vunit.RelocationPlace {
	match place {
		.text { return vunit.RelocationPlace.text }
		.read_only { return vunit.RelocationPlace.read_only }
		.tls { return vunit.RelocationPlace.tls }
		.data { return vunit.RelocationPlace.data }
	}
}

fn vlk_relocation_kind(kind image.RelocationKind) vunit.RelocationKind {
	match kind {
		.direct { return vunit.RelocationKind.direct }
		.got { return vunit.RelocationKind.got }
		.absolute { return vunit.RelocationKind.absolute }
		.tpoff { return vunit.RelocationKind.tpoff }
	}
}

fn vlk_width(width image.RelocationWidth) vunit.RelocationWidth {
	match width {
		.narrow { return vunit.RelocationWidth.narrow }
		.wide { return vunit.RelocationWidth.wide }
	}
}
