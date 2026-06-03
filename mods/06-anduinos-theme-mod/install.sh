set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

print_ok "Installing AnduinOS templates and themes..."
apt install $INTERACTIVE anduinos-templates
judge "Install anduinos-templates"

print_ok "Installing AnduinOS desktop theme..."
apt install $INTERACTIVE anduinos-theme
judge "Install anduinos-theme"

print_ok "Base packages installed."
