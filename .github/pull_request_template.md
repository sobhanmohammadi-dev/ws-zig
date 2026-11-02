## Summary

Describe the change and why it is needed.

## Behaviour

Which Whitespace behaviour is affected? If this is a compatibility change, state
what the reference implementation does.

## Verification

- [ ] `zig fmt --check build.zig src`
- [ ] `zig build test`
- [ ] `zig build -Doptimize=ReleaseSmall`
- [ ] `./tests/run.sh check`
- [ ] `./tests/differential.sh <reference> ./zig-out/bin/wspace` (if a reference
      build was available)

## Notes

Anything reviewers should know: trade-offs, size impact, follow-up work, or
behaviour deliberately left unchanged.
