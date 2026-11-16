module cli

// The -Wl, options the compiler reads, in the terms the image writer uses.
//
// A `-Wl,` flag is not a passthrough here: this compiler has its own linker, so
// the option either changes the image that linker writes or it must be refused
// by name. Silently accepting one leaves a build believing a security or
// runtime-linker flag took effect when it did not, which is what issue #64
// reported. The spellings below are the ones the image can express; everything
// else is refused with the option as it was written.
//
// The flags are read here and not in `parse` because which linker sees them is
// a command-line fact that parse cannot know yet: -external-linker may name the
// tool further down the same line, and that path forwards them untouched.

// LinkerOptions is what the -Wl, options this compiler's own linker implements
// decide about the image it writes. The zero value is a link with no option
// given, which is what every run that names none gets.
pub struct LinkerOptions {
pub mut:
	// execstack is -Wl,-z,execstack: the stack the kernel maps is executable.
	execstack bool
	// noexecstack is -Wl,-z,noexecstack: the stack is not executable, even for
	// a unit whose code takes a nested function's address and needs it to be.
	// The option is the promise in every linker; a program that needs an
	// executable stack then faults, which is what asking for this means.
	noexecstack bool
	// bind_now is -Wl,-z,now: the dynamic table says every imported name is
	// bound before the first instruction runs. This compiler's images already
	// bind their imports eagerly, so the flag writes the promise rather than
	// changing a relocation.
	bind_now bool
	// relro is -Wl,-z,relro: the image carries a PT_GNU_RELRO segment over the
	// tables the loader writes and nothing writes again.
	relro bool
	// soname is -Wl,-soname,NAME: the name a shared object records inside
	// itself as its own, which is the string a program linked against it puts
	// in DT_NEEDED and the name the loader searches for. Empty means the image
	// records none, which is what a link that asked for nothing gets; gcc and
	// ld write no DT_SONAME for a shared object either unless this option is
	// given.
	soname string
}

// linker_options reads the payloads of the -Wl, flags for this compiler's own
// linker. Every payload is a comma-joined list of linker arguments, which is
// the spelling gcc gives its linker: `-Wl,-z,now` is `-z now` and
// `-Wl,--gc-sections` is one option. A payload carrying anything this linker
// cannot express is an error naming the flag as it was written, because a
// recorded option is indistinguishable from an applied one at the end of a
// build.
pub fn linker_options(args []string) !LinkerOptions {
	mut options := LinkerOptions{}
	for payload in args {
		if payload == '' {
			return error('-Wl, names no linker option')
		}
		words := payload.split(',')
		mut i := 0
		for i < words.len {
			word := words[i]
			if word == '-soname' {
				// The one option here that takes a string rather than a
				// keyword: `-Wl,-soname,libvcc.so.0` names the image's own
				// name, and the name is the whole rest of the payload because
				// a comma would end it.
				if i + 1 >= words.len || words[i + 1] == '' {
					return error('-Wl,${payload}: -soname needs a name')
				}
				options.soname = words[i + 1]
				i += 2
				continue
			}
			if word != '-z' {
				return error('-Wl,${payload}: the in-house linker does not implement ${word}')
			}
			if i + 1 >= words.len {
				return error('-Wl,${payload}: -z needs an argument')
			}
			keyword := words[i + 1]
			// A keyword with a negative spelling sets the pair the way a
			// repeated command-line flag does: the last one written wins, so a
			// build can append `-z norelro` to a line that already had it on.
			match keyword {
				'execstack' {
					options.execstack = true
					options.noexecstack = false
				}
				'noexecstack' {
					options.noexecstack = true
					options.execstack = false
				}
				'now' {
					options.bind_now = true
				}
				'lazy' {
					options.bind_now = false
				}
				'relro' {
					options.relro = true
				}
				'norelro' {
					options.relro = false
				}
				else {
					return error('-Wl,${payload}: the in-house linker does not implement -z ${keyword}')
				}
			}
			i += 2
		}
	}
	return options
}

// external_linker_arguments is the same payloads in the shape the other linker
// reads. It is a passthrough: nothing is interpreted and nothing is refused,
// because the tool named by -external-linker is the one that decides what its
// own options mean. A comma is the separator gcc uses between the options
// inside one -Wl, word, so `-Wl,-z,now` reaches the linker as `-z now`.
pub fn external_linker_arguments(args []string) []string {
	mut out := []string{}
	for payload in args {
		for word in payload.split(',') {
			if word != '' {
				out << word
			}
		}
	}
	return out
}
