#!/usr/bin/env python3
"""Fail unless a cktool schema has SipCheck's sourced-Scan string fields."""

from __future__ import annotations

import pathlib
import re
import sys


REQUIRED_FIELDS = ("factSourceKind", "factSourceURL")


def scan_record_block(schema: str) -> str:
    match = re.search(r'\bRECORD\s+TYPE\s+"?Scan"?\s*([({])', schema, re.IGNORECASE)
    if not match:
        raise ValueError("CloudKit schema has no Scan record type")

    opening = match.group(1)
    closing = ")" if opening == "(" else "}"
    depth = 0
    for index in range(match.start(1), len(schema)):
        character = schema[index]
        if character == opening:
            depth += 1
        elif character == closing:
            depth -= 1
            if depth == 0:
                return schema[match.start() : index + 1]
    raise ValueError("CloudKit Scan record block is not balanced")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {pathlib.Path(sys.argv[0]).name} SCHEMA.ckdb", file=sys.stderr)
        return 2

    schema_path = pathlib.Path(sys.argv[1])
    try:
        block = scan_record_block(schema_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        print(f"schema assertion failed: {error}", file=sys.stderr)
        return 1

    missing = []
    for field in REQUIRED_FIELDS:
        pattern = rf'^\s*(?:FIELD\s+)?"?{re.escape(field)}"?\s+STRING\b'
        if not re.search(pattern, block, re.IGNORECASE | re.MULTILINE):
            missing.append(f"Scan.{field} STRING")
    if missing:
        print("schema assertion failed: missing " + ", ".join(missing), file=sys.stderr)
        return 1

    print("CloudKit Scan provenance schema verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
