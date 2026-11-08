# Interop

vcc can be handed to V as the C compiler for a V build. This page records what
V expects of that binary, as this repository reads the V tree. Nothing here is
required to use vcc as an ordinary C compiler.

The classification rules, the version strings, the caching and the archive
named below are recorded in this repository's
[README.md](https://github.com/HuntedByTheIRS/vcc/blob/main/README.md) and
[CONTRIBUTING.md](https://github.com/HuntedByTheIRS/vcc/blob/main/CONTRIBUTING.md).
They are this repository's reading of V, not a copy of V's code. The authority
is V's own source, `vlib/v/driver/driver.v` and `vlib/v/pref/pref.v`; where this
page and that source disagree, the source wins.

## How V classifies a compiler

V resolves the compiler name from the real path of the binary. A name holding
`tcc` or `tinyc` is classified as `tinyc` immediately. Otherwise V runs the
binary with `--version` and looks for `tiny c compiler` or `tcc version` in the
output. The answer decides which flags V passes and which shape of C it emits.
That is why vcc's version line matters beyond cosmetics: a line V does not
recognize puts the binary in a different class and changes what V asks of it.

The authority for the exact classification is `effective_c_compiler_name` in
[vlib/v/driver/driver.v](https://github.com/vlang/v/blob/master/vlib/v/driver/driver.v)
and `ccompiler_can_assemble` in
[vlib/v/pref/pref.v](https://github.com/vlang/v/blob/master/vlib/v/pref/pref.v).
This repository records the rules above rather than restating that code as a
settled fact.

## Identity and caching

V caches artifacts keyed on that identity and compares the compiler against the
default `cc`. Two consequences follow for a compiler used in this position. The
version output has to be stable and machine-parseable, because a line that
changes between runs changes the cache key or the class. And integration tests
run from a clean cache, because a stale artifact under the old identity hides a
classification change.

vcc answers `--version` from one source. `cli/cli.v` sets `version` from the
`v.mod` text embedded in the binary at compile time (`@VMOD_FILE`), so a
binary copied somewhere without its source still answers, and `version_line()`
prints `vcc <version> (pure V)`. `v.mod` names the version once. A change to
that line changes what V thinks this binary is, which is why the repository
asks that the V source line justifying such a change be named in the commit
body.

## The archive a tcc build links

The tcc V vendors carries a garbage collector. V links it into every tcc build
from `thirdparty/tcc/lib/libgc.a`, so a compiler used in its place has to be
able to link an archive against the program it just compiled. A compiler that
cannot link the archive cannot build V. `v -showcc -cc tcc probe.v` prints the
whole command V would run, which is the list to match. The vendored tree lives
in V's repository, not in this one; vcc does not vendor it.

## The V self-build

Four builds, each one a check on the step before it, in `ROADMAP.md` M8:

```sh
v -cc tcc -o v-tcc cmd/v              # 1. V, built with the vendored tcc
v -cc tcc -o vcc-v1 .                 # 2. vcc, built by that V
v-tcc -cc ./vcc-v1 -o v-v2 cmd/v      # 3. V, built by vcc instead of tcc
./v-v2 -cc ./vcc-v1 -o vcc-v2 .       # 4. vcc, built by the V that vcc built
```

Steps 2 and 4 work today in the in-house form: `v -nocache -cc ./vcc -o
/tmp/vcc-self .` exits 0, and the compiler it produces runs and compiles a
program. Step 3 is the one that cannot be faked: vcc has to compile every
megabyte of C V emits for itself, link it, and produce a V that passes V's own
test suite. It is the strongest single test of the compiler and it is still
open.

[[Building]] has the build steps, [[Roadmap]] has the milestones, and
[[The-Gate]] is the set of checks a pull request passes.

## What V asks on the command line

V passes the flags of the compiler it classified. vcc accepts the flags V
passes to a C compiler (`-std=gnu11`, `-std=c99`, `-fwrapv`, `-fPIC`, `-g`,
`-w`, `-Werror=implicit-function-declaration`, `-bt25`, `-B<dir>`, `-I<dir>`,
`-L<dir>`, `-l<name>`, `-Wl,` passthroughs, `-D` defines), plus the
preprocessor's own flags and `--version`. A flag it does not implement is
recorded and never refused, because V passes flags for work it expects done
and a compiler that errors on `-bt25` fails a build it was meant to serve.

The extensions V's generated C uses (`typeof`, `__int128`, the atomic
builtins, statement expressions, `__attribute__`) are in the dialect table
because that C uses them, not because they were easy. [[C-Support]] has the
dialect side. [[Pure-V]] has the one exception to the linking rule,
`-external-linker=NAME`, which refuses `cc`, `gcc`, `clang`, `c++` and `tcc`
by name, because a C compiler finishing C compilation is the one thing that
rule exists to prevent.

## Reading the authority

The repository's `CONTRIBUTING.md` points anyone touching interop at V's source:

```sh
cd /path/to/v
grep -n "effective_c_compiler_name" -A 45 vlib/v/driver/driver.v
grep -n "ccompiler_can_assemble" -A 25 vlib/v/pref/pref.v
grep -n "ccompiler\b" vlib/v/driver/driver.v | head
```

A change to `--version`, or to how a flag is accepted, changes what V thinks
this binary is. Say which V source line justifies the change in the commit
body.
