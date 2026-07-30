#!/usr/bin/env python3
"""Verify or minimally patch SipCheck's sourced-Scan CloudKit fields."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys


REQUIRED_FIELDS = ("factSourceKind", "factSourceURL")


def scan_record_span(schema: str) -> tuple[int, int]:
    match = re.search(r'(?i:\bRECORD\s+TYPE\s+)"?Scan"?\s*([({])', schema)
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
                return match.start(), index + 1
    raise ValueError("CloudKit Scan record block is not balanced")


def scan_record_block(schema: str) -> str:
    start, end = scan_record_span(schema)
    return schema[start:end]


def missing_fields(block: str) -> list[str]:
    declaration_pattern = re.compile(
        r'^[ \t]*(?:(?i:FIELD)[ \t]+)?"?([A-Za-z_][A-Za-z0-9_]*)"?'
        r'[ \t]+((?:(?i:ENCRYPTED)[ \t]+)?[A-Za-z][A-Za-z0-9_]*)\b',
        re.MULTILINE,
    )
    declarations = [
        (match.group(1), " ".join(match.group(2).upper().split()))
        for match in declaration_pattern.finditer(block)
    ]

    missing = []
    for field in REQUIRED_FIELDS:
        matches = [(name, kind) for name, kind in declarations if name.casefold() == field.casefold()]
        if any(name != field for name, _ in matches):
            raise ValueError(f"Scan.{field} exists with incompatible letter case")
        if len(matches) > 1:
            raise ValueError(f"Scan.{field} is declared more than once")
        if matches and matches[0][1] != "STRING":
            raise ValueError(f"Scan.{field} has incompatible type {matches[0][1]}")
        if not matches:
            missing.append(field)
    return missing


def patch_scan_record(schema: str) -> tuple[str, list[str]]:
    start, end = scan_record_span(schema)
    block = schema[start:end]
    missing = missing_fields(block)
    if not missing:
        return schema, []

    # cktool exports field declarations before the record's GRANT clauses.
    # Insert only the absent fields at that boundary and preserve every other
    # byte of the exported Development schema.
    grant = re.search(r'^(?P<indent>[ \t]*)GRANT\b', block, re.IGNORECASE | re.MULTILINE)
    if not grant:
        raise ValueError("CloudKit Scan record type has no GRANT boundary")
    indentation = grant.group("indent")
    addition = "".join(f"{indentation}{field} STRING,\n" for field in missing)
    insertion = start + grant.start()
    return schema[:insertion] + addition + schema[insertion:], missing


def assert_schema(schema: str) -> None:
    block = scan_record_block(schema)
    missing = missing_fields(block)
    if missing:
        labels = [f"Scan.{field} STRING" for field in missing]
        raise ValueError("missing " + ", ".join(labels))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("schema", type=pathlib.Path)
    parser.add_argument("--patch-output", type=pathlib.Path)
    args = parser.parse_args()

    try:
        schema = args.schema.read_text(encoding="utf-8")
        if args.patch_output:
            schema, inserted = patch_scan_record(schema)
            assert_schema(schema)
            args.patch_output.write_text(schema, encoding="utf-8")
            if inserted:
                print("Patched CloudKit Scan fields: " + ", ".join(inserted))
            else:
                print("CloudKit Scan provenance fields already present; schema copied unchanged.")
            return 0
        assert_schema(schema)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"schema assertion failed: {error}", file=sys.stderr)
        return 1

    print("CloudKit Scan provenance schema verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
