# wspace — a Whitespace v0.3 interpreter in Zig

A complete, dependency-free reimplementation of the Whitespace v0.3 interpreter
originally written in Haskell by Edwin Brady, rewritten from scratch in Zig with
executable size, memory use and execution speed as first-class constraints.

The final binary is **28 KB**, statically linked, stripped, and links against no
C library and no third-party code.

```console
$ zig build -Doptimize=ReleaseSmall
$ ./zig-out/bin/wspace wspace-0.3-original/examples/hworld.ws
Hello, world of spaces!
```

## What is Whitespace?

Whitespace is an esoteric programming language from 2003 in which space, tab and
line feed are the only meaningful characters; everything else is a comment. It is
a stack machine with a heap, labels, subroutines and character/number I/O. The
bundled `docs/tutorial.html` is the original language tutorial, and
`wspace-0.3-original/` holds the reference implementation this project is
compatible with.

## Features

- Complete Whitespace **v0.3** instruction set, including the `copy` (nth) and
  `slide` stack operations that distinguish 0.3 from earlier drafts.
- Behaviour preserved from the reference implementation, including its less
  obvious corners: floor-rounded `div`/`mod`, `slide` tolerating depths beyond
  the stack, zero-padded heap growth, first-definition-wins labels, and parse
  errors that are only reported if execution reaches them.
- Byte-identical stdout and identical exit codes to the reference across the
  whole test suite and all seven bundled example programs.
- No dependencies. No libc. No runtime framework. One static binary.
- Clean diagnostics instead of GHC runtime dumps, with exit code 1 on failure.
- Iterative execution — no host-stack recursion, so deep Whitespace call stacks
  cannot overflow the process stack.

## Supported language version

Whitespace **v0.3**, exactly the instruction set implemented by `wspace` 0.3:

| Group | Instructions |
| --- | --- |
| Stack | `push`, `copy` (duplicate nth), `slide`, `dup`, `swap`, `discard` |
| Arithmetic | `add`, `sub`, `mul`, `div`, `mod` |
| Heap | `store`, `retrieve` |
| Flow | `label`, `call`, `jump`, `if zero`, `if negative`, `return`, `end` |
| I/O | `output character`, `output number`, `read character`, `read number` |

There is no `copy`-free variant and no extension beyond the reference: anything
the reference cannot run, this interpreter does not run either (see
[docs/compatibility.md](docs/compatibility.md) for the three deliberate
deviations).

## Installation

Prebuilt binaries are not published yet; build from source. You need Zig
**0.17.0** — the exact version this project is developed and tested against —
and nothing else. Python 3 is required only to run the test suite's assembler.

```console
$ git clone https://github.com/sobhanmohammadi-dev/ws-zig
$ cd wspace
$ zig build -Doptimize=ReleaseSmall
$ install -m 0755 zig-out/bin/wspace ~/.local/bin/wspace
```

## Building

```console
$ zig build                                  # debug build
$ zig build -Doptimize=ReleaseSafe            # safe build, used by the tests
$ zig build -Doptimize=ReleaseSmall          # smallest release build
$ zig build -Doptimize=ReleaseFast           # fastest release build
$ zig build run -- program.ws                # build and run a program
```

Full details, including the exact recorded sizes, are in
[docs/building.md](docs/building.md).

## Usage

```console
$ wspace program.ws          # run a program
$ wspace                     # print the usage banner
```

Exactly one argument is accepted, matching the reference interpreter. There are
no options: no `--help`, no `--version`, no flags. When the argument count is
wrong the banner is printed and the exit status is 0; when a program fails, the
diagnostic goes to stderr and the exit status is 1.

```console
$ printf '5\n' | ./zig-out/bin/wspace wspace-0.3-original/examples/fact.ws
Enter a number: 5! = 120
```

See [docs/usage.md](docs/usage.md) for input semantics, exit codes and the
bundled examples.

## Testing

```console
$ zig build test                 # unit tests for the decoder
$ ./tests/run.sh check           # conformance suite (36 cases, reference-recorded)
$ ./tests/differential.sh /path/to/haskell-wspace ./zig-out/bin/wspace
```

The conformance expectations in `tests/expected/` were recorded from the actual
Haskell reference interpreter, built with GHC 9.10.1, so the suite checks
compatibility rather than self-consistency. The differential script runs both
interpreters over every case and example and compares stdout and exit status.

## Performance and binary size

Measured on Ubuntu 24.04, x86-64, Zig 0.17.0, median of three runs:

| Binary | Size |
| --- | --- |
| `ReleaseSmall` (shipped configuration) | **28,112 bytes** |
| `ReleaseFast` | 46,848 bytes |
| `ReleaseSafe` | 233,680 bytes |
| Haskell reference (GHC 9.10.1, `-O`) | 2,772,608 bytes |

| Benchmark | Reference | This interpreter |
| --- | --- | --- |
| 2,000,000-iteration arithmetic loop | 582.9 ms | **62.2 ms** |
| 20,000-iteration loop after 8,000 instructions | 7,960.7 ms | **3.1 ms** |
| 5,000 pushes then 5,000 discards | 340.7 ms | **1.8 ms** |

The large gap on the second benchmark is structural: the reference fetches
instructions with `program !! pc`, which is linear in the instruction pointer,
so execution cost grows with program size. This implementation decodes once into
a flat array and indexes it in constant time.

Memory: peak resident set is below 0.4 MiB for typical programs (the Haskell
binary sits at 3.6–8.1 MiB), and 14.5 MiB for a deliberately huge 400,000
instruction program whose decoded form alone is 6.4 MiB.

Method, caveats and reproduction commands: [docs/performance.md](docs/performance.md).

## Architecture

Three source modules, no frameworks:

- `src/parse.zig` — reads tokens straight from the source bytes and decodes them
  into a flat `[]Instr` array, interning labels and recording the first
  definition of each. Malformed code is remembered, not raised.
- `src/vm.zig` — an iterative `pc` loop over a 16-byte tagged-union instruction
  representation, with growable value stack, zero-padded heap, call stack, and
  unbuffered input/output.
- `src/sys.zig` — the only platform layer: `read`, `write`, `openat`, `close`
  bound directly to Linux syscalls, keeping libc and the standard library's I/O
  machinery out of the binary.
- `src/main.zig` — argument handling, file loading, exit codes.

See [docs/architecture.md](docs/architecture.md) for the data structures, memory
ownership and the reasoning behind each choice.

## Project structure

```
build.zig, build.zig.zon     build definition and package manifest
src/                         interpreter (4 modules)
src/tests.zig                decoder unit tests (zig build test)
tests/                       assembler, conformance runner, differential runner
tests/cases/                 readable .asm fixtures and their stdin
tests/expected/              stdout and exit status recorded from the reference
bench/                       benchmark programs and measurement helpers
docs/                        architecture, building, usage, compatibility, performance
wspace-0.3-original/         the original Haskell implementation (reference)
```

## License and provenance

This project is a derivative work of **wspace 0.3**, Copyright (C) 2003
Edwin Brady, which is distributed under the GNU General Public License, version 2
or (at your option) any later version. A rewrite in another language does not
remove those obligations, so this repository is distributed under the same terms:
**GPL-2.0-or-later**. `LICENSE` contains the verbatim GPL v2 text taken from the
original project's `COPYING`, and the unmodified reference sources remain in
`wspace-0.3-original/` with their copyright headers intact.

The Zig implementation is an independent rewrite: no Haskell code is executed at
build time or run time, and the binary contains no Haskell runtime.

## Contributing

Bug reports, compatibility findings and pull requests are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md). Behaviour changes must come with a test case
and, where the reference can run it, a differential result.

## Acknowledgements

- Edwin Brady, for Whitespace and the original `wspace` interpreter (2003).
- The GHC maintainers, for a reference implementation that can still be compiled
  and used as a behavioural oracle twenty years later.
