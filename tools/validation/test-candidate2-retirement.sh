#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
TOTAL=0
PASS=0
RETIREMENT_JSON="$REPO_ROOT/docs/releases/0.2.0-alpha-candidate-2-retirement.json"
ARTIFACT_JSON="$REPO_ROOT/docs/releases/0.2.0-alpha-artifact.json"
RETIRED_SHA="1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669"
RETIRED_SHA512="51bdb60298460d1204dd6b641ed7d531c9d34da98fecf90fbfbbabf9beeef0dc42fe86e59646c7cd4c8746b1c5e48d05afc81712758c51cb2096a77c45e0902e"
ACTIVE_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
OTHER_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

pass() {
    PASS=$((PASS + 1))
    printf '[PASS] %s\n' "$1"
}

check() {
    local name="$1"
    shift
    TOTAL=$((TOTAL + 1))
    if "$@"; then
        pass "$name"
    else
        printf '[FAIL] %s\n' "$name" >&2
        exit 1
    fi
}

json_value() {
    local file="$1"
    local expr="$2"
    python3 - "$file" "$expr" <<'PYEOF'
import json
import sys

value = json.load(open(sys.argv[1], encoding="utf-8"))
for part in sys.argv[2].split('.'):
    value = value[part]
print(value)
PYEOF
}

write_provenance() {
    local path="$1"
    local status="$2"
    local usable="$3"
    local sha="$4"
    printf '{"verification_status":"%s","usable_as_migration_source":%s,"sha256":"%s"}\n' "$status" "$usable" "$sha" > "$path"
}

snapshot_results() {
    local output="$1"
    if [[ ! -d "$REPO_ROOT/infra/package-staging/results" ]]; then
        : > "$output"
        return 0
    fi
    if find "$REPO_ROOT/infra/package-staging/results" -mindepth 1 -printf '%P %s %T@\n' >/dev/null 2>&1; then
        find "$REPO_ROOT/infra/package-staging/results" -mindepth 1 -printf '%P %s %T@\n' 2>/dev/null | sort > "$output"
    else
        python3 - "$REPO_ROOT/infra/package-staging/results" "$output" <<'PYEOF'
import os
import sys

root, out = sys.argv[1:3]
rows = []
for current, dirs, files in os.walk(root):
    for name in dirs + files:
        path = os.path.join(current, name)
        st = os.stat(path)
        rows.append(f"{os.path.relpath(path, root)} {st.st_size} {st.st_mtime}\n")
with open(out, "w", encoding="utf-8") as f:
    f.writelines(sorted(rows))
PYEOF
    fi
}

run_install_failure_case() {
    local name="$1"
    local provenance_file="$2"
    local observed_sha="$3"
    local expected_pattern="$4"
    local case_dir="$TMP_DIR/install-$TOTAL"
    local bin_dir="$case_dir/bin"
    mkdir -p "$bin_dir"
    printf 'not an iso\n' > "$case_dir/cand2.iso"
    printf '#!/usr/bin/env bash\nprintf "%s  %%s\\n" "${1:-file}"\n' "$observed_sha" > "$bin_dir/sha256sum"
    printf '#!/usr/bin/env bash\nprintf "%s  %%s\\n" "${1:-file}"\n' "$RETIRED_SHA512" > "$bin_dir/sha512sum"
    chmod +x "$bin_dir/sha256sum" "$bin_dir/sha512sum"

    TOTAL=$((TOTAL + 1))
    if PATH="$bin_dir:$PATH" CANDIDATE2_PROVENANCE_FILE="$provenance_file" bash "$REPO_ROOT/tools/vm/install-candidate2.sh" --iso "$case_dir/cand2.iso" --disk "$case_dir/cand2.qcow2" --mode uefi --runtime-evidence-dir "$case_dir/runtime" > "$case_dir/install.out" 2> "$case_dir/install.err"; then
        printf '[FAIL] %s accepted invalid installer provenance/hash state\n' "$name" >&2
        exit 1
    fi
    grep -q "$expected_pattern" "$case_dir/install.err"
    [[ ! -e "$case_dir/cand2.qcow2" ]]
    if find "$case_dir" \( -name 'qemu-*.pid' -o -name '*.qcow2' \) -print | grep . >/dev/null; then
        printf '[FAIL] %s created disk or QEMU process artifacts\n' "$name" >&2
        exit 1
    fi
    pass "$name"
}

write_collector_stage_logs() {
    local stage_dir="$1"
    local candidate_sha="$2"
    local test_iso_command="${3:-test-iso-build}"
    mkdir -p "$stage_dir"
    local head_sha
    head_sha=$(git -C "$REPO_ROOT" rev-parse HEAD)
    printf '{"candidate_branch":"validation/0.3.0-alpha-candidate-2","candidate_sha":"%s","remote_candidate_sha":"%s","git_head":"%s","working_tree_clean":true,"target_build_version":"0.3.0-alpha","workflow_run_id":"100","exit_code":0,"status":"PASS"}\n' "$candidate_sha" "$candidate_sha" "$candidate_sha" > "$stage_dir/stage-candidate-selection.json"
    printf '{"command":"check-retired-candidate-claims.py","exit_code":0,"status":"PASS","source_commit":"%s","environment":"fixture"}\n' "$head_sha" > "$stage_dir/stage-documentation.json"
    for stage in package-build repository-publication tamper rollback installer test-iso-boot; do
        printf '{"command":"%s","exit_code":0,"status":"PASS","environment":"fixture","observations":{"captured_apt_output":"Reading package lists... Done","source_commit":"%s","iso_sha256":"abc","slideshow_verified":true,"vm_command_logs":"qemu"}}\n' "$stage" "$head_sha" > "$stage_dir/stage-${stage}.json"
    done
    printf '{"command":"cmp --silent build-a.iso build-b.iso","exit_code":0,"status":"PASS","environment":"fixture","artifact_hashes":{"build_a_sha256":"abc","build_b_sha256":"abc","build_a_sha512":"def","build_b_sha512":"def","cmp_exit_code":0},"observations":{"build_a_iso":"build-a.iso","build_b_iso":"build-b.iso"}}\n' > "$stage_dir/stage-reproducibility.json"
    printf '{"command":"apt-get update && apt-get install -y genixbit-os-desktop && apt-get check","exit_code":0,"status":"PASS","environment":"fixture","environment_id":"Disposable Ubuntu client","observations":{"captured_apt_output":"Reading package lists... Done\\nGet:1 http://127.0.0.1 resolute-alpha main"}}\n' > "$stage_dir/stage-clean-install.json"
    printf '{"command":"./tools/vm/install-candidate2.sh && ./tools/vm/migrate-candidate2.sh --staging-url http://127.0.0.1:8080","exit_code":0,"status":"PASS","environment":"fixture","observations":{"candidate2_iso_sha256":"%s"}}\n' "$candidate_sha" > "$stage_dir/stage-candidate-upgrade.json"
    printf '{"command":"%s","exit_code":0,"status":"PASS","source_commit":"%s","environment":"fixture","observations":{"source_commit":"%s","iso_filename":"fixture.iso","iso_size_bytes":1,"iso_sha256":"abc"}}\n' "$test_iso_command" "$head_sha" "$head_sha" > "$stage_dir/stage-test-iso-build.json"
}

run_collector_failure_case() {
    local name="$1"
    local provenance_file="$2"
    local evidence_sha="$3"
    local expected_pattern="$4"
    local case_dir="$TMP_DIR/collector-$TOTAL"
    local stage_dir="$case_dir/stage-logs"
    write_collector_stage_logs "$stage_dir" "$evidence_sha"

    TOTAL=$((TOTAL + 1))
    if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" --active-release-mode candidate2-retirement-test --stage-logs-dir "$stage_dir" --current-dir "$case_dir/current" --candidate2-provenance-file "$provenance_file" > "$case_dir/collector.out" 2> "$case_dir/collector.err"; then
        printf '[FAIL] %s accepted invalid evidence/provenance state\n' "$name" >&2
        exit 1
    fi
    grep -q "$expected_pattern" "$case_dir/collector.err"
    pass "$name"
}

check "retirement JSON parses successfully" python3 -m json.tool "$RETIREMENT_JSON"
check "status equals RETIRED_INVALID_ZERO_FILLED" test "$(json_value "$RETIREMENT_JSON" status)" = "RETIRED_INVALID_ZERO_FILLED"
check "usable_as_release_artifact is false" test "$(json_value "$RETIREMENT_JSON" usable_as_release_artifact)" = "False"
check "usable_as_migration_source is false" test "$(json_value "$RETIREMENT_JSON" usable_as_migration_source)" = "False"
check "historical size is preserved" test "$(json_value "$RETIREMENT_JSON" size_bytes)" = "2540554240"
check "historical SHA-256 is preserved" test "$(json_value "$RETIREMENT_JSON" sha256)" = "$RETIRED_SHA"
check "historical SHA-512 is preserved" test "$(json_value "$RETIREMENT_JSON" sha512)" = "$RETIRED_SHA512"
check "historical GCS generation is preserved" test "$(json_value "$RETIREMENT_JSON" gcp_object_generation)" = "1784810864397202"
check "release metadata no longer marks object PASS" test "$(json_value "$ARTIFACT_JSON" verification_status)" = "RETIRED_INVALID_ZERO_FILLED"

TOTAL=$((TOTAL + 1))
if bash "$REPO_ROOT/tools/validation/check-release-manifest.sh" --manifest "$REPO_ROOT/docs/releases/0.2.0-alpha.env" > "$TMP_DIR/manifest.out" 2> "$TMP_DIR/manifest.err"; then
    printf '[FAIL] release manifest validation accepted retired artifact\n' >&2
    exit 1
fi
pass "release manifest validation rejects retired object"

missing_install_provenance="$TMP_DIR/missing-install-provenance.json"
malformed_install_provenance="$TMP_DIR/malformed-install-provenance.json"
retired_install_provenance="$TMP_DIR/retired-install-provenance.json"
unusable_install_provenance="$TMP_DIR/unusable-install-provenance.json"
active_install_provenance="$TMP_DIR/active-install-provenance.json"
false_usable_retired_install_provenance="$TMP_DIR/false-usable-retired-install-provenance.json"
printf '{not-json\n' > "$malformed_install_provenance"
write_provenance "$retired_install_provenance" "RETIRED_INVALID_ZERO_FILLED" false "$RETIRED_SHA"
write_provenance "$unusable_install_provenance" "PASS" false "$ACTIVE_SHA"
write_provenance "$active_install_provenance" "PASS" true "$ACTIVE_SHA"
write_provenance "$false_usable_retired_install_provenance" "PASS" true "$RETIRED_SHA"

run_install_failure_case "install-candidate2.sh fails closed when metadata is missing" "$missing_install_provenance" "$ACTIVE_SHA" 'provenance file missing or unreadable'
run_install_failure_case "install-candidate2.sh fails closed when metadata is malformed" "$malformed_install_provenance" "$ACTIVE_SHA" 'provenance file is malformed'
run_install_failure_case "install-candidate2.sh rejects retired metadata before disk or QEMU" "$retired_install_provenance" "$RETIRED_SHA" 'retired or unusable\|retired: recorded object'
run_install_failure_case "install-candidate2.sh rejects unusable metadata before disk or QEMU" "$unusable_install_provenance" "$ACTIVE_SHA" 'retired or unusable'
run_install_failure_case "install-candidate2.sh rejects retired SHA even if metadata is falsely usable" "$false_usable_retired_install_provenance" "$RETIRED_SHA" 'retired: recorded object'
run_install_failure_case "install-candidate2.sh rejects arbitrary nonmatching ISO SHA" "$active_install_provenance" "$OTHER_SHA" 'SHA-256 mismatch'

TOTAL=$((TOTAL + 1))
snapshot_results "$TMP_DIR/results-before.txt"
if ACTIVE_RELEASE_MODE=candidate2-retirement-test bash "$REPO_ROOT/tools/validation/validate-package-migration.sh" > "$TMP_DIR/migration.out" 2> "$TMP_DIR/migration.err"; then
    printf '[FAIL] migration validation accepted retired artifact\n' >&2
    exit 1
fi
grep -q 'Candidate 2 artifact is retired' "$TMP_DIR/migration.out" "$TMP_DIR/migration.err"
snapshot_results "$TMP_DIR/results-after.txt"
cmp "$TMP_DIR/results-before.txt" "$TMP_DIR/results-after.txt"
pass "migration validation rejects retired artifact and preserves production evidence"

pending_migration_provenance="$TMP_DIR/pending-migration-provenance.json"
unknown_migration_provenance="$TMP_DIR/unknown-migration-provenance.json"
empty_status_migration_provenance="$TMP_DIR/empty-status-migration-provenance.json"
active_migration_provenance="$TMP_DIR/active-migration-provenance.json"
write_provenance "$pending_migration_provenance" "PENDING" true "$ACTIVE_SHA"
write_provenance "$unknown_migration_provenance" "UNKNOWN" true "$ACTIVE_SHA"
write_provenance "$empty_status_migration_provenance" "" true "$ACTIVE_SHA"
write_provenance "$active_migration_provenance" "PASS" true "$ACTIVE_SHA"

TOTAL=$((TOTAL + 1))
snapshot_results "$TMP_DIR/pending-results-before.txt"
if ACTIVE_RELEASE_MODE=candidate2-retirement-test CANDIDATE2_PROVENANCE_FILE="$pending_migration_provenance" bash "$REPO_ROOT/tools/validation/validate-package-migration.sh" > "$TMP_DIR/pending-migration.out" 2> "$TMP_DIR/pending-migration.err"; then
    printf '[FAIL] migration validation accepted PENDING artifact status\n' >&2
    exit 1
fi
grep -q "Candidate 2 provenance status 'PENDING' is not an active artifact status." "$TMP_DIR/pending-migration.out" "$TMP_DIR/pending-migration.err"
snapshot_results "$TMP_DIR/pending-results-after.txt"
cmp "$TMP_DIR/pending-results-before.txt" "$TMP_DIR/pending-results-after.txt"
pass "migration validation rejects PENDING usable provenance and preserves production evidence"

TOTAL=$((TOTAL + 1))
snapshot_results "$TMP_DIR/unknown-results-before.txt"
if ACTIVE_RELEASE_MODE=candidate2-retirement-test CANDIDATE2_PROVENANCE_FILE="$unknown_migration_provenance" bash "$REPO_ROOT/tools/validation/validate-package-migration.sh" > "$TMP_DIR/unknown-migration.out" 2> "$TMP_DIR/unknown-migration.err"; then
    printf '[FAIL] migration validation accepted UNKNOWN artifact status\n' >&2
    exit 1
fi
grep -q "Candidate 2 provenance status 'UNKNOWN' is not an active artifact status." "$TMP_DIR/unknown-migration.out" "$TMP_DIR/unknown-migration.err"
snapshot_results "$TMP_DIR/unknown-results-after.txt"
cmp "$TMP_DIR/unknown-results-before.txt" "$TMP_DIR/unknown-results-after.txt"
pass "migration validation rejects UNKNOWN usable provenance and preserves production evidence"

TOTAL=$((TOTAL + 1))
snapshot_results "$TMP_DIR/empty-status-results-before.txt"
if ACTIVE_RELEASE_MODE=candidate2-retirement-test CANDIDATE2_PROVENANCE_FILE="$empty_status_migration_provenance" bash "$REPO_ROOT/tools/validation/validate-package-migration.sh" > "$TMP_DIR/empty-status-migration.out" 2> "$TMP_DIR/empty-status-migration.err"; then
    printf '[FAIL] migration validation accepted empty artifact status\n' >&2
    exit 1
fi
grep -q "Candidate 2 provenance status '' is not an active artifact status." "$TMP_DIR/empty-status-migration.out" "$TMP_DIR/empty-status-migration.err"
snapshot_results "$TMP_DIR/empty-status-results-after.txt"
cmp "$TMP_DIR/empty-status-results-before.txt" "$TMP_DIR/empty-status-results-after.txt"
pass "migration validation rejects empty usable provenance and preserves production evidence"

TOTAL=$((TOTAL + 1))
active_migration_bin="$TMP_DIR/active-migration-bin"
mkdir -p "$active_migration_bin"
for binary in bash dirname pwd git grep cut date python3 sed mktemp rm mkdir chmod; do
    real_binary=$(command -v "$binary")
    if [[ "$real_binary" != /* ]]; then
        case "$binary" in
            bash) real_binary="/bin/bash" ;;
            dirname) real_binary="/usr/bin/dirname" ;;
            pwd) real_binary="/bin/pwd" ;;
        esac
    fi
    if [[ "$binary" == "bash" ]]; then
        printf '#!/bin/sh\nexec %q "$@"\n' "$real_binary" > "$active_migration_bin/$binary"
    else
        printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$real_binary" > "$active_migration_bin/$binary"
    fi
    chmod +x "$active_migration_bin/$binary"
done
if PATH="$active_migration_bin" ACTIVE_RELEASE_MODE=candidate2-retirement-test CANDIDATE2_PROVENANCE_FILE="$active_migration_provenance" bash "$REPO_ROOT/tools/validation/validate-package-migration.sh" > "$TMP_DIR/active-migration.out" 2> "$TMP_DIR/active-migration.err"; then
    printf '[FAIL] active migration fixture unexpectedly completed full validation\n' >&2
    exit 1
fi
if grep -q 'not an active artifact status\|Candidate 2 artifact is retired\|not usable as a migration source' "$TMP_DIR/active-migration.out" "$TMP_DIR/active-migration.err"; then
    printf '[FAIL] active migration fixture was blocked by provenance status instead of the next controlled phase\n' >&2
    exit 1
fi
grep -q 'GPG binary not found' "$TMP_DIR/active-migration.out" "$TMP_DIR/active-migration.err"
pass "migration validation accepts active provenance and reaches next controlled phase"

missing_collector_provenance="$TMP_DIR/missing-collector-provenance.json"
malformed_collector_provenance="$TMP_DIR/malformed-collector-provenance.json"
retired_collector_provenance="$TMP_DIR/retired-collector-provenance.json"
unusable_collector_provenance="$TMP_DIR/unusable-collector-provenance.json"
empty_collector_provenance="$TMP_DIR/empty-collector-provenance.json"
active_collector_provenance="$TMP_DIR/active-collector-provenance.json"
printf '{not-json\n' > "$malformed_collector_provenance"
write_provenance "$retired_collector_provenance" "RETIRED_INVALID_ZERO_FILLED" false "$RETIRED_SHA"
write_provenance "$unusable_collector_provenance" "PASS" false "$ACTIVE_SHA"
write_provenance "$empty_collector_provenance" "PASS" true ""
write_provenance "$active_collector_provenance" "PASS" true "$ACTIVE_SHA"

run_collector_failure_case "evidence collection fails when provenance is missing" "$missing_collector_provenance" "$ACTIVE_SHA" 'provenance file missing'
run_collector_failure_case "evidence collection fails when provenance is malformed" "$malformed_collector_provenance" "$ACTIVE_SHA" 'provenance file is malformed'
run_collector_failure_case "evidence collection rejects retired provenance" "$retired_collector_provenance" "$RETIRED_SHA" 'retired or unusable'
run_collector_failure_case "evidence collection rejects unusable provenance" "$unusable_collector_provenance" "$ACTIVE_SHA" 'retired or unusable'
run_collector_failure_case "evidence collection rejects empty active provenance SHA" "$empty_collector_provenance" "$ACTIVE_SHA" 'sha256 field is missing or invalid'
run_collector_failure_case "evidence collection rejects PASS evidence using retired hash" "$active_collector_provenance" "$RETIRED_SHA" 'retired zero-filled artifact'
run_collector_failure_case "evidence collection rejects arbitrary non-retired mismatching SHA" "$active_collector_provenance" "$OTHER_SHA" 'does not match active provenance SHA-256'

TOTAL=$((TOTAL + 1))
active_match_dir="$TMP_DIR/collector-active-match"
write_collector_stage_logs "$active_match_dir/stage-logs" "$ACTIVE_SHA"
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" --active-release-mode candidate2-retirement-test --stage-logs-dir "$active_match_dir/stage-logs" --current-dir "$active_match_dir/current" --candidate2-provenance-file "$active_collector_provenance" > "$active_match_dir/collector.out" 2> "$active_match_dir/collector.err"; then
    printf '[FAIL] evidence collection unexpectedly passed minimal active fixture\n' >&2
    exit 1
fi
grep -q 'must execute build.sh' "$active_match_dir/collector.err"
pass "evidence collection active fixture SHA match reaches next validation stage"

TOTAL=$((TOTAL + 1))
shim_bin="$TMP_DIR/bin"
mkdir -p "$shim_bin"
for binary in qemu-system-x86_64 qemu-img timeout socat jq curl sha256sum sha512sum xorriso isoinfo mksquashfs unsquashfs gpg gpgv dpkg-deb apt-get; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$shim_bin/$binary"
    chmod +x "$shim_bin/$binary"
done
printf '#!/usr/bin/env bash\nprintf "x86_64\\n"\n' > "$shim_bin/uname"
printf '#!/usr/bin/env bash\nprintf "8\\n"\n' > "$shim_bin/nproc"
cat > "$shim_bin/df" <<'SHIM_DF'
#!/usr/bin/env bash
cat <<'DFEOF'
Filesystem 1K-blocks Used Available Use% Mounted on
testfs 200000000 1 100000000 1% .
DFEOF
SHIM_DF
printf '#!/usr/bin/env bash\nif [[ "${1:-}" == "MemAvailable" ]]; then printf "MemAvailable: 20000000 kB\\n"; exit 0; fi\nexec /usr/bin/grep "$@"\n' > "$shim_bin/grep"
printf '#!/usr/bin/env bash\nif [[ "${1:-}" == "-c" && "${2:-}" == "import jsonschema" ]]; then exit 0; fi\nexec %q "$@"\n' "$(command -v python3)" > "$shim_bin/python3"
chmod +x "$shim_bin"/*
touch "$TMP_DIR/kvm" "$TMP_DIR/ovmf-code.fd" "$TMP_DIR/ovmf-vars.fd" "$TMP_DIR/seabios.bin"
FIXTURE_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD)
if ! PATH="$shim_bin:/usr/bin:/bin:/sbin" PREFLIGHT_TEST_ARCH=x86_64 PREFLIGHT_RESULTS_DIR="$TMP_DIR/preflight" PREFLIGHT_KVM_PATH="$TMP_DIR/kvm" PREFLIGHT_MIN_DISK_KB=1 PREFLIGHT_MIN_MEMORY_KB=1 PREFLIGHT_MIN_CPU_THREADS=1 PREFLIGHT_OVMF_CODE_CANDIDATES="$TMP_DIR/ovmf-code.fd" PREFLIGHT_OVMF_VARS_CANDIDATES="$TMP_DIR/ovmf-vars.fd" PREFLIGHT_SEABIOS_CANDIDATES="$TMP_DIR/seabios.bin" ACTIVE_RELEASE_PROVENANCE_FILE="$REPO_ROOT/docs/releases/0.3.0-alpha-artifact.json" STAGING_SIGNING_PASSPHRASE=secret GENIXBIT_STAGING_SERVER=http://127.0.0.1:18080 ACTIVE_RELEASE_SOURCE_COMMIT="$FIXTURE_SHA" EXPECTED_CANDIDATE_SHA="$FIXTURE_SHA" GITHUB_SHA="$FIXTURE_SHA" GITHUB_RUN_ID=test-run GITHUB_RUN_ATTEMPT=1 bash "$REPO_ROOT/tools/validation/run-release-preflight.sh" > "$TMP_DIR/preflight.out" 2> "$TMP_DIR/preflight.err"; then
    printf '[FAIL] preflight rejected pending active artifact metadata\n' >&2
    exit 1
fi
python3 -m json.tool "$TMP_DIR/preflight/preflight-results.json" >/dev/null
test "$(json_value "$TMP_DIR/preflight/preflight-results.json" status)" = "PASS"
test "$(json_value "$TMP_DIR/preflight/preflight-results.json" active_artifact_status)" = "PENDING_BUILD"
pass "preflight creates valid PASS JSON with pending active artifact metadata"

TOTAL=$((TOTAL + 1))
dd if=/dev/zero of="$TMP_DIR/zero.iso" bs=1M count=2 status=none
if env MIN_ISO_SIZE_MB=1 bash "$REPO_ROOT/tools/validation/check-iso-structure.sh" --iso "$TMP_DIR/zero.iso" > "$TMP_DIR/zero.out" 2> "$TMP_DIR/zero.err"; then
    printf '[FAIL] structural checker accepted zero-filled file\n' >&2
    exit 1
fi
grep -q 'Primary Volume Descriptor signature missing' "$TMP_DIR/zero.err"
pass "structural checker rejects sufficiently large zero-filled file"

check "documentation contains no active retired Candidate 2 release claims" python3 "$REPO_ROOT/tools/validation/check-retired-candidate-claims.py"
check "retired Candidate 2 claim checker behavior" bash "$REPO_ROOT/tools/validation/test-retired-candidate-claims.sh"
check "no secret or private material is written to test output" bash -c "! grep -R 'secret\|PRIVATE KEY\|passphrase' '$TMP_DIR' >/dev/null 2>&1"

printf '[PASS] Candidate 2 retirement tests passed: %s/%s\n' "$PASS" "$TOTAL"
