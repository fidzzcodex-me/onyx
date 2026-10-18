#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXTENSIONS = {".dart", ".kt", ".kts", ".cpp", ".h", ".java", ".gradle"}
SKIP_PARTS = {"build", ".dart_tool", ".gradle", ".cxx", "node_modules"}


def strip_strings(line: str) -> str:
    out = []
    i = 0
    quote = None
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def check(path: Path):
    problems = []
    in_block = False
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if in_block:
            problems.append((number, raw.strip()))
            if "*/" in raw:
                in_block = False
            continue
        stripped = strip_strings(raw)
        if "//" in stripped:
            problems.append((number, raw.strip()))
        if "/*" in stripped:
            problems.append((number, raw.strip()))
            if "*/" not in stripped:
                in_block = True
    return problems


def main() -> int:
    bad = 0
    for path in sorted(ROOT.rglob("*")):
        if path.suffix not in EXTENSIONS or not path.is_file():
            continue
        if SKIP_PARTS.intersection(path.relative_to(ROOT).parts):
            continue
        for number, text in check(path):
            bad += 1
            print(f"{path.relative_to(ROOT)}:{number}: {text}")
    if bad:
        print(f"{bad} baris komentar ditemukan")
        return 1
    print("Tidak ada komentar // atau /* */ pada kode")
    return 0


if __name__ == "__main__":
    sys.exit(main())
