# Compatibility

The behavioural reference is the Haskell `wspace` 0.3 implementation vendored in
`wspace-0.3-original/`. Everything in this document was checked by running both
interpreters, not inferred from the specification.

## How compatibility is verified

1. The reference was built with GHC 9.10.1 (`-O`). Two 2003-era imports had to be
   updated to compile — `import IO` → `Prelude` plus `System.IO`, and
   `System(getArgs)` → `System.Environment (getArgs)`. Those are build fixes; the
   semantics are untouched.
2. `tests/run.sh record` runs every fixture and every bundled example through the
   reference and stores stdout and exit status in `tests/expected/`.
3. `tests/run.sh check` runs this interpreter against those recorded values.
4. `tests/differential.sh` runs both interpreters side by side over all cases and
   examples, with inputs, and compares stdout and exit status directly.

Current result: **36 of 36 conformance cases pass** and **33 of 33 differential
comparisons are identical** (three deliberate deviations are excluded and
documented below).

## Instruction set

All v0.3 instructions are implemented with the reference's operand order and
stack effects:

| Mnemonic | Encoding | Notes |
| --- | --- | --- |
| `push n` | `SS n` | sign token then magnitude, most significant bit first |
| `copy n` | `SBS n` | push a copy of the nth value below the top |
| `slide n` | `STN n` | remove n values below the top |
| `dup` / `swap` / `discard` | `SNS` / `SNT` / `SNN` | |
| `add` / `sub` / `mul` | `TSSS` / `TSST` / `TSSN` | second-from-top op top |
| `div` / `mod` | `TSTS` / `TSTT` | floor rounding, sign of divisor for `mod` |
| `store` / `retrieve` | `TTS` / `TTT` | address below value |
| `label` / `call` / `jump` | `NSS` / `NST` / `NSN` | label is space/tab tokens |
| `if zero` / `if negative` | `NTS` / `NTT` | jump when the popped value matches |
| `return` / `end` | `NTN` / `NNN` | |
| `output character` / `output number` | `TNSS` / `TNST` | |
| `read character` / `read number` | `TNTS` / `TNTT` | address from stack, value into heap |

## Reference behaviours preserved

These are unusual, and all of them are intentional in this port:

- **Non-whitespace bytes are ignored**, including carriage returns. Files with
  CRLF line endings work because `\r` is dropped; a file using only CR as its line
  terminator has no instructions at all.
- **Numbers are sign-then-magnitude**, most significant bit first, terminated by a
  line feed. A literal with no sign token (`push` followed directly by the
  terminator) is an error, as `makeNumber []` is in the reference.
- **`slide` is total**: a slide deeper than the stack keeps only the top value, and
  a negative slide removes nothing. Only an empty stack is an error.
- **`div` and `mod` round towards negative infinity**: `-7 div 2` is `-4` and
  `-7 mod 2` is `1`, `7 mod -2` is `-1`. C-style truncation would differ.
- **The heap grows with zeros** up to the highest address written; reading an
  address that was never written returns 0.
- **Labels resolve to the first definition** when a name is duplicated.
- **Parse errors are lazy**: malformed code after an `end` is never reported,
  because the reference never evaluates that part of the program.
- **Running past the end of the program is an error**, including for an empty file.
- **Output characters are Unicode code points encoded as UTF-8**; `output number`
  writes decimals with no trailing newline.
- **The usage banner and argument handling** are reproduced byte for byte, and a
  wrong argument count exits 0.

## Deliberate deviations

Three, all recorded as `.zigonly` test cases:

1. **Values are 64-bit two's complement**, not Haskell `Integer`. Any program whose
   intermediate values fit in 64 bits behaves identically; arithmetic that would
   exceed that wraps instead of growing. This is the size/performance trade-off
   chosen for this port.
2. **`read number` accepts decimal only.** The reference uses `read :: Integer`,
   which also accepts `0x`/`0o` literals and parenthesised negatives. A negative
   decimal input such as `-5` works in both.
3. **A negative heap address is an error.** The reference recurses forever in
   `store x (-1) []`, i.e. it hangs; this interpreter reports
   `wspace: negative heap address (-1)` and exits 1.

Two further differences are observable only at the edges:

- **Diagnostics** are printed as `wspace: <message>` with exit status 1, instead of
  GHC's `wspace: user error (...)` plus call stack. Exit codes match; wording does
  not.
- **`read character` reads one byte**, so non-ASCII input yields the byte value
  rather than a decoded code point. For ASCII input, which is what Whitespace
  programs use in practice, behaviour is identical.

## Platform notes

The interpreter produces the same stdout bytes and exit codes on Linux, macOS and
Windows; the conformance suite runs on all three in CI.

- Linux uses raw syscalls; macOS uses libSystem; Windows uses the C runtime with
  its standard streams switched to binary mode, so `\n` is never rewritten to
  `\r\n`.
- Program paths are transcoded to UTF-16 on Windows, so non-ASCII paths work.
- Console output is written as UTF-8 bytes. A Windows console may render them
  according to its active code page; redirecting to a file or pipe yields the
  exact bytes the Unix builds produce.
- `read character` returns a byte value, so multi-byte input is reported one byte
  at a time on every platform.

## Exit status

| Situation | Reference | This interpreter |
| --- | --- | --- |
| Program reaches `end` | 0 | 0 |
| Wrong number of arguments | 0 | 0 |
| Missing/unreadable file | 1 | 1 |
| Runtime error (underflow, undefined label, division by zero, EOF) | 1 | 1 |
| Malformed instruction reached | 1 | 1 |
| Malformed instruction after `end` | not evaluated | not evaluated |
