# Roadmap

vcc is a usable C compiler today. What follows is the order the remaining work
takes and how each step is verified. Every milestone ends at the same gate: the
suite passes, the corpora pass, and wall time and peak memory do not regress.

## Where the tree is

The compiler runs the whole pipeline itself. The preprocessor reads the glibc
headers on this machine, the front end reads the C those headers are made of
and the definitions after them, `codegen/` writes ELF64, and `linking/` merges
translation units, reads relocatable objects and `ar` archives, and writes
executables, shared objects and static programs. The runtime helpers the
machine has no instruction for come from `libvcc.a`.

The evidence, counted by the runners rather than kept by hand:

- `v test .` runs 1,725 tests.
- `v run tools/compliance.vsh` runs 1,154 conformance cases across the dialects.
- `v run tools/regress.vsh` runs 126 regression cases and the goldens.

Self-compilation was measured on this tree: `v -nocache -cc ./vcc -o
/tmp/vcc-self .` exits 0, and the compiler it builds reports `vcc 0.0.3 (pure
V)` and compiles a program that runs. What is left of the V chain is step 3
below.

Speed, from `v run tools/bench.vsh` against the tcc V vendors: 4.1x tcc's wall
time and 8.7x its peak memory on a 2,000-term constant chain, and 18.9x and
19.6x at 20,000 terms. The ratio grows with the input because tcc's time is
nearly flat while vcc's tracks the tokens and nodes it allocates. That gap is
M6, and it is measured rather than felt.

## M0 to M4: the foundation

These landed in order and each one is still checked by the gate.

M0 was the stub: a lexer for C's preprocessing tokens, a parser for the first
subset, an ELF64 writer whose output runs, and a diagnostic with a location for
every unsupported construct.

M1 was the preprocessor: `#include` with quoted and angle search paths,
object-like and function-like macros with `#` and `##`, variadic macros, the
full `#if` grammar, `#pragma once`, `#line`, `#error`, the `__DATE__`-class
macros, and real `-I`, `-D`, `-U`, `-nostdinc` and `-E`. Its fidelity is checked
against `tcc -E` token by token.

M2 was the front end: declarations and declarators including the pointer and
array spellings that read backwards, structs, unions, enums, typedefs,
bitfields, `sizeof` and `alignof`, casts, compound literals, designated
initializers, `switch`, loops, `goto`, labels, variadic functions, `_Bool` and
the integer and floating types, and constant folding. It is checked by parsing
and type-checking generated C, the C in V's `thirdparty/`, and programs from
outside the tree, and comparing acceptance with tcc and gcc.

M3 was the x86-64 back end: instruction selection, register allocation, stack
frames and the SysV calling convention, global and thread-local storage,
sections, relocations, unwind tables, and the integer and floating point
semantics the standard requires. It is checked by running the programs, not by
reading the assembly.

M4 was objects and linking: ELF relocatable objects, an `ar` archive reader,
executable linking against libc, static and shared output, `-L`/`-l` search
order, `-shared`, `-r`, `-nostdlib`, `-Wl,` passthroughs and the crt start
files. It is checked by linking programs that use libc, libm, pthreads and dl
and running them.

## M5: the rest of the language

The dialect table in `standard/features.v` records the constructs that are not
implemented, and each one becomes a row that changes status.

- `_Alignof` and `<stdalign.h>`'s `alignof`.
- `_Noreturn`.
- C23 `constexpr`.
- The C23 keywords `bool`, `true`, `false` and `nullptr`.
- The decimal floating types, `_Decimal32`, `_Decimal64` and `_Decimal128`.
- The `d` and `D` suffixes on floating constants.

`_Imaginary` stays unimplemented on purpose: C99 makes the imaginary types
optional, and the type is deprecated and drafted for removal in C2y. A use is
refused by name.

Verified by the conformance corpus, which gains a case with each row that
changes status, and by the compiler accepting the same program gcc accepts.

## M6: speed

The constraint, not a stretch goal. TCC is fast because it is a single-pass
compiler with almost no intermediate representation, and vcc has to be within
reach of that on the workload that matters: the megabyte-scale generated C of a
V self-build.

- Phase timings from `-bench` for every stage, tracked per commit rather than
  discovered later.
- A wall-time and peak-memory budget for the self-build, measured against the
  bundled tcc on the same machine, checked in CI once the number is stable.
- Design choices that follow from the target: one pass over tokens, no building
  of a full AST where a streaming decision will do, arena allocation rather than
  per-node heap traffic, and buffered output.
- Parallel compilation of translation units, the way tcc and V's `fastc` both
  do, once the single-threaded path is fast rather than instead of making it
  fast.

Verified by the numbers, in every pull request that touches a hot path.

## M6a: two pipelines behind one command line

The default builds an AST. Parse into a tree, run `optimizer/` over it, emit
from it. That is the path correctness is proven on, and it is where the
diagnostics and the tests live. An AST is what makes an optimizer, a type
checker and a second target possible, so it stays.

`-no-ast` is the second path: skip the tree and compile while reading the
tokens, deciding as it goes. Nothing is allocated per node, nothing is walked,
nothing is freed. That is where the rest of the distance to tcc's speed sits,
since tcc does the same and allocates almost nothing on the way. The intent for
this path is to beat tcc on the self-build rather than to match it, and the AST
path is the one that has to stay close to it.

The rule that keeps it honest: **the same input produces the same bytes on both
paths.** The AST path is the reference implementation and the streaming path is
a verified fast version of it, not a second compiler with its own opinions. Any
difference is a bug in the streaming path, and the comparison belongs in the
gate over the same corpus the tests use, not in a one-off experiment.

Sequencing: M3 first (a streaming emitter cannot exist before there is an
emitter), then the streaming path as an alternative front end feeding the same
back end, then the byte-for-byte comparison, and only then a number that claims
to beat tcc.

## M7: more targets, and debug info

The compiler describes its target in `backend/`: `arch/` is the machine, `os/`
is the system, `abi/` is the calling convention, and `backend.v` composes them.
A new machine is a module under `backend/arch` plus a line in the composition,
so this milestone grows by tables rather than by branches.

- arm64 Linux, then macOS and Windows. Each one is a back end and a linking
  story, not a flag.
- `-g` producing usable DWARF instead of being accepted and ignored.

Verified by compiling and running the corpora on each target, and by a debugger
reading the line table and the frame information a `-g` build writes.

## M8: the V self-build

The largest C input this tree knows. Four builds, each one a check on the step
before it:

```sh
v -cc tcc -o v-tcc cmd/v              # 1. V, built with the vendored tcc
v -cc tcc -o vcc-v1 .                 # 2. vcc, built by that V
v-tcc -cc ./vcc-v1 -o v-v2 cmd/v      # 3. V, built by vcc instead of tcc
./v-v2 -cc ./vcc-v1 -o vcc-v2 .       # 4. vcc, built by the V that vcc built
```

Steps 2 and 4 work today in the in-house form. `v -nocache -cc ./vcc -showcc -o
/tmp/self .` exits 0 and writes a compiler that runs, and that compiler builds
the C V emits for this tree: `vcc-v1 -c -std=gnu11 -w -o src.o src.c` exits 0
and writes 46,067,936 bytes, the size of the object the host writes for the same
file.

Step 3 is the one that cannot be faked: vcc has to compile every megabyte of C
V emits for itself, link it against libc and libgc, and produce a V that passes
V's own test suite. It is the strongest single test of the compiler rather than
the reason the compiler exists, and it is not done.

The chain is verified by running it on a clean checkout, running `v test` on the
V that step 3 produced, and comparing the behavior of `vcc-v2` with `vcc-v1` on
the same inputs. The chain then belongs in CI, because a fixed point that is not
continuously checked is a fixed point nobody has.

### What the chain found

Two defects are worth keeping in the record, because they are the kind of thing
only a large input finds.

A compiler built this way once wrote the wrong bytes where the section names
belong in the objects it writes: `.text`, `.rodata` and `.data` came out as the
bytes of the section contents. The image keys a string by the literal's own
bytes, the object writer built its name table from literals that spell the three
section keys, and the writable-data rewrite compared every reference's name
against those keys, so a reference to the literal `.text` was rewritten into a
reference to the code section. The comparison is by kind now: a key is compared
only against a reference whose kind names a place, and a `take_address` names an
interned entry whatever it spells.

Step 4 was once blocked by a compiler this tree built segfaulting on inputs
that make the collector run while the front end is working. The fault was in
libgcc's unwinder: `uw_update_context_1` took a general protection fault on a
`movaps` to its own frame because the sixteen-byte stack alignment the ABI
requires across a call was not there. The alignment was lost in a call this
compiler generated: a call whose arguments do not all fit in registers takes one
more word than it needs when the count of them is odd, and that word was taken
before the stacked arguments were evaluated. An argument that is itself a call
therefore ran with the reservation standing, eight bytes off. The fix is one
rule in `codegen/`. The measurement is a scanner that walks a function's control
flow tracking `rsp` modulo sixteen; the object for V's generated C had 2,337
call sites out of alignment before the fix and reports 0 after it.
`regression/iso/c99/0066-codegen-call-inside-a-stacked-argument.c` holds the
smallest shape.

## Later, and not yet planned

- A bootable Linux kernel. It is the hardest stress test a C compiler can be
  handed, and it would force what a userspace corpus never does: a freestanding
  build with no libc, inline assembly at the edges, section and alignment
  attributes, no red zone, the kernel code model, and a link driven by a script
  instead of start files. The freestanding target and `__asm__` in the tree are
  the beginning of that, and nothing today is arranged for the rest of it.
- Reproducible builds across hosts, beyond the same-input-same-bytes rule that
  already holds on one host.
- Diagnostics that carry a suggested fix, which needs a type checker that can
  tell why the program failed rather than only that it did.

## Not on the roadmap

- C++ beyond what C already provides.
- Being a build system, a package manager, or an IDE. vcc compiles C, links it,
  and exits.
- Written in anything but pure V.
