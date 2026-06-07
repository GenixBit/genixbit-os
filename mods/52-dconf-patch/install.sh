#!/bin/bash
# AnduinOS Dynamic Dconf Configuration
#
# Static dconf/gschema/GDM defaults are shipped by the
# anduinos-dconf-defaults Apkg package (installed by mod 01).
# This mod only handles build-time dynamic configs that vary
# per locale (weather location).
#
# Keyboard layout is NOT set here — GNOME reads /etc/default/keyboard
# (set by Ubiquity during install), so each user gets their own layout.
#
# The dconf update at the end compiles all fragments — including
# those shipped by individual Apkg extension packages — into the
# final system database.
set -euo pipefail

print_ok "Generating dynamic build-time dconf configuration"

if [ -z "$CONFIG_WEATHER_LOCATION" ]; then
    print_error "Error: CONFIG_WEATHER_LOCATION is not set."
    exit 1
fi

# Write weather location dconf fragment
mkdir -p /etc/dconf/db/anduinos.d/
cat > /etc/dconf/db/anduinos.d/04-dynamic-configs.conf << EOF
# AnduinOS Dynamic Configuration
# Auto-generated during ISO build

# ============================================================================
# Weather Extension Location
# ============================================================================
[org/gnome/shell/extensions/simple-weather]
locations=$CONFIG_WEATHER_LOCATION
