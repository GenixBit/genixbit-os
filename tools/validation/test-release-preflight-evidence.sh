#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
PREFLIGHT="$REPO_ROOT/tools/validation/run-release-preflight.sh"
TMP_DIR=$(mktemp -d)
REAL_PYTHON=$(command -v python3)
TOTAL=0
PASS=0

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

make_executable() {
    local path="$1"
    shift
    printf '%s\n' '#!/usr/bin/env bash' > "$path"
    printf '%s\n' 'set -euo pipefail' >> "$path"
    printf '%s\n' "$@" >> "$path"
    chmod +x "$path"
}

make_shims() {
    local bin_dir="$1"
    local missing_binary="${2:-}"
    mkdir -p "$bin_dir"

    make_executable "$bin_dir/python3" \
        'if [[ "${1:-}" == "-c" && "${2:-}" == "import jsonschema" ]]; then exit 0; fi' \
        "exec \"$REAL_PYTHON\" \"\$@\""
    make_executable "$bin_dir/uname" 'printf "%s\n" "${TEST_ARCH:-x86_64}"'
    make_executable "$bin_dir/nproc" 'printf "%s\n" "${TEST_CPU:-8}"'
    make_executable "$bin_dir/df" 'printf "%s\n" "Filesystem 1K-blocks Used Available Use% Mounted on"' 'printf "%s\n" "testfs 200000000 1 ${TEST_DISK_AVAIL:-100000000} 1% ."'
    make_executable "$bin_dir/grep" \
        'if [[ "${1:-}" == "MemAvailable" ]]; then printf "MemAvailable: %s kB\n" "${TEST_MEM_AVAIL:-20000000}"; exit 0; fi' \
        'exec /usr/bin/grep "$@"'
    make_executable "$bin_dir/curl" '[[ "${TEST_CURL_FAIL:-0}" == "1" ]] && exit 22' 'exit 0'
    make_executable "$bin_dir/sha256sum" 'printf "%s  %s\n" "${TEST_SHA256:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}" "${1:-file}"'
    make_executable "$bin_dir/sha512sum" 'printf "%s  %s\n" "51bdb60298460d1204dd6b641ed7d531c9d34da98fecf90fbfbbabf9beeef0dc42fe86e59646c7cd4c8746b1c5e48d05afc81712758c51cb2096a77c45e0902e" "${1:-file}"'

    local binary
    for binary in qemu-system-x86_64 qemu-img timeout socat jq xorriso isoinfo mksquashfs unsquashfs gpg gpgv dpkg-deb apt-get; do
        [[ "$binary" == "$missing_binary" ]] && continue
        make_executable "$bin_dir/$binary" 'exit 0'
    done
}

json_get() {
    local file="$1"
    local expr="$2"
    "$REAL_PYTHON" - "$file" "$expr" <<'PYEOF'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
expr = sys.argv[2]
value = data
for part in expr.split('.'):
    value = value[part]
print(value)
PYEOF
}

assert_json() {
    local file="$1"
    local status="$2"
    local phase="$3"
    local expected_exit_zero="$4"
    local source_commit="$5"
    local run_id="$6"
    local run_attempt="$7"
    "$REAL_PYTHON" -m json.tool "$file" >/dev/null

    [[ "$(json_get "$file" status)" == "$status" ]] || return 1
    [[ "$(json_get "$file" source_commit)" == "$source_commit" ]] || return 1
    [[ "$(json_get "$file" workflow_run_id)" == "$run_id" ]] || return 1
    [[ "$(json_get "$file" workflow_run_attempt)" == "$run_attempt" ]] || return 1

    local exit_code
    exit_code=$(json_get "$file" exit_code)
    if [[ "$expected_exit_zero" == "yes" ]]; then
        [[ "$exit_code" == "0" ]] || return 1
    else
        [[ "$exit_code" != "0" ]] || return 1
        [[ "$(json_get "$file" failed_phase)" == "$phase" ]] || return 1
    fi
}

run_case() {
    local name="$1"
    local expected_status="$2"
    local expected_phase="$3"
    local expected_exit_zero="$4"
    local expected_rc_zero="$5"
    local missing_binary="${6:-}"
    shift 6 || true

    TOTAL=$((TOTAL + 1))
    local case_dir="$TMP_DIR/case-$TOTAL"
    local bin_dir="$case_dir/bin"
    local results_dir="$case_dir/results"
    mkdir -p "$case_dir" "$results_dir" "$case_dir/dist"
    make_shims "$bin_dir" "$missing_binary"

    local kvm_path="$case_dir/kvm"
    local ovmf_code="$case_dir/OVMF_CODE.fd"
    local ovmf_vars="$case_dir/OVMF_VARS.fd"
    local seabios="$case_dir/bios.bin"
    local artifact_provenance="$case_dir/artifact.json"
    : > "$kvm_path"
    : > "$ovmf_code"
    : > "$ovmf_vars"
    : > "$seabios"
    printf '{"schema_version":"1.0","release_version":"0.3.0-alpha","candidate_branch":null,"candidate_source_commit":null,"filename":null,"size_bytes":null,"sha256":null,"sha512":null,"object_generation":null,"verification_status":"PENDING_BUILD","usable_as_release_artifact":false,"usable_as_migration_source":false}\n' > "$artifact_provenance"

    local source_commit="abcdef1234567890abcdef1234567890abcdef12"
    local run_id="preflight-test-run"
    local run_attempt="7"
    local secret="top-secret-passphrase-value"
    local iso_marker=""

    while (($# > 0)); do
        case "$1" in
            --arch) export TEST_ARCH="$2"; shift 2 ;;
            --missing-kvm) rm -f "$kvm_path"; shift ;;
            --missing-firmware) rm -f "$ovmf_vars"; shift ;;
            --disk) export TEST_DISK_AVAIL="$2"; shift 2 ;;
            --memory) export TEST_MEM_AVAIL="$2"; shift 2 ;;
            --no-secret) secret=""; shift ;;
            --curl-fail) export TEST_CURL_FAIL=1; shift ;;
            --mark-iso-structure) iso_marker="$case_dir/iso-structure-ran"; shift ;;
            *) printf '[FAIL] Unknown test option: %s\n' "$1" >&2; exit 1 ;;
        esac
    done

    set +e
    PATH="$bin_dir:/usr/bin:/bin:/sbin" \
    PREFLIGHT_RESULTS_DIR="$results_dir" \
    PREFLIGHT_KVM_PATH="$kvm_path" \
    PREFLIGHT_MIN_DISK_KB=1 \
    PREFLIGHT_MIN_MEMORY_KB=1 \
    PREFLIGHT_MIN_CPU_THREADS=1 \
    PREFLIGHT_OVMF_CODE_CANDIDATES="$ovmf_code" \
    PREFLIGHT_OVMF_VARS_CANDIDATES="$ovmf_vars" \
    PREFLIGHT_SEABIOS_CANDIDATES="$seabios" \
    ACTIVE_RELEASE_PROVENANCE_FILE="$artifact_provenance" \
    ACTIVE_RELEASE_VERSION="0.3.0-alpha" \
    ACTIVE_RELEASE_MODE="fresh-install-only" \
    GITHUB_SHA="$source_commit" \
    GITHUB_RUN_ID="$run_id" \
    GITHUB_RUN_ATTEMPT="$run_attempt" \
    RUNNER_NAME="preflight-test-runner" \
    STAGING_SIGNING_PASSPHRASE="$secret" \
    GENIXBIT_STAGING_SERVER="http://127.0.0.1:18080" \
    bash "$PREFLIGHT" > "$case_dir/stdout.log" 2> "$case_dir/stderr.log"
    local rc=$?
    set -e

    unset TEST_ARCH TEST_DISK_AVAIL TEST_MEM_AVAIL TEST_CURL_FAIL TEST_SHA256

    local result_file="$results_dir/preflight-results.json"
    [[ -s "$result_file" ]] || {
        printf '[FAIL] %s did not write preflight-results.json\n' "$name" >&2
        exit 1
    }
    assert_json "$result_file" "$expected_status" "$expected_phase" "$expected_exit_zero" "$source_commit" "$run_id" "$run_attempt" || {
        printf '[FAIL] %s produced invalid JSON evidence\n' "$name" >&2
        cat "$result_file" >&2
        exit 1
    }

    if [[ "$expected_rc_zero" == "yes" ]]; then
        [[ "$rc" == "0" ]] || { printf '[FAIL] %s returned rc=%s, expected 0\n' "$name" "$rc" >&2; exit 1; }
    else
        [[ "$rc" != "0" ]] || { printf '[FAIL] %s returned rc=0, expected nonzero\n' "$name" >&2; exit 1; }
        [[ "$(json_get "$result_file" exit_code)" == "$rc" ]] || { printf '[FAIL] %s did not preserve original rc\n' "$name" >&2; exit 1; }
    fi

    if /usr/bin/grep -R "top-secret-passphrase-value" "$result_file" "$case_dir/stdout.log" "$case_dir/stderr.log" >/dev/null 2>&1; then
        printf '[FAIL] %s leaked secret material\n' "$name" >&2
        exit 1
    fi
    if [[ -n "$iso_marker" && -e "$iso_marker" ]]; then
        printf '[FAIL] %s reached ISO structural validation unexpectedly\n' "$name" >&2
        exit 1
    fi

    PASS=$((PASS + 1))
    printf '[PASS] %s\n' "$name"
}

run_case "architecture failure produces valid FAIL JSON" FAIL architecture no no "" --arch arm64
run_case "missing KVM produces valid FAIL JSON" FAIL kvm no no "" --missing-kvm
run_case "missing required binary produces valid FAIL JSON" FAIL required_binaries no no socat
run_case "missing firmware produces valid FAIL JSON" FAIL firmware no no "" --missing-firmware
run_case "insufficient disk produces valid FAIL JSON" FAIL disk no no "" --disk 0
run_case "insufficient memory produces valid FAIL JSON" FAIL memory no no "" --memory 0
run_case "missing secret produces valid FAIL JSON without leaking" FAIL secret no no "" --no-secret
run_case "unreachable staging server produces valid FAIL JSON" FAIL staging_server no no "" --curl-fail
run_case "pending active artifact accepted before build" PASS "" yes yes "" --mark-iso-structure
run_case "successful preflight produces PASS JSON" PASS "" yes yes ""
run_case "JSON source commit and workflow identity match supplied values" PASS "" yes yes ""
run_case "failure JSON contains the real first failed phase" FAIL architecture no no "" --arch arm64
run_case "script returns the original non-zero exit code" FAIL kvm no no "" --missing-kvm
run_case "no private key passphrase or unredacted secret appears in evidence" FAIL secret no no "" --no-secret

printf '[PASS] Release preflight evidence tests passed: %s/%s\n' "$PASS" "$TOTAL"
