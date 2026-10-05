#!/usr/bin/env python3
"""Lumen OS installer — the graphical installer on the live USB.

Runs on the live Lumen desktop, Bazzite-style: you try the system while you
answer a few questions (network, disk, account, region, look, apps), then
it installs. The work itself is done by lumen-os-install, the same engine as
the text-mode installer, fed an answers file; this app shows its progress.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

HOME = Path.home()
LUMEN_PATH = Path(os.environ.get("LUMEN_PATH", HOME / ".local/share/lumen"))
if not (LUMEN_PATH / "themes").is_dir():
    # Running from a checkout (or /opt/lumen on the live USB).
    LUMEN_PATH = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "lumen"
WALLPAPERS = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "backgrounds/lumen"
HERE = Path(__file__).resolve().parent
ENGINE = os.environ.get("LUMEN_OS_INSTALL", "/usr/local/bin/lumen-os-install")
LOG = Path("/var/log/lumen-os-install.log")
DEMO = os.environ.get("LUMEN_INSTALLER_DEMO") == "1"  # UI only, never touches disks

BROWSERS = [("firefox", "Firefox", "Fast, private, by Mozilla"), ("chromium", "Chromium", "The open-source base of Chrome"),
            ("brave", "Brave", "Blocks ads and trackers"), ("zen-browser", "Zen", "Calm, Firefox-based")]
TERMINALS = [("ghostty", "Ghostty", "Fast and modern (recommended)"), ("alacritty", "Alacritty", "Minimal and quick"),
             ("kitty", "Kitty", "Feature-rich")]
EDITORS = [("code", "VS Code", "Code - OSS, with extensions"), ("zed", "Zed", "Fast, collaborative"),
           ("nvim", "Neovim", "In the terminal")]
LAYOUTS = [("classic", "Lumen", "Top bar, title bars and a taskbar along the bottom", "yes", "yes"),
           ("modern", "Top bar only", "No taskbar: tap the Windows key for Start and your apps", "no", "yes"),
           ("minimal", "Minimal", "Edge-to-edge tiling windows, no title bars", "no", "no")]
# Steps of the engine and of the desktop installer, for the progress bar.
STEPS = ["Mirrors", "Partitioning", "Encrypting", "Formatting", "Creating btrfs", "Installing the base system",
         "Configuring the system", "Copying Lumen", "[1/9]", "[2/9]", "[3/9]", "[4/9]", "[5/9]", "[6/9]",
         "[7/9]", "[8/9]", "[9/9]", "LUMEN-INSTALL-OK"]
FRIENDLY = {"[1/9]": "Checking the new system", "[2/9]": "Choosing your apps", "[3/9]": "Preparing the package manager",
            "[4/9]": "Installing the desktop", "[5/9]": "Installing your apps", "[6/9]": "Writing your settings",
            "[7/9]": "Setting up system services", "[8/9]": "Styling", "[9/9]": "Finishing up"}


def run(*cmd: str, timeout: int = 15) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def detached(*cmd: str) -> None:
    try:
        subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError as err:
        print(f"lumen-installer: {err}", file=sys.stderr)


def lumen(*argv: str) -> None:
    path = LUMEN_PATH / "bin" / argv[0]
    detached(str(path) if path.exists() else argv[0], *argv[1:])


# --- system information -------------------------------------------------------------------
def boot_disk() -> str:
    """The USB stick we booted from, so it isn't offered as a target."""
    src = run("findmnt", "-no", "SOURCE", "/run/archiso/bootmnt").strip()
    if not src:
        return ""
    return run("lsblk", "-no", "PKNAME", src).strip()


def disks() -> list[dict]:
    try:
        data = json.loads(run("lsblk", "-J", "-b", "-d", "-o", "NAME,SIZE,MODEL,TYPE,TRAN,RM,RO") or "{}")
    except json.JSONDecodeError:
        return []
    skip = boot_disk()
    found = []
    for d in data.get("blockdevices", []):
        if d.get("type") != "disk" or d.get("ro") or d["name"] == skip or d["name"].startswith(("loop", "zram", "sr")):
            continue
        size = int(d.get("size") or 0)
        if size < 20 * 1000**3:
            continue
        model = (d.get("model") or "").strip() or ("USB drive" if d.get("tran") == "usb" else "Disk")
        # What's on it now (e.g. "Windows · 4 partitions"), so it isn't erased by accident.
        contents = run("lumen-disk-info", f"/dev/{d['name']}").strip()
        detail = f"/dev/{d['name']} · {(d.get('tran') or '').upper() or 'internal'}"
        if contents:
            detail += f" · has {contents}"
        found.append({"path": f"/dev/{d['name']}", "label": model, "size": f"{size / 1000**3:.0f} GB",
                      "detail": detail, "contents": contents})
    if DEMO:  # never real disks in the demo
        found = [{"path": "/dev/demo", "label": "Demo disk", "size": "500 GB", "contents": "Windows · 4 partitions",
                  "detail": "nothing will be written · has Windows · 4 partitions"}]
    return found


def alongside_space(path: str) -> dict[str, str]:
    """Can Lumen go next to the Windows on this disk, and how big can it be?
    (lumen-disk-info --space: max_gb=…, or error=…)."""
    if DEMO:
        return {"max_gb": "180"}
    out = run("sudo", "-n", "lumen-disk-info", "--space", path, timeout=90)
    info = {}
    for line in out.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            info[k] = " ".join(shlex.split(v)) if v else ""
    return info or {"error": "Couldn't check the free space on this disk."}


def online() -> bool:
    return run("nmcli", "-t", "-f", "CONNECTIVITY", "general").strip() in ("full", "limited") or \
        run("curl", "-fsSI", "--max-time", "5", "-o", "/dev/null", "-w", "%{http_code}", "https://geo.mirror.pkgbuild.com") != ""


def wifi_networks() -> list[tuple[str, int, bool]]:
    out = run("nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "yes", timeout=25)
    seen: dict[str, tuple[str, int, bool]] = {}
    for line in out.splitlines():
        parts = re.split(r"(?<!\\):", line)
        if len(parts) < 3 or not parts[0]:
            continue
        ssid = parts[0].replace("\\:", ":")
        signal = int(parts[1] or 0)
        if ssid not in seen or seen[ssid][1] < signal:
            seen[ssid] = (ssid, signal, parts[2] not in ("", "--"))
    return sorted(seen.values(), key=lambda n: -n[1])


def timezones() -> list[str]:
    zones = [z for z in run("timedatectl", "list-timezones").split() if "/" in z]
    return zones or ["UTC"]


def guess_timezone() -> str:
    tz = run("curl", "-fsS", "--max-time", "4", "https://ipapi.co/timezone", timeout=6).strip()
    return tz if re.fullmatch(r"[A-Za-z_]+(/[A-Za-z0-9_+-]+)+", tz or "") else "UTC"


def keymaps() -> list[str]:
    maps = run("localectl", "list-keymaps").split()
    common = ["us", "uk", "de", "fr", "es", "it", "pt-latin1", "br-abnt2", "se-lat6", "no", "dk", "fi", "pl2", "cz-qwertz", "jp106"]
    return [m for m in common if not maps or m in maps] + sorted(set(maps) - set(common))


def read_theme(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            data[k.strip()] = v.strip()
    return data


def themes() -> list[tuple[str, dict]]:
    found = {}
    for d in sorted((LUMEN_PATH / "themes").iterdir()):
        if (d / "theme.conf").is_file():
            found[d.name] = read_theme(d / "theme.conf")
    # Lumen first, CachyOS-inspired second, then the rest A–Z.
    order = ["lumen", "cachy"]
    return sorted(found.items(), key=lambda kv: (order.index(kv[0]) if kv[0] in order else 9, kv[1].get("name", kv[0])))


def wallpaper_for(slug: str) -> Path | None:
    d = WALLPAPERS / slug
    if d.is_dir():
        pics = sorted(p for p in d.iterdir() if p.suffix.lower() in (".jpg", ".png"))
        if pics:
            return pics[0]
    return None


# --- the window ------------------------------------------------------------------------------
class Installer(Adw.ApplicationWindow):
    def __init__(self, app: Adw.Application):
        super().__init__(application=app, title="Install Lumen OS", default_width=980, default_height=720)
        self.answers: dict[str, str] = {
            "theme": "lumen", "layout": "classic", "browser": "firefox", "terminal": "ghostty", "editor": "code",
            "gaming": "0", "encrypt": "", "keymap": "us", "timezone": "UTC", "autologin": "0",
        }
        self.disk_choice: dict | None = None
        self.proc: subprocess.Popen | None = None
        self.done_steps: set[str] = set()
        self.load_style()

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT, vexpand=True)
        self.pages = [
            ("welcome", self.page_welcome()),
            ("network", self.page_network()),
            ("disk", self.page_disk()),
            ("account", self.page_account()),
            ("region", self.page_region()),
            ("look", self.page_look()),
            ("apps", self.page_apps()),
            ("review", self.page_review()),
        ]
        for name, widget in self.pages:
            self.stack.add_named(widget, name)
        self.stack.add_named(self.page_progress(), "progress")
        self.stack.add_named(self.page_finished(), "finished")
        self.stack.add_named(self.page_failed(), "failed")

        self.back = Gtk.Button(label="Back")
        self.back.connect("clicked", lambda *_: self.go(-1))
        self.next = Gtk.Button(label="Next", css_classes=["suggested-action", "pill"])
        self.next.connect("clicked", lambda *_: self.go(+1))
        self.dots = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER, hexpand=True)
        self.nav = Gtk.Box(spacing=12, margin_start=24, margin_end=24, margin_bottom=18, margin_top=6)
        self.nav.append(self.back)
        self.nav.append(self.dots)
        self.nav.append(self.next)

        view = Adw.ToolbarView()
        view.add_top_bar(Adw.HeaderBar(title_widget=Adw.WindowTitle(title="Install Lumen OS",
                                                                    subtitle="Demo mode: nothing will be written" if DEMO else "")))
        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        body.append(self.stack)
        body.append(self.nav)
        view.set_content(body)
        self.toast = Adw.ToastOverlay(child=view)
        self.set_content(self.toast)
        self.index = 0
        # LUMEN_INSTALLER_PAGE=disk opens at a page (screenshots and tests).
        start = os.environ.get("LUMEN_INSTALLER_PAGE", "")
        self.show_index(next((i for i, p in enumerate(self.pages) if p[0] == start), 0))

    # --- helpers -------------------------------------------------------------------------
    def load_style(self) -> None:
        display = Gdk.Display.get_default()
        if not display:
            return
        for path, prio in ((CONFIG / "current/theme/apps.css", 0), (HERE / "style.css", 1)):
            if path.exists():
                provider = Gtk.CssProvider()
                provider.load_from_path(str(path))
                Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + prio)
        # Swatch colours for the theme gallery.
        css = []
        for slug, t in themes():
            for key in ("bg", "bg_alt", "accent", "accent2", "red", "yellow", "green", "fg"):
                if t.get(key, "").startswith("#"):
                    css.append(f".sw-{slug}-{key} {{ background: {t[key]}; }}")
        provider = Gtk.CssProvider()
        provider.load_from_string("\n".join(css)) if hasattr(provider, "load_from_string") else provider.load_from_data("\n".join(css).encode())
        Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 2)
        env = CONFIG / "current/theme/theme.env"
        light = env.exists() and 'LUMEN_THEME_MODE="light"' in env.read_text()
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_LIGHT if light else Adw.ColorScheme.FORCE_DARK)

    def page(self, title: str, subtitle: str, *children: Gtk.Widget) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin_start=48, margin_end=48, margin_top=12, margin_bottom=12)
        box.append(Gtk.Label(label=title, xalign=0, css_classes=["title-1"]))
        if subtitle:
            box.append(Gtk.Label(label=subtitle, xalign=0, wrap=True, css_classes=["dim-label", "installer-sub"]))
        for c in children:
            box.append(c)
        clamp = Adw.Clamp(maximum_size=860, child=box)
        return Gtk.ScrolledWindow(child=clamp, hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)

    def toast_msg(self, text: str) -> None:
        self.toast.add_toast(Adw.Toast(title=text, timeout=3))

    def go(self, step: int) -> None:
        if step > 0 and not self.validate(self.pages[self.index][0]):
            return
        if step > 0 and self.pages[self.index][0] == "review":
            self.confirm_install()
            return
        self.show_index(max(0, min(len(self.pages) - 1, self.index + step)))

    def show_index(self, i: int) -> None:
        self.index = i
        name = self.pages[i][0]
        self.stack.set_visible_child_name(name)
        self.back.set_sensitive(i > 0)
        review_label = "Install alongside Windows" if self.alongside() else "Erase disk and install"
        self.next.set_label(review_label if name == "review" else "Next")
        self.next.remove_css_class("destructive-action")
        self.next.remove_css_class("suggested-action")
        self.next.add_css_class("destructive-action" if name == "review" else "suggested-action")
        while (c := self.dots.get_first_child()):
            self.dots.remove(c)
        for j in range(len(self.pages)):
            dot = Gtk.Box(css_classes=["dot", "dot-active" if j == i else "dot-idle"], valign=Gtk.Align.CENTER)
            dot.set_size_request(8, 8)
            self.dots.append(dot)
        if name == "review":
            self.fill_review()
        if name == "network":
            self.refresh_network()

    # --- 1. welcome --------------------------------------------------------------------------
    def page_welcome(self) -> Gtk.Widget:
        svg = LUMEN_PATH / "share/icons/hicolor/scalable/apps/lumen-logo.svg"
        logo = Gtk.Image.new_from_file(str(svg)) if svg.exists() else Gtk.Image(icon_name="lumen-logo")
        logo.set_pixel_size(96)
        logo.set_margin_top(24)
        hello = Gtk.Label(label="Welcome to Lumen OS", css_classes=["title-1"])
        text = Gtk.Label(wrap=True, justify=Gtk.Justification.CENTER, css_classes=["installer-sub"],
                         label="You're running Lumen from the USB stick right now: look around, open apps, try the "
                               "Start menu (tap the Windows key). When you're ready, this installer asks a few "
                               "questions and puts Lumen on your computer. It only takes a few minutes.")
        keymap = Adw.ComboRow(title="Keyboard layout", subtitle="Used for the disk password and the console")
        self.keymaps = keymaps()
        keymap.set_model(Gtk.StringList.new(self.keymaps))
        keymap.connect("notify::selected", lambda r, *_: self.answers.__setitem__("keymap", self.keymaps[r.get_selected()]))
        group = Adw.PreferencesGroup(margin_top=12)
        group.add(keymap)
        tips = Gtk.Button(label="New to Lumen? Open the tips", css_classes=["flat"], halign=Gtk.Align.CENTER)
        tips.connect("clicked", lambda *_: lumen("lumen-welcome"))
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, halign=Gtk.Align.CENTER)
        for w in (logo, hello, text, group, tips):
            box.append(w)
        return self.page("", "", box)

    # --- 2. network --------------------------------------------------------------------------
    def page_network(self) -> Gtk.Widget:
        self.net_status = Adw.ActionRow(title="Checking your connection…")
        self.net_icon = Gtk.Image(icon_name="network-wired-symbolic")
        self.net_status.add_prefix(self.net_icon)
        status = Adw.PreferencesGroup()
        status.add(self.net_status)
        self.wifi_group = Adw.PreferencesGroup(title="Wi-Fi networks")
        rescan = Gtk.Button(icon_name="view-refresh-symbolic", valign=Gtk.Align.CENTER, css_classes=["flat"], tooltip_text="Scan again")
        rescan.connect("clicked", lambda *_: self.scan_wifi())
        self.wifi_group.set_header_suffix(rescan)
        self.wifi_rows: list[Gtk.Widget] = []
        return self.page("Connect to the internet", "Lumen downloads the latest packages while it installs. "
                         "Plugged-in and virtual machine connections work by themselves.", status, self.wifi_group)

    def refresh_network(self) -> None:
        def check() -> bool:
            ok = online()
            self.net_status.set_title("Connected to the internet" if ok else "Not connected yet")
            self.net_status.set_subtitle("" if ok else "Choose a Wi-Fi network below, or plug in a cable")
            self.net_icon.set_from_icon_name("network-transmit-receive-symbolic" if ok else "network-offline-symbolic")
            self.connected = ok
            return False
        GLib.timeout_add(100, check)
        if not self.wifi_rows:
            self.scan_wifi()

    def scan_wifi(self) -> None:
        for r in self.wifi_rows:
            self.wifi_group.remove(r)
        self.wifi_rows = []
        nets = wifi_networks()
        if not nets:
            row = Adw.ActionRow(title="No Wi-Fi networks found", subtitle="No Wi-Fi adapter, or nothing in range")
            self.wifi_group.add(row)
            self.wifi_rows.append(row)
            return
        for ssid, signal, secured in nets[:12]:
            row = Adw.ActionRow(title=ssid, subtitle=f"{signal}%{' · secured' if secured else ''}", activatable=True)
            icon = "network-wireless-signal-excellent-symbolic" if signal > 66 else \
                "network-wireless-signal-good-symbolic" if signal > 33 else "network-wireless-signal-weak-symbolic"
            row.add_prefix(Gtk.Image(icon_name=icon))
            row.connect("activated", lambda _r, s=ssid, sec=secured: self.connect_wifi(s, sec))
            self.wifi_group.add(row)
            self.wifi_rows.append(row)

    def connect_wifi(self, ssid: str, secured: bool) -> None:
        def do(password: str) -> None:
            cmd = ["nmcli", "device", "wifi", "connect", ssid] + (["password", password] if password else [])
            ok = subprocess.run(cmd, capture_output=True, timeout=45).returncode == 0
            self.toast_msg(f"Connected to {ssid}" if ok else f"Couldn't connect to {ssid}")
            self.refresh_network()
        if not secured:
            do("")
            return
        dialog = Adw.AlertDialog(heading=f"Password for {ssid}")
        entry = Gtk.PasswordEntry(show_peek_icon=True, activates_default=True)
        dialog.set_extra_child(entry)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("connect", "Connect")
        dialog.set_response_appearance("connect", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("connect")
        dialog.connect("response", lambda _d, r: r == "connect" and do(entry.get_text()))
        dialog.present(self)

    # --- 3. disk -------------------------------------------------------------------------------
    def page_disk(self) -> Gtk.Widget:
        group = Adw.PreferencesGroup(title="Install on", description="Erasing a disk deletes everything on it. "
                                     "A disk with Windows can keep it: Lumen goes alongside.")
        self.disk_list = disks()
        first: Gtk.CheckButton | None = None
        if not self.disk_list:
            group.add(Adw.ActionRow(title="No suitable disk found", subtitle="Lumen needs at least 20 GB"))
        for d in self.disk_list:
            check = Gtk.CheckButton(group=first)
            first = first or check
            row = Adw.ActionRow(title=f"{d['label']} · {d['size']}", subtitle=d["detail"], activatable_widget=check)
            row.add_prefix(check)
            row.add_prefix(Gtk.Image(icon_name="drive-harddisk-symbolic"))
            if d.get("contents"):
                row.add_suffix(Gtk.Label(label="Not empty", css_classes=["error", "caption-heading"]))
            check.connect("toggled", lambda c, d=d: c.get_active() and self.pick_disk(d))
            group.add(row)

        # A disk with Windows: install alongside it (keep Windows), or erase it.
        self.space_cache: dict[str, dict] = {}
        self.how = Adw.PreferencesGroup(title="Windows is on this disk", visible=False)
        self.how_mode = Adw.ComboRow(title="Install", model=Gtk.StringList.new(
            ["Alongside Windows (keep it)", "Erase the whole disk"]))
        self.how_size = Adw.SpinRow.new_with_range(30, 30, 1)
        self.how_size.set_title("Space for Lumen (GB)")
        self.how_size.set_subtitle("Windows keeps the rest. You choose which to start at every start-up.")
        self.how_status = Adw.ActionRow(title="", visible=False, css_classes=["error"])
        self.how_mode.connect("notify::selected", lambda *_: self.update_how())
        for w in (self.how_mode, self.how_size, self.how_status):
            self.how.add(w)
        if first:
            first.set_active(True)
            self.pick_disk(self.disk_list[0])
        crypt = Adw.PreferencesGroup(title="Encryption", description="Recommended for laptops: nobody can read your files "
                                     "without the password, even with the disk in hand. You type it at every start.")
        self.encrypt = Adw.SwitchRow(title="Encrypt the disk")
        self.crypt_pass = Adw.PasswordEntryRow(title="Disk password", visible=False)
        self.crypt_pass2 = Adw.PasswordEntryRow(title="Disk password again", visible=False)
        self.encrypt.connect("notify::active", lambda s, *_: (self.crypt_pass.set_visible(s.get_active()),
                                                              self.crypt_pass2.set_visible(s.get_active())))
        for w in (self.encrypt, self.crypt_pass, self.crypt_pass2):
            crypt.add(w)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        box.append(self.how)
        box.append(crypt)
        return self.page("Where should Lumen go?", "", group, box)

    def pick_disk(self, d: dict) -> None:
        self.disk_choice = d
        has_windows = "Windows" in d.get("contents", "")
        self.how.set_visible(has_windows)
        if has_windows and d["path"] not in self.space_cache:
            self.space_cache[d["path"]] = alongside_space(d["path"])
        self.update_how()

    def alongside(self) -> bool:
        """Installing next to Windows on the chosen disk?"""
        how = getattr(self, "how", None)
        return bool(getattr(self, "disk_choice", None) and how and how.get_visible() and self.how_mode.get_selected() == 0)

    def update_how(self) -> None:
        if not self.how.get_visible():
            return
        info = self.space_cache.get(self.disk_choice["path"], {})
        err = info.get("error", "")
        max_gb = int(info.get("max_gb", "0") or 0)
        if not err and max_gb < 30:
            err = f"Only {max_gb} GB can be freed next to Windows; Lumen needs 30 GB. Free up space in Windows first."
        along = self.how_mode.get_selected() == 0
        self.how_status.set_visible(along and bool(err))
        self.how_status.set_title(err)
        self.how_size.set_visible(along and not err)
        if not err and max_gb >= 30:
            self.how_size.set_range(30, max_gb)
            if self.how_size.get_value() <= 30:
                self.how_size.set_value(min(max_gb, max(30, min(60, max_gb // 2 if max_gb // 2 > 60 else max_gb))))

    # --- 4. account ----------------------------------------------------------------------------
    def page_account(self) -> Gtk.Widget:
        group = Adw.PreferencesGroup()
        self.fullname = Adw.EntryRow(title="Your name")
        self.username = Adw.EntryRow(title="Username")
        self.password = Adw.PasswordEntryRow(title="Password")
        self.password2 = Adw.PasswordEntryRow(title="Password again")
        self.hostname = Adw.EntryRow(title="Computer name", text="lumen")
        self.autologin = Adw.SwitchRow(title="Log in automatically", subtitle="Skip the login screen. Best with disk encryption")
        self.user_edited = False
        self.fullname.connect("changed", self.suggest_username)
        self.username.connect("changed", lambda *_: setattr(self, "user_edited", self.username.is_focus() or self.user_edited))
        for w in (self.fullname, self.username, self.password, self.password2, self.hostname, self.autologin):
            group.add(w)
        return self.page("Who will use it?", "Your account can install apps and change settings (with your password).", group)

    def suggest_username(self, *_: object) -> None:
        if self.user_edited:
            return
        first = (self.fullname.get_text().strip().split() or [""])[0].lower()
        self.username.set_text(re.sub(r"[^a-z0-9_-]", "", first)[:24])

    # --- 5. region -----------------------------------------------------------------------------
    def page_region(self) -> Gtk.Widget:
        self.zones = timezones()
        guess = guess_timezone()
        self.answers["timezone"] = guess if guess in self.zones else "UTC"
        tz = Adw.ComboRow(title="Time zone", enable_search=True)
        tz.set_model(Gtk.StringList.new(self.zones))
        if self.answers["timezone"] in self.zones:
            tz.set_selected(self.zones.index(self.answers["timezone"]))
        tz.connect("notify::selected", lambda r, *_: self.answers.__setitem__("timezone", self.zones[r.get_selected()]))
        group = Adw.PreferencesGroup(description="Detected from your internet connection; change it if it's wrong.")
        group.add(tz)
        return self.page("Where are you?", "", group)

    # --- 6. look (CachyOS-style theme picker) ------------------------------------------------------
    def page_look(self) -> Gtk.Widget:
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=4, min_children_per_line=2,
                           row_spacing=14, column_spacing=14, homogeneous=True)
        self.theme_buttons: dict[str, Gtk.Button] = {}
        for slug, t in themes():
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            wp = wallpaper_for(slug)
            if wp:
                pic = Gtk.Picture.new_for_filename(str(wp))
                pic.set_content_fit(Gtk.ContentFit.COVER)
                pic.set_size_request(200, 112)
                pic.add_css_class("theme-preview")
                card.append(pic)
            else:
                ph = Gtk.Box(css_classes=["theme-preview", f"sw-{slug}-bg"])
                ph.set_size_request(200, 112)
                card.append(ph)
            sw = Gtk.Box(spacing=4, halign=Gtk.Align.CENTER)
            for key in ("accent", "accent2", "red", "yellow", "green"):
                dot = Gtk.Box(css_classes=["swatch", f"sw-{slug}-{key}"])
                dot.set_size_request(16, 16)
                sw.append(dot)
            card.append(sw)
            card.append(Gtk.Label(label=t.get("name", slug), css_classes=["heading"]))
            b = Gtk.Button(child=card, css_classes=["theme-card"])
            b.connect("clicked", lambda _b, s=slug: self.pick_theme(s))
            self.theme_buttons[slug] = b
            flow.append(b)
        self.pick_theme("lumen", apply=False)

        layouts = Adw.PreferencesGroup(title="Layout", description="Change any of this later from the Lumen menu.")
        first: Gtk.CheckButton | None = None
        for key, name, desc, taskbar, titlebars in LAYOUTS:
            check = Gtk.CheckButton(group=first)
            first = first or check
            row = Adw.ActionRow(title=name, subtitle=desc, activatable_widget=check)
            row.add_prefix(check)
            check.connect("toggled", lambda c, k=key, tb=taskbar: c.get_active() and self.pick_layout(k, tb))
            layouts.add(row)
        if first:
            first.set_active(True)
        return self.page("Make it yours", "Pick a theme: the desktop around you changes as you click. "
                         "Every theme restyles windows, bars, menus, the terminal and apps together.", flow, layouts)

    def pick_theme(self, slug: str, apply: bool = True) -> None:
        self.answers["theme"] = slug
        for s, b in self.theme_buttons.items():
            (b.add_css_class if s == slug else b.remove_css_class)("theme-card-active")
        if apply and not DEMO:
            lumen("lumen-theme", "set", slug)
            GLib.timeout_add(800, lambda: (self.load_style(), False)[1])

    def pick_layout(self, key: str, taskbar: str) -> None:
        self.answers["layout"] = key
        if not DEMO:
            lumen("lumen-taskbar", "on" if taskbar == "yes" else "off")

    # --- 7. apps -------------------------------------------------------------------------------
    def choice_group(self, title: str, key: str, options: list[tuple[str, str, str]]) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup(title=title)
        first: Gtk.CheckButton | None = None
        for value, name, desc in options:
            check = Gtk.CheckButton(group=first)
            first = first or check
            row = Adw.ActionRow(title=name, subtitle=desc, activatable_widget=check)
            row.add_prefix(check)
            check.connect("toggled", lambda c, v=value: c.get_active() and self.answers.__setitem__(key, v))
            group.add(row)
        if first:
            first.set_active(True)
        return group

    def page_apps(self) -> Gtk.Widget:
        gaming = Adw.PreferencesGroup(title="Gaming")
        self.gaming = Adw.SwitchRow(title="Set up gaming", subtitle="Steam with Proton, GameMode, MangoHud, gamescope and 32-bit drivers")
        gaming.add(self.gaming)
        return self.page("Your apps", "Everything else (files, images, video, PDFs, the App Store) is included. "
                         "Add more later from the App Store.",
                         self.choice_group("Web browser", "browser", BROWSERS),
                         self.choice_group("Terminal", "terminal", TERMINALS),
                         self.choice_group("Code editor", "editor", EDITORS), gaming)

    # --- 8. review -----------------------------------------------------------------------------
    def page_review(self) -> Gtk.Widget:
        self.review = Adw.PreferencesGroup()
        return self.page("Ready to install", "Check the details. Installing erases the chosen disk.", self.review)

    def fill_review(self) -> None:
        # Rows can't be cleared from a PreferencesGroup, so swap in a new one.
        parent = self.review.get_parent()
        new = Adw.PreferencesGroup()
        a = self.collect()
        layout = next(l for l in LAYOUTS if l[0] == a["layout"])
        theme = dict(themes()).get(a["theme"], {}).get("name", a["theme"])
        rows = [
            ("drive-harddisk-symbolic", "Disk", (f"{self.disk_choice['label']} · {self.disk_choice['size']} ({a['disk']}) — "
                                                 + (f"alongside Windows, {int(self.how_size.get_value())} GB for Lumen" if self.alongside() else "will be erased"))
             if self.disk_choice else "none"),
            ("channel-secure-symbolic", "Encryption", "On" if a["encrypt"] else "Off"),
            ("avatar-default-symbolic", "Account", f"{a['fullname']} ({a['user']}) on “{a['hostname']}”" + (", logs in automatically" if a["autologin"] == "1" else "")),
            ("preferences-system-time-symbolic", "Time zone", a["timezone"]),
            ("input-keyboard-symbolic", "Keyboard", a["keymap"]),
            ("applications-graphics-symbolic", "Look", f"{theme} theme, {layout[1]} layout"),
            ("applications-internet-symbolic", "Apps", f"{a['browser']}, {a['terminal']}, {a['editor']}" + (", gaming" if a["gaming"] == "1" else "")),
        ]
        for icon, title, sub in rows:
            row = Adw.ActionRow(title=title, subtitle=sub)
            row.add_prefix(Gtk.Image(icon_name=icon))
            new.add(row)
        if parent is not None:
            parent.remove(self.review)
            parent.append(new)
        self.review = new

    # --- validation and answers --------------------------------------------------------------------
    def validate(self, page: str) -> bool:
        if page == "network" and not getattr(self, "connected", False) and not DEMO:
            if not online():
                self.toast_msg("Connect to the internet first")
                return False
        if page == "disk":
            if not self.disk_choice:
                self.toast_msg("No disk to install on")
                return False
            if self.alongside() and self.how_status.get_visible():
                self.toast_msg("Lumen can't go alongside Windows on this disk yet (see the message)")
                return False
            if self.encrypt.get_active():
                p1, p2 = self.crypt_pass.get_text(), self.crypt_pass2.get_text()
                if len(p1) < 4:
                    self.toast_msg("Choose a disk password (at least 4 characters)")
                    return False
                if p1 != p2:
                    self.toast_msg("The disk passwords don't match")
                    return False
        if page == "account":
            if not self.fullname.get_text().strip():
                self.toast_msg("Enter your name")
                return False
            if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", self.username.get_text()):
                self.toast_msg("Username: lower-case letters, digits, - and _")
                return False
            if not self.password.get_text():
                self.toast_msg("Choose a password")
                return False
            if self.password.get_text() != self.password2.get_text():
                self.toast_msg("The passwords don't match")
                return False
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,62}", self.hostname.get_text()):
                self.toast_msg("Computer name: letters, digits and -")
                return False
        return True

    def collect(self) -> dict[str, str]:
        a = dict(self.answers)
        layout = next(l for l in LAYOUTS if l[0] == a["layout"])
        a.update({
            "disk": self.disk_choice["path"] if self.disk_choice else "",
            "mode": "alongside" if self.alongside() else "erase",
            "size": str(int(self.how_size.get_value())) if self.alongside() else "",
            "encrypt": self.crypt_pass.get_text() if self.encrypt.get_active() else "",
            "fullname": self.fullname.get_text().strip(),
            "user": self.username.get_text(),
            "pass": self.password.get_text(),
            "hostname": self.hostname.get_text(),
            "autologin": "1" if self.autologin.get_active() else "0",
            "gaming": "1" if self.gaming.get_active() else "0",
            "taskbar": "1" if layout[3] == "yes" else "0",
            "titlebars": "1" if layout[4] == "yes" else "0",
        })
        return a

    # --- install ---------------------------------------------------------------------------------
    def confirm_install(self) -> None:
        d = self.disk_choice
        if self.alongside():
            gb = int(self.how_size.get_value())
            dialog = Adw.AlertDialog(heading="Install alongside Windows?",
                                     body=f"Windows will be shrunk to make {gb} GB of room for Lumen. Windows and its files "
                                          "are kept, and you choose which to start every time the computer starts.\n\n"
                                          "Resizing is safe, but back up anything important first (a power cut during it "
                                          "could cause damage).")
            dialog.add_response("cancel", "Cancel")
            dialog.add_response("install", "Install alongside Windows")
            dialog.set_response_appearance("install", Adw.ResponseAppearance.SUGGESTED)
            dialog.set_default_response("cancel")
            dialog.connect("response", lambda _d, r: r == "install" and self.start_install())
            dialog.present(self)
            return
        body = f"Everything on {d['label']} ({d['size']}, {d['path']}) will be permanently erased."
        if d.get("contents"):
            body += (f"\n\nThis disk is not empty: it has {d['contents']}. Installing deletes it all, including "
                     "any Windows and its files. Copy anything you want to keep to another drive first.\n\n"
                     "Type ERASE to confirm.")
        dialog = Adw.AlertDialog(heading="Erase this disk?", body=body)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("install", "Erase and install")
        dialog.set_response_appearance("install", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")
        if d.get("contents"):
            # A disk with something on it needs the word typed, not just a click.
            entry = Gtk.Entry(placeholder_text="ERASE")
            dialog.set_extra_child(entry)
            dialog.set_response_enabled("install", False)
            entry.connect("changed", lambda e: dialog.set_response_enabled("install", e.get_text().strip() == "ERASE"))
        dialog.connect("response", lambda _d, r: r == "install" and self.start_install())
        dialog.present(self)

    def start_install(self) -> None:
        answers = self.collect()
        fd, path = tempfile.mkstemp(prefix="lumen-answers-", dir="/run/user/%d" % os.getuid() if Path(f"/run/user/{os.getuid()}").is_dir() else None)
        with os.fdopen(fd, "w") as f:
            for k, v in answers.items():
                f.write(f"{k}={v.replace(chr(10), ' ')}\n")
        os.chmod(path, 0o600)
        self.nav.set_visible(False)
        self.stack.set_visible_child_name("progress")
        cmd = ["sudo", "-n", ENGINE, "--answers", path]
        if DEMO:
            cmd = ["bash", "-c", "for s in Mirrors Partitioning Formatting 'Creating btrfs' 'Installing the base system' "
                   "'Configuring the system' 'Copying Lumen' '[1/9]' '[4/9]' '[8/9]' '[9/9]'; do echo \"==> $s\"; sleep 1; done; "
                   "echo LUMEN-INSTALL-OK"]
        self.proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.answers_path = path
        channel = GLib.IOChannel.unix_new(self.proc.stdout.fileno())
        GLib.io_add_watch(channel, GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP, self.on_output)
        GLib.timeout_add(1500, self.tail_log)

    def note_progress(self, line: str) -> None:
        for step in STEPS:
            if step in line and step not in self.done_steps:
                self.done_steps.add(step)
                label = FRIENDLY.get(step, step.replace("Mirrors", "Choosing the fastest download mirrors"))
                self.progress_label.set_text(label)
                self.progress.set_fraction(min(0.99, (STEPS.index(step) + 1) / len(STEPS)))

    def append_log(self, line: str) -> None:
        buf = self.log_view.get_buffer()
        buf.insert(buf.get_end_iter(), line)
        if buf.get_line_count() > 400:
            start = buf.get_start_iter()
            buf.delete(start, buf.get_iter_at_line(buf.get_line_count() - 400)[1])
        self.log_view.scroll_to_iter(buf.get_end_iter(), 0, False, 0, 1)

    def on_output(self, _channel: GLib.IOChannel, condition: GLib.IOCondition) -> bool:
        line = self.proc.stdout.readline() if self.proc and self.proc.stdout else ""
        if line:
            clean = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", line)
            self.append_log(clean)
            self.note_progress(clean)
            return True
        if self.proc and self.proc.poll() is None and not (condition & GLib.IOCondition.HUP):
            return True
        rc = self.proc.wait() if self.proc else 1
        try:
            os.unlink(self.answers_path)
        except OSError:
            pass
        if rc == 0:
            self.progress.set_fraction(1.0)
            self.stack.set_visible_child_name("finished")
        else:
            self.fail_text.set_text(self.log_tail())
            self.stack.set_visible_child_name("failed")
        return False

    def tail_log(self) -> bool:
        if not self.proc or self.proc.poll() is not None:
            return False
        try:
            with LOG.open() as f:
                f.seek(max(0, LOG.stat().st_size - 4000))
                for line in f.read().splitlines():
                    self.note_progress(line)
        except OSError:
            pass
        return True

    def log_tail(self) -> str:
        try:
            return "\n".join(LOG.read_text(errors="replace").splitlines()[-25:])
        except OSError:
            buf = self.log_view.get_buffer()
            return buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False)[-3000:]

    def page_progress(self) -> Gtk.Widget:
        self.progress = Gtk.ProgressBar(show_text=False, margin_top=12)
        self.progress_label = Gtk.Label(label="Starting…", xalign=0, css_classes=["title-4"])
        tip = Gtk.Label(wrap=True, xalign=0, css_classes=["dim-label"],
                        label="This takes a few minutes: almost everything comes from the USB stick. Keep exploring the live desktop meanwhile; "
                              "just don't switch the computer off.")
        self.log_view = Gtk.TextView(editable=False, monospace=True, cursor_visible=False, wrap_mode=Gtk.WrapMode.CHAR,
                                     css_classes=["installer-log"])
        scroller = Gtk.ScrolledWindow(child=self.log_view, min_content_height=260, vexpand=True)
        details = Gtk.Expander(label="Details", child=scroller)
        return self.page("Installing Lumen OS", "", self.progress_label, self.progress, tip, details)

    def page_finished(self) -> Gtk.Widget:
        status = Adw.StatusPage(icon_name="emblem-ok-symbolic", title="Lumen OS is installed",
                                description="Remove the USB stick, then restart. After logging in, tap the Windows key to open Start.")
        restart = Gtk.Button(label="Restart now", halign=Gtk.Align.CENTER, css_classes=["suggested-action", "pill"])
        restart.connect("clicked", lambda *_: detached("systemctl", "reboot"))
        status.set_child(restart)
        return status

    def page_failed(self) -> Gtk.Widget:
        self.fail_text = Gtk.Label(wrap=True, xalign=0, selectable=True, css_classes=["installer-log"])
        status = Adw.StatusPage(icon_name="dialog-error-symbolic", title="The installation didn't finish",
                                description="Nothing else on your computer was changed. The details are below and in "
                                            "/var/log/lumen-os-install.log.")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.append(Gtk.ScrolledWindow(child=self.fail_text, min_content_height=220))
        again = Gtk.Button(label="Start over", halign=Gtk.Align.CENTER, css_classes=["pill"])
        again.connect("clicked", lambda *_: (self.nav.set_visible(True), self.show_index(0)))
        box.append(again)
        status.set_child(box)
        return status


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id="org.lumen.Installer", flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_activate(self) -> None:
        win = self.props.active_window or Installer(self)
        win.present()


if __name__ == "__main__":
    sys.exit(App().run(sys.argv[:1]))
