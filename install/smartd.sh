#!/usr/bin/env bash
# smartd: a computer with no SMART drives (virtual machines, some USB
# enclosures) is fine, not a failed service. Run as root.
set -euo pipefail
install -D -m644 /dev/stdin /etc/systemd/system/smartd.service.d/lumen.conf <<'EOF'
# an4rch: exit cleanly when there are no drives to watch.
[Service]
ExecStart=
ExecStart=/usr/bin/smartd -n -q nodev0
EOF
systemctl daemon-reload 2>/dev/null || true
