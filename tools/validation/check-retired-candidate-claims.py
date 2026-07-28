#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Reject active release claims for the retired 0.2.0-alpha Candidate 2 ISO."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Any


DEFAULT_PATHS = ("README.md", "CHANGELOG.md", "ROADMAP.md", "docs", "website")
DEFAULT_RETIREMENT_FILE = "docs/releases/0.2.0-alpha-candidate-2-retirement.json"
SKIP_DIRS = {".git", "node_modules", "__pycache__"}
DEFAULT_SKIP_FILES = {
    pathlib.Path("tools/validation/check-retired-candidate-claims.py"),
    pathlib.Path("tools/validation/test-retired-candidate-claims.sh"),
}
TEXT_SUFFIXES = {".md", ".html", ".json", ".env", ".txt", ".yml", ".yaml"}

RETIRED_FILENAME = "GenixBitOS-0.2.0-alpha-2607220558.iso"
RETIRED_SHA256 = "1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669"
RETIRED_SHA512 = "51bdb60298460d1204dd6b641ed7d531c9d34da98fecf90fbfbbabf9beeef0dc42fe86e59646c7cd4c8746b1c5e48d05afc81712758c51cb2096a77c45e0902e"
RETIRED_GENERATION = "1784810864397202"

EXPECTED_RETIREMENT = {
    "status": "RETIRED_INVALID_ZERO_FILLED",
    "usable_as_release_artifact": False,
    "usable_as_migration_source": False,
    "size_bytes": 2540554240,
    "sha256": RETIRED_SHA256,
    "sha512": RETIRED_SHA512,
    "gcp_object_generation": RETIRED_GENERATION,
}

CANDIDATE2_CONTEXT = re.compile(
    rf"candidate\s*2|(?<!alpha-)candidate-2|0\.2\.0-alpha|{re.escape(RETIRED_FILENAME)}|{RETIRED_SHA256}|{RETIRED_SHA512}",
    re.I,
)
DIFFERENT_SECTION = re.compile(r"candidate|release|0\.\d+\.\d+-alpha|0\.3\.0|0\.1\.0", re.I)
NON_CANDIDATE2_SECTION = re.compile(r"candidate\s*1|0\.1\.0-alpha", re.I)
ACTIVE_IDENTIFIER_CLAIM = re.compile(
    r"validated\s+release|fully\s+validated|validation\s+(?:complete|successful)|release\s+(?:approved|available)|"
    r"boot(?:ed)?\s+successfully|boots?\s+to\s+(?:the\s+)?live\s+desktop|installation\s+completed\s+successfully|"
    r"installer\s+(?:passed|completed\s+successfully)|installed[- ]system\s+validated|migration\s+pass(?:ed)?|"
    r"build\s+a.*build\s+b.*reproducib|byte-for-byte\s+identical|bit-for-bit\s+identical|reproducibility\s+pass|"
    r"verified\s+iso\s+installation\s+images",
    re.I,
)
NEGATED_ACTIVE_CLAIM = re.compile(r"\b(?:must\s+not|cannot|do\s+not|not\s+be\s+used\s+to\s+claim|not\s+a\s+valid|no\s+valid|no\s+usable)\b", re.I)

# These are factual statements that may appear near Candidate 2 identifiers. They do not override a forbidden active claim on the same line.
ALLOWLIST_PATTERNS = (
    re.compile(r"source commit|candidate branch|branch created|source branch", re.I),
    re.compile(r"checksum.*object identity only|object identity only|digest match proves only", re.I),
    re.compile(r"retired|RETIRED_INVALID_ZERO_FILLED|zero-filled|zero filled", re.I),
    re.compile(r"RETRACTED_UNBOUND_EVIDENCE|unbound", re.I),
    re.compile(r"NOT_VALIDATED|no valid .*currently exists|no usable .*currently", re.I),
)

FORBIDDEN_PATTERNS: tuple[tuple[str, re.Pattern[str], bool], ...] = (
    ("validation-result-pass", re.compile(r"\|\s*Validation Result\s*\|\s*\*\*?PASS\*\*?\s*\||<td>\s*Validation Result\s*</td>\s*<td>\s*(?:<[^>]+>)*PASS", re.I), True),
    ("verification-status-pass", re.compile(r"\bverification_status\b\s*[:=]\s*[\"']?PASS[\"']?", re.I), True),
    ("overall-status-pass", re.compile(r"\boverall(?:[_ -]?\w+)?[_ -]?status\b\s*[:=]\s*[\"']?PASS\b", re.I), True),
    ("fully-validated", re.compile(r"\bfully\s+validated\b", re.I), True),
    ("validation-complete", re.compile(r"\bvalidation\s+complete\b", re.I), True),
    ("validation-successful", re.compile(r"\bvalidation\s+successful\b", re.I), True),
    ("release-approved", re.compile(r"\brelease\s+approved\b", re.I), True),
    ("release-available", re.compile(r"\brelease\s+available\b|\bavailable\s*\(\s*0\.2\.0-alpha\s*\)", re.I), True),
    ("validated-0.2.0-release", re.compile(r"\bvalidated\s+0\.2\.0-alpha\s+release\b", re.I), False),
    ("verified-iso-installation-images", re.compile(r"\bverified\s+iso\s+installation\s+images\b", re.I), False),
    ("booted-successfully", re.compile(r"\bboot(?:ed)?\s+successfully\b|\bboots?\s+to\s+(?:the\s+)?live\s+desktop\b", re.I), True),
    ("boots-target-disk", re.compile(r"\bboots?\s+directly\s+from\s+target\s+(?:virtual\s+)?disk\b", re.I), True),
    ("installer-success", re.compile(r"\binstaller\b.*\b(?:passed|completed\s+successfully)\b|\binstallation\s+completed\s+successfully\b", re.I), True),
    ("installed-system-validated", re.compile(r"\binstalled[- ]system\b.*\bvalidated\b|\bvalidated\b.*\binstalled[- ]system\b", re.I), True),
    ("apt-guest-health-pass", re.compile(r"\b(?:APT|apt)\b.*\b(?:guest\s+)?health\b.*\bpass(?:ed)?\b|\bpackage[- ]health\b.*\bpass(?:ed)?\b", re.I), True),
    ("build-a-build-b-reproducible", re.compile(r"\bbuild\s+a\b.*\bbuild\s+b\b.*\breproducib", re.I), True),
    ("byte-for-byte-identical", re.compile(r"\b(?:byte-for-byte|bit-for-bit)\s+identical\b|\b100%\s+(?:byte-for-byte|bit-for-bit)\b", re.I), True),
    ("reproducibility-pass", re.compile(r"\breproducibility\b.*\bpass\b|\bpass\b.*\breproducibility\b", re.I), True),
)


def relpath(root: pathlib.Path, path: pathlib.Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def format_failure(root: pathlib.Path, path: pathlib.Path, line: int, rule: str, text: str) -> str:
    return f"{relpath(root, path)}:{line}: {rule}: {text.strip()}"


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


def validate_retirement_file(root: pathlib.Path, retirement_file: pathlib.Path) -> list[str]:
    failures: list[str] = []
    if not retirement_file.exists():
        return [format_failure(root, retirement_file, 1, "retirement-file", "missing retirement metadata")]
    try:
        data = json.loads(retirement_file.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001 - fail closed with parse detail
        return [format_failure(root, retirement_file, 1, "retirement-json", f"malformed retirement metadata: {exc}")]
    for field, expected in EXPECTED_RETIREMENT.items():
        actual = data.get(field)
        if actual != expected:
            failures.append(format_failure(root, retirement_file, 1, f"retirement.{field}", f"expected {expected!r}, got {actual!r}"))
    return failures


def validate_readme_blocked_state(root: pathlib.Path) -> list[str]:
    readme = root / "README.md"
    if not readme.exists():
        return [format_failure(root, readme, 1, "replacement-state", "README.md is missing")]
    text = readme.read_text(encoding="utf-8")
    normalized = re.sub(r"[`*_]", "", text)
    no_replacement = re.search(r"(?:current\s+valid\s+release\s+artifact\s*[:|-]\s*none|no\s+valid\s+(?:replacement|release)\s+artifact\s+currently\s+exists|no\s+usable\s+.*iso\s+currently\s+exists)", normalized, re.I | re.S)
    blocked_gate = re.search(r"release\s+gate\s*[:|-]?\s*blocked.*(?:newly\s+built|new\s+valid|replacement).*validated\s+.*artifact", normalized, re.I | re.S)
    failures = []
    if not no_replacement:
        failures.append(format_failure(root, readme, 1, "replacement-state", "missing no-valid-replacement-artifact statement"))
    if not blocked_gate:
        failures.append(format_failure(root, readme, 1, "release-gate-blocked", "missing blocked release-gate replacement-artifact statement"))
    return failures


def allowed_historical_only(line: str) -> bool:
    return any(pattern.search(line) for pattern in ALLOWLIST_PATTERNS)


def scan_line(line: str, context: bool) -> list[tuple[str, str]]:
    matches: list[tuple[str, str]] = []
    if NEGATED_ACTIVE_CLAIM.search(line):
        return []
    if CANDIDATE2_CONTEXT.search(line) and ACTIVE_IDENTIFIER_CLAIM.search(line):
        if RETIRED_FILENAME in line:
            matches.append(("filename-active-release-claim", line))
        if RETIRED_SHA256 in line:
            matches.append(("sha256-active-release-claim", line))
        if RETIRED_SHA512 in line:
            matches.append(("sha512-active-release-claim", line))
    for rule, pattern, requires_context in FORBIDDEN_PATTERNS:
        if requires_context and not context:
            continue
        if pattern.search(line):
            matches.append((rule, line))
    if matches:
        return matches
    # The allowlist is explicit documentation for permitted historical statements.
    # It intentionally does not suppress active claims, which returned above.
    if context and allowed_historical_only(line):
        return []
    return []


def markdown_context(line: str, current: int | None) -> int | None:
    match = re.match(r"^(#{1,6})\s+(.+)$", line)
    if not match:
        return current
    level = len(match.group(1))
    title = match.group(2)
    if NON_CANDIDATE2_SECTION.search(title):
        return None
    if CANDIDATE2_CONTEXT.search(title):
        return level
    if current is not None and level <= current and DIFFERENT_SECTION.search(title):
        return None
    return current


def scan_markdown(root: pathlib.Path, path: pathlib.Path, lines: list[str]) -> list[str]:
    failures: list[str] = []
    context_level: int | None = None
    for lineno, line in enumerate(lines, start=1):
        context_level = markdown_context(line, context_level)
        context = context_level is not None or bool(CANDIDATE2_CONTEXT.search(line))
        for rule, text in scan_line(line, context):
            failures.append(format_failure(root, path, lineno, rule, text))
    return failures


def scan_html(root: pathlib.Path, path: pathlib.Path, lines: list[str]) -> list[str]:
    failures: list[str] = []
    context_until = 0
    in_context_container = False
    for lineno, line in enumerate(lines, start=1):
        lower = line.lower()
        if re.search(r"<(section|article|table)\b", lower):
            in_context_container = False
        if CANDIDATE2_CONTEXT.search(line):
            context_until = lineno + 12
            in_context_container = True
        context = in_context_container or lineno <= context_until
        for rule, text in scan_line(line, context):
            failures.append(format_failure(root, path, lineno, rule, text))
        if re.search(r"</(section|article|table)>", lower):
            in_context_container = False
    return failures


def flatten_json(value: Any, prefix: str = "") -> list[tuple[str, Any]]:
    if isinstance(value, dict):
        rows: list[tuple[str, Any]] = []
        for key, child in value.items():
            rows.extend(flatten_json(child, f"{prefix}.{key}" if prefix else str(key)))
        return rows
    if isinstance(value, list):
        rows = []
        for index, child in enumerate(value):
            rows.extend(flatten_json(child, f"{prefix}[{index}]"))
        return rows
    return [(prefix, value)]


def json_scalar_has_candidate2(value: Any) -> bool:
    return isinstance(value, (str, int, float, bool)) and CANDIDATE2_CONTEXT.search(str(value)) is not None


def scan_json_object(root: pathlib.Path, path: pathlib.Path, value: Any, prefix: str = "") -> list[str]:
    failures: list[str] = []
    if isinstance(value, dict):
        local_context = any(CANDIDATE2_CONTEXT.search(str(key)) or json_scalar_has_candidate2(child) for key, child in value.items())
        for key, child in value.items():
            child_prefix = f"{prefix}.{key}" if prefix else str(key)
            rendered = f"{child_prefix}: {child}"
            child_context = local_context or CANDIDATE2_CONTEXT.search(rendered) is not None
            if child_context and isinstance(child, str) and child.upper() == "PASS" and re.search(r"status|result|validation|verification", str(key), re.I):
                failures.append(format_failure(root, path, 1, "json-candidate2-pass-status", rendered))
            if isinstance(child, (dict, list)):
                failures.extend(scan_json_object(root, path, child, child_prefix))
            else:
                for rule, offending in scan_line(rendered, child_context):
                    failures.append(format_failure(root, path, 1, rule, offending))
        return failures
    if isinstance(value, list):
        for index, child in enumerate(value):
            failures.extend(scan_json_object(root, path, child, f"{prefix}[{index}]"))
    return failures


def scan_structured(root: pathlib.Path, path: pathlib.Path, lines: list[str]) -> list[str]:
    text = "\n".join(lines)
    failures: list[str] = []
    if path.suffix == ".json":
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            return scan_plain(root, path, lines)
        return scan_json_object(root, path, data)
    return scan_plain(root, path, lines)


def scan_plain(root: pathlib.Path, path: pathlib.Path, lines: list[str]) -> list[str]:
    failures: list[str] = []
    doc_context = bool(CANDIDATE2_CONTEXT.search("\n".join(lines)))
    for lineno, line in enumerate(lines, start=1):
        context = doc_context or bool(CANDIDATE2_CONTEXT.search(line))
        for rule, text in scan_line(line, context):
            failures.append(format_failure(root, path, lineno, rule, text))
    return failures


def scan_file(root: pathlib.Path, path: pathlib.Path) -> list[str]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return []
    if path.suffix == ".md":
        return scan_markdown(root, path, lines)
    if path.suffix == ".html":
        return scan_html(root, path, lines)
    if path.suffix == ".json" or path.name.endswith(".env"):
        return scan_structured(root, path, lines)
    return scan_plain(root, path, lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--retirement-file", default=DEFAULT_RETIREMENT_FILE, help="Candidate 2 retirement metadata JSON")
    parser.add_argument("paths", nargs="*", default=list(DEFAULT_PATHS))
    args = parser.parse_args()

    root = pathlib.Path.cwd().resolve()
    retirement_file = (root / args.retirement_file).resolve()
    failures: list[str] = []
    failures.extend(validate_retirement_file(root, retirement_file))
    failures.extend(validate_readme_blocked_state(root))

    for path in iter_files(root, args.paths):
        try:
            relative = path.relative_to(root)
        except ValueError:
            relative = None
        if relative in DEFAULT_SKIP_FILES:
            continue
        failures.extend(scan_file(root, path))

    if failures:
        print("Retired Candidate 2 claim check failed:", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print("Retired Candidate 2 claim check passed.")
    print("Retirement metadata validated: RETIRED_INVALID_ZERO_FILLED, release=false, migration=false, size=2540554240")
    print("Replacement ISO claimed: NO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
