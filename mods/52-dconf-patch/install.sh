#!/bin/bash
# AnduinOS Dynamic Dconf Configuration
#
# Static dconf/gschema/GDM defaults are shipped by the
# anduinos-dconf-defaults Apkg package (installed by mod 01).
# This mod only handles build-time dynamic configs that vary
# per locale (input method, weather location).
#
# The dconf update at the end compiles all fragments — including
# those shipped by individual Apkg extension packages — into the
# final system database.
set -euo pipefail

print_ok "Generating dynamic build-time dconf configuration"

# Validate required environment variables
if [ -z "$CONFIG_INPUT_METHOD" ]; then
    print_error "Error: CONFIG_INPUT_METHOD is not set."
    exit 1
fi

if [ -z "$CONFIG_WEATHER_LOCATION" ]; then
    print_error "Error: CONFIG_WEATHER_LOCATION is not set."
    exit 1
fi

# Write dynamic dconf fragment (slot 04 — after system extensions, before per-extension)
mkdir -p /etc/dconf/db/anduinos.d/

# Only write input-sources when explicitly configured (not default US keyboard).
# GNOME Shell reads /etc/default/keyboard when no sources are set in dconf,
# which respects the user's keyboard choice from Ubiquity.
INPUT_SECTION=""
if [ "$CONFIG_INPUT_METHOD" != "[('xkb', 'us')]" ]; then
    INPUT_SECTION="[org/gnome/desktop/input-sources]
sources=$CONFIG_INPUT_METHOD

"
fi

cat > /etc/dconf/db/anduinos.d/04-dynamic-configs.conf << EOF
# AnduinOS Dynamic Configuration
# Auto-generated during ISO build

${INPUT_SECTION}# ============================================================================
# Weather Extension Location
# ============================================================================
[org/gnome/shell/extensions/simple-weather]
locations=$CONFIG_WEATHER_LOCATION
EOF
judge "Generate dynamic dconf config"

# Compile all dconf fragments into the system database
print_ok "Compiling dconf system database"
dconf update
judge "Compile dconf system database"
