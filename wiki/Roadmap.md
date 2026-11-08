# Roadmap

The compiler is usable today. This page is the short form of `ROADMAP.md`, the
file of record. Each milestone names how it is verified, and every one ends at
the same gate: the suite passes, the corpora pass, and wall time and peak
memory do not regress.

## Where the tree is

The whole pipeline runs in the tree: the preprocessor reads the glibc headers
on this machine, the front end reads the C those headers are made of, the back
end writes ELF64, and the linker merges units, reads objects and archives, and
writes executables, shared objects and static programs.

The runners count the evidence: 1,725 tests, 1,154 conformance cases and 126
regression cases. Self-compilation works: `v -nocache -cc ./vcc -o
/tmp/vcc-self .` exits 0, and the compiler it produces reports `vcc 0.0.3
(pure V)` and compiles a program that runs.

Speed is measured, not felt. Against the tcc V vendors, `tools/bench.vsh`
records vcc at 4.1x tcc's wall time and 8.7x its peak memory on a 2,000-term
constant chain, and 18.9x and 19.6x at 20,000 terms. The ratio grows with the
input because tcc's time is nearly flat while vcc's tracks the tokens and
nodes it allocates. That gap is the M6 problem.

## M0 to M4: the foundation, landed

M0 was the stub: a lexer for C's preprocessing tokens, a parser for the first
subset, an ELF64 writer whose output runs, and a diagnostic with a location for
every unsupported construct.

M1 was the preprocessor: `#include` with quoted and angle search paths,
object-like and function-like macros with `#` and `##`, variadic macros, the
full `#if` grammar, `#pragma once`, `#line`, `#error`, the `__DATE__`-class
macros, and real `-I`, `-D`, `-U`, `-nostdinc` and `-E`. It is checked against
`tcc -E` token by token.

M2 was the front end: declarations and declarators, structs, unions, enums,
typedefs, bitfields, `sizeof` and `alignof`, casts, compound literals,
designated initializers, `switch`, loops, `goto`, labels, variadic functions,
`_Bool` and the integer and floating types, and constant folding. It is checked
against generated C, the C in V's `thirdparty/`, programs from outside the
tree, and tcc and gcc's acceptance.

M3 was the x86-64 back end: instruction selection, register allocation, stack
frames and the SysV calling convention, global and thread-local storage,
sections, relocations, unwind tables, and the integer and floating point
semantics the standard requires. It is checked by running the programs.

M4 was objects and linking: ELF relocatable objects, an `ar` archive reader,
executable linking against libc, static and shared output, `-L`/`-l` search
order, `-shared`, `-r`, `-nostdlib`, `-Wl,` passthroughs and the crt start
files. It is checked by linking programs that use libc, libm, pthreads and dl
and running them.

## M5: the rest of the language

The dialect table records the constructs that are not implemented, and each one
becomes a row that changes status: `_Alignof` and `<stdalign.h>`'s `alignof`,
`_Noreturn`, C23 `constexpr`, the C23 keywords `bool`, `true`, `false` and
`nullptr`, the decimal floating types, and the `d` and `D` suffixes on floating
constants.

`_Imaginary` stays unimplemented on purpose: C99 makes the imaginary types
optional, and the type is deprecated and drafted for removal in C2y.

Verified by the conformance corpus, which gains a case with each row that
changes status, and by the compiler accepting the same program gcc accepts.

## M6: speed

The constraint rather than a stretch goal. TCC is fast because it is a
single-pass compiler with almost no intermediate representation, and vcc has to
be within reach of that on the workload that matters: the megabyte-scale
generated C of a V self-build.

The milestone carries phase timings from `-bench` tracked per commit, a
wall-time and peak-memory budget for the self-build checked in CI once the
number is stable, design choices that follow from the target, and parallel
compilation of translation units once the single-threaded path is fast.

Verified by the numbers, in every pull request that touches a hot path.

## M6a: two pipelines behind one command line

The default builds an AST and runs `optimizer/` over it; that path is where
correctness, the diagnostics and the tests live. `-no-ast` is the second path:
skip the tree and compile while reading the tokens, allocating nothing per
node. That is where the rest of the distance to tcc's speed sits, and the
intent is to beat tcc on the self-build rather than to match it.

The rule that keeps it honest: the same input produces the same bytes on both
paths, so the AST path stays the reference and the streaming path is a verified
fast version of it. Sequencing: the emitter first, then the streaming path as
an alternative front end feeding the same back end, then the byte-for-byte
comparison over the same corpus the tests use, and only then a number that
claims to beat tcc.

## M7: more targets, and debug info

The target description lives in `backend/`: `arch/` is the machine, `os/` is
the system, `abi/` is the calling convention. A new machine is a module under
`backend/arch` plus a line in the composition, so this milestone grows by
tables rather than by platform branches.

arm64 Linux, then macOS and Windows, each a back end and a linking story. And
`-g` producing usable DWARF instead of being accepted and ignored.

Verified by compiling and running the corpora on each target, and by a debugger
reading the line table and frame information a `-g` build writes.

## M8: the V self-build

The largest C input this tree knows, and the strongest single verification
available. Four builds, each one a check on the step before it.

```sh
v -cc tcc -o v-tcc cmd/v              # 1. V, built with the vendored tcc
v -cc tcc -o vcc-v1 .                 # 2. vcc, built by that V
v-tcc -cc ./vcc-v1 -o v-v2 cmd/v      # 3. V, built by vcc instead of tcc
./v-v2 -cc ./vcc-v1 -o vcc-v2 .       # 4. vcc, built by the V that vcc built
```

Steps 2 and 4 work today in the in-house form. Step 3 is the one that cannot be
faked: vcc has to compile the megabytes of C V emits for itself, link them
against libc and libgc, and produce a V that builds and passes V's own suite.
It is not done, and it is a test of the compiler rather than the reason the
compiler exists.

Verified by running the chain on a clean checkout, running `v test` on the V
that step 3 produced, and comparing the behavior of `vcc-v2` with `vcc-v1` on
the same inputs. The chain then belongs in CI, because a fixed point that is
not continuously checked is a fixed point nobody has.

## Later, and not yet planned

- A bootable Linux kernel. The hardest stress test a C compiler can be handed:
  freestanding with no libc, inline assembly, section and alignment attributes,
  no red zone, the kernel code model, and a link driven by a script rather than
  start files. The freestanding target and `__asm__` are the beginning of it;
  nothing today is arranged for the rest.
- Reproducible builds across hosts, beyond the same-input-same-bytes rule that
  already holds on one host.
- Diagnostics that carry a suggested fix, which needs a type checker that can
  tell why the program failed rather than only that it did.

## Not on the roadmap

- C++ beyond what C already provides.
- Being a build system, a package manager, or an IDE. vcc compiles C, links it,
  and exits.
- Written in anything but pure V.
