# Building

## Toolchain

| Component | Version |
| --- | --- |
| Zig | **0.17.0** (exact; the build file declares `minimum_zig_version = "0.17.0"`) |
| Targets | Linux, macOS, Windows on x86-64 and ARM64 |
| External dependencies | none |

Install Zig from <https://ziglang.org/download/> and put `zig` on `PATH`.
Python 3 is needed only by the test suite's assembler, not by the interpreter.

## Commands

```console
$ zig build                                  # debug build → zig-out/bin/wspace
$ zig build -Doptimize=ReleaseSafe           # safety checks on
$ zig build -Doptimize=ReleaseSmall          # smallest build; the shipped configuration
$ zig build -Doptimize=ReleaseFast           # fastest build
$ zig build run -- program.ws                # build and run
$ zig build test                             # unit tests
$ make dist                                  # all six targets, into dist/
```

`-Doptimize=Debug` builds are large (about 3.3 MB) because they keep safety checks
and are not stripped; use a release mode for anything you measure or ship.

## Supported platforms

The three platform backends live in `src/sys.zig` and are selected at compile
time. Only the operations the interpreter needs are bound: read a file, read
stdin, write stdout and stderr.

| Target | I/O backend | `ReleaseSmall` size |
| --- | --- | --- |
| `x86_64-linux` | raw Linux syscalls, no libc | 28,000 bytes |
| `aarch64-linux` | raw Linux syscalls, no libc | 27,472 bytes |
| `x86_64-macos` | libSystem | 37,704 bytes |
| `aarch64-macos` | libSystem | 68,568 bytes |
| `x86_64-windows` | C runtime (`_wopen`, `_read`, `_write`) | 91,648 bytes |
| `aarch64-windows` | C runtime (`_wopen`, `_read`, `_write`) | 39,424 bytes |

Linux is the only target that avoids libc entirely, because it is the only one
with a stable raw-call ABI for these operations. Any other target stops the build
with an explicit message from `src/sys.zig` rather than producing a binary that
silently misbehaves.

Windows builds switch the standard streams to binary mode at startup, so program
output is byte-identical to the Unix builds and is not subject to `\n` to `\r\n`
translation.

```console
$ zig build -Doptimize=ReleaseSmall -Dtarget=aarch64-macos --prefix dist/aarch64-macos
$ zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-windows --prefix dist/x86_64-windows
```

Path arguments are transcoded to UTF-16 on Windows, so non-ASCII program paths
work. Console output is written as UTF-8 bytes, which a Windows console may
render according to its active code page; redirecting to a file or pipe gives the
exact bytes.

## Measured artifact sizes

Built with Zig 0.17.0 on Ubuntu 24.04 x86-64, `strip = true`, `single_threaded =
true`:

| Linux configuration | Size |
| --- | --- |
| `-Doptimize=ReleaseSmall` | 28,160 bytes |
| `-Doptimize=ReleaseFast` | 46,784 bytes |
| `-Doptimize=ReleaseSafe` | 233,840 bytes |
| `-Doptimize=Debug` | 3,340,962 bytes |

`file` reports `ELF 64-bit LSB executable, x86-64, statically linked, stripped`
and `ldd` reports `not a dynamic executable`. The large `bss` that `size` shows is
the default 8 MiB stack reservation, not memory the interpreter touches.

## Why `ReleaseSmall`

`ReleaseSmall` is the default recommendation: it is much smaller than
`ReleaseFast` while staying within a few percent on the benchmarks in
[docs/performance.md](performance.md). `ReleaseSafe` keeps integer/array safety
checks and costs about 200 KB, which makes it useful for fuzzing or debugging but
not for shipping.

## Verifying a build

```console
$ ./tests/run.sh check                       # 36 conformance cases
$ ./tests/differential.sh /path/to/reference ./zig-out/bin/wspace
$ zig fmt --check build.zig src
```

The differential comparison needs the Haskell interpreter; see
[CONTRIBUTING.md](../CONTRIBUTING.md) for how to build it with a current GHC.
