# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-11-02

Cross-platform release.

### Added

- macOS (x86-64, ARM64) and Windows (x86-64, ARM64) builds from the same source.
  macOS I/O goes through libSystem and Windows through the C runtime, selected at
  compile time; Linux keeps its raw syscall path and remains libc-free.
- `make dist` builds all six targets into `dist/`.
- Windows standard streams are set to binary mode, so output is byte-identical to
  the Unix builds rather than CRLF translated.
- Windows program paths are transcoded to UTF-16, so non-ASCII paths work.
- CI matrix building and running the conformance suite on Linux, macOS and
  Windows, plus a tag-triggered release workflow that publishes archives for all
  six targets.

### Changed

- `src/sys.zig` rejects targets it has no backend for with an explicit compile
  error instead of assuming Linux.

## [0.1.0] - 2026-11-02

Initial release: a complete rewrite of the Whitespace v0.3 interpreter in Zig.

### Added

- Decoder for the full Whitespace v0.3 instruction set, reading tokens directly
  from source bytes and interning labels with first-definition-wins semantics.
- Iterative execution engine with a 16-byte tagged-union instruction
  representation, growable value stack, zero-padded heap and explicit call stack.
- Reference-compatible arithmetic: floor-rounded `div`/`mod`, wrapping 64-bit
  operands, division-by-zero detection.
- Character and number I/O with UTF-8 output, byte-oriented character input and
  decimal number input, storing results through a heap address taken from the
  stack.
- Deferred parse errors, so malformed code after `end` is never reported, matching
  the reference's lazy parser.
- CLI reproducing the reference's single-argument handling and usage banner.
- Linux syscall layer (`read`, `write`, `openat`, `close`); no libc, no
  dependencies.
- Unit tests for the decoder, 33 reference-recorded conformance cases covering
  every instruction and error path, and a differential harness that compares this
  interpreter with the Haskell original.
- Benchmark programs and measurement helpers.

### Known deviations

- Values are 64-bit two's complement rather than arbitrary-precision integers.
- `read number` accepts decimal input only.
- A negative heap address reports an error instead of hanging.
- Diagnostics use `wspace: <message>` rather than the GHC runtime's wording.

See [docs/compatibility.md](docs/compatibility.md).
