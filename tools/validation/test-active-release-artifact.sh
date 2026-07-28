#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
CHECKER="$REPO_ROOT/tools/validation/check-active-release-artifact.py"
TMP_DIR=$(mktemp -d)
REAL_PYTHON=$(command -v python3)
TOTAL=0
PASS=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); printf '[PASS] %s\n' "$1"; }

make_executable() {
    local path="$1"
    shift
    printf '%s\n' '#!/usr/bin/env bash' > "$path"
    printf '%s\n' 'set -euo pipefail' >> "$path"
    printf '%s\n' "$@" >> "$path"
    chmod +x "$path"
}

make_preflight_shims() {
    local bin="$1"
    mkdir -p "$bin"
    make_executable "$bin/uname" 'printf "x86_64\n"'
    make_executable "$bin/nproc" 'printf "8\n"'
    make_executable "$bin/df" 'printf "%s\n" "Filesystem 1K-blocks Used Available Use% Mounted on"' 'printf "%s\n" "testfs 200000000 1 100000000 1% ."'
    make_executable "$bin/grep" 'if [[ "${1:-}" == "MemAvailable" ]]; then printf "MemAvailable: 20000000 kB\n"; exit 0; fi' 'exec /usr/bin/grep "$@"'
    make_executable "$bin/curl" 'exit 0'
    make_executable "$bin/python3" \
        'if [[ "${1:-}" == "-c" && "${2:-}" == "import jsonschema" ]]; then exit 0; fi' \
        "exec \"$REAL_PYTHON\" \"\$@\""
    local binary
    for binary in qemu-system-x86_64 qemu-img timeout socat jq sha256sum sha512sum xorriso isoinfo mksquashfs unsquashfs gpg gpgv dpkg-deb apt-get; do
        make_executable "$bin/$binary" 'exit 0'
    done
}

write_pending() {
    local path="$1"
    cat > "$path" <<'JSON'
{
  "schema_version": "1.0",
  "release_version": "0.3.0-alpha",
  "candidate_branch": null,
  "candidate_source_commit": null,
  "filename": null,
  "size_bytes": null,
  "sha256": null,
  "sha512": null,
  "object_generation": null,
  "verification_status": "PENDING_BUILD",
  "usable_as_release_artifact": false,
  "usable_as_migration_source": false
}
JSON
}

write_active() {
    local path="$1" iso="$2" commit="$3" filename="${4:-GenixBitOS-0.3.0-alpha-test.iso}"
    local size sha256 sha512
    size=$(wc -c < "$iso" | tr -d ' ')
    sha256=$(sha256sum "$iso" | awk '{print $1}')
    sha512=$(sha512sum "$iso" | awk '{print $1}')
    cat > "$path" <<JSON
{
  "schema_version": "1.0",
  "release_version": "0.3.0-alpha",
  "candidate_branch": "validation/0.3.0-alpha-candidate-test",
  "candidate_source_commit": "$commit",
  "filename": "$filename",
  "size_bytes": $size,
  "sha256": "$sha256",
  "sha512": "$sha512",
  "object_generation": "active-generation-test",
  "verification_status": "PASS",
  "usable_as_release_artifact": true,
  "usable_as_migration_source": false
}
JSON
}

make_iso() {
    local iso="$1"
    mkdir -p "$TMP_DIR/iso-root/casper" "$TMP_DIR/iso-root/EFI/BOOT"
    printf kernel > "$TMP_DIR/iso-root/casper/vmlinuz"
    printf initrd > "$TMP_DIR/iso-root/casper/initrd"
    mksquashfs "$TMP_DIR/iso-root" "$TMP_DIR/iso-root/casper/filesystem.squashfs" -noappend >/dev/null 2>&1
    printf efi > "$TMP_DIR/iso-root/EFI/BOOT/BOOTX64.EFI"
    printf efiboot > "$TMP_DIR/iso-root/EFI/efiboot.img"
    xorriso -as mkisofs -quiet -o "$iso" -V GENIXBIT_TEST -eltorito-boot EFI/BOOT/BOOTX64.EFI -no-emul-boot "$TMP_DIR/iso-root" >/dev/null 2>&1
}

expect_pass() { local name="$1"; shift; TOTAL=$((TOTAL + 1)); "$@" >/dev/null; pass "$name"; }
expect_fail() { local name="$1" field="$2"; shift 2; TOTAL=$((TOTAL + 1)); if "$@" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then printf '[FAIL] %s unexpectedly passed\n' "$name" >&2; exit 1; fi; if ! grep -q "$field" "$TMP_DIR/err" "$TMP_DIR/out"; then printf '[FAIL] %s did not report %s\n' "$name" "$field" >&2; exit 1; fi; pass "$name"; }

commit="abcdef1234567890abcdef1234567890abcdef12"
pending="$TMP_DIR/pending.json"
write_pending "$pending"
iso="$TMP_DIR/GenixBitOS-0.3.0-alpha-test.iso"
make_iso "$iso"
active="$TMP_DIR/active.json"
write_active "$active" "$iso" "$commit"
preflight_bin="$TMP_DIR/preflight-bin"
make_preflight_shims "$preflight_bin"
iso_validation_bin="$TMP_DIR/iso-validation-bin"
mkdir -p "$iso_validation_bin"
make_executable "$iso_validation_bin/mdir" 'exit 0'

expect_pass "host preflight succeeds without requiring pre-existing ISO" env PREFLIGHT_RESULTS_DIR="$TMP_DIR/preflight" PREFLIGHT_KVM_PATH="$TMP_DIR/kvm" PREFLIGHT_MIN_DISK_KB=1 PREFLIGHT_MIN_MEMORY_KB=1 PREFLIGHT_MIN_CPU_THREADS=1 PREFLIGHT_OVMF_CODE_CANDIDATES="$TMP_DIR/ovmf-code" PREFLIGHT_OVMF_VARS_CANDIDATES="$TMP_DIR/ovmf-vars" PREFLIGHT_SEABIOS_CANDIDATES="$TMP_DIR/seabios" STAGING_SIGNING_PASSPHRASE=secret GENIXBIT_STAGING_SERVER=http://127.0.0.1:18080 ACTIVE_RELEASE_PROVENANCE_FILE="$pending" bash -c 'touch "$PREFLIGHT_KVM_PATH" "$PREFLIGHT_OVMF_CODE_CANDIDATES" "$PREFLIGHT_OVMF_VARS_CANDIDATES" "$PREFLIGHT_SEABIOS_CANDIDATES"; PATH="'$preflight_bin':/usr/bin:/bin:/sbin" bash tools/validation/run-release-preflight.sh'
expect_fail "artifact validation fails when provenance is PENDING_BUILD" verification_status python3 "$CHECKER" --provenance-file "$pending" --source-commit "$commit" --iso "$iso" --require-pass
expect_pass "artifact validation accepts only exact active provenance" env MIN_ISO_SIZE_MB=0 PATH="$iso_validation_bin:$PATH" python3 "$CHECKER" --provenance-file "$active" --source-commit "$commit" --iso "$iso" --require-pass

for field in filename sha256 sha512 object_generation; do
    bad="$TMP_DIR/bad-$field.json"; cp "$active" "$bad"
    python3 - "$bad" "$field" <<'PY'
import json, sys
p, field = sys.argv[1:3]
d = json.load(open(p, encoding='utf-8'))
vals = {
 'filename': 'GenixBitOS-0.2.0-alpha-2607220558.iso',
 'sha256': '1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669',
 'sha512': '51bdb60298460d1204dd6b641ed7d531c9d34da98fecf90fbfbbabf9beeef0dc42fe86e59646c7cd4c8746b1c5e48d05afc81712758c51cb2096a77c45e0902e',
 'object_generation': '1784810864397202',
}
d[field] = vals[field]
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2)
PY
    case "$field" in
        filename) expect_fail "Candidate 2 filename fails" retired_filename env MIN_ISO_SIZE_MB=0 PATH="$iso_validation_bin:$PATH" python3 "$CHECKER" --provenance-file "$bad" --source-commit "$commit" --iso "$iso" --require-pass ;;
        sha256) expect_fail "Candidate 2 SHA-256 fails" retired_sha256 env MIN_ISO_SIZE_MB=0 PATH="$iso_validation_bin:$PATH" python3 "$CHECKER" --provenance-file "$bad" --source-commit "$commit" --iso "$iso" --require-pass ;;
        sha512) expect_fail "Candidate 2 SHA-512 fails" retired_sha512 env MIN_ISO_SIZE_MB=0 PATH="$iso_validation_bin:$PATH" python3 "$CHECKER" --provenance-file "$bad" --source-commit "$commit" --iso "$iso" --require-pass ;;
        object_generation) expect_fail "Candidate 2 object generation fails" retired_object_generation env MIN_ISO_SIZE_MB=0 PATH="$iso_validation_bin:$PATH" python3 "$CHECKER" --provenance-file "$bad" --source-commit "$commit" --iso "$iso" --require-pass ;;
    esac
done

expect_fail "missing active provenance fails" active_provenance_file python3 "$CHECKER" --provenance-file "$TMP_DIR/missing.json" --source-commit "$commit" --iso "$iso" --require-pass
printf '{not-json\n' > "$TMP_DIR/malformed.json"
expect_fail "malformed active provenance fails" active_provenance_file python3 "$CHECKER" --provenance-file "$TMP_DIR/malformed.json" --source-commit "$commit" --iso "$iso" --require-pass
expect_fail "wrong source commit fails" candidate_source_commit env MIN_ISO_SIZE_MB=0 PATH="$iso_validation_bin:$PATH" python3 "$CHECKER" --provenance-file "$active" --source-commit 0000000000000000000000000000000000000000 --iso "$iso" --require-pass
expect_fail "wrong release version fails" release_version env MIN_ISO_SIZE_MB=0 PATH="$iso_validation_bin:$PATH" python3 "$CHECKER" --provenance-file "$active" --release-version 0.2.0-alpha --source-commit "$commit" --iso "$iso" --require-pass
wrong_file="$TMP_DIR/wrong-file.json"; cp "$active" "$wrong_file"; python3 - "$wrong_file" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d['filename']='wrong.iso'; json.dump(d, open(p,'w'), indent=2)
PY
expect_fail "wrong filename fails" iso python3 "$CHECKER" --provenance-file "$wrong_file" --source-commit "$commit" --iso "$TMP_DIR/wrong.iso" --require-pass
hash_bad="$TMP_DIR/hash-bad.json"; cp "$active" "$hash_bad"; python3 - "$hash_bad" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d['sha256']='0'*64; json.dump(d, open(p,'w'), indent=2)
PY
expect_fail "hash mismatch fails" sha256 env MIN_ISO_SIZE_MB=0 PATH="$iso_validation_bin:$PATH" python3 "$CHECKER" --provenance-file "$hash_bad" --source-commit "$commit" --iso "$iso" --require-pass
bad_iso="$TMP_DIR/bad.iso"; printf bad > "$bad_iso"; bad_iso_json="$TMP_DIR/bad-iso.json"; write_active "$bad_iso_json" "$bad_iso" "$commit" bad.iso
expect_fail "structurally invalid ISO fails" iso_structure python3 "$CHECKER" --provenance-file "$bad_iso_json" --source-commit "$commit" --iso "$bad_iso" --require-pass
expect_pass "valid active ISO reaches VM phase" env MIN_ISO_SIZE_MB=0 PATH="$iso_validation_bin:$PATH" bash -c "python3 '$CHECKER' --provenance-file '$active' --source-commit '$commit' --iso '$iso' --require-pass >/dev/null"

gate="$TMP_DIR/gate.json"
cat > "$gate" <<JSON
{"categories":{"clean_install_readiness":{"status":"PASS"},"vm_readiness":{"status":"PASS"},"installer_readiness":{"status":"PASS"},"package_health_readiness":{"status":"PASS"},"reproducibility_readiness":{"status":"PASS"},"upgrade_readiness":{"status":"NOT_APPLICABLE","reason":"No valid prior GenixBit OS release artifact exists from which to execute an upgrade or rollback test."},"rollback_readiness":{"status":"NOT_APPLICABLE","reason":"No valid prior GenixBit OS release artifact exists from which to execute an upgrade or rollback test."}},"summary":{"pass_count":5,"fail_count":0,"blocked_count":0,"not_tested_count":0,"not_applicable_count":2,"release_ready":true,"stable_ready":false,"overall_gate_status":"PASS_ALPHA_FRESH_INSTALL"}}
JSON
expect_pass "fresh-install-only does not execute migration from Candidate 2" python3 "$CHECKER" --gate-file "$gate"
expect_pass "upgrade is NOT_APPLICABLE not PASS" python3 "$CHECKER" --gate-file "$gate"
expect_pass "rollback is NOT_APPLICABLE not PASS" python3 "$CHECKER" --gate-file "$gate"
bad_gate="$TMP_DIR/bad-gate.json"; cp "$gate" "$bad_gate"; python3 - "$bad_gate" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d['categories']['vm_readiness']['status']='FAIL'; d['summary']['pass_count']=4; d['summary']['fail_count']=1; json.dump(d, open(p,'w'), indent=2)
PY
expect_fail "required fresh-install failures block release readiness" overall_gate_status python3 "$CHECKER" --gate-file "$bad_gate"
expect_pass "PASS_ALPHA_FRESH_INSTALL requires all mandatory runtime checks" python3 "$CHECKER" --gate-file "$gate"
TOTAL=$((TOTAL + 1)); if git -C "$REPO_ROOT" grep -n 'CANDIDATE2_ISO_URL' -- .github/workflows/release-gate.yml tools/validation/run-release-preflight.sh >/dev/null; then printf '[FAIL] active workflow references CANDIDATE2_ISO_URL\n' >&2; exit 1; fi; pass "no active workflow references CANDIDATE2_ISO_URL"

printf '[PASS] active release artifact tests passed: %s/%s\n' "$PASS" "$TOTAL"
