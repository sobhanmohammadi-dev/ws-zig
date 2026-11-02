# Building

## Toolchain

| Component | Version |
| --- | --- |
| Zig | **0.17.0** (exact; the build file declares `minimum_zig_version = "0.17.0"`) |
| Target | `x86_64-linux` (primary), Linux on any architecture Zig supports |
| libc | not used |
| External dependencies | none |

Install Zig from <https://ziglang.org/download/> and put `zig` on `PATH`.
Python 3 is needed only by the test suite's assembler, not by the interpreter.

## Commands

```console
$ zig build                                  # debug build → zig-out/bin/wspace
$ zig build -Doptimize=ReleaseSafe           # safety checks on, used by CI
$ zig build -Doptimize=ReleaseSmall          # smallest build; the shipped configuration
$ zig build -Doptimize=ReleaseFast           # fastest build
$ zig build run -- program.ws                # build and run
$ zig build test                             # unit tests
```

`-Doptimize=Debug` builds are large (about 3.3 MB) because they keep safety checks
and are not stripped; use a release mode for anything you measure or ship.

## Measured artifact sizes

Built with Zig 0.17.0 on Ubuntu 24.04 x86-64, `strip = true`, `single_threaded =
true`, no libc:

| Configuration | Size |
| --- | --- |
| `-Doptimize=ReleaseSmall` | 28,112 bytes |
| `-Doptimize=ReleaseFast` | 46,848 bytes |
| `-Doptimize=ReleaseSafe` | 233,680 bytes |
| `-Doptimize=Debug` | 3,332,109 bytes |

`file` reports `ELF 64-bit LSB executable, x86-64, statically linked, stripped`
and `ldd` reports `not a dynamic executable`. Section sizes for the shipped build
are roughly 26 KB of text and no initialised data; the large `bss` reported by
`size` is the default 8 MiB stack reservation, not memory the interpreter touches.

## Why `ReleaseSmall`

`ReleaseSmall` is the default recommendation: it is 40% smaller than
`ReleaseFast` while staying within a few percent on the benchmarks in
[docs/performance.md](performance.md). `ReleaseSafe` keeps integer/array safety
checks and costs about 200 KB, which makes it useful for fuzzing or debugging but
not for shipping.

## Cross-compilation

The build system accepts `-Dtarget=`, but `src/sys.zig` implements the platform
layer for Linux only and refuses to compile elsewhere with an explanatory
`@compileError`. Adding another target means adding `read`/`write`/`openat`/
`close` for it in that file; nothing else is platform-specific.

## Verifying a build

```console
$ ./tests/run.sh check                       # 36 conformance cases
$ ./tests/differential.sh /path/to/reference ./zig-out/bin/wspace
$ zig fmt --check build.zig src
```

The differential comparison needs the Haskell interpreter; see
[CONTRIBUTING.md](../CONTRIBUTING.md) for how to build it with a current GHC.
