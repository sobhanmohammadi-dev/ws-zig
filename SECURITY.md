# Security policy

## Supported versions

Only the latest release on the default branch receives security fixes.

## Reporting a vulnerability

Please report suspected vulnerabilities privately through GitHub's
"Report a vulnerability" advisory feature on this repository rather than in a
public issue. Include the program, input and the observed behaviour, plus the
build mode and Zig version.

Expect an initial response within a week. If the report is confirmed, a fix and a
disclosure note will be prepared before public details are posted.

## Threat model

`wspace` executes untrusted Whitespace programs by design, so its security
boundary is the interpreter itself:

- Malformed or hostile programs must not cause undefined behaviour, memory
  corruption or uncontrolled crashes; they should terminate with a diagnostic and
  exit status 1.
- Stack, heap and call stack grow only in proportion to what the program uses; a
  program can exhaust memory, and that is reported as an error rather than
  silently corrupting state.
- The interpreter performs no network access, spawns no processes, and reads only
  the file named on the command line plus stdin.

Out of scope: resource exhaustion by intentionally huge programs, and the
behaviour of the vendored reference implementation in `wspace-0.3-original/`,
which is included unmodified for reference and is not executed by this project.
