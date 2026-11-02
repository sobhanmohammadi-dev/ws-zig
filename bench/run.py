#!/usr/bin/env python3
"""Run an interpreter over a program and report wall time and peak memory.

    bench/run.py BINARY PROGRAM [REPEATS]

Wall time is the median of the repeats; peak resident memory is the maximum
over all repeats, read from the kernel's resource accounting for children.
"""

from __future__ import annotations

import os
import resource
import statistics
import subprocess
import sys
import time


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        print("usage: run.py BINARY PROGRAM [REPEATS]", file=sys.stderr)
        return 2
    binary, program = argv[1], argv[2]
    repeats = int(argv[3]) if len(argv) == 4 else 3

    times = []
    for _ in range(repeats):
        start = time.monotonic()
        with subprocess.Popen(
            [binary, program],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ) as child:
            child.wait()
        times.append(time.monotonic() - start)

    peak_kb = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    print(
        f"{os.path.basename(binary)}: median {statistics.median(times) * 1000:.1f} ms, "
        f"peak rss {peak_kb / 1024:.1f} MiB"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
