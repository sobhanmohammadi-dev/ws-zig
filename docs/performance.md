# Performance

## Method

- Machine: Cloud Linux VM, Ubuntu 24.04.5, x86-64.
- Compiler: Zig 0.17.0, `-Doptimize=ReleaseSmall` unless stated.
- Reference: the Haskell implementation in `wspace-0.3-original/`, built with
  GHC 9.10.1 and `-O`.
- Wall time: `bench/run.py`, median of three runs, stdout discarded.
- Peak memory: `VmHWM` sampled from `/proc/<pid>/status` every millisecond.
  Programs that finish faster than the first sample report below the method's
  resolution, which is why some rows are marked `< 0.4 MiB` rather than a number.

Reproduce with:

```console
$ zig build -Doptimize=ReleaseSmall
$ for p in loop wide stack_small stack; do python3 tests/assemble.py bench/$p.asm bench/$p.ws; done
$ python3 bench/run.py /tmp/wspace-ref bench/loop.ws 3
$ python3 bench/run.py ./zig-out/bin/wspace bench/loop.ws 3
```

## Binary size

| Configuration | Bytes | Ratio to reference |
| --- | --- | --- |
| `ReleaseSmall`, stripped, no libc | 28,112 | 0.010× |
| `ReleaseFast`, stripped, no libc | 46,848 | 0.017× |
| `ReleaseSafe`, stripped, no libc | 233,680 | 0.084× |
| Haskell reference, GHC 9.10.1 `-O` | 2,772,608 | 1.0× |

The `ReleaseSmall` binary is statically linked and stripped: 26,852 bytes of text,
no initialised data, and no dynamic loader. Size comes from three decisions rather
than from post-hoc shrinking: no libc (raw Linux syscalls), no standard-library
I/O stack, and a single decode pass into a flat array with no hash maps, no
formatting framework and no error-name tables.

## Execution time

| Benchmark | What it measures | Reference | This interpreter |
| --- | --- | --- | --- |
| `bench/loop.ws` — 2,000,000 iterations of a 7-instruction loop | dispatch throughput | 582.9 ms | 62.2 ms |
| `bench/wide.ws` — the same loop after 8,000 dead instructions, 20,000 iterations | instruction fetch cost vs program size | 7,960.7 ms | 3.1 ms |
| `bench/stack_small.ws` — 5,000 pushes then 5,000 discards | stack growth and per-instruction overhead | 340.7 ms | 1.8 ms |

The first benchmark is an ordinary constant-factor win (about 9×). The second is
structural: the reference fetches with `program !! pc`, whose cost is linear in
the instruction pointer, so a hot loop placed after a large block of code pays
O(pc) per instruction. Decoding once into an array makes that O(1). Programs with
large bodies and hot loops therefore see speed-ups of orders of magnitude rather
than percentages.

## Memory

| Case | Reference | This interpreter |
| --- | --- | --- |
| `hworld.ws` | 3.63 MiB | below sampling resolution (< 0.4 MiB) |
| `loop.ws` | 7.80 MiB | below sampling resolution (< 0.4 MiB) |
| `stack_small.ws` (5,000 live values) | 8.08 MiB | 0.38 MiB |
| 400,000-instruction program (`bench/stack.ws`, 200,000 live values) | not measurable — the reference is quadratic here | 14.51 MiB |

The interpreter allocates only where the language demands it: one arena for decoded
instructions and labels (16 bytes per instruction), and three growable arrays for
the value stack, heap and call stack. There is no per-instruction allocation, no
garbage collector and no output buffering beyond a 4 KiB input buffer.

The last row is dominated by program representation, not by data: 400,000 decoded
instructions occupy 6.4 MiB, and arena growth during decoding peaks around 14 MiB
because the arenas double while the source file is still mapped. For realistic
programs (hundreds to thousands of instructions) resident memory stays under half
a megabyte.

## Limitations of these numbers

- A single VM, no CPU pinning and no repetition across machines; treat the ratios
  as indicative, the absolute numbers as specific to this environment.
- The reference binary includes the GHC runtime, which contributes most of its
  2.7 MB and 3.6 MiB baseline; part of the size and memory win is simply not
  shipping a Haskell runtime.
- `ReleaseFast` is faster than `ReleaseSmall` on arithmetic-heavy code by a few
  percent, but 67% larger; neither mode was separately re-benchmarked per
  benchmark above.
- Memory sampling cannot resolve sub-millisecond programs, so "< 0.4 MiB" is a
  bound derived from the smallest resolvable measurement, not a profile.
