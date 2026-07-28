#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Validate active 0.3.0-alpha release artifact provenance without Candidate 2 fallback."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import sys

DEFAULT_VERSION = "0.3.0-alpha"
DEFAULT_MODE = "fresh-install-only"
DEFAULT_PROVENANCE = "docs/releases/0.3.0-alpha-artifact.json"
PHASE_STATUS = {
    "pending": "PENDING_BUILD",
    "built": "BUILT_UNVALIDATED",
    "validated-unpublished": "VALIDATED_UNPUBLISHED",
    "pass": "PASS",
}
RETIRED_FILENAME = "GenixBitOS-0.2.0-alpha-2607220558.iso"
RETIRED_SHA256 = "1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669"
RETIRED_SHA512 = "51bdb60298460d1204dd6b641ed7d531c9d34da98fecf90fbfbbabf9beeef0dc42fe86e59646c7cd4c8746b1c5e48d05afc81712758c51cb2096a77c45e0902e"
RETIRED_GENERATION = "1784810864397202"
NA_REASON = "No valid prior GenixBit OS release artifact exists from which to execute an upgrade or rollback test."


def fail(field: str, message: str) -> None:
    print(f"[FAIL] {field}: {message}", file=sys.stderr)
    sys.exit(1)


def load_json(path: pathlib.Path) -> dict:
    if not path.is_file():
        fail("active_provenance_file", f"missing active provenance file: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        fail("active_provenance_file", f"malformed active provenance file: {exc}")


def sha(path: pathlib.Path, algo: str) -> str:
    h = hashlib.new(algo)
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def reject_retired(data: dict, iso_path: pathlib.Path | None = None) -> None:
    fields = [
        str(data.get("filename", "")),
        str(data.get("sha256", "")),
        str(data.get("sha512", "")),
        str(data.get("object_generation", "")),
    ]
    if iso_path is not None:
        fields.append(iso_path.name)
    if RETIRED_FILENAME in fields:
        fail("retired_filename", RETIRED_FILENAME)
    if RETIRED_SHA256 in fields:
        fail("retired_sha256", RETIRED_SHA256)
    if RETIRED_SHA512 in fields:
        fail("retired_sha512", RETIRED_SHA512)
    if RETIRED_GENERATION in fields:
        fail("retired_object_generation", RETIRED_GENERATION)


def validate_hash_bound_iso(data: dict, args: argparse.Namespace) -> pathlib.Path:
    iso = pathlib.Path(args.iso or os.environ.get("ACTIVE_RELEASE_ISO_LOCAL") or data.get("filename") or "").resolve()
    reject_retired(data, iso)
    if not iso.is_file() or iso.stat().st_size <= 0:
        fail("iso", f"real nonempty ISO missing: {iso}")
    if data.get("size_bytes") != iso.stat().st_size:
        fail("size_bytes", f"expected {iso.stat().st_size}, got {data.get('size_bytes')!r}")
    if data.get("sha256") != sha(iso, "sha256"):
        fail("sha256", "active ISO SHA-256 mismatch")
    if data.get("sha512") != sha(iso, "sha512"):
        fail("sha512", "active ISO SHA-512 mismatch")
    checker = pathlib.Path(args.repo_root) / "tools/validation/check-iso-structure.sh"
    res = subprocess.run(["bash", str(checker), "--iso", str(iso)], capture_output=True, text=True)
    if res.returncode != 0:
        fail("iso_structure", "active ISO structural validation failed")
    return iso


def validate_provenance(data: dict, args: argparse.Namespace, require_pass: bool) -> pathlib.Path | None:
    reject_retired(data)
    if data.get("release_version") != args.release_version:
        fail("release_version", f"expected {args.release_version}, got {data.get('release_version')!r}")
    expected_status = PHASE_STATUS[args.phase]
    if data.get("verification_status") != expected_status:
        fail("verification_status", f"expected {expected_status}, got {data.get('verification_status')!r}")
    expected_commit = args.source_commit or os.environ.get("ACTIVE_RELEASE_SOURCE_COMMIT")
    if expected_commit and data.get("candidate_source_commit") != expected_commit:
        fail("candidate_source_commit", f"expected {expected_commit}, got {data.get('candidate_source_commit')!r}")
    if args.phase == "pass":
        if data.get("usable_as_release_artifact") is not True:
            fail("usable_as_release_artifact", "must be true only after immutable publication validation")
        if data.get("object_generation") in (None, ""):
            fail("object_generation", "missing immutable object identifier")
    else:
        if data.get("usable_as_release_artifact") is not False:
            fail("usable_as_release_artifact", "must remain false before immutable publication")
        if data.get("usable_as_migration_source") is not False:
            fail("usable_as_migration_source", "fresh-install artifact must not be a migration source")
        if data.get("object_generation") is not None:
            fail("object_generation", "must remain null before immutable publication")
    if args.phase in ("built", "validated-unpublished", "pass") and (data.get("filename") is None or str(data.get("filename", "")).strip() == ""):
        fail("filename", "missing active ISO filename")
    if args.phase in ("built", "validated-unpublished", "pass") or require_pass:
        return validate_hash_bound_iso(data, args)
    return None


def validate_gate(path: pathlib.Path) -> None:
    data = load_json(path)
    categories = data.get("categories", {})
    summary = data.get("summary", {})
    actual_na = sum(1 for c in categories.values() if c.get("status") == "NOT_APPLICABLE")
    if summary.get("not_applicable_count") != actual_na:
        fail("not_applicable_count", f"expected {actual_na}, got {summary.get('not_applicable_count')!r}")
    for name in ("upgrade_readiness", "rollback_readiness"):
        cat = categories.get(name, {})
        if cat.get("status") != "NOT_APPLICABLE":
            fail(name, "fresh-install-only must mark this category NOT_APPLICABLE")
        if cat.get("reason") != NA_REASON:
            fail(name, "missing factual NOT_APPLICABLE reason")
    mandatory = ["clean_install_readiness", "vm_readiness", "installer_readiness", "package_health_readiness", "reproducibility_readiness"]
    mandatory_pass = all(categories.get(name, {}).get("status") == "PASS" for name in mandatory)
    failures = sum(1 for c in categories.values() if c.get("status") in ("FAIL", "BLOCKED"))
    if summary.get("overall_gate_status") == "PASS_ALPHA_FRESH_INSTALL":
        if not mandatory_pass or failures:
            fail("overall_gate_status", "PASS_ALPHA_FRESH_INSTALL requires all mandatory fresh-install categories PASS and no failures/blockers")
        if summary.get("release_ready") is not True or summary.get("stable_ready") is not False:
            fail("release_ready", "alpha fresh-install pass requires release_ready=true and stable_ready=false")
    print("[PASS] active release gate summary validated")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=os.getcwd())
    parser.add_argument("--provenance-file", default=os.environ.get("ACTIVE_RELEASE_PROVENANCE_FILE", DEFAULT_PROVENANCE))
    parser.add_argument("--release-version", default=os.environ.get("ACTIVE_RELEASE_VERSION", DEFAULT_VERSION))
    parser.add_argument("--mode", default=os.environ.get("ACTIVE_RELEASE_MODE", DEFAULT_MODE))
    parser.add_argument("--source-commit", default=os.environ.get("ACTIVE_RELEASE_SOURCE_COMMIT", ""))
    parser.add_argument("--iso", default=os.environ.get("ACTIVE_RELEASE_ISO_LOCAL", ""))
    parser.add_argument("--phase", choices=sorted(PHASE_STATUS), default="pass")
    parser.add_argument("--require-pass", action="store_true")
    parser.add_argument("--allow-pending", action="store_true")
    parser.add_argument("--gate-file")
    args = parser.parse_args()

    if args.mode != DEFAULT_MODE:
        fail("ACTIVE_RELEASE_MODE", f"unsupported active release mode: {args.mode}")
    if args.gate_file:
        validate_gate(pathlib.Path(args.gate_file))
        return 0
    data = load_json(pathlib.Path(args.provenance_file))
    if args.allow_pending and data.get("verification_status") == "PENDING_BUILD":
        reject_retired(data)
        if data.get("release_version") != args.release_version:
            fail("release_version", f"expected {args.release_version}, got {data.get('release_version')!r}")
        print("[PASS] active release artifact pending build")
        return 0
    validate_provenance(data, args, require_pass=args.require_pass)
    print("[PASS] active release artifact provenance validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
