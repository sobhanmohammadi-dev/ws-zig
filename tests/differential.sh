#!/bin/sh
# Differential comparison between two Whitespace interpreters.
#
#   tests/differential.sh A B
#
# Runs every test case and every bundled example through both interpreters and
# compares stdout and exit status. Cases marked `.zigonly` are skipped: they
# document deliberate deviations. stderr is not compared because the reference
# prints GHC runtime diagnostics while this implementation prints its own
# `wspace: ...` messages.

set -u

if [ "$#" -ne 2 ]; then
    echo "usage: differential.sh INTERPRETER_A INTERPRETER_B" >&2
    exit 2
fi

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
a=$1
b=$2

for interpreter in "$a" "$b"; do
    if [ ! -x "$interpreter" ]; then
        echo "differential.sh: not executable: $interpreter" >&2
        exit 2
    fi
done

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT INT TERM

same=0
different=0
skipped=0

compare() {
    name=$1
    program=$2
    input=$3

    "$a" "$program" <"$input" >"$work/a.out" 2>"$work/a.err"
    a_code=$?
    "$b" "$program" <"$input" >"$work/b.out" 2>"$work/b.err"
    b_code=$?

    if cmp -s "$work/a.out" "$work/b.out" && [ "$a_code" = "$b_code" ]; then
        same=$((same + 1))
        return
    fi

    different=$((different + 1))
    printf 'MISMATCH %s\n' "$name"
    printf '  exit: %s vs %s\n' "$a_code" "$b_code"
    if ! cmp -s "$work/a.out" "$work/b.out"; then
        printf '  stdout A: %s\n' "$(od -c "$work/a.out" | head -3)"
        printf '  stdout B: %s\n' "$(od -c "$work/b.out" | head -3)"
    fi
}

for asm in "$root"/tests/cases/*.asm; do
    [ -f "$asm" ] || continue
    name=$(basename "$asm" .asm)
    if [ -f "$root/tests/cases/$name.zigonly" ]; then
        skipped=$((skipped + 1))
        continue
    fi
    python3 "$root/tests/assemble.py" "$asm" "$work/$name.ws" || exit 1
    input=/dev/null
    [ -f "$root/tests/cases/$name.in" ] && input="$root/tests/cases/$name.in"
    compare "$name" "$work/$name.ws" "$input"
done

for example in "$root"/wspace-0.3-original/examples/*.ws; do
    [ -f "$example" ] || continue
    name=$(basename "$example" .ws)
    input=/dev/null
    [ -f "$root/tests/cases/example_$name.in" ] && input="$root/tests/cases/example_$name.in"
    compare "example:$name" "$example" "$input"
done

printf '\ndifferential: %d identical, %d different, %d skipped\n' "$same" "$different" "$skipped"
[ "$different" -eq 0 ]
