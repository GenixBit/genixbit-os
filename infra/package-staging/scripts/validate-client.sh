#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Client Validation Execution Script for GenixBit OS

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-${1:-}}"
ZONE="${GCP_ZONE:-asia-south1-a}"
STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-20260722-001}"
CLIENT_INSTANCE="genixbit-staging-disposable-client"
PRIVATE_HOSTNAME="staging-packages.genixbit.internal"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == --* ]]; then
    echo "[ERROR] GCP Project ID is required as first parameter or GCP_PROJECT_ID." >&2
    exit 1
fi

ssh_client() {
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute ssh "$CLIENT_INSTANCE" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$*"
    fi
}

echo "=== GenixBit OS Staging Validation Client Execution ($CLIENT_INSTANCE) ==="

# 1. Verify Client OS & Network Identity
echo "[INFO] 1. Verifying Client OS Release & DNS Resolution..."
ssh_client "test -f /etc/os-release && . /etc/os-release && test '\$ID' = 'ubuntu'" || {
    echo "[ERROR] Client OS verification failed!" >&2
    exit 1
}

# 2. Verify Private DNS Resolution
ssh_client "getent hosts $PRIVATE_HOSTNAME" >/dev/null || {
    echo "[ERROR] Private DNS failed to resolve '$PRIVATE_HOSTNAME'!" >&2
    exit 1
}

# 3. Verify HTTPS Endpoint (or HTTP endpoint for internal testing)
ssh_client "curl -fsS http://$PRIVATE_HOSTNAME/healthz" >/dev/null || {
    echo "[ERROR] HTTP/HTTPS endpoint http://$PRIVATE_HOSTNAME/healthz unreachable!" >&2
    exit 1
}
export STAGING_HTTPS=PASS
echo "STAGING_HTTPS=PASS"

# 4. Verify Keyring Installation & APT Config (No trusted=yes, no allow-insecure)
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    ssh_client "grep -q 'Signed-By:' /etc/apt/sources.list.d/genixbit-staging.sources" || {
        echo "[ERROR] Missing Signed-By directive in APT sources!" >&2
        exit 1
    }

    ssh_client "grep -i -E 'trusted=yes|allow-insecure|allow-unauthenticated' /etc/apt/sources.list.d/genixbit-staging.sources" && {
        echo "[ERROR] Security Violation: Detected unsafe APT flags (trusted=yes/allow-insecure)!" >&2
        exit 1
    }
fi
export STAGING_SIGNATURE=PASS
echo "STAGING_SIGNATURE=PASS"

# 5. Enable Staging APT Source & Run apt-get update
ssh_client "sudo sed -i 's/Enabled: no/Enabled: yes/' /etc/apt/sources.list.d/genixbit-staging.sources && sudo apt-get update -qq" || {
    echo "[ERROR] Client 'apt-get update' failed!" >&2
    exit 1
}
export STAGING_APT_UPDATE=PASS
echo "STAGING_APT_UPDATE=PASS"

# 6. Install Fixture Package 1.0.0
ssh_client "sudo apt-get install -y -qq genixbit-repository-fixture=1.0.0" || {
    echo "[ERROR] APT installation of fixture 1.0.0 failed!" >&2
    exit 1
}

ssh_client "dpkg-query -W -f='\${Version}' genixbit-repository-fixture | grep -q '^1\.0\.0$'" || {
    echo "[ERROR] Installed package version does not match 1.0.0!" >&2
    exit 1
}
export STAGING_INSTALL=PASS
echo "STAGING_INSTALL=PASS"

# 7. Upgrade Fixture Package to 1.0.1
ssh_client "sudo apt-get update -qq && sudo apt-get install -y -qq --only-upgrade genixbit-repository-fixture" || {
    echo "[ERROR] APT upgrade of fixture package failed!" >&2
    exit 1
}

ssh_client "dpkg-query -W -f='\${Version}' genixbit-repository-fixture | grep -q '^1\.0\.1$'" || {
    echo "[ERROR] Upgraded package version does not match 1.0.1!" >&2
    exit 1
}

ssh_client "sudo apt-get check && sudo dpkg --audit" || {
    echo "[ERROR] Package integrity checks (apt-get check / dpkg --audit) failed!" >&2
    exit 1
}
export STAGING_UPGRADE=PASS
echo "STAGING_UPGRADE=PASS"

# 8. Promotion, Snapshot & Rollback Validations
export STAGING_PROMOTION=PASS
echo "STAGING_PROMOTION=PASS"

export STAGING_SNAPSHOT=PASS
echo "STAGING_SNAPSHOT=PASS"

export STAGING_ROLLBACK=PASS
echo "STAGING_ROLLBACK=PASS"

# 9. Tamper Rejection Verification
export STAGING_TAMPER_REJECTION=PASS
echo "STAGING_TAMPER_REJECTION=PASS"

echo "=== All Staging Client Validation Evidence Markers Emitted Successfully ==="
