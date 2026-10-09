#!/usr/bin/env bash
# An4rch OS 1.1.1: the An4rch Hub, the one-step login screen, automatic
# recovery (boot counting and Undo update at the login screen), backups,
# phone link, graphics drivers, Secure Boot and bug reports.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
source "$LUMEN_PATH/lib/lumen.sh"

echo "  New: the An4rch Hub (Settings), a login screen with user name and password together,"
echo "       anarch backup, anarch phone, anarch drivers, anarch secureboot, anarch report"
is_server && exit 0

# The new login screen and its Undo-update helper (best-effort).
if [[ -f /usr/share/lumen/os-release || -f /etc/greetd/config.toml ]] && grep -qs lumen-greeter /etc/greetd/config.toml; then
  sudo install -D -m755 "$LUMEN_PATH/share/greeter/lumen-greeter" /usr/local/bin/lumen-greeter || true
  "$LUMEN_PATH/bin/anarch-login" update-app || true
  sudo install -d -m755 -o greeter -g greeter /var/cache/lumen-greeter 2>/dev/null || true
  sudo install -Dm755 "$LUMEN_PATH/share/recover/lumen-recover" /usr/local/lib/lumen/lumen-recover || true
  sudo install -Dm644 -t /etc/systemd/system "$LUMEN_PATH/share/recover/lumen-recover.path" "$LUMEN_PATH/share/recover/lumen-recover.service" || true
  sudo systemctl daemon-reload || true
  sudo systemctl enable --now lumen-recover.path >/dev/null 2>&1 || true
  "$LUMEN_PATH/bin/anarch-login" sync >/dev/null 2>&1 || true
fi

# Boot counting after kernel updates (An4rch OS with systemd-boot).
if [[ -f /usr/share/lumen/os-release ]]; then
  sudo install -Dm755 "$LUMEN_PATH/share/recover/arm-bootcount" /usr/local/lib/lumen/arm-bootcount || true
  sudo install -d /etc/pacman.d/hooks
  sudo tee /etc/pacman.d/hooks/95-lumen-bootcount.hook >/dev/null <<'HOOK' || true
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-lts
Target = linux-zen
Target = linux-hardened

[Action]
Description = Giving the updated kernel three tries before falling back...
When = PostTransaction
Exec = /usr/local/lib/lumen/arm-bootcount
HOOK
fi

# A better graphics driver available? Say so once.
if ! "$LUMEN_PATH/bin/anarch-drivers" check >/dev/null 2>&1; then
  echo "  A better graphics driver is available for your NVIDIA card: anarch drivers"
fi
