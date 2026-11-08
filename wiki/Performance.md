# Performance

## The target

Compile speed is part of what this compiler is for, not a stretch goal. tcc is
the bar, and the largest workload available here is the V self-build: a few
megabytes of generated C per run. Wall time and peak memory both count, and a
compiler that is correct but does not finish in a usable time is not a compiler
anyone will keep using.

`AGENTS.md` puts the same constraint in the tree: TCC-class speed, wall time
and peak RSS both, and never a speed improvement claimed from intuition. Speed
claims here are measurements, and the commands that produce them are printed
beside the numbers.

## How it is measured

`v run tools/bench.vsh` builds the tree under test rather than trusting a
binary lying around, generates a workload, and runs vcc and the tcc V vendors
on the same input. Wall time is the best of a few attempts and comes from the
clock around the whole call, which includes process startup. Peak memory comes
from `/usr/bin/time` for the attempt that was kept, since a peak from a slower
run belongs to a different measurement. Generated workloads are one function
returning a long constant expression, which is a workload both compilers
accept and one that grows with `--terms`.

The comparison tcc is found next to the `v` binary at
`thirdparty/tcc/tcc.exe`, or named with `--tcc PATH`. `--no-compare` runs vcc
alone. `tools/README.md` has the rest of the harness.

## The numbers

The numbers the repository records, from `README.md`, measured with
`v run tools/bench.vsh` against the tcc V vendors:

| terms | vcc wall | tcc wall | ratio | vcc peak | tcc peak | ratio |
|---|---|---|---|---|---|---|
| 2 000 | 23.2 ms | 5.7 ms | 4.1x | 27.0 MB | 3.1 MB | 8.7x |
| 20 000 | 127.9 ms | 6.8 ms | 18.9x | 62.5 MB | 3.2 MB | 19.6x |

The ratio grows with the input because tcc's own time barely moves, 5.7 ms to
6.8 ms across these two counts, while vcc's tracks the tokens and nodes it
allocates. That is a design problem and the M6 problem, not a constant factor
to trim. Each row is one run of `v run tools/bench.vsh`, with `--terms 20000`
for the second.

## The commands

```sh
v run tools/bench.vsh                       # generated workload, vcc against tcc
v run tools/bench.vsh --terms 20000         # a bigger generated workload
v run tools/bench.vsh --terms 100000 --runs 5
./vcc -bench file.c -o out                  # per-phase timings
/usr/bin/time -v ./vcc -o /tmp/out src.c    # wall time and peak RSS
```

`--terms N` sets the length of the generated constant chain and `--runs N` the
number of attempts. `./vcc -bench` reports microseconds per phase, which
`tools/README.md` notes are printed but not kept as a history across commits.
`.github/workflows/ci.yml` runs the harness and writes the numbers into the
run summary, and nothing fails on them yet: a shared runner's wall time is not
a budget to hold a pull request to. The self-compile runs in CI as a
correctness gate, not as a timed benchmark yet.

## What counts as a speed claim

A correctness-preserving change measured here is the only kind of speed claim
the tree accepts. The gate enforces the correctness half ([[The-Gate]]), and
ROADMAP M6 sets the budget: phase timings from `-bench` tracked per commit, a
wall-time and peak-memory budget for the V self-build measured against the
bundled tcc on the same machine, and design choices that follow from the
target, meaning a single pass over tokens, no full tree where a streaming
decision will do, arena allocation rather than per-node heap traffic, and
buffered output.

## The streaming path

The default pipeline builds an AST, because an optimizer, a type checker and a
second target are all built on one. `-no-ast` is the second path, planned:
skip the tree and compile while reading the tokens, deciding as it goes, with
nothing allocated per node, nothing walked and nothing freed. That is where
the rest of the distance to tcc's speed sits, since tcc does the same and
allocates almost nothing on the way. [[Architecture]] has the pipeline.

The rule that keeps the two honest is in ROADMAP M6a: the same input produces
the same bytes on both paths. The AST path is the reference implementation and
the streaming path is a verified fast version of it, not a second compiler
with its own opinions. Any difference is a bug in the streaming path, and the
comparison belongs in the gate over the same corpus the tests use. The
sequencing is the emitter first, then the streaming path as an alternative
front end feeding the same back end, then the byte-for-byte comparison, and
only then a number that claims to beat tcc. [[Roadmap]] has the milestones.

## The long-input case

Long input is a test case. The one crash this tree has had was a fold that
recursed once per term in an operator chain and took the stack out at about
three thousand terms; `v run tools/bench.vsh --terms 20000` is what found it.
A phase is run on input that is large rather than only on input that is
interesting, and a deep structure counts against a limit the author chose
rather than against the stack.
