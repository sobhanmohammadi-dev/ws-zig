# Architecture

The interpreter is a single-threaded batch program: read a file, decode it, run
it, exit. The design follows from that and from the size and memory goals, not
from general-purpose virtual-machine patterns.

## Pipeline

```
source bytes ──decode──▶ []Instr + labels ──execute──▶ stdout
                              │
                              └─ optional deferred parse error
```

There is no token array, no AST and no intermediate buffer of decoded operands:
`src/parse.zig` walks the raw file bytes, skips every byte that is not space, tab
or line feed, and appends one instruction per decoded operation.

## Instruction representation

```zig
pub const Instr = union(enum) {
    push: i64,
    dup,
    copy: i64,
    slide: i64,
    swap,
    discard,
    add, sub, mul, div, mod,
    store, retrieve,
    label: u32, call: u32, jump: u32, jump_zero: u32, jump_negative: u32,
    ret,
    out_char, out_num, read_char, read_num,
    end,
};
```

A tagged union keeps the payload and the tag together in 16 bytes, so a decoded
program costs 16 bytes per instruction and dispatch is a single `switch` with no
virtual calls. Label operands are 32-bit indices into a label table rather than
strings or pointers, which keeps jumps cheap and instructions small.

## Labels

A label is a sequence of space and tab tokens ending in a line feed. During
decoding each distinct label name is interned into a table of
`{ name, first_position }`; duplicates resolve to the first definition, which is
what the reference's linear `findLabel'` scan does. Interning uses a linear scan
because real programs have a handful of labels and a hash map would cost more
code than it saves.

Interning happens at decode time, so execution never compares label strings:
`call`/`jump`/`if zero`/`if negative` look up `label_table[id].pos`, and an
undefined label is an error at the moment the instruction executes — matching the
reference, which only fails when it runs the instruction.

## Deferred parse errors

The reference decodes lazily: `parse` is only evaluated as far as the program
counter reaches, so trailing garbage after an `end` is never examined, and a
malformed instruction fails when it is executed rather than when the file is
loaded. A flat decode would normally turn that into an up-front error.

Instead, decoding stops at the first malformed instruction, records
`{ kind, offset }`, and keeps the successfully decoded prefix. Execution reports
the recorded error only when the program counter runs past the end of that
prefix. Observable behaviour therefore matches the reference for both "garbage
after end" and "garbage reached during execution".

## Execution

`Vm.run` is a `while (true)` loop around `prog[pc]`, incrementing `pc` before
dispatching so that `call` pushes the return address the reference would push.
There is no recursion anywhere: a Whitespace program with a million-deep call
stack consumes heap for the call stack, not process stack, so it cannot overflow
the host stack and cannot crash the interpreter.

Operand order follows the reference exactly. In particular `store` takes the
address from the second stack slot and the value from the top, `div`/`mod` use
Zig's `@divFloor`/`@mod` (the same rounding as Haskell's `div`/`mod`), and
`slide` tolerates an argument larger than the stack because Haskell's `drop` is
total.

## Memory

| Allocation | Owner | Lifetime |
| --- | --- | --- |
| Decoded instructions, label table, label names | one `ArenaAllocator` over `page_allocator` | the whole run, freed in `main` |
| Value stack, heap, call stack, input line buffer | `page_allocator` directly, via `std.ArrayList` | the whole run, freed in `Vm.deinit` |

Decoding is the only phase that allocates many small objects, so it uses an arena
and pays a single free at exit. The runtime structures use the page allocator
directly so that growth (`realloc`) returns memory instead of accumulating dead
blocks in the arena. The heap is a dense `[]i64` padded with zeros up to the
highest address written, mirroring the reference's list heap; retrieving beyond
it is an error, exactly as `heap !! n` fails there.

No allocation happens per instruction: pushing checks capacity and grows
amortised, output is written straight to a file descriptor, and formatting uses
fixed stack buffers.

## Platform layer

`src/sys.zig` binds `read`, `write`, `openat` and `close` to Linux syscalls. Zig
0.17 routes portable I/O through `std.Io`, which brings in thread and event-loop
machinery that a batch interpreter never uses; binding the four syscalls directly
keeps the binary at 28 KB and removes libc entirely. The trade-off is explicit:
this version targets Linux only, and `sys.zig` fails to compile elsewhere with a
clear message rather than pretending to support it.

## Error handling

Errors are values, not panics: the VM returns `error{Runtime}` after writing a
`wspace: ...` diagnostic to stderr. Malformed programs — stack underflow, bad
heap addresses, division by zero, undefined labels, truncated input — therefore
end with exit status 1 and a message, never with a trap, a hang or undefined
behaviour. The two places where arithmetic could trap in Zig (`div`/`mod` by
zero, `INT64_MIN / -1`) are checked explicitly.
