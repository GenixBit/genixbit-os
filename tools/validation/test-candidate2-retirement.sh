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

TOTAL=$((TOTAL + 1))
printf 'not an iso\n' > "$TMP_DIR/cand2.iso"
install_bin="$TMP_DIR/install-bin"
mkdir -p "$install_bin"
printf '#!/usr/bin/env bash\nprintf "%s  %%s\\n" "${1:-file}"\n' "$RETIRED_SHA" > "$install_bin/sha256sum"
chmod +x "$install_bin/sha256sum"
if PATH="$install_bin:$PATH" bash "$REPO_ROOT/tools/vm/install-candidate2.sh" --iso "$TMP_DIR/cand2.iso" --disk "$TMP_DIR/cand2.qcow2" --mode uefi --runtime-evidence-dir "$TMP_DIR/runtime" > "$TMP_DIR/install.out" 2> "$TMP_DIR/install.err"; then
    printf '[FAIL] install-candidate2.sh accepted retired artifact\n' >&2
    exit 1
fi
grep -q 'Candidate 2 artifact is retired: recorded object is exactly 2540554240 zero bytes and is not an ISO.' "$TMP_DIR/install.err"
[[ ! -s "$TMP_DIR/cand2.qcow2" ]]
pass "install-candidate2.sh rejects retired artifact before launching QEMU"

TOTAL=$((TOTAL + 1))
if bash "$REPO_ROOT/tools/validation/validate-package-migration.sh" > "$TMP_DIR/migration.out" 2> "$TMP_DIR/migration.err"; then
    printf '[FAIL] migration validation accepted retired artifact\n' >&2
    exit 1
fi
grep -q 'Candidate 2 artifact is retired' "$TMP_DIR/migration.out" "$TMP_DIR/migration.err"
pass "migration validation rejects retired artifact"

TOTAL=$((TOTAL + 1))
stage_dir="$TMP_DIR/stage-logs"
mkdir -p "$stage_dir"
for stage in package-build repository-publication clean-install tamper rollback installer test-iso-build test-iso-boot; do
    printf '{"command":"%s","exit_code":0,"status":"PASS","observations":{"captured_apt_output":"Reading package lists... Done","source_commit":"%s","iso_sha256":"abc","slideshow_verified":true,"vm_command_logs":"qemu"}}\n' "$stage" "$(git -C "$REPO_ROOT" rev-parse HEAD)" > "$stage_dir/stage-${stage}.json"
done
printf '{"command":"apt-get update && apt-get install -y genixbit-os-desktop && apt-get check","exit_code":0,"status":"PASS","environment_id":"Disposable Ubuntu client","observations":{"captured_apt_output":"Reading package lists... Done\\nGet:1 http://127.0.0.1 resolute-alpha main"}}\n' > "$stage_dir/stage-clean-install.json"
printf '{"command":"upgrade","exit_code":0,"status":"PASS","observations":{"candidate2_iso_sha256":"%s"}}\n' "$RETIRED_SHA" > "$stage_dir/stage-candidate-upgrade.json"
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" --stage-logs-dir "$stage_dir" > "$TMP_DIR/collector.out" 2> "$TMP_DIR/collector.err"; then
    printf '[FAIL] evidence collection accepted retired SHA\n' >&2
    exit 1
fi
grep -q 'retired zero-filled artifact' "$TMP_DIR/collector.err"
pass "evidence collection rejects PASS evidence using retired hash"

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
touch "$TMP_DIR/kvm" "$TMP_DIR/ovmf-code" "$TMP_DIR/ovmf-vars" "$TMP_DIR/seabios" "$TMP_DIR/cand2-preflight.iso"
if PATH="$shim_bin:/usr/bin:/bin:/sbin" PREFLIGHT_RESULTS_DIR="$TMP_DIR/preflight" PREFLIGHT_KVM_PATH="$TMP_DIR/kvm" PREFLIGHT_MIN_DISK_KB=1 PREFLIGHT_MIN_MEMORY_KB=1 PREFLIGHT_MIN_CPU_THREADS=1 PREFLIGHT_OVMF_CODE_CANDIDATES="$TMP_DIR/ovmf-code" PREFLIGHT_OVMF_VARS_CANDIDATES="$TMP_DIR/ovmf-vars" PREFLIGHT_SEABIOS_CANDIDATES="$TMP_DIR/seabios" PREFLIGHT_CANDIDATE2_LOCAL="$TMP_DIR/cand2-preflight.iso" STAGING_SIGNING_PASSPHRASE=secret GENIXBIT_STAGING_SERVER=http://127.0.0.1:18080 GITHUB_SHA=test-sha GITHUB_RUN_ID=test-run GITHUB_RUN_ATTEMPT=1 bash "$REPO_ROOT/tools/validation/run-release-preflight.sh" > "$TMP_DIR/preflight.out" 2> "$TMP_DIR/preflight.err"; then
    printf '[FAIL] preflight accepted retired artifact metadata\n' >&2
    exit 1
fi
python3 -m json.tool "$TMP_DIR/preflight/preflight-results.json" >/dev/null
test "$(json_value "$TMP_DIR/preflight/preflight-results.json" failed_phase)" = "candidate2_artifact_status"
pass "preflight creates valid FAIL JSON with candidate2_artifact_status"

TOTAL=$((TOTAL + 1))
dd if=/dev/zero of="$TMP_DIR/zero.iso" bs=1M count=2 status=none
if env MIN_ISO_SIZE_MB=1 bash "$REPO_ROOT/tools/validation/check-iso-structure.sh" --iso "$TMP_DIR/zero.iso" > "$TMP_DIR/zero.out" 2> "$TMP_DIR/zero.err"; then
    printf '[FAIL] structural checker accepted zero-filled file\n' >&2
    exit 1
fi
grep -q 'Primary Volume Descriptor signature missing' "$TMP_DIR/zero.err"
pass "structural checker rejects sufficiently large zero-filled file"

check "documentation no longer says Candidate 2 successfully completed release validation" bash -c "! git grep -n 'Candidate 2.*successfully completed release validation\|successfully completed release validation.*Candidate 2' -- README.md CHANGELOG.md docs website tools tests >/dev/null"
check "tests do not write into production runtime or evidence directories" bash -c "! find '$TMP_DIR' -path '*infra/package-staging/results*' -print | grep ."
check "no secret or private material is written to test output" bash -c "! grep -R 'secret\|PRIVATE KEY\|passphrase' '$TMP_DIR' >/dev/null 2>&1"

printf '[PASS] Candidate 2 retirement tests passed: %s/%s\n' "$PASS" "$TOTAL"
