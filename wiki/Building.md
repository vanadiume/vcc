# Building

vcc is a compiler written in V, and V builds it. On Linux x86-64 the build is
a short list of commands: build V once, build the compiler, run the suite, and
run the gate.

## Which V builds the tree

The tree needs V built from source on Linux x86-64, at a commit that accepts
it.

The 0.5.2 release cannot build this tree. Its checker rejects a `for {}` whose
every path returns, which `parser/parser.v` uses, so the build stops in the
parser. Every commit after 0.5.2 accepts the shape. CI pins the commit it
builds and tests with in a `V_COMMIT` variable in
[.github/workflows/ci.yml](https://github.com/HuntedByTheIRS/vcc/blob/main/.github/workflows/ci.yml),
and the pin moves only after the tree is re-verified against the commit it
moves to.

The pin also has a floor. `parser/literals.v` reads a long double's literal
through a u128, and upstream V gained u128 and i128 on 2026-10-01. A V older
than that fails the build with `error: unknown function: u128`, and every test
file fails behind it. The comment on `V_COMMIT` records both facts.

## Building and running

```sh
git clone https://github.com/vlang/v && cd v && make   # once
cd /path/to/vcc
v -gc none -o vcc .        # build the compiler
v test .                   # the suite
v run tools/gate.vsh       # format, pure-V rule, build, prod build, tests, doc links, workflows
v run tools/bench.vsh      # wall time and peak memory, tcc alongside
./vcc -bench file.c -o out # per-phase timings
```

`v -gc none -o vcc .` writes the compiler to `./vcc`. The compiler frees what it
allocates, so it is built with no garbage collector; `v -o vcc .` builds the same
source with V's default collector and is not the compiler this tree ships.
`v test .` runs the suite.
[[The-Gate]] describes the gate, the suite and the corpora.
`v run tools/build.vsh` is the front door over the same commands when one run
is wanted.

An installed compiler comes with its runtime: `/usr/local/bin/vcc` with
`/usr/local/lib/libvcc.a` and the `libvcc.so` chain by default, or the same under
`--prefix`. `v run tools/build.vsh install --release` takes the latest GitHub
release, verifies the digest published beside it, and places the pair; `install`
without `--release` builds the compiler from this checkout and pulls libvcc from
its repository at the pinned commit. Either path then compiles and runs a
program that calls a helper from the archive and a second one that links with
`-shared-libvcc` against the library, so the install is proved where it lands.
`v run tools/build.vsh update-install` puts the latest release over an installed
prefix, and `v run tools/build.vsh uninstall` removes the files the install
placed. A release ships the same tree as `vcc-<version>-x86_64-linux.tar.gz`,
laid out under `usr/bin` and `usr/lib`.

## A first program

```sh
printf '#include <stdio.h>\nint main(void) { puts("Hello, world!"); return 0; }\n' > hello.c
./vcc hello.c -o hello && ./hello
./vcc -run hello.c        # same, without leaving an image behind
```

`-run` compiles the program, runs it, and exits with the program's own exit
status. It writes no image, so the tree keeps no file behind.

## Reading a parse with -print-ast

`-print-ast` parses the input, prints the tree the emitter would be given, and
stops without writing anything. A parse or an optimization is read from that
output rather than guessed at.

## Flags

vcc accepts the flag surface a build system hands a C compiler; [[Interop]]
covers the V side of that contract. It also has flags of its own:

`--version`, `-v`, `-vv`, `-h`, `-hh`, `-E`, `-c`, `-o`, `-run`, `-bench`,
`-print-ast`, the `-O0` through `-O3` and `-Os` levels, `-fno-builtin` and
`-fno-builtin-NAME`, `-fbracket-depth=N` (how deep a parenthesis, brace or
statement may nest, 256 by default; 0 lifts the limit), `-fPIC`/`-fpic`,
`-nostdinc`, `-undef`, `-include`,
`-imacros`, the dependency flags `-M`/`-MM`/`-MD`/`-MMD`/`-MF`/`-MT`/`-MQ`,
`-dM`, `-Wclass`/`-Wno-class`, `-femulation=NAME` (define the identity macros
of gcc, clang or tcc instead of vcc's own), `-fuse-ld=NAME`,
`-shared`, `-static`, `-nostdlib`, `-nodefaultlibs`, `--link-libgcc`,
`-shared-libvcc`, `-shared-libgcc`, and the gcc `-print-` family.
`./vcc -hh` prints the annotated surface.

A program links the runtime archive `libvcc.a`, where the helpers the machine has
no instruction for live under libgcc's symbol names. It is looked for where a
`-l` name is looked for and then beside the compiler, and only the members the
program reaches are pulled, so an ordinary program carries none of it.
`-nodefaultlibs` keeps the start files and takes the C library and libvcc away,
`-nostdlib` takes the start files too, and `--link-libgcc` names the toolchain's
`libgcc.a` instead. With either of the first two the image names only the
libraries the command line names, and an import none of them defines is refused
at compile time rather than left for the loader to report at start. The libgcc
archive is looked for in the search a link makes, which ends with the toolchain's
own directory, so a machine with gcc installed needs no `-L`; a machine without
it refuses the flag by name.
`-shared-libvcc` is the same runtime as a shared library: the image names
`libvcc.so.0` instead of pulling members out of the archive, so the library has
to be there when the program starts. It is refused with `-static`, with
`--link-libgcc`, and with `-shared-libgcc`. `-shared-libgcc` is the counterpart
on the libgcc side and needs `--link-libgcc` beside it, so the runtime it makes
shared is the one the command line named.

`v run tools/build.vsh libvcc` builds the archive from the libvcc repository
with this compiler and links a program against it. `install --release` puts the
latest release under a prefix, and plain `install` builds the runtime and the
compiler first.

`-O` today turns on one optimizer pass: a call whose value the compiler knows
(`abs`, `labs`, `llabs`) with a literal argument folds to that value. `-O0`
makes the call and `-O2` folds it. `-fno-builtin` takes the fold back.

`-fuse-ld=NAME` hands the final link to a linker already on the
system, for an input the in-house linker cannot consume yet, such as an object
carrying a section or a relocation it does not model. It refuses `cc`,
`gcc`, `clang`, `c++` and `tcc` by name, because a C compiler finishing C
compilation is the one thing the pure-V rule exists to prevent. It is the
single exception to that rule, and it is off by default. [[Pure-V]] covers the
rule.

A flag the compiler does not implement is recorded and never refused, because
a compiler that errors on `-bt25` fails a build it was supposed to serve.

## Directory layout

| Path | Contents |
|---|---|
| `main.v` | entry point: command line in, output file out, pipeline in between |
| `cli/` | the command line: flags, usage, version, phase timings |
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
| `extensions/` | the `-fvcc-exts=` interface, built on the extension rows in `standard/` |
| `tools/` | gate, benchmark and corpus scripts; not part of the compiler |
| `compliance/` | the conformance corpus, one directory per standard: one C program per standard-library check, run by `tools/compliance.vsh` |
| `regression/` | one C program per bug that must not come back, one directory per standard, run by `tools/regress.vsh` |
| `goldens/` | C programs whose recorded output is compared byte for byte, one directory per standard |

The C in `compliance/`, `regression/` and `goldens/` is the only C in the
tree, and it is input the compiler is handed rather than part of the compiler
itself.

A new machine, a new system, or a new calling convention is a module of its
own under `backend/`, and `codegen/` never learns about it. [[Architecture]]
describes the pipeline these modules form.

## See also

- [[The-Gate]], for the checks a change has to pass.
- [[Pure-V]], for the rule and where C may appear.
- [[Interop]], for what V asks of a C compiler.
