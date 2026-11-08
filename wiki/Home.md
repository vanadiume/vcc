# Home

vcc is a general-purpose C compiler for Linux x86-64, written in V. It has its
own preprocessor, parser, optimizer, code generator and linker, and writes
ELF64 executables, relocatable objects, shared objects and static programs. It
is BSD 3-Clause and adds no dependency to `v.mod`.

## Two constraints

**Pure V.** No C source in the compiler, no part of the pipeline handed to a C
compiler, no vendored C library. If a piece cannot be written in V yet, it
stays unimplemented and the construct is refused with a diagnostic rather than
worked around. There is one exception, named and off by default:
`-external-linker=NAME` hands the final link to a linker already on the
system, for the inputs vcc cannot consume yet, such as an object carrying a
relocation the reader does not model. It refuses `cc`, `gcc`, `clang`, `c++`
and `tcc` by name, because a C compiler finishing C compilation is the one
thing the rule exists to prevent.

**Speed.** Compile speed is part of what the compiler is for. tcc is the bar,
and the largest workload available here is the V self-build: a few megabytes of
generated C. Wall time and peak memory are measured, never guessed, and the
command that produced a number is printed beside it.

## Where the tree is today

A working compiler for a very large subset of Linux x86-64 C. The preprocessor
is real, the front end reads what a real header is made of and the function
definitions after it, and the back end writes a dynamically linked executable
that calls into libc, so `#include <stdio.h>` and `puts` work end to end. `-c`
writes a real ELF64 relocatable object, `-shared` writes a shared object, and
`-static` writes a static program. The in-house linker merges translation
units, reads objects and `ar` archives, and refuses an unresolved import by
name.

The runners count the evidence: 1,725 tests, 1,154 conformance cases across
the C dialects, and 126 regression cases. `README.md` carries the detail, and
[[C-Support]] has the language side.

What is not there: other targets (arm64, macOS and Windows), debug information
behind `-g`, a few standard constructs such as `_Alignof`, `_Noreturn`, C23
`constexpr`, the C23 `bool`/`true`/`false`/`nullptr` keywords and the decimal
types, and the speed gap to tcc. vcc also compiles the C V generates from
vcc's own source, but V itself built by vcc and passing V's suite is still
open. [[Performance]] covers the speed question.

## The V toolchain

vcc started inside V's toolchain and can still be handed to V as its C
compiler. That compatibility is maintained and documented in [[Interop]]; it is
not a requirement for using vcc.

## The wiki

- [[Building]] for the toolchain, the pinned V commit and the ways to run the
  compiler.
- [[Architecture]] for how the pipeline is put together and where a new target
  goes.
- [[The-Gate]] for the checks a change has to pass.
- [[Pure-V]] for the rule and its one exception.
- [[C-Support]] for what the compiler reads today and what it refuses.
- [[Performance]] for the benchmark, the numbers and the speed target.
- [[Roadmap]] for the milestones and what verifies each one.
- [[Community]] for where to ask, where to report and the house rules.
- [[Interop]] for what V asks of a C compiler and how vcc answers.
