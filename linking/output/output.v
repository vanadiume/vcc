module output

import backend
import backend.os.elf
import backend.os.linux
import image as unit

// Wrapping a merged program as the bytes of an output file. It is a seam and
// deliberately thin: the container in backend/os/elf writes the shape the kind
// asks for, and `kind` is which of the three the command line named, so a static
// program and a shared object reach the container from here rather than through
// a second path. `options` is what the -Wl, flags added, and it reaches the same
// writer the single-input path uses so the two cannot disagree about what a
// stack permission or a RELRO segment means. The `image` module is imported
// under another name because this function is named for what it returns, and
// the name would otherwise shadow the module its argument's type is written
// from.
pub fn image(program unit.Program, target backend.Target, kind linux.LinkKind, options linux.LinkOptions) ![]u8 {
	return elf.write_options(program, target, kind, options)
}
