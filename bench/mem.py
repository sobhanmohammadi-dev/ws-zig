#!/usr/bin/env python3
"""Measure peak resident memory and wall time of one child process.

    bench/mem.py BINARY PROGRAM

Uses wait4 so the reported rusage belongs to that child alone, rather than to
every child the calling process has ever waited for.
"""

from __future__ import annotations

import os
import sys
import time


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: mem.py BINARY PROGRAM", file=sys.stderr)
        return 2
    binary, program = argv[1], argv[2]

    devnull = os.open("/dev/null", os.O_RDONLY)
    started = time.monotonic()
    pid = os.posix_spawn(
        binary,
        [binary, program],
        os.environ,
        file_actions=[(os.POSIX_SPAWN_DUP2, devnull, 0)],
    )
    _, status, usage = os.wait4(pid, 0)
    elapsed = (time.monotonic() - started) * 1000
    os.close(devnull)

    code = os.waitstatus_to_exitcode(status)
    print(f"{os.path.basename(binary)}: {elapsed:.1f} ms, peak rss {usage.ru_maxrss / 1024:.1f} MiB, exit {code}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
