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

vcc compiles C to native Linux x86-64 programs. The preprocessor, parser,
optimizer, code generator and linker are its own, so a build needs nothing from
the system but a C library: no assembler and no system linker.

It accepts the C that real projects are written in, C89 through C23 and their
GNU variants, with the gaps listed under Status. It writes ELF64 executables,
relocatable objects, shared objects and static binaries. The source is plain V
in separate modules with no dependency in `v.mod`.

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
output. `v -gc none -o vcc .` is the same compile called directly, and it names
the memory mode because the compiler frees what it allocates and runs with no
collector. `v run
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
looking for the archive in the system library directories and then beside
itself. A compiler installed without the archive still builds programs that call
no helper, and refuses one that calls a helper by the name of the helper. The
install step finishes by compiling and running a program that calls one, so an
install that cannot find its own archive fails there.

## What it supports

- The dialects: `-std=c89`, `c99`, `c11`, `c17`, `c23` and `c29`, the GNU
  spelling of each (`gnu89` through `gnu29`), the ISO spellings
  (`iso9899:1990` through `iso9899:2029`), and the `c90`, `c18`, `c2y` and
  `gnu2y` aliases. A construct the selected mode forbids is a pedantic message,
  silent until `-Wpedantic`; `-pedantic-errors` makes it an error.
- A real preprocessor, including `#include_next`, function-like macros with `#`
  and `##`, variadic arguments, the full `#if` grammar, `#pragma once`,
  `#line`, `#error`, `_Pragma` and `__has_include`. Its output is compared with
  `tcc -E` token by token.
- The whole front end and type system: typedefs, structs, unions, enums,
  bitfields, designated initializers, compound literals, function pointers,
  variadic functions, aggregates passed and returned by value, variable-length
  arrays, the full operator set, `switch` and `goto`, `char` through `__int128`
  signed and unsigned, `float`, `double`, `long double`, `_Complex` at all
  three widths, `_Bool` and C23 `_BitInt(128)`, with the standard's conversions.
- The extensions real code uses: `typeof`, `__typeof__`, `typeof_unqual`, C23
  `auto`, `_Generic`, `_Static_assert`, statement expressions, `__asm__`,
  `__attribute__`, the `__atomic_*` operations, the common `__builtin_*` set,
  and the count-leading and count-trailing builtins. `-fvcc-exts=` turns the
  gated ones on by name.
- SysV x86-64 code generation with stack frames, thread-local storage, unwind
  tables and position-independent code, `-O0` through `-O3` and `-Os`, and a
  linker that takes translation units, relocatable objects and `ar` archives on
  one command line, resolves `-l` names through the system ld scripts, pulls
  only the members a program reaches, and refuses an unresolved import by name.
  `-shared`, `-static`, `-nostdlib` and `-nodefaultlibs` are supported.
- Diagnostics that name the construct and its file, line and column, and never
  an empty output file that fails later.

`wiki/C-Support.md` has the same ground in more detail.

## Status

What is missing:

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
- Speed. vcc is behind tcc, and the numbers are under Performance.
- A complete V self-build. vcc does compile the C that V generates from vcc's
  own source, and the compiler it produces runs. V itself built by vcc and
  passing V's own suite is still open.

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

`./vcc -hh` prints the rest, which includes `--version`, `-fno-builtin`,
`-nostdinc`, `-undef`, `-include`, `-imacros`, the dependency flags,
`-dM`, `-Wclass`/`-Wno-class`, `-fvcc-exts=`, `-Wpedantic`,
`-femulation=NAME`, `-external-linker=NAME`, `-target` and the gcc `-print-`
family. A flag the compiler does not implement is recorded and never refused,
so a build system that passes one does not stop here.

### The runtime archive

`libvcc.a` carries the helpers the machine has no instruction for, under
libgcc's symbol names, and only the members a program reaches are pulled in. A
division or a remainder of two `__int128` values is a call into it (`__divti3`,
`__udivti3`, `__modti3`, `__umodti3`); a multiplication and a shift of that width
are instructions, emitted inline unless `-fignore-natives` asks for the archive's
version.

`-nodefaultlibs` keeps the start files and takes the C library and libvcc away;
`-nostdlib` takes the start files too, and the program leaves through the
kernel's exit. `-target x86_64-linux-freestanding` is the same machine and system
calls with no C library at all: no standard headers, no start files, no library
in the image, and `__STDC_HOSTED__` is 0.

### Dialects and extensions

Each row of `standard/features.v` names a construct, the standard it belongs to,
and what this compiler does with it. `-std=` selects a mode, and the table is
checked against the token stream. The reserved-namespace spellings (`__typeof__`,
`__asm__`) are read in every mode the way gcc reads them; the ones a standard
introduced (`typeof`, `auto`, `_Generic`, `_Static_assert`, `_BitInt`) are gated
and can be brought down to an earlier mode with `-fvcc-exts=`.

```sh
./vcc -fvcc-exts=all prog.c -o prog               # every extension the compiler has
./vcc -fvcc-exts=typeof,generic -std=c99 prog.c   # named ones
```

## Performance

`v run tools/bench.vsh` builds the tree under test, generates a long constant
expression, and runs vcc and the tcc that V vendors on the same input. Wall time
is the best of several runs; peak memory comes from `/usr/bin/time`.

| terms | vcc wall | tcc wall | ratio | vcc peak | tcc peak | ratio |
|---|---|---|---|---|---|---|
| 2 000 | 23.2 ms | 5.7 ms | 4.1x | 27.0 MB | 3.1 MB | 8.7x |
| 20 000 | 127.9 ms | 6.8 ms | 18.9x | 62.5 MB | 3.2 MB | 19.6x |

The ratio grows with the input because tcc's time barely moves while vcc's
tracks the tokens and nodes it allocates. That is a design problem and the M6
problem in `ROADMAP.md`, not a constant factor to trim. The second row is
`--terms 20000`, and `./vcc -bench file.c -o out` prints per-phase timings when
a build is slower than expected.

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

`v test .` runs the suite, with a test beside the module it exercises as a
`*_test.v` file. `v run tools/compliance.vsh` compiles and runs the corpus under
`compliance/`, one directory per standard, checking the compiler against the
standard rather than against its own tests. `v run tools/regress.vsh` runs
`regression/`, one program per fixed bug, and `goldens/`, whose recorded output
is compared byte for byte. `v run tools/gate.vsh` runs the formatting, purity,
build, test, doc link and workflow checks a pull request has to pass, and CI
runs the same gate. `CONTRIBUTING.md` covers the workflow, the commit format and
the prose rules.

## Stress tests

Two programs matter more than any unit test:

- The V bootstrap. V emits a few megabytes of C for itself, and vcc compiles
  that C into a working compiler. `v -cc ./vcc -o /tmp/vcc-self .` exits 0 and
  the compiler it produces runs; V itself built by vcc and passing V's own suite
  (step 3 of the four-build chain) is still open. `ROADMAP.md` M8 has the
  record.
- A bootable Linux kernel. It forces what a userspace corpus never does: a
  freestanding build with no libc, inline assembly, section and alignment
  attributes, no red zone, the kernel code model, and a link driven by a script
  rather than start files. The freestanding target and `__asm__` are the
  beginning of that; nothing in the tree is arranged for the rest yet.

## Compatibility

vcc accepts the flag surface build systems hand a C compiler, plus the
preprocessor's own flags. `--version` is stable and machine-parseable, because
some build systems classify a compiler by its version output and cache artifacts
against that identity.

The compiler started inside V's toolchain and can still be handed to V as its C
compiler, though using vcc does not require V. `wiki/Interop.md` and `ROADMAP.md`
have the classification rules and the bootstrap chain.

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
