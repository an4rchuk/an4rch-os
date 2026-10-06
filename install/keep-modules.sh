#!/usr/bin/env bash
# Keep the running kernel's modules when a kernel update replaces them, until
# the next restart. Without this, after `pacman -Syu` updates linux the
# running kernel can't load anything new: USB sticks (exFAT, NTFS), new USB
# devices and VPNs stop working until a restart. Run as root; safe to run again.
set -euo pipefail

install -d /usr/local/lib/lumen /etc/pacman.d/hooks
cat >/usr/local/lib/lumen/keep-modules <<'SCRIPT'
#!/usr/bin/env bash
# keep-modules pre|post|clean — see /etc/pacman.d/hooks/*lumen-keep-modules*.
set -u
run=$(uname -r)
dir=/usr/lib/modules/$run
save=/usr/lib/modules/.lumen-running-$run
case "${1:-}" in
  pre)
    # Hard links: instant, no extra space; they survive pacman deleting the originals.
    [[ -d "$dir" && ! -e "$save" ]] && cp -al "$dir" "$save"
    ;;
  post)
    if [[ -d "$save" && ! -e "$dir/modules.dep" ]]; then
      rm -rf "$dir"
      mv "$save" "$dir"
      touch "$dir/.lumen-kept"
      depmod "$run" 2>/dev/null || true
    else
      rm -rf "$save"
    fi
    ;;
  clean)
    # At boot: drop modules kept for a kernel that's no longer running.
    for d in /usr/lib/modules/*/; do
      d=${d%/}
      [[ -e "$d/.lumen-kept" && "${d##*/}" != "$run" ]] && rm -rf "$d"
    done
    rm -rf /usr/lib/modules/.lumen-running-*
    ;;
  *) echo "usage: keep-modules pre|post|clean" >&2; exit 2 ;;
esac
exit 0
SCRIPT
chmod 755 /usr/local/lib/lumen/keep-modules

hook() { # FILE WHEN ARG DESCRIPTION
  cat >"/etc/pacman.d/hooks/$1" <<HOOK
[Trigger]
Operation = Upgrade
Operation = Remove
Type = Path
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = $4
When = $2
Exec = /usr/local/lib/lumen/keep-modules $3
HOOK
}
hook 10-lumen-keep-modules-pre.hook PreTransaction pre "Keeping the running kernel's modules until restart..."
hook 90-lumen-keep-modules-post.hook PostTransaction post "Restoring the running kernel's modules until restart..."

cat >/etc/systemd/system/lumen-clean-modules.service <<'UNIT'
[Unit]
Description=Remove kernel modules kept for a kernel that is no longer running

[Service]
Type=oneshot
ExecStart=/usr/local/lib/lumen/keep-modules clean

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable lumen-clean-modules.service >/dev/null 2>&1 || true
