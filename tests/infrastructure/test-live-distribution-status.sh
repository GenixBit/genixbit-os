#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Automated lightweight check for live GenixBit OS distribution & public web portals.

set -Eeuo pipefail

pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

ISO_URL="https://storage.googleapis.com/genixbit-growth-os-downloads/GenixBitOS-0.2.0-alpha-2607220558.iso"
CHECKSUM_URL="https://storage.googleapis.com/genixbit-growth-os-downloads/GenixBitOS-0.2.0-alpha-2607220558.iso.sha256"
EXPECTED_SIZE=2540554240

echo "=== 1. Checking Checksum File Availability ==="
checksum_out=$(curl -sL "$CHECKSUM_URL")
if [[ "$checksum_out" == *"d9aa0d2e850fdbcfb87beeaecb1ea2762a4d9522aa48d3bc6aa2bd0c6ee6f228"* ]]; then
    pass "Checksum file is publicly available and contains expected SHA-256."
else
    fail "Checksum file missing or invalid: $checksum_out"
fi

echo "=== 2. Checking ISO HEAD Request & Content-Length ==="
headers=$(curl -sIL "$ISO_URL")
if echo "$headers" | grep -qi "HTTP/.* 200"; then
    pass "ISO HEAD request returned HTTP 200 OK."
else
    fail "ISO HEAD request failed: $headers"
fi

if echo "$headers" | grep -qi "content-length: $EXPECTED_SIZE"; then
    pass "ISO Content-Length matches expected $EXPECTED_SIZE bytes."
else
    fail "ISO Content-Length mismatch: $headers"
fi

echo "=== 3. Checking HTTP Range Request Support ==="
range_headers=$(curl -sI -r 0-1023 "$ISO_URL")
if echo "$range_headers" | grep -qi "HTTP/.* 206"; then
    pass "HTTP Range request returned HTTP 206 Partial Content."
else
    fail "Range request failed: $range_headers"
fi

echo "=== 4. Checking OS Portal (os.genixbit.com) ==="
os_html=$(curl -sL https://os.genixbit.com)
if echo "$os_html" | grep -q "$ISO_URL"; then
    pass "OS portal contains expected ISO download URL."
else
    fail "OS portal missing ISO download URL."
fi

if echo "$os_html" | grep -qi "Download coming after validation"; then
    fail "OS portal still contains old placeholder text!"
else
    pass "OS portal free of old placeholder text."
fi

echo "=== 5. Checking Docs Portal (docs.os.genixbit.com) ==="
docs_html=$(curl -sL https://docs.os.genixbit.com)
if echo "$docs_html" | grep -q "$CHECKSUM_URL"; then
    pass "Docs portal contains expected checksum URL."
else
    fail "Docs portal missing checksum URL."
fi

echo "=== 6. Checking Package Status Portal (packages.os.genixbit.com) ==="
pkg_html=$(curl -sL https://packages.os.genixbit.com)
if echo "$pkg_html" | grep -qi "NOT DEPLOYED"; then
    pass "Package-status portal retains 'NOT DEPLOYED' status marker."
else
    fail "Package-status portal missing NOT DEPLOYED marker."
fi

if echo "$pkg_html" | grep -qi "ISO Distribution"; then
    pass "Package-status portal contains 'ISO Distribution' status section."
else
    fail "Package-status portal missing ISO Distribution marker."
fi

echo ""
pass "All automated live distribution checks passed successfully!"
