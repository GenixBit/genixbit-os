#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
CHECKER="$REPO_ROOT/tools/validation/check-retired-candidate-claims.py"
TMP_DIR=$(mktemp -d)
TOTAL=0
PASS=0

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

pass() {
    PASS=$((PASS + 1))
    printf '[PASS] %s\n' "$1"
}

write_retirement_json() {
    local path="$1"
    mkdir -p "$(dirname -- "$path")"
    cat > "$path" <<'JSON'
{
  "schema_version": "1.0",
  "release_version": "0.2.0-alpha",
  "candidate_branch": "validation/0.2.0-alpha-candidate-2",
  "candidate_source_commit": "88a1550a9129a80ffd2c4cf73838122020a782cb",
  "filename": "GenixBitOS-0.2.0-alpha-2607220558.iso",
  "size_bytes": 2540554240,
  "sha256": "1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669",
  "sha512": "51bdb60298460d1204dd6b641ed7d531c9d34da98fecf90fbfbbabf9beeef0dc42fe86e59646c7cd4c8746b1c5e48d05afc81712758c51cb2096a77c45e0902e",
  "gcp_object_generation": "1784810864397202",
  "status": "RETIRED_INVALID_ZERO_FILLED",
  "usable_as_release_artifact": false,
  "usable_as_migration_source": false
}
JSON
}

write_readme() {
    local path="$1"
    cat > "$path" <<'MD'
# Fixture

- **Current valid release artifact**: none;
- **Release gate**: blocked pending a newly built and validated replacement artifact.
MD
}

create_fixture_repo() {
    local dir="$1"
    mkdir -p "$dir/docs/releases" "$dir/website"
    write_readme "$dir/README.md"
    write_retirement_json "$dir/docs/releases/0.2.0-alpha-candidate-2-retirement.json"
}

record_pass_case() {
    local name="$1"
    shift
    TOTAL=$((TOTAL + 1))
    "$@"
    pass "$name"
}

expect_fail_cmd() {
    local name="$1"
    local expected="$2"
    shift 2
    local out="$TMP_DIR/fail-$TOTAL.out"
    local err="$TMP_DIR/fail-$TOTAL.err"
    TOTAL=$((TOTAL + 1))
    if "$@" > "$out" 2> "$err"; then
        printf '[FAIL] %s unexpectedly passed\n' "$name" >&2
        exit 1
    fi
    grep -q "$expected" "$err"
    pass "$name"
}

expect_fixture_fail() {
    local name="$1"
    local expected="$2"
    local file_rel="$3"
    local text="$4"
    local dir="$TMP_DIR/fixture-$TOTAL"
    create_fixture_repo "$dir"
    mkdir -p "$(dirname -- "$dir/$file_rel")"
    printf '%s\n' "$text" > "$dir/$file_rel"
    expect_fail_cmd "$name" "$expected" bash -c "cd '$dir' && python3 '$CHECKER'"
}

expect_fixture_pass() {
    local name="$1"
    local file_rel="$2"
    local text="$3"
    local dir="$TMP_DIR/fixture-$TOTAL"
    create_fixture_repo "$dir"
    mkdir -p "$(dirname -- "$dir/$file_rel")"
    printf '%s\n' "$text" > "$dir/$file_rel"
    record_pass_case "$name" bash -c "cd '$dir' && python3 '$CHECKER' >/dev/null"
}

# 1. Current repository passes.
record_pass_case "current repository passes" python3 "$CHECKER"

# 2. Missing retirement JSON fails.
missing_dir="$TMP_DIR/missing-retirement"
create_fixture_repo "$missing_dir"
rm "$missing_dir/docs/releases/0.2.0-alpha-candidate-2-retirement.json"
expect_fail_cmd "missing retirement JSON fails" "retirement-file" bash -c "cd '$missing_dir' && python3 '$CHECKER'"

# 3. Malformed retirement JSON fails.
malformed_dir="$TMP_DIR/malformed-retirement"
create_fixture_repo "$malformed_dir"
printf '{not-json\n' > "$malformed_dir/docs/releases/0.2.0-alpha-candidate-2-retirement.json"
expect_fail_cmd "malformed retirement JSON fails" "retirement-json" bash -c "cd '$malformed_dir' && python3 '$CHECKER'"

# 4. Wrong retirement status fails.
wrong_status_dir="$TMP_DIR/wrong-status"
create_fixture_repo "$wrong_status_dir"
python3 - "$wrong_status_dir/docs/releases/0.2.0-alpha-candidate-2-retirement.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["status"] = "PASS"
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
expect_fail_cmd "wrong retirement status fails" "retirement.status" bash -c "cd '$wrong_status_dir' && python3 '$CHECKER'"

# 5. usable_as_release_artifact true fails.
release_true_dir="$TMP_DIR/release-true"
create_fixture_repo "$release_true_dir"
python3 - "$release_true_dir/docs/releases/0.2.0-alpha-candidate-2-retirement.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["usable_as_release_artifact"] = True
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
expect_fail_cmd "usable_as_release_artifact true fails" "retirement.usable_as_release_artifact" bash -c "cd '$release_true_dir' && python3 '$CHECKER'"

# 6. usable_as_migration_source true fails.
migration_true_dir="$TMP_DIR/migration-true"
create_fixture_repo "$migration_true_dir"
python3 - "$migration_true_dir/docs/releases/0.2.0-alpha-candidate-2-retirement.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["usable_as_migration_source"] = True
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
expect_fail_cmd "usable_as_migration_source true fails" "retirement.usable_as_migration_source" bash -c "cd '$migration_true_dir' && python3 '$CHECKER'"

# 7. Changed historical SHA or size fails.
changed_meta_dir="$TMP_DIR/changed-meta"
create_fixture_repo "$changed_meta_dir"
python3 - "$changed_meta_dir/docs/releases/0.2.0-alpha-candidate-2-retirement.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["size_bytes"] = 1
data["sha256"] = "0" * 64
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
expect_fail_cmd "changed historical SHA or size fails" "retirement.size_bytes" bash -c "cd '$changed_meta_dir' && python3 '$CHECKER'"

# 8. Missing no-valid-replacement statement fails.
missing_replacement_dir="$TMP_DIR/missing-replacement"
create_fixture_repo "$missing_replacement_dir"
printf '# Fixture\n\n- **Release gate**: blocked pending a newly built and validated replacement artifact.\n' > "$missing_replacement_dir/README.md"
expect_fail_cmd "missing no valid replacement statement fails" "replacement-state" bash -c "cd '$missing_replacement_dir' && python3 '$CHECKER'"

# 9-16. Active Candidate 2 claims fail.
expect_fixture_fail "Candidate 2 fully validated claim fails" "docs/bad.md:3: fully-validated" "docs/bad.md" $'## Candidate 2\n\nThis candidate is fully validated.'
expect_fixture_fail "Candidate 2 validation-complete claim fails" "docs/bad.md:3: validation-complete" "docs/bad.md" $'## Candidate 2\n\nRelease validation complete.'
expect_fixture_fail "screenshot Validation Result PASS fails" "docs/shot.md:3: validation-result-pass" "docs/shot.md" $'## 0.2.0-alpha screenshots\n\n| Validation Result | **PASS** |'
expect_fixture_fail "nested Candidate 2 subsection active claim fails" "docs/nested.md:5: validation-successful" "docs/nested.md" $'## Candidate 2\n\n### Child heading without candidate name\n\nValidation successful.'
expect_fixture_fail "HTML table active claim fails" "website/index.html:4: validation-result-pass" "website/index.html" $'<section>\n<h2>0.2.0-alpha Candidate 2</h2>\n<table>\n<tr><td>Validation Result</td><td>PASS</td></tr>\n</table>\n</section>'
expect_fixture_fail "JSON Candidate 2 PASS status fails" "docs/status.json:1: json-candidate2-pass-status" "docs/status.json" '{"candidate":"0.2.0-alpha Candidate 2","verification_status":"PASS"}'
expect_fixture_fail "retired filename plus boot success claim fails" "docs/boot.md:3: booted-successfully" "docs/boot.md" $'## Candidate 2\n\nGenixBitOS-0.2.0-alpha-2607220558.iso booted successfully.'
expect_fixture_fail "Build A and Build B reproducibility claim fails" "docs/repro.md:3: build-a-build-b-reproducible" "docs/repro.md" $'## Candidate 2\n\nBuild A and Build B are reproducible.'

# 17-18. Allowed historical wording passes.
expect_fixture_pass "historical checksum identity wording passes" "docs/good.md" "Candidate 2 checksum matched object identity only; object is retired and zero-filled."
expect_fixture_pass "RETRACTED_UNBOUND_EVIDENCE screenshot wording passes" "docs/screens.md" "Candidate 2 screenshots are RETRACTED_UNBOUND_EVIDENCE and release status is NOT_VALIDATED."

# 19. Checker does not scan or match its own source/test fixtures by default.
self_skip_dir="$TMP_DIR/self-skip"
create_fixture_repo "$self_skip_dir"
mkdir -p "$self_skip_dir/tools/validation"
printf 'Candidate 2 fully validated\n' > "$self_skip_dir/tools/validation/check-retired-candidate-claims.py"
printf 'Candidate 2 validation complete\n' > "$self_skip_dir/tools/validation/test-retired-candidate-claims.sh"
record_pass_case "checker skips own source/test fixtures by default" bash -c "cd '$self_skip_dir' && python3 '$CHECKER' >/dev/null"

# 20. Failure output contains exact fixture filename and line number.
line_dir="$TMP_DIR/line-output"
create_fixture_repo "$line_dir"
mkdir -p "$line_dir/docs"
cat > "$line_dir/docs/line-check.md" <<'MD'
## Candidate 2

This is fully validated.
MD
TOTAL=$((TOTAL + 1))
if bash -c "cd '$line_dir' && python3 '$CHECKER'" > "$line_dir/out" 2> "$line_dir/err"; then
    printf '[FAIL] line-number fixture unexpectedly passed\n' >&2
    exit 1
fi
grep -q 'docs/line-check.md:3: fully-validated' "$line_dir/err"
pass "failure output contains fixture filename and line number"

printf '[PASS] retired Candidate 2 claim tests passed: %s/%s\n' "$PASS" "$TOTAL"
