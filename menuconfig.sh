#!/bin/bash
# menuconfig.sh — Interactive TUI configuration for AnduinOS
# Run via: make menuconfig  or  ./menuconfig.sh
set -uo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG_FILE="$SCRIPT_DIR/args.sh"

if ! command -v whiptail &>/dev/null; then
    echo "Error: whiptail is required. Install with: sudo apt install whiptail"
    exit 1
fi

source "$CONFIG_FILE"
WHIP=(whiptail --title "AnduinOS Configuration" --backtitle "make menuconfig")

# ── write helpers ──────────────────────────────────────────────

set_simple() {
    local key="$1" value="$2"
    local tmp
    tmp=$(mktemp)
    while IFS= read -r line; do
        if [[ "$line" =~ ^export\ ${key}= ]]; then
            printf 'export %s="%s"\n' "$key" "$value" >> "$tmp"
        else
            printf '%s\n' "$line" >> "$tmp"
        fi
    done < "$CONFIG_FILE"
    mv "$tmp" "$CONFIG_FILE"
}

set_multiline() {
    local key="$1"; shift
    local items=("$@")

    local block=""
    local i=0 count=${#items[@]}
    for item in "${items[@]}"; do
        if [ $((i+1)) -lt $count ]; then
            block+="    ${item} \\"$'\n'
        else
            block+="    ${item}"$'\n'
        fi
        ((i++))
    done

    local tmp
    tmp=$(mktemp)
    local in_block=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^export\ ${key}=\" ]]; then
            printf 'export %s="\n' "$key" >> "$tmp"
            printf '%s' "$block" >> "$tmp"
            printf '"\n' >> "$tmp"
            in_block=1
        elif [[ $in_block -eq 1 && "$line" == '"' ]]; then
            in_block=0
        elif [[ $in_block -eq 0 ]]; then
            printf '%s\n' "$line" >> "$tmp"
        fi
    done < "$CONFIG_FILE"
    mv "$tmp" "$CONFIG_FILE"
}

# ── whiptail helpers ───────────────────────────────────────────

yesno()  { "${WHIP[@]}" --yesno  "$1" 8 60; }
msgbox() { "${WHIP[@]}" --msgbox "$1" 12 60; }
inputbox() {
    local val
    val=$("${WHIP[@]}" --inputbox "$1" 12 60 "$2" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    echo "$val"
}

menu_select() {
    local title="$1" default="$2"; shift 2
    local args=()
    for entry in "$@"; do
        IFS="|" read -r tag desc <<< "$entry"
        args+=("$tag" "$desc")
    done
    local val
    val=$("${WHIP[@]}" --menu "$title" 20 60 14 "${args[@]}" \
        --default-item "$default" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    echo "$val"
}

radiolist_select() {
    local title="$1" default="$2"; shift 2
    local args=()
    for entry in "$@"; do
        IFS="|" read -r tag desc <<< "$entry"
        [ "$tag" = "$default" ] && args+=("$tag" "$desc" "ON") || args+=("$tag" "$desc" "OFF")
    done
    local val
    val=$("${WHIP[@]}" --radiolist "$title" 16 60 8 "${args[@]}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    echo "$val"
}

checklist_select() {
    local title="$1" default="$2"; shift 2
    local args=()
    for entry in "$@"; do
        IFS="|" read -r tag desc <<< "$entry"
        [[ " $default " == *" $tag "* ]] && args+=("$tag" "$desc" "ON") || args+=("$tag" "$desc" "OFF")
    done
    local val
    val=$("${WHIP[@]}" --checklist "$title" 24 70 16 "${args[@]}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    echo "$val"
}

# ── sub-menus ──────────────────────────────────────────────────

menu_identity() {
    local name business version
    name=$(inputbox "Target OS codename (lowercase, no spaces or special chars):\n\nUsed for filenames, volume labels, etc." "$TARGET_NAME")
    [ $? -ne 0 ] && return 1

    business=$(inputbox "Target OS display name (no special characters):\n\nShown in GRUB menu, ISO filename, disk info." "$TARGET_BUSINESS_NAME")
    [ $? -ne 0 ] && return 1

    version=$(inputbox "Version number (x.y.z format):\n\nExample: 2.0.0" "$TARGET_BUILD_VERSION")
    [ $? -ne 0 ] && return 1

    set_simple "TARGET_NAME" "$name"
    set_simple "TARGET_BUSINESS_NAME" "$business"
    set_simple "TARGET_BUILD_VERSION" "$version"
    TARGET_NAME="$name"
    TARGET_BUSINESS_NAME="$business"
    TARGET_BUILD_VERSION="$version"
}

menu_ubuntu_base() {
    local codename=$(menu_select "Ubuntu base version:" "$TARGET_UBUNTU_VERSION" \
        "noble|Ubuntu 24.04 LTS (Noble Numbat)" \
        "oracular|Ubuntu 24.10 (Oracular Oriole)" \
        "plucky|Ubuntu 25.04 (Plucky Puffin)" \
        "questing|Ubuntu 25.10 (Questing Quokka)" \
        "resolute|Ubuntu 26.04 (Resolute Rodent)")
    [ $? -ne 0 ] && return 1

    local build_mirror=$(inputbox "APT mirror used during debootstrap:\n\nThe Ubuntu mirror to download the base system from.\nSee https://docs.anduinos.com/Install/Select-Best-Apt-Source.html\n\nPress Enter for default (Aiursoft mirror)." "$BUILD_UBUNTU_MIRROR")
    [ $? -ne 0 ] && return 1

    local live_mirror=$(inputbox "APT mirror in the live system / installed OS:\n\nThe Ubuntu mirror configured in the final installed system." "$LIVE_UBUNTU_MIRROR")
    [ $? -ne 0 ] && return 1

    set_simple "TARGET_UBUNTU_VERSION" "$codename"
    set_simple "BUILD_UBUNTU_MIRROR" "$build_mirror"
    set_simple "LIVE_UBUNTU_MIRROR" "$live_mirror"
    TARGET_UBUNTU_VERSION="$codename"
    BUILD_UBUNTU_MIRROR="$build_mirror"
    LIVE_UBUNTU_MIRROR="$live_mirror"
}

menu_language() {
    local lang=$(menu_select "System language:" "$LANG_MODE" \
        "en_US|English (United States)" \
        "en_GB|English (United Kingdom)" \
        "zh_CN|Chinese (Simplified)" \
        "zh_TW|Chinese (Traditional - Taiwan)" \
        "zh_HK|Chinese (Traditional - Hong Kong)" \
        "ja_JP|Japanese" \
        "ko_KR|Korean" \
        "vi_VN|Vietnamese" \
        "th_TH|Thai" \
        "de_DE|German" \
        "fr_FR|French" \
        "es_ES|Spanish" \
        "ru_RU|Russian" \
        "it_IT|Italian" \
        "pt_BR|Portuguese (Brazil)" \
        "pt_PT|Portuguese (Portugal)" \
        "ar_SA|Arabic" \
        "nl_NL|Dutch" \
        "sv_SE|Swedish" \
        "pl_PL|Polish" \
        "tr_TR|Turkish" \
        "ro_RO|Romanian")
    [ $? -ne 0 ] && return 1

    # Derive LANG_PACK_CODE from LANG_MODE
    local pack_code="${lang%%_*}"
    case "$lang" in
        pt_BR|pt_PT) pack_code="pt" ;;
        zh_CN|zh_TW|zh_HK) pack_code="zh" ;;
    esac

    local tz=""
    while [ -z "$tz" ]; do
        tz=$(inputbox "Timezone:\n\nRun 'ls /usr/share/zoneinfo/' to browse available timezones.\nExample: America/Los_Angeles, Asia/Shanghai, Europe/London" "${TIMEZONE:-America/Los_Angeles}")
        [ $? -ne 0 ] && return 1
        [ -z "$tz" ] && msgbox "Timezone cannot be empty."
    done

    local weather=$(inputbox "Default weather location (JSON format):\n\nUsed by the GNOME weather extension.\nExample:\n['{\"name\":\"San Francisco, CA, US\",\"lat\":37.77,\"lon\":-122.41}']" "$CONFIG_WEATHER_LOCATION")
    [ $? -ne 0 ] && return 1

    set_simple "LANG_MODE" "$lang"
    set_simple "LANG_PACK_CODE" "$pack_code"
    set_simple "TIMEZONE" "$tz"
    set_simple "CONFIG_WEATHER_LOCATION" "$weather"
    LANG_MODE="$lang"
    LANG_PACK_CODE="$pack_code"
    TIMEZONE="$tz"
    CONFIG_WEATHER_LOCATION="$weather"
}

menu_store() {
    local store=$(radiolist_select "App store provider:" "$STORE_PROVIDER" \
        "flatpak|Flatpak — GNOME Software with Flatpak plugin (recommended)" \
        "snap|Snap — GNOME Software with Snap plugin" \
        "web|Web shortcut — browser-based app store" \
        "none|None — no app store")
    [ $? -ne 0 ] && return 1

    local flathub=""
    local flathub_gpg=""
    if [ "$store" = "flatpak" ]; then
        flathub=$(inputbox "Flathub mirror URL (leave empty for default):\n\nExample: https://mirrors.ustc.edu.cn/flathub" "$FLATHUB_MIRROR")
        [ $? -ne 0 ] && return 1
        if [ -n "$flathub" ]; then
            flathub_gpg=$(inputbox "Flathub GPG key URL (required if mirror is set):\n\nExample: https://mirrors.ustc.edu.cn/flathub/flathub.gpg" "$FLATHUB_GPG")
            [ $? -ne 0 ] && return 1
        fi
    fi

    set_simple "STORE_PROVIDER" "$store"
    set_simple "FLATHUB_MIRROR" "$flathub"
    set_simple "FLATHUB_GPG" "$flathub_gpg"
    STORE_PROVIDER="$store"
    FLATHUB_MIRROR="$flathub"
    FLATHUB_GPG="$flathub_gpg"
}

menu_browser() {
    local ff=$(menu_select "Firefox installation method:" "$FIREFOX_PROVIDER" \
        "official_apt|Official APT — from Mozilla's official repository (recommended)" \
        "deb|Canonical PPA — deb package with mirror support" \
        "flatpak|Flatpak — from Flathub (requires STORE=flatpak)" \
        "snap|Snap — from Snap Store (requires STORE=snap)" \
        "none|None — do not install Firefox")
    [ $? -ne 0 ] && return 1

    local live_ff=""
    local build_ff=""
    local ff_locale=""
    if [ "$ff" = "deb" ]; then
        live_ff=$(inputbox "Live system Firefox PPA mirror:\n\nExample: ppa.launchpadcontent.net" "$LIVE_FIREFOX_MIRROR")
        [ $? -ne 0 ] && return 1
        build_ff=$(inputbox "Build-time Firefox PPA mirror (optional, leave empty if not needed):\n\nExample: mirror-ppa.aiursoft.com" "$BUILD_FIREFOX_MIRROR")
        [ $? -ne 0 ] && return 1
        ff_locale=$(inputbox "Firefox locale package (optional):\n\nExample: firefox-locale-zh-hans" "$FIREFOX_LOCALE_PACKAGE")
        [ $? -ne 0 ] && return 1
    fi

    set_simple "FIREFOX_PROVIDER" "$ff"
    set_simple "LIVE_FIREFOX_MIRROR" "$live_ff"
    set_simple "BUILD_FIREFOX_MIRROR" "$build_ff"
    set_simple "FIREFOX_LOCALE_PACKAGE" "$ff_locale"
    FIREFOX_PROVIDER="$ff"
    LIVE_FIREFOX_MIRROR="$live_ff"
    BUILD_FIREFOX_MIRROR="$build_ff"
    FIREFOX_LOCALE_PACKAGE="$ff_locale"
}

menu_input() {
    local im=$(radiolist_select "Input method engine:" "${INPUT_METHOD_INSTALL:-none}" \
        "none|No extra input method (keyboard layouts only)" \
        "ibus-rime|Rime — Chinese (Simplified/Traditional), best for zh_CN" \
        "ibus-libpinyin|LibPinyin — Chinese (Simplified), lightweight" \
        "ibus-chewing|Chewing — Chinese (Traditional - Taiwan)" \
        "ibus-table-cangjie|Cangjie — Chinese (Traditional - Hong Kong)" \
        "ibus-mozc|Mozc — Japanese" \
        "ibus-hangul|Hangul — Korean" \
        "ibus-unikey|Unikey — Vietnamese" \
        "ibus-libthai|LibThai — Thai")
    [ $? -ne 0 ] && return 1
    [ "$im" = "none" ] && im=""

    local rime="false"
    if [ "$im" = "ibus-rime" ]; then
        if yesno "Configure AnduinOS custom Rime settings?\n\nInstalls our pre-configured Rime input method with optimized settings."; then
            rime="true"
        fi
    fi

    local layout=$(menu_select "Default keyboard layout:" "us" \
        "us|English (US) — [('xkb', 'us')]" \
        "us+r|US + Rime — [('xkb', 'us'), ('ibus', 'rime')]" \
        "us+cw|US + Chewing — [('xkb', 'us'), ('ibus', 'chewing')]" \
        "us+mz|US + Mozc (JP) — [('xkb', 'us'), ('xkb', 'jp'), ('ibus', 'mozc-jp')]" \
        "us+hk|US + Hangul — [('xkb', 'us'), ('ibus', 'hangul')]" \
        "us+uk|US + Unikey — [('xkb', 'us'), ('ibus', 'Unikey')]" \
        "us+th|US + Thai — [('xkb', 'us'), ('xkb', 'th'), ('ibus', 'libthai')]" \
        "us+de|US + German — [('xkb', 'us'), ('xkb', 'de')]" \
        "us+fr|US + French — [('xkb', 'us'), ('xkb', 'fr')]" \
        "us+es|US + Spanish — [('xkb', 'us'), ('xkb', 'es')]" \
        "us+ru|US + Russian — [('xkb', 'us'), ('xkb', 'ru')]" \
        "us+it|US + Italian — [('xkb', 'us'), ('xkb', 'it')]" \
        "us+pt|US + Portuguese — [('xkb', 'us'), ('xkb', 'pt')]" \
        "us+br|US + Brazilian — [('xkb', 'us'), ('xkb', 'br')]" \
        "us+ara|US + Arabic — [('xkb', 'us'), ('xkb', 'ara')]" \
        "us+nl|US + Dutch — [('xkb', 'us'), ('xkb', 'nl')]" \
        "us+se|US + Swedish — [('xkb', 'us'), ('xkb', 'se')]" \
        "us+pl|US + Polish — [('xkb', 'us'), ('xkb', 'pl')]" \
        "us+tr|US + Turkish — [('xkb', 'us'), ('xkb', 'tr')]" \
        "us+ro|US + Romanian — [('xkb', 'us'), ('xkb', 'ro')]" \
        "us+gb|US + UK — [('xkb', 'us'), ('xkb', 'gb')]")
    [ $? -ne 0 ] && return 1

    # Map short codes to actual CONFIG_INPUT_METHOD values
    local config_input="[('xkb', 'us')]"
    case "$layout" in
        us)     config_input="[('xkb', 'us')]" ;;
        us+r)   config_input="[('xkb', 'us'), ('ibus', 'rime')]" ;;
        us+cw)  config_input="[('xkb', 'us'), ('ibus', 'chewing')]" ;;
        us+mz)  config_input="[('xkb', 'us'), ('xkb', 'jp'), ('ibus', 'mozc-jp')]" ;;
        us+hk)  config_input="[('xkb', 'us'), ('ibus', 'hangul')]" ;;
        us+uk)  config_input="[('xkb', 'us'), ('ibus', 'Unikey')]" ;;
        us+th)  config_input="[('xkb', 'us'), ('xkb', 'th'), ('ibus', 'libthai')]" ;;
        us+de)  config_input="[('xkb', 'us'), ('xkb', 'de')]" ;;
        us+fr)  config_input="[('xkb', 'us'), ('xkb', 'fr')]" ;;
        us+es)  config_input="[('xkb', 'us'), ('xkb', 'es')]" ;;
        us+ru)  config_input="[('xkb', 'us'), ('xkb', 'ru')]" ;;
        us+it)  config_input="[('xkb', 'us'), ('xkb', 'it')]" ;;
        us+pt)  config_input="[('xkb', 'us'), ('xkb', 'pt')]" ;;
        us+br)  config_input="[('xkb', 'us'), ('xkb', 'br')]" ;;
        us+ara) config_input="[('xkb', 'us'), ('xkb', 'ara')]" ;;
        us+nl)  config_input="[('xkb', 'us'), ('xkb', 'nl')]" ;;
        us+se)  config_input="[('xkb', 'us'), ('xkb', 'se')]" ;;
        us+pl)  config_input="[('xkb', 'us'), ('xkb', 'pl')]" ;;
        us+tr)  config_input="[('xkb', 'us'), ('xkb', 'tr')]" ;;
        us+ro)  config_input="[('xkb', 'us'), ('xkb', 'ro')]" ;;
        us+gb)  config_input="[('xkb', 'us'), ('xkb', 'gb')]" ;;
    esac

    set_simple "INPUT_METHOD_INSTALL" "$im"
    set_simple "CONFIG_IBUS_RIME" "$rime"
    set_simple "CONFIG_INPUT_METHOD" "$config_input"
    INPUT_METHOD_INSTALL="$im"
    CONFIG_IBUS_RIME="$rime"
    CONFIG_INPUT_METHOD="$config_input"
}

menu_preinstalled_apps() {
    # Parse currently selected apps from the sourced variables
    # DEFAULT_APPS and DEFAULT_CLI_TOOLS are space-separated after bash sourcing

    local app_choices=(
        "gnome-chess|Chess game"
        "gnome-clocks|World clocks, alarms, stopwatch"
        "gnome-weather|Weather forecast app"
        "gnome-calendar|Calendar application"
        "gnome-text-editor|Simple text editor"
        "seahorse|Password and encryption key manager"
        "papers|Document viewer (PDF, etc.)"
        "shotwell|Photo manager"
        "sysprof|System profiler"
        "remmina|Remote desktop client (+ RDP plugin)"
        "rhythmbox|Music player and organizer"
        "showtime|Video player"
        "transmission-gtk|BitTorrent client"
        "ffmpegthumbnailer|Video thumbnailer for file manager"
        "usb-creator-gtk|Bootable USB creator"
        "baobab|Disk usage analyzer"
        "file-roller|Archive manager"
        "gnome-sushi|File previewer (space bar)"
        "qalculate-gtk|Powerful calculator"
        "yelp|Help browser"
        "gparted|Partition editor"
        "gnome-disk-utility|Disk management"
        "gnome-logs|System log viewer"
        "resources|System resource monitor"
        "gnome-sound-recorder|Audio recorder"
        "gnome-characters|Character map"
        "gnome-power-manager|Power settings"
        "gnome-snapshot|Screenshot tool"
        "gnome-font-viewer|Font viewer"
        "gnome-browser-connector|Extension browser connector"
    )

    local cli_choices=(
        "curl|URL data transfer tool"
        "vim|Vi Improved — text editor"
        "nano|Simple terminal text editor"
        "git|Version control system"
        "build-essential|C/C++ compiler and build tools"
        "make|Build automation tool"
        "gcc|GNU C compiler"
        "g++|GNU C++ compiler"
        "net-tools|Network utilities (ifconfig, netstat)"
        "htop|Interactive process viewer"
        "httping|HTTP request latency tool"
        "iputils-ping|Network ping tool"
        "iputils-tracepath|Network path tracer"
        "dnsutils|DNS query tools (dig, nslookup)"
        "smartmontools|Disk health monitoring"
        "traceroute|Network route tracer"
        "whois|Domain registry lookup"
        "nmap|Network scanner"
        "fastfetch|System info display"
    )

    # Build whiptail args for GUI apps checklist
    local app_tags=()
    local app_desc=()
    local default_apps="$DEFAULT_APPS"
    local app_args=()
    for entry in "${app_choices[@]}"; do
        IFS="|" read -r tag desc <<< "$entry"
        [[ " $default_apps " == *" $tag "* ]] && app_args+=("$tag" "$desc" "ON") || app_args+=("$tag" "$desc" "OFF")
    done

    local selected_apps
    selected_apps=$("${WHIP[@]}" --checklist "Default GUI applications to preinstall:" 24 75 16 "${app_args[@]}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1

    # Build whiptail args for CLI tools checklist
    local cli_args=()
    local default_cli="$DEFAULT_CLI_TOOLS"
    for entry in "${cli_choices[@]}"; do
        IFS="|" read -r tag desc <<< "$entry"
        [[ " $default_cli " == *" $tag "* ]] && cli_args+=("$tag" "$desc" "ON") || cli_args+=("$tag" "$desc" "OFF")
    done

    local selected_cli
    selected_cli=$("${WHIP[@]}" --checklist "Default CLI tools to preinstall:" 24 75 16 "${cli_args[@]}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1

    # Convert whiptail output (quoted strings) to array
    eval "local app_arr=($selected_apps)"
    eval "local cli_arr=($selected_cli)"

    set_multiline "DEFAULT_APPS" "${app_arr[@]}"
    set_multiline "DEFAULT_CLI_TOOLS" "${cli_arr[@]}"
    DEFAULT_APPS="${app_arr[*]}"
    DEFAULT_CLI_TOOLS="${cli_arr[*]}"
}

menu_other() {
    local sw_props="ON"
    [ "$INSTALL_MODIFIED_SOFTWARE_PROPERTIES_GTK" = "true" ] && sw_props="ON" || sw_props="OFF"
    "${WHIP[@]}" --yesno "Install modified software-properties-gtk?\n\nAdds our customized Software & Updates GUI tool." 8 60 --defaultno 2>/dev/null
    [ $? -eq 0 ] && sw_props="true" || sw_props="false"

    set_simple "INSTALL_MODIFIED_SOFTWARE_PROPERTIES_GTK" "$sw_props"
    INSTALL_MODIFIED_SOFTWARE_PROPERTIES_GTK="$sw_props"

    local frontend="noninteractive"
    [ "${DEBIAN_FRONTEND:-noninteractive}" = "readline" ] && frontend="readline"
    local new_frontend=$(radiolist_select "Build frontend mode:" "$frontend" \
        "noninteractive|Silent — no prompts, uses default answers (recommended for CI)" \
        "readline|Interactive — shows debconf prompts during build")
    [ $? -ne 0 ] && return 1

    set_simple "DEBIAN_FRONTEND" "$new_frontend"
    DEBIAN_FRONTEND="$new_frontend"
}

# ── main menu ──────────────────────────────────────────────────

show_status() {
    msgbox "Current Configuration
━━━━━━━━━━━━━━━━━━━━━━━━

  Target OS:      $TARGET_BUSINESS_NAME ($TARGET_NAME)
  Version:        $TARGET_BUILD_VERSION
  Ubuntu Base:    $TARGET_UBUNTU_VERSION
  Language:       $LANG_MODE
  Timezone:       $TIMEZONE
  Store:          $STORE_PROVIDER
  Firefox:        $FIREFOX_PROVIDER
  Input Method:   ${INPUT_METHOD_INSTALL:-none}
  GUI Apps:       $(echo "$DEFAULT_APPS" | wc -w) packages
  CLI Tools:      $(echo "$DEFAULT_CLI_TOOLS" | wc -w) packages
  Frontend:       ${DEBIAN_FRONTEND:-noninteractive}"
}

main_menu() {
    while true; do
        local choice
        choice=$("${WHIP[@]}" --menu "AnduinOS Build Configuration\n\nSelect a category to configure." \
            18 60 10 \
            "identity"   "System Identity" \
            "base"       "Ubuntu Base & Mirrors" \
            "language"   "Language, Timezone & Region" \
            "store"      "Software Store" \
            "browser"    "Browser (Firefox)" \
            "input"      "Input Method & Keyboard" \
            "apps"       "Preinstalled Applications" \
            "other"      "Other Settings" \
            "status"     "Show Current Configuration" \
            "save"       "Save & Exit" \
            3>&1 1>&2 2>&3)

        case "$choice" in
            identity) menu_identity ;;
            base)     menu_ubuntu_base ;;
            language) menu_language ;;
            store)    menu_store ;;
            browser)  menu_browser ;;
            input)    menu_input ;;
            apps)     menu_preinstalled_apps ;;
            other)    menu_other ;;
            status)   show_status ;;
            save|"")  break ;;
        esac
    done
}

# ── entry ──────────────────────────────────────────────────────

main_menu

# Reload and print summary
source "$CONFIG_FILE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Configuration saved."
echo "  Run 'make' to build $TARGET_BUSINESS_NAME $TARGET_BUILD_VERSION ($LANG_MODE)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
