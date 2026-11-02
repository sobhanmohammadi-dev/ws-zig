#!/bin/sh
# Conformance test runner.
#
#   tests/run.sh              compare zig-out/bin/wspace with tests/expected
#   tests/run.sh record       rewrite tests/expected from $INTERPRETER
#   tests/run.sh record-zig   rewrite only the deliberate-deviation cases
#
# Every case in tests/cases is assembled and run. The examples shipped with the
# reference implementation are run too, using tests/cases/example_<name>.in as
# stdin when present.
#
# Set INTERPRETER to test another implementation. Cases marked with a `.zigonly`
# file document deliberate deviations and are skipped unless $INTERPRETER is the
# default Zig binary.

set -u

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
interpreter=${INTERPRETER:-"$root/zig-out/bin/wspace"}
mode=${1:-check}
default_interpreter="$root/zig-out/bin/wspace"

case "$mode" in
    check | record | record-zig) ;;
    *)
        echo "run.sh: unknown mode '$mode' (use check, record or record-zig)" >&2
        exit 2
        ;;
esac

if [ ! -x "$interpreter" ]; then
    echo "run.sh: interpreter not found: $interpreter" >&2
    echo "run.sh: build it with: zig build -Doptimize=ReleaseSafe" >&2
    exit 2
fi

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT INT TERM

passed=0
failed=0
skipped=0
report=""

fail() {
    failed=$((failed + 1))
    report="$report\nFAIL $1"
}

run_case() {
    name=$1
    program=$2
    input=$3
    expected_out="$root/tests/expected/$name.out"
    expected_code="$root/tests/expected/$name.code"

    "$interpreter" "$program" <"$input" >"$work/$name.out" 2>"$work/$name.err"
    code=$?

    if [ "$mode" = "record" ] || [ "$mode" = "record-zig" ]; then
        mkdir -p "$root/tests/expected"
        cp "$work/$name.out" "$expected_out"
        printf '%s\n' "$code" >"$expected_code"
        passed=$((passed + 1))
        report="$report\nREC  $name (exit $code)"
        return
    fi

    if [ ! -f "$expected_out" ]; then
        fail "$name (no expected output; run tests/run.sh record)"
        return
    fi
    if ! cmp -s "$work/$name.out" "$expected_out"; then
        fail "$name (stdout differs)"
        return
    fi
    expected_status=$(cat "$expected_code" 2>/dev/null || echo 0)
    if [ "$code" != "$expected_status" ]; then
        fail "$name (exit $code, expected $expected_status)"
        return
    fi
    if [ "$code" != "0" ] && ! grep -q '^wspace: ' "$work/$name.err"; then
        fail "$name (missing diagnostic on stderr)"
        return
    fi
    passed=$((passed + 1))
}

want_case() {
    # $1 is 1 for a deliberate-deviation case.
    zigonly=$1
    if [ "$mode" = "record-zig" ] && [ "$zigonly" -eq 0 ]; then
        return 1
    fi
    if [ "$mode" != "record-zig" ] && [ "$zigonly" -eq 1 ] && [ "$interpreter" != "$default_interpreter" ]; then
        return 1
    fi
    return 0
}

for asm in "$root"/tests/cases/*.asm; do
    [ -f "$asm" ] || continue
    name=$(basename "$asm" .asm)
    zigonly=0
    [ -f "$root/tests/cases/$name.zigonly" ] && zigonly=1

    if ! want_case "$zigonly"; then
        skipped=$((skipped + 1))
        continue
    fi
    if ! python3 "$root/tests/assemble.py" "$asm" "$work/$name.ws"; then
        fail "$name (assembly)"
        continue
    fi
    input=/dev/null
    [ -f "$root/tests/cases/$name.in" ] && input="$root/tests/cases/$name.in"
    run_case "$name" "$work/$name.ws" "$input"
done

for example in "$root"/wspace-0.3-original/examples/*.ws; do
    [ -f "$example" ] || continue
    name="example_$(basename "$example" .ws)"
    if ! want_case 0; then
        skipped=$((skipped + 1))
        continue
    fi
    input=/dev/null
    [ -f "$root/tests/cases/$name.in" ] && input="$root/tests/cases/$name.in"
    run_case "$name" "$example" "$input"
done

printf '%b\n' "${report#\\n}"
printf '\n%s: %d passed, %d failed, %d skipped\n' "$mode" "$passed" "$failed" "$skipped"
[ "$failed" -eq 0 ]
