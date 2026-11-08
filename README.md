<p align="center">
  <img src="vcc.png" alt="vcc logo: a green V" width="300" style="border-radius: 15px;">
</p>

<h1 align="center">vcc</h1>

<p align="center">A general-purpose C compiler for Linux x86-64, written in V.</p>

<p align="center">
  <a href="https://github.com/HuntedByTheIRS/vcc/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/HuntedByTheIRS/vcc/ci.yml?style=flat&label=ci" alt="ci status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/HuntedByTheIRS/vcc?style=flat" alt="license"></a>
  <a href="https://github.com/HuntedByTheIRS/vcc"><img src="https://img.shields.io/github/languages/top/HuntedByTheIRS/vcc?style=flat&label=pure%20V" alt="pure V"></a>
  <a href="ROADMAP.md"><img src="https://img.shields.io/badge/platform-linux%20x86--64-2ea043?style=flat" alt="platform: Linux x86-64"></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/HuntedByTheIRS/vcc/main/.github/badges/tests.json&query=$.tests&label=tests&color=2ea043&style=flat" alt="tests"></a>
  <a href="compliance/README.md"><img src="https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/HuntedByTheIRS/vcc/main/.github/badges/compliance-tests.json&query=$.tests&label=compliance%20tests&color=2ea043&style=flat" alt="compliance tests"></a>
  <a href="regression/README.md"><img src="https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/HuntedByTheIRS/vcc/main/.github/badges/regressions.json&query=$.failed&label=regressions&color=critical&style=flat" alt="regressions"></a>
  <a href="ARCHITECTURE.md"><img src="https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/HuntedByTheIRS/vcc/main/.github/badges/lines.json&query=$.lines&label=lines&color=2ea043&style=flat" alt="lines of V, tests excluded"></a>
  <a href="https://github.com/HuntedByTheIRS/vcc/commits/main"><img src="https://img.shields.io/github/last-commit/HuntedByTheIRS/vcc?style=flat" alt="last commit"></a>
</p>

vcc compiles C to native Linux x86-64 programs. It has its own preprocessor,
parser, optimizer, code generator and linker, so a build needs nothing from the
system but a C library: no assembler and no system linker. The compiler and its
runtime archive are the whole toolchain.

It accepts the C that real projects are written in, in the C89 through C23
dialects and their GNU variants, with the gaps listed under Status. It writes
ELF64 executables, relocatable objects, shared objects and static binaries.

The compiler is 69,693 lines of V, tests excluded. It builds with one command,
has no dependency in `v.mod`, and installs as two files: the compiler and its
runtime archive. The source is ordinary V in separate modules, so the whole
pipeline is something you can read and change without leaving the language.

This is a working compiler, not a plan for one. `v test .` runs 1,725 tests;
`v run tools/compliance.vsh` compiles and runs 1,154 conformance cases across
the C dialects; `v run tools/regress.vsh` runs 126 programs, one per bug that
must not come back. The badges above read the counts from the runners, not from
a number kept by hand.

## What it supports

- C89 through C23 and the GNU dialects: `-std=c89`, `c99`, `c11`, `c17`, `c23`
  and `c29`, plus the GNU spelling of each (`gnu89` through `gnu29`). The ISO
  spellings (`iso9899:1990` through `iso9899:2029`) and the `c90`, `c18`, `c2y`
  and `gnu2y` aliases work as well. A construct the selected mode forbids is a
  pedantic message, silent until `-Wpedantic`; `-pedantic-errors` makes it an
  error.
- A real preprocessor: `#include` with C's search order and `#include_next`,
  object-like and function-like macros with `#`, `##` and variadic arguments,
  the full `#if` expression grammar, `#pragma once`, `#line`, `#error`,
  `#warning`, `_Pragma`, the location and clock macros, and `__has_include`.
  Its output is compared with `tcc -E` token by token.
- The whole front end: typedefs, prototypes, structs, unions, enums, bitfields,
  designated initializers, compound literals, function pointers, variadic
  functions, objects of aggregate type passed and returned by value, arrays and
  variable-length arrays, `sizeof` and casts, the full operator set, and control
  flow including `switch` and `goto`.
- The types: `char` through `long long`, signed and unsigned, `float`, `double`,
  `long double`, `_Complex` at all three widths, `_Bool`, `__int128`, C23
  `_BitInt(128)`, and C's aggregate and pointer types. Enum constants, integer
  conversions and the usual arithmetic conversions follow the standard.
- The extensions real code uses: `typeof`, `__typeof__`, `typeof_unqual`, C23
  `auto`, `_Generic`, `_Static_assert`, statement expressions, `__asm__`,
  `__attribute__`, the `__atomic_*` operations, the `__builtin_*` memory, string
  and bit operations, and the count-leading and count-trailing builtins.
  `-fvcc-exts=` turns the gated ones on by name.
- Code generation for SysV x86-64: stack frames, global and thread-local
  storage, position-independent code, unwind tables with `.eh_frame_hdr`, and
  the runtime helpers the machine has no instruction for. `-O0` through `-O3`
  and `-Os` are accepted; `-O1` and above fold calls whose value the compiler
  knows.
- Linking: one command line can hold several translation units, relocatable
  objects and `ar` archives. The in-house linker merges them, resolves `-l`
  names through the system ld scripts, pulls only the archive members a program
  reaches, and refuses an unresolved import at compile time with its name.
  `-shared`, `-static`, `-nostdlib` and `-nodefaultlibs` are supported.
- Diagnostics that name the construct and its file, line and column, and never
  an empty output file that fails later.

## Status

What is missing, in full:

- Other targets. The compiler is Linux x86-64 only. arm64, macOS and Windows are
  back ends and linking stories that do not exist yet.
- Debug information. `-g` is accepted and currently ignored.
- A few standard constructs. `_Alignof` and `<stdalign.h>`'s `alignof`,
  `_Noreturn`, C23 `constexpr`, the C23 keywords `bool`, `true`, `false` and
  `nullptr`, the decimal floating types, and the `d` and `D` suffixes on
  floating constants are refused by name. `_Imaginary` is refused by name,
  which C99 allows an implementation to do.
- A static link that reaches a library the linker cannot unpack. It resolves
  what its archives provide and refuses an import it could not resolve, naming
  it. A dynamic program or shared object that names the library works.
- An object or archive carrying a section or relocation the linker does not
  model. It is refused by name rather than placed at a guessed address.
  `-external-linker=NAME` is the way through.
- Speed. vcc is behind tcc, and the numbers are below. The design has a second
  pipeline planned to close the gap; the claim is that the gap is measured, not
  that it is closed.
- A complete V self-build. vcc does compile the C that V generates from vcc's
  own source, and the compiler it produces runs. V itself built by vcc and
  passing V's own suite is still open.

## Quick start

You need V built from source on Linux x86-64, at a commit that accepts this
tree. The 0.5.2 release does not: its checker rejects a `for {}` whose every
path returns, which `parser/parser.v` uses. Everything since accepts it, and CI
pins the commit it tests with in `.github/workflows/ci.yml`.

```sh
git clone https://github.com/vlang/v && cd v && make   # once
git clone https://github.com/HuntedByTheIRS/vcc && cd vcc
v run tools/build.vsh build -o vcc   # the official build
v test .                             # run the suite
```

`v run tools/build.vsh build` is the official way to build the compiler. It
builds vcc with V and reports where the binary landed; `-o PATH` names the
output. `v -o vcc .` is the same compile called directly. `v run
tools/build.vsh` without a step runs the whole front door, which adds the gate,
the corpora, the benchmark, the image and the version report.

```sh
printf '#include <stdio.h>\nint main(void) { puts("Hello, world!"); return 0; }\n' > hello.c
./vcc hello.c -o hello && ./hello
./vcc -run hello.c        # compile and run without leaving an image behind
```

`-run` exits with the program's status. `-print-ast` parses, prints the tree the
emitter would receive, and stops without writing anything.

## Install

A release carries one tarball, `vcc-<version>-x86_64-linux.tar.gz`, holding an
install tree:

```
usr/bin/vcc
usr/lib/libvcc.a
```

Untar it at the root, or build both files from this tree and let the build
script place them:

```sh
sudo tar --extract --gzip --file vcc-<version>-x86_64-linux.tar.gz --directory /
v run tools/build.vsh install                 # /usr/local/bin/vcc, /usr/local/lib/libvcc.a
v run tools/build.vsh install --prefix /usr   # /usr/bin/vcc, /usr/lib/libvcc.a
```

The install is both files. vcc writes the machine code itself but links a
program against `libvcc.a` for the helpers the machine has no instruction for,
and it looks for the archive in the system library directories and then beside
itself. A compiler installed without the archive still builds programs that call
no helper, and refuses one that calls a helper by the name of the helper.

`v run tools/build.vsh install` builds libvcc with the compiler it just built,
copies the two files into the prefix (through sudo when the prefix is not
writable), and then compiles and runs a program that calls a helper from the
archive, so an install that cannot find its own runtime archive fails there. It
takes `--libvcc DIR` when the tree is not the `libvcc` sibling.

## Flags

The common ones:

```
-o outfile        output name (default a.out)
-c                compile to a relocatable object only
-E                preprocess and print, then stop
-run              compile to a temporary file and run it
-print-ast        print the tree the emitter would be given, then stop
-bench            per-phase timings
-std=version      select a dialect
-I -D -U -L -l    the include, define and library paths
-O0..-O3 -Os      optimization level
-fPIC -fpic       position-independent code
-shared           write a shared object
-static           write a static program
-w                suppress warnings
-h -hh            short and full help
```

Also accepted: `--version`, `-v`, `-vv`, `-fno-builtin` and
`-fno-builtin-NAME`, `-fignore-natives`, `-nostdinc`, `-undef`, `-include`,
`-imacros`, the dependency flags `-M`/`-MM`/`-MD`/`-MMD` and
`-MF`/`-MT`/`-MQ`, `-dM`, `-Wclass`/`-Wno-class`, `-fvcc-exts=` and
`-fno-vcc-exts=`, `-Wpedantic`/`-pedantic`/`-pedantic-errors`,
`-femulation=NAME` (define the identity macros of gcc, clang or tcc),
`-external-linker=NAME`, `-nostdlib`, `-nodefaultlibs`, `--link-libgcc`,
`-target`, and the gcc `-print-` family. `./vcc -hh` prints the annotated
surface. A flag the compiler does not implement is recorded and never refused,
so a build system that passes one does not stop here.

### The runtime archive

A program links `libvcc.a` for the helpers the machine has no instruction for,
under libgcc's symbol names. The archive is looked for where a `-l` name is
looked for and then beside the compiler, and only the members a program reaches
are pulled into it, so a program that calls no helper carries none of it. A
release ships the archive beside the compiler; "Install" above has the layout.

`-nodefaultlibs` keeps the start files and takes the C library and libvcc away.
`-nostdlib` takes the start files as well, and the program that comes out leaves
through the kernel's exit because there is no library's exit to call. With
either flag the image names only the libraries the command line names, and an
import none of them defines is refused at compile time rather than left for the
loader to report at start.

`--link-libgcc` puts the toolchain's `libgcc.a` in libvcc's place. Only a
compiler built with `-d experimental_libgcc` accepts the flag.

A division or a remainder of two `__int128` values is a call to the archive,
because the machine has no instruction that divides a pair: the compiler emits
`__divti3`, `__udivti3`, `__modti3` or `__umodti3`, and a program that divides
without an archive to link is refused by the helper's name. A multiplication and
a shift of that width are instructions the machine has, so they are emitted
inline; `-fignore-natives` asks for the archive's `__multi3` and `__ashlti3`,
`__ashrti3` or `__lshrti3` instead.

`-target x86_64-linux-freestanding` is the same machine and the same system
calls with no C library at all: no standard header directories, no start files,
no library named in the image, and `__STDC_HOSTED__` is 0. It is what a runtime
library that must call nothing is built for.

### Dialects and extensions

The dialect table in `standard/features.v` has one row per construct: the
standard it belongs to, whether a GNU dialect takes it, and what this compiler
does with it. `-std=` selects a mode, and the table is checked against the
token stream. The spellings that follow the reserved-namespace rules
(`__typeof__`, `__asm__`) are read in every mode, the way gcc reads them; the
ones a standard introduced (`typeof`, `auto`, `_Generic`, `_Static_assert`,
`_BitInt`) are gated by the table and can be brought down to an earlier mode
with `-fvcc-exts=`.

```sh
./vcc -fvcc-exts=all prog.c -o prog               # every extension the compiler has
./vcc -fvcc-exts=typeof,generic -std=c99 prog.c   # named ones
```

The names are the extension column of the rows, not a list kept apart from them.

Reporting is separate from refusing. A construct the selected mode merely does
not allow is a pedantic message, silent until `-Wpedantic` or `-pedantic` asks
for it, promoted to an error by `-pedantic-errors` or `-Werror=pedantic`, and
silenced by `-w`. A construct the mode does not have at all is a diagnostic the
compiler raises on its own account, which no flag silences. System headers are
exempt.

Each row's phrasing was checked against gcc 16.2.1 under the relevant `-std=`,
and the comment on the row records what was measured. `-std=c99 -pedantic` on
`typeof(int) x = 3;` reports `ISO C99 forbids the typeof specifier` and exits
non-zero, matching gcc; `-std=c11` accepts `_Generic` silently where
`-std=c99 -pedantic` warns.

## Performance

Correctness comes first, but compile speed is part of what a C compiler is for,
so it is measured on every change that touches a hot path. `v run tools/bench.vsh`
builds the tree under test, generates a long constant expression, and runs vcc
and the tcc that V vendors on the same input. Wall time is the best of several
runs; peak memory comes from `/usr/bin/time`.

| terms | vcc wall | tcc wall | ratio | vcc peak | tcc peak | ratio |
|---|---|---|---|---|---|---|
| 2 000 | 23.2 ms | 5.7 ms | 4.1x | 27.0 MB | 3.1 MB | 8.7x |
| 20 000 | 127.9 ms | 6.8 ms | 18.9x | 62.5 MB | 3.2 MB | 19.6x |

The ratio grows with the input because tcc's time barely moves (5.7 ms to
6.8 ms) while vcc's tracks the tokens and nodes it allocates. That is a design
problem and the M6 problem in `ROADMAP.md`, not a constant factor to trim. Each
row is one run of `v run tools/bench.vsh`, with `--terms 20000` for the second.

`./vcc -bench file.c -o out` prints per-phase timings, which is where to look
first when a build is slower than expected.

## How it is put together

`main.v` reads the command line and runs the stages in order. The preprocessor
owns the lexer, because its unit of work is a file. The parser produces an
`ast.TranslationUnit`. The optimizer runs over the tree. `codegen.emit` returns
an emitted unit, and `linking/` merges units into one image. Each stage is a
module with one job, and the doc comments state the rules the boundaries keep.

| Path | Contents |
|---|---|
| `main.v` | entry point: command line in, output file out, pipeline in between |
| `cli/` | flags, usage, version, phase timings |
| `tokenize/` | lexer: source text to tokens |
| `diagnostics/` | what a diagnostic is: class, severity, and the one place it becomes text |
| `standard/` | the dialects: `-std=` spellings, the modes, and the feature table |
| `preprocess/` | the C preprocessor |
| `ast/` | node types only |
| `parser/` | tokens in, `ast` out |
| `optimizer/` | `ast` in, `ast` out: `-O` levels and the builtin table |
| `printer/` | `ast` in, text out: what `-print-ast` prints |
| `backend/` | target description: `arch/` the machine, `os/` the system, `abi/` the calling convention, `backend.v` composes them |
| `codegen/` | `ast` in, an emitted unit out |
| `image/` | the emitted unit: machine code, the data it reads, the references between them |
| `linking/` | the in-house linker: units of one link in, one image out |
| `extensions/` | the `-fvcc-exts=` interface, built on the rows in `standard/features.v` |
| `tools/` | gate, benchmark and corpus scripts; not part of the compiler |
| `compliance/` | the conformance corpus, one directory per standard |
| `regression/` | one C program per bug that must not come back, one directory per standard |
| `goldens/` | C programs whose recorded output is compared byte for byte |
| `wiki/` | the pages of the GitHub wiki, copied there by the wiki workflow on a push to main |

The C in `compliance/`, `regression/` and `goldens/` is the only C in the tree,
and it is input the compiler is handed rather than part of the compiler itself.

`ARCHITECTURE.md` describes the pipeline, the target description and the
invariants in full.

## Testing

`v test .` runs the suite. A test sits beside the module it exercises as a
`*_test.v` file. A change to the lexer, the parser or the back end arrives with
a test that fails before it and passes after.

`v run tools/compliance.vsh` compiles and runs the corpus under `compliance/`,
one directory per standard, checking the compiler against the standard rather
than against its own tests. `v run tools/regress.vsh` runs `regression/`, one
program per fixed bug, and `goldens/`, whose recorded output is compared byte
for byte. `v run tools/gate.vsh` runs the formatting, purity, build, test, doc
link and workflow checks a pull request has to pass; CI runs the same gate.

`CONTRIBUTING.md` covers the workflow, the commit format and the prose rules.

## Stress tests

The suite is not the only measure. Two programs matter more than any unit test:

- The V bootstrap. V emits a few megabytes of C for itself, and vcc compiles
  that C into a working compiler. `v -cc ./vcc -o /tmp/vcc-self .` exits 0 and
  the compiler it produces runs; V itself built by vcc and passing V's own suite
  (step 3 of the four-build chain) is still open. `ROADMAP.md` M8 has the
  record.
- A bootable Linux kernel. It is the hardest stress test a C compiler can be
  handed, and it forces what a userspace corpus never does: a freestanding
  build with no libc, inline assembly, section and alignment attributes, no red
  zone, the kernel code model, and a link driven by a script rather than start
  files. The freestanding target and `__asm__` are the beginning of that;
  nothing in the tree is arranged for the rest yet.

## Compatibility

vcc accepts the flag surface build systems hand a C compiler, plus the
preprocessor's own flags. `--version` is stable and machine-parseable, because
some build systems classify a compiler by its version output and cache artifacts
against that identity. A flag the compiler does not implement is recorded and
never refused.

The compiler started inside V's toolchain and can still be handed to V as its C
compiler. That compatibility is maintained; using vcc does not require V. The
classification V uses, the flags it passes, and the bootstrap chain that
exercises them are in `wiki/Interop.md` and `ROADMAP.md`.

## Docs

- `CONTRIBUTING.md` for the build, test and commit workflow.
- `ARCHITECTURE.md` for how the compiler is put together.
- `ROADMAP.md` for the milestones between here and a complete compiler.
- `tools/README.md` for the gate, the corpora and the benchmark harness.
- `ISSUES.md` for where reports, questions and feature requests go.
- `SECURITY.md` for what counts as a vulnerability in a compiler.
- `CODE_OF_CONDUCT.md` for how people are expected to treat each other.
- The [wiki](https://github.com/HuntedByTheIRS/vcc/wiki) for the same material
  arranged by task, built from `wiki/` on a push to main.

## License

BSD 3-Clause. See `LICENSE`.
