#!/usr/bin/env python3
"""Assemble readable Whitespace v0.3 mnemonics into `.ws` source.

The interpreter only reads space, tab and line feed, which makes test programs
impossible to review in their encoded form. Test cases are therefore written
with mnemonics and assembled on the fly:

    push 42
    outnum
    end

Anything after `#` is a comment and is dropped. `raw` injects literal token
characters (`s`, `t`, `n`) for malformed-encoding tests.

This tool belongs to the test suite, not to the interpreter.
"""

from __future__ import annotations

import sys

SPACE, TAB, NEWLINE = " ", "\t", "\n"

# Opcode prefixes from the reference implementation's parser (Input.hs).
OPCODES = {
    "push": "ss",
    "copy": "sts",
    "slide": "stn",
    "dup": "sns",
    "swap": "snt",
    "discard": "snn",
    "add": "tsss",
    "sub": "tsst",
    "mul": "tssn",
    "div": "tsts",
    "mod": "tstt",
    "store": "tts",
    "retrieve": "ttt",
    "label": "nss",
    "call": "nst",
    "jump": "nsn",
    "ifzero": "nts",
    "ifnegative": "ntt",
    "ret": "ntn",
    "end": "nnn",
    "outchar": "tnss",
    "outnum": "tnst",
    "readchar": "tnts",
    "readnum": "tntt",
}

NUMERIC = {"push", "copy", "slide"}
LABELLED = {"label", "call", "jump", "ifzero", "ifnegative"}
RAW = {"s": SPACE, "t": TAB, "n": NEWLINE}


def emit(encoded: str) -> str:
    """Turn an s/t/n letter string into the bytes the interpreter reads."""
    return "".join(RAW[c] for c in encoded)


def encode_number(value: int) -> str:
    """Sign token, then the magnitude most significant bit first, then newline."""
    sign = TAB if value < 0 else SPACE
    magnitude = abs(value)
    if magnitude == 0:
        return sign + NEWLINE
    bits = bin(magnitude)[2:]
    return sign + "".join(TAB if bit == "1" else SPACE for bit in bits) + NEWLINE


def encode_label(name: str) -> str:
    """A label is the name's bytes as bits, least-significant bit first."""
    if not name:
        raise ValueError("label names cannot be empty")
    tokens = []
    for byte in name.encode():
        for shift in range(7, -1, -1):
            tokens.append(TAB if (byte >> shift) & 1 else SPACE)
    return "".join(tokens) + NEWLINE


def assemble(text: str) -> str:
    out = []
    for number, line in enumerate(text.splitlines(), start=1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.endswith(":"):
            out.append(emit(OPCODES["label"]) + encode_label(line[:-1].strip()))
            continue
        parts = line.split()
        mnemonic = parts[0].lower()

        if mnemonic == "raw":
            if len(parts) != 2:
                raise ValueError(f"line {number}: raw needs exactly one argument")
            try:
                out.append("".join(RAW[c] for c in parts[1]))
            except KeyError as exc:
                raise ValueError(f"line {number}: bad raw token {exc}") from None
            continue

        if mnemonic not in OPCODES:
            raise ValueError(f"line {number}: unknown mnemonic {mnemonic!r}")

        out.append(emit(OPCODES[mnemonic]))
        if mnemonic in NUMERIC:
            if len(parts) != 2:
                raise ValueError(f"line {number}: {mnemonic} needs a number")
            out.append(encode_number(int(parts[1])))
        elif mnemonic in LABELLED:
            if len(parts) != 2:
                raise ValueError(f"line {number}: {mnemonic} needs a label name")
            out.append(encode_label(parts[1]))
        elif len(parts) != 1:
            raise ValueError(f"line {number}: {mnemonic} takes no argument")
    return "".join(out)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: assemble.py INPUT.asm OUTPUT.ws", file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as handle:
            source = handle.read()
        encoded = assemble(source).encode()
    except (OSError, ValueError) as exc:
        print(f"assemble.py: {exc}", file=sys.stderr)
        return 1
    with open(argv[2], "wb") as handle:
        handle.write(encoded)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
