# Contributing

Thanks for helping. This project values behavioural fidelity to the reference
implementation above all else, then binary size, memory use and speed.

## Before you start

- Check the issue tracker; if you are reporting a compatibility bug, include the
  `.ws` program (or an `.asm` fixture) and the exact input.
- For anything larger than a typo, open an issue first so the approach can be
  agreed before you write code.

## Development setup

```console
$ zig version          # must be 0.17.0
$ zig build -Doptimize=ReleaseSafe
$ zig build test
$ ./tests/run.sh check
```

## Style

- `zig fmt build.zig src` must be clean; CI enforces `zig fmt --check`.
- Prefer small functions and explicit error handling. Do not add silent
  fallbacks, panics or `unreachable` on paths a program can reach.
- Keep the dependency count at zero. A new dependency needs a justification in the
  pull request that outweighs the size and maintenance cost.
- Comments explain *why*, especially where behaviour is inherited from the
  reference and looks wrong (the `slide`, `store` and parse-error semantics are
  the usual traps).

## Tests

Every behavioural change needs a case in `tests/cases/`, written in the readable
mnemonic form (see `tests/assemble.py` for the instruction table). Cases are
assembled and run by `tests/run.sh`.

- Expected stdout and exit status are recorded from the Haskell reference:
  `INTERPRETER=/path/to/haskell-wspace ./tests/run.sh record`.
- Deliberate deviations are marked with a `.zigonly` marker file and recorded from
  this interpreter instead: `./tests/run.sh record-zig`.
- Before opening a pull request, run
  `./tests/differential.sh /path/to/haskell-wspace ./zig-out/bin/wspace` and make
  sure nothing new differs.

### Building the reference interpreter

The vendored sources predate modern GHC; two imports need updating to compile with
GHC 9.x (this is a build-only change, semantics are untouched):

```console
$ cp wspace-0.3-original/*.hs /tmp/refbuild/
$ cd /tmp/refbuild
$ sed -i 's/^import IO$/import Prelude\nimport System.IO (hFlush, stdout)/' VM.hs
$ sed -i 's/import System(getArgs)/import System.Environment (getArgs)/' main.hs
$ ghc -O -o wspace-ref main.hs Input.hs VM.hs Tokens.hs
```

If `-lgmp` is missing on your system, point the compiler at the runtime library
(for example with `LIBRARY_PATH`).

## Commits and pull requests

- Use Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `ci:`, `perf:`,
  `chore:`), one logical change per commit.
- Describe the behaviour being changed and how it was verified; mention the
  reference result when compatibility is involved.
- Do not reformat unrelated code or reorder unrelated definitions in the same
  pull request.
- Do not include generated binaries or `zig-out/` output.

## Licensing of contributions

This project is GPL-2.0-or-later because it is a derivative of the 2003 Haskell
interpreter. By contributing you agree that your contribution is licensed under
the same terms. Do not paste code from projects with incompatible licenses.
