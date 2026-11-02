# Usage

## Command line

```
wspace FILE
```

`wspace` accepts exactly one argument, a path to a Whitespace program, and runs
it. This mirrors the reference interpreter, which also has no options.

| Invocation | Behaviour | Exit status |
| --- | --- | --- |
| `wspace program.ws` | runs the program | 0 on `end`, 1 on any error |
| `wspace` | prints the usage banner | 0 |
| `wspace a b` | prints the usage banner | 0 |
| `wspace missing.ws` | `wspace: missing.ws: FileNotFound` on stderr | 1 |
| `wspace --help` | tries to open a file named `--help` | 1 |

The banner is byte-identical to the reference, including its historical
"wspace 0.2 (c) 2003 Edwin Brady" title:

```
wspace 0.2 (c) 2003 Edwin Brady
-------------------------------
Usage: wspace [file]
```

Because the reference treats every single argument as a file name, so does this
interpreter. `--help` and `--version` are not options; parsing them as flags would
change observable behaviour.

## Input and output

- `output number` writes the decimal value with no trailing separator, using
  `-` for negatives.
- `output character` writes one Unicode code point encoded as UTF-8; values
  outside `0..0x10FFFF` and surrogate halves are an error.
- `read number` reads one line and stores the parsed decimal value at the heap
  address taken from the top of the stack. Surrounding ASCII whitespace and a
  leading `-` are accepted.
- `read character` reads one byte from stdin and stores its value at the heap
  address taken from the top of the stack.
- Input is read from stdin without buffering changes that would be visible to the
  program; output is written immediately, so prompts appear before a read blocks.
- End of file during a read is an error, exit status 1.

Both read instructions consume an address from the stack and write into the heap;
they do not push the value read. This matches the reference and the original
tutorial ("the read instructions take the heap address in which to store the
result from the top of the stack").

## Running the bundled examples

The examples in `wspace-0.3-original/examples/` are the programs shipped with the
reference implementation. Build first, then:

```console
$ zig build -Doptimize=ReleaseSmall
$ ./zig-out/bin/wspace wspace-0.3-original/examples/hworld.ws
Hello, world of spaces!
$ ./zig-out/bin/wspace wspace-0.3-original/examples/count.ws
1
2
...
10
$ printf '5\n' | ./zig-out/bin/wspace wspace-0.3-original/examples/fact.ws
Enter a number: 5! = 120
$ printf '3\n' | ./zig-out/bin/wspace wspace-0.3-original/examples/hanoi.ws
Enter a number: 1 -> 3
1 -> 2
3 -> 2
1 -> 3
2 -> 1
2 -> 3
1 -> 3
$ printf 'Ada\n' | ./zig-out/bin/wspace wspace-0.3-original/examples/name.ws
Please enter your name: Hello Ada
```

## Reading diagnostics

Failures print a single line to stderr and exit 1:

```
wspace: stack underflow (dup)
wspace: undefined label ( )
wspace: division by zero
wspace: heap address out of range (12)
wspace: invalid number on input (abc)
wspace: unrecognised instruction at byte 41
wspace: unexpected end of program in number literal at byte 88
wspace: instruction pointer out of range (117)
```

The wording differs from the GHC runtime's `wspace: user error (...)` /
`Prelude.!!: index too large` output by design; stdout and exit codes match the
reference exactly. See [compatibility.md](compatibility.md).

## Testing your interpreter build

```console
$ ./tests/run.sh check
$ ./tests/run.sh check            # after building a different mode
$ INTERPRETER=./zig-out/bin/wspace ./tests/run.sh check
```
