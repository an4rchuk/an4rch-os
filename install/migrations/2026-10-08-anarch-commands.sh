#!/usr/bin/env bash
# An4rch OS 1.1.0: every lumen-* command is now anarch-* (the old names are
# obsolete and only forward). Your own config files that call them are updated;
# the originals are kept in ~/.local/state/lumen/before-anarch/.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
python3 - "$LUMEN_PATH" <<'PY'
import os, re, shutil, sys
from pathlib import Path
root = Path(sys.argv[1])
home = Path.home()
cfg = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
backup = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")) / "lumen/before-anarch"
names = sorted((p.name[len("anarch-"):] for p in (root / "bin").glob("anarch-*")), key=len, reverse=True)
if not names:
    sys.exit(0)
rx = re.compile(r"(?<![\w-])lumen-(%s)(?![\w-])(?!/)(?!\.(?:service|desktop|timer|conf|lua|py|css|sh|json|jsonc|svg|png)\b)"
                % "|".join(map(re.escape, names)))
front = re.compile(r"(?<![\w./-])lumen(?= +(?:%s|help|version)\b)" % "|".join(map(re.escape, names)))
candidates = [home / ".zshrc", home / ".zprofile", home / ".bashrc"]
for sub in ("waybar", "hypr", "fuzzel", "uwsm", "mako", "ghostty", "alacritty", "kitty", "satty", "lumen", "systemd"):
    d = cfg / sub
    if d.is_dir():
        candidates += [p for p in d.rglob("*") if p.is_file() and p.stat().st_size < 1_000_000
                       and "current" not in p.relative_to(cfg).parts]
apps = home / ".local/share/applications"
if apps.is_dir():
    candidates += list(apps.glob("*.desktop"))
changed = 0
for p in candidates:
    if not p.is_file() or p.is_symlink():
        continue
    try:
        text = p.read_text()
    except (UnicodeDecodeError, OSError):
        continue
    new = front.sub("anarch", rx.sub(r"anarch-\1", text))
    if new != text:
        dest = backup / p.relative_to(home)
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.exists():
            shutil.copy2(p, dest)
        p.write_text(new)
        changed += 1
if changed:
    print(f"  Updated {changed} of your config files to the anarch-* commands (originals in {backup})")
PY
