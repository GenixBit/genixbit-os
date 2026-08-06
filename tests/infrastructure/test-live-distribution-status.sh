#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Automated lightweight check for live GenixBit OS distribution & public web portals.

set -Eeuo pipefail

pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

ISO_RELEASE_URL="https://github.com/GenixBit/genixbit-os/releases/tag/v1.0.0-lts"

echo "=== 1. Checking GitHub Release Availability ==="
release_headers=$(curl -sIL "$ISO_RELEASE_URL")
if echo "$release_headers" | grep -qi "HTTP/.* 200"; then
    pass "GitHub release returned HTTP 200 OK."
else
    fail "GitHub release page request failed: $release_headers"
fi

echo "=== 2. Checking OS Portal (os.genixbit.com) ==="
os_html=$(curl -sL https://os.genixbit.com)
if echo "$os_html" | grep -qi "1\.0\.0-lts\|0\.3\.0-alpha"; then
    pass "OS portal displays release indicators."
else
    fail "OS portal does not display release indicators."
fi

if echo "$os_html" | grep -qi "GenixBitOS-.*\.iso"; then
    pass "OS portal links ISO download artifact."
else
    fail "OS portal missing ISO download link!"
fi

echo "=== 3. Checking Docs Portal (docs.os.genixbit.com) ==="
docs_html=$(curl -sL https://docs.os.genixbit.com)
if echo "$docs_html" | grep -qi "1\.0\.0-lts\|0\.3\.0-alpha"; then
    pass "Docs portal displays documentation."
else
    fail "Docs portal missing documentation."
fi

echo "=== 4. Checking Package Status Portal (packages.os.genixbit.com) ==="
pkg_html=$(curl -sL https://packages.os.genixbit.com)
if echo "$pkg_html" | grep -qi "NOT DEPLOYED"; then
    pass "Package-status portal retains 'NOT DEPLOYED' status marker."
else
    fail "Package-status portal missing NOT DEPLOYED marker."
fi

if echo "$pkg_html" | grep -qi "PUBLISHED"; then
    pass "Package-status portal displays 0.3.0-alpha PUBLISHED status."
else
    fail "Package-status portal missing 0.3.0-alpha PUBLISHED marker."
fi

if echo "$pkg_html" | grep -qi "genixbit-os-developer-profile"; then
    pass "Package-status portal displays Phase 4 profile packages."
else
    fail "Package-status portal missing Phase 4 profile packages."
fi

if echo "$pkg_html" | grep -qi "genixbit-os-ai-runtime"; then
    pass "Package-status portal displays Phase 5 AI runtime package."
else
    fail "Package-status portal missing Phase 5 AI runtime package."
fi

if echo "$pkg_html" | grep -qi "genixbit-os-ai-center"; then
    pass "Package-status portal displays Phase 6 AI Center and Agents packages."
else
    fail "Package-status portal missing Phase 6 AI Center and Agents packages."
fi

if echo "$pkg_html" | grep -qi "genixbit-os-store"; then
    pass "Package-status portal displays Phase 7 GenixBit Store package."
else
    fail "Package-status portal missing Phase 7 GenixBit Store package."
fi

echo ""
pass "All automated live distribution checks passed successfully!"
