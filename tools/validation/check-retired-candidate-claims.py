#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Reject active release claims for the retired 0.2.0-alpha Candidate 2 ISO."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys


DEFAULT_PATHS = (
    "README.md",
    "CHANGELOG.md",
    "ROADMAP.md",
    "docs",
    "website",
)

SKIP_DIRS = {".git", "node_modules", "__pycache__"}
TEXT_SUFFIXES = {".md", ".html", ".json", ".env", ".txt", ".yml", ".yaml"}

FORBIDDEN_PATTERNS = (
    (
        "validated 0.2.0-alpha release",
        re.compile(r"\bvalidated\s+0\.2\.0-alpha\s+release\b", re.I),
    ),
    (
        "validated 0.2.0-alpha Candidate 2",
        re.compile(r"\bvalidated\s+0\.2\.0-alpha\s+candidate\s+2\b", re.I),
    ),
    (
        "Candidate 2 validation successful",
        re.compile(r"\bcandidate\s+2\b.*\bvalidation\s+successful\b|\bvalidation\s+successful\b.*\bcandidate\s+2\b", re.I),
    ),
    (
        "Candidate 2 release validation complete",
        re.compile(r"\bcandidate\s+2\b.*\brelease\s+validation\s+complete\b|\brelease\s+validation\s+complete\b.*\bcandidate\s+2\b", re.I),
    ),
    (
        "Candidate 2 status PASS",
        re.compile(r"\bcandidate\s+2\b.*\bstatus\s*:\s*\*\*pass\*\*|\bstatus\s*:\s*\*\*pass\*\*.*\bcandidate\s+2\b", re.I),
    ),
    (
        "retired 0.2.0-alpha object available",
        re.compile(r"\bavailable\s*\(\s*0\.2\.0-alpha\s*\)", re.I),
    ),
    (
        "verified ISO installation images",
        re.compile(r"\bverified\s+iso\s+installation\s+images\b", re.I),
    ),
    (
        "Candidate 2 boots to live desktop",
        re.compile(r"\bcandidate\s+iso\s+boots\s+to\s+(?:the\s+)?live\s+desktop\b", re.I),
        True,
    ),
    (
        "Candidate 2 live desktop success",
        re.compile(r"\blive\s+desktop\s+gui\s+loads\s+successfully\b", re.I),
        True,
    ),
    (
        "Candidate 2 Build A/B ISO reproducibility",
        re.compile(r"\bbuild\s+a\b.*\bbuild\s+b\b.*\bisos?\b.*\b(?:100%|byte-for-byte|bit-for-bit)\b", re.I),
        True,
    ),
)

CANDIDATE2_CONTEXT = re.compile(r"candidate\s*2|candidate-2|0\.2\.0-alpha|2607220558", re.I)


def iter_files(root: pathlib.Path, paths: list[str]) -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for raw in paths:
        path = (root / raw).resolve()
        if not path.exists():
            continue
        if path.is_file():
            if path.suffix in TEXT_SUFFIXES or path.name.endswith(".env"):
                files.append(path)
            continue
        for item in path.rglob("*"):
            if any(part in SKIP_DIRS for part in item.parts):
                continue
            if item.is_file() and (item.suffix in TEXT_SUFFIXES or item.name.endswith(".env")):
                files.append(item)
    return sorted(set(files))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", default=list(DEFAULT_PATHS))
    args = parser.parse_args()

    root = pathlib.Path.cwd().resolve()
    failures: list[str] = []

    for path in iter_files(root, args.paths):
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        try:
            rel = path.relative_to(root)
        except ValueError:
            rel = path
        candidate2_context = False
        for lineno, line in enumerate(lines, start=1):
            if line.startswith("#"):
                candidate2_context = bool(CANDIDATE2_CONTEXT.search(line))
            line_has_candidate2_context = candidate2_context or bool(CANDIDATE2_CONTEXT.search(line))
            for entry in FORBIDDEN_PATTERNS:
                label, pattern = entry[0], entry[1]
                requires_context = len(entry) == 3 and bool(entry[2])
                if requires_context and not line_has_candidate2_context:
                    continue
                if pattern.search(line):
                    failures.append(f"{rel}:{lineno}: {label}: {line.strip()}")

    if failures:
        print("Retired Candidate 2 claim check failed:", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print("Retired Candidate 2 claim check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
