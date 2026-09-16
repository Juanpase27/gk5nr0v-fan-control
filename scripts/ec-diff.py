#!/usr/bin/env python3
"""Byte-level diff between two `hexdump -C` EC dumps.

Usage: ec-diff.py <dump_idle.txt> <dump_load.txt>
"""
import sys


def parse(path):
    data = bytearray(256)
    with open(path) as f:
        for line in f:
            tokens = line.split()
            if not tokens:
                continue
            try:
                offset = int(tokens[0], 16)
            except ValueError:
                continue
            for i, tok in enumerate(tokens[1:]):
                if len(tok) == 2 and all(c in "0123456789abcdef" for c in tok):
                    data[offset + i] = int(tok, 16)
    return data


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 1

    a, b = parse(sys.argv[1]), parse(sys.argv[2])
    for i in range(256):
        if a[i] != b[i]:
            le_a = int.from_bytes(a[i:i + 2], "little")
            le_b = int.from_bytes(b[i:i + 2], "little")
            print(f"0x{i:02X}: {a[i]:3d} (0x{a[i]:02X}) -> {b[i]:3d} (0x{b[i]:02X})"
                  f"  LE16 idle=0x{le_a:04X} load=0x{le_b:04X}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
