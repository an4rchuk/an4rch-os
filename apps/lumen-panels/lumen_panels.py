#!/usr/bin/env python3
"""an4rch quick panels — drop down from the top bar's icons, like the sound
panel: Networks (Wi-Fi, airplane mode, hotspot, the connected network with
its download and upload speed, networks to join), Bluetooth (on/off,
devices to connect or pair) and Power (battery, power mode, brightness,
lock / sleep / log out / restart / shut down).

    lumen_panels.py network|bluetooth|power   open that panel (again: close)
    lumen_panels.py --daemon                   start hidden (at login)

It stays running hidden after the first open, so clicking an icon shows its
panel at once. Click outside it or press Esc to close it. Slow commands
(nmcli, bluetoothctl) run in the background so the panel never freezes.
"""

from __future__ import annotations

import os
import re
import secrets
import socket
import subprocess
import sys
import threading
from pathlib import Path
from typing import Callable

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

try:  # Layer shell turns the window into a proper overlay on Wayland.
    gi.require_version("Gtk4LayerShell", "1.0")
    from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402
except (ValueError, ImportError):
    LayerShell = None

APP_ID = "org.lumen.Panels"
PAGES = ("network", "bluetooth", "power")
HOME = Path.home()
LUMEN_PATH = Path(os.environ.get("LUMEN_PATH", HOME / ".local/share/lumen"))
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "lumen"
THEME_CSS = CONFIG / "current/theme/apps.css"
BASE_CSS = LUMEN_PATH / "apps/lumen-audio/style.css"  # the sound panel's look, shared
STYLE_CSS = Path(__file__).with_name("style.css")
DEMO = os.environ.get("LUMEN_PANELS_DEMO") == "1"  # tests: sample data, no commands


# --- helpers ---------------------------------------------------------------------------

def out(*cmd: str, timeout: float = 6) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def ok(*cmd: str, timeout: float = 30) -> tuple[bool, str]:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode == 0, (r.stderr or r.stdout).strip()
    except (OSError, subprocess.SubprocessError) as err:
        return False, str(err)


def spawn(*cmd: str) -> None:
    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError as err:
        print(f"anarch-panel: {err}", file=sys.stderr)


def lumen(*argv: str) -> None:
    path = LUMEN_PATH / "bin" / argv[0]
    spawn(str(path) if path.exists() else argv[0], *argv[1:])


def notify(title: str, body: str = "", icon: str = "dialog-information") -> None:
    spawn("notify-send", "-a", "an4rch", "-i", icon, title, body)


def background(work: Callable[[], object], done: Callable[[object], None] | None = None) -> None:
    """Run work() in a thread, then done(result) in the GTK main loop."""
    def runner() -> None:
        result = work()
        if done is not None:
            GLib.idle_add(lambda: (done(result), False)[1])
    threading.Thread(target=runner, daemon=True).start()


def nm_split(line: str) -> list[str]:
    """Split an `nmcli -t` line: fields are separated by ':', and a ':' or '\\'
    inside a value is escaped with a backslash."""
    fields, cur, i = [], [], 0
    while i < len(line):
        c = line[i]
        if c == "\\" and i + 1 < len(line):
            cur.append(line[i + 1])
            i += 2
            continue
        if c == ":":
            fields.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    fields.append("".join(cur))
    return fields


def human_rate(bps: float) -> str:
    for unit in ("B/s", "KB/s", "MB/s", "GB/s"):
        if bps < 1000 or unit == "GB/s":
            return f"{bps:.0f} {unit}" if unit == "B/s" or bps >= 100 else f"{bps:.1f} {unit}"
        bps /= 1000
    return ""


def signal_icon(signal: int) -> str:
    level = "excellent" if signal > 75 else "good" if signal > 50 else "ok" if signal > 25 else "weak"
    return f"network-wireless-signal-{level}-symbolic"


def clear(box: Gtk.Widget) -> None:
    while (child := box.get_first_child()) is not None:
        box.remove(child)


def label(text: str, *classes: str, **kw) -> Gtk.Label:
    kw.setdefault("xalign", 0)
    return Gtk.Label(label=text, css_classes=list(classes), **kw)


def icon_button(icon: str, tooltip: str, cb: Callable[[], None], *classes: str) -> Gtk.Button:
    b = Gtk.Button(icon_name=icon, tooltip_text=tooltip, css_classes=["flat", "circular", *classes],
                   valign=Gtk.Align.CENTER)
    b.connect("clicked", lambda *_: cb())
    return b


def text_button(text: str, cb: Callable[[], None], icon: str | None = None, *classes: str) -> Gtk.Button:
    b = Gtk.Button(css_classes=["pill", *classes], valign=Gtk.Align.CENTER)
    inner = Gtk.Box(spacing=6)
    if icon:
        inner.append(Gtk.Image.new_from_icon_name(icon))
    inner.append(Gtk.Label(label=text))
    b.set_child(inner)
    b.connect("clicked", lambda *_: cb())
    return b


def toggle_chip(icon: str, tooltip: str, on_toggle: Callable[[bool], None]) -> Gtk.Box:
    """A small switch with an icon, like KDE's Wi-Fi / airplane toggles."""
    box = Gtk.Box(spacing=6, css_classes=["chip"], tooltip_text=tooltip)
    sw = Gtk.Switch(valign=Gtk.Align.CENTER)
    box.switch = sw  # type: ignore[attr-defined]
    box.updating = False  # type: ignore[attr-defined]

    def changed(s: Gtk.Switch, _p) -> None:
        if not box.updating:  # type: ignore[attr-defined]
            on_toggle(s.get_active())
    sw.connect("notify::active", changed)
    box.append(sw)
    box.append(Gtk.Image.new_from_icon_name(icon))
    return box


def set_chip(chip: Gtk.Box, active: bool) -> None:
    chip.updating = True  # type: ignore[attr-defined]
    chip.switch.set_active(active)  # type: ignore[attr-defined]
    chip.updating = False  # type: ignore[attr-defined]


# --- Network ---------------------------------------------------------------------------

class NetworkPage(Gtk.Box):
    def __init__(self, panel: "Panels"):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.panel = panel
        self.networks: list[dict] = []
        self.known: set[str] = set()
        self.profiles: dict[str, str] = {}
        self.active: dict = {}
        self.wired: dict = {}
        self.open_password: str | None = None
        self.counters: tuple[str, int, int, int] | None = None
        self.speed: Gtk.Label | None = None
        self.speed_timer = 0

        head = Gtk.Box(spacing=8)
        head.append(label("Networks", "title", hexpand=True))
        head.append(icon_button("view-refresh-symbolic", "Look for networks", self.rescan))
        head.append(icon_button("emblem-system-symbolic", "Network settings",
                                lambda: self.panel.leave("anarch-settings", "network")))
        self.append(head)

        bar = Gtk.Box(spacing=8)
        self.wifi_chip = toggle_chip("network-wireless-symbolic", "Wi-Fi", self.set_wifi)
        self.plane_chip = toggle_chip("airplane-mode-symbolic", "Airplane mode", self.set_airplane)
        bar.append(self.wifi_chip)
        bar.append(self.plane_chip)
        self.hotspot = text_button("Hotspot", self.toggle_hotspot, "network-wireless-hotspot-symbolic")
        bar.append(self.hotspot)
        self.search = Gtk.SearchEntry(placeholder_text="Search…", hexpand=True)
        self.search.connect("search-changed", lambda *_: self.fill_available())
        bar.append(self.search)
        self.append(bar)

        self.hotspot_info = label("", "dim", wrap=True, selectable=True)
        self.hotspot_info.set_visible(False)
        self.append(self.hotspot_info)

        self.connected_label = label("Connected", "section")
        self.append(self.connected_label)
        self.connected = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.append(self.connected)

        self.available_label = label("Available", "section")
        self.append(self.available_label)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, propagate_natural_height=True,
                                    max_content_height=360)
        self.available = Gtk.ListBox(css_classes=["devices"], selection_mode=Gtk.SelectionMode.NONE)
        scroll.set_child(self.available)
        self.append(scroll)
        self.status = label("", "dim", wrap=True)
        self.append(self.status)

        foot = Gtk.Box(spacing=8, homogeneous=True, margin_top=4)
        foot.append(text_button("Hidden network…", lambda: self.panel.leave("anarch-wifi")))
        foot.append(text_button("Network settings", lambda: self.panel.leave("anarch-settings", "network")))
        self.append(foot)

    # data ----------------------------------------------------------------------------
    def opened(self) -> None:
        self.refresh(rescan=True)
        if not self.speed_timer:
            self.speed_timer = GLib.timeout_add_seconds(1, self.tick)

    def closed(self) -> None:
        if self.speed_timer:
            GLib.source_remove(self.speed_timer)
            self.speed_timer = 0
        self.counters = None

    def rescan(self) -> None:
        self.status.set_text("Looking for networks…")
        background(lambda: ok("nmcli", "device", "wifi", "rescan", timeout=15),
                   lambda _r: GLib.timeout_add_seconds(3, lambda: (self.refresh(), False)[1]))

    @staticmethod
    def read() -> dict:
        if DEMO:
            return {"wifi": True, "airplane": False, "hotspot": False,
                    "active": {"name": "Home Wi-Fi", "device": "wlan0", "signal": 72, "state": "connected"},
                    "wired": {"device": "eth0", "state": "unavailable"},
                    "known": {"Home Wi-Fi"}, "profiles": {"Home Wi-Fi": "Home Wi-Fi"},
                    "networks": [{"ssid": "Home Wi-Fi", "signal": 72, "security": "WPA2", "inuse": True},
                                 {"ssid": "Cafe Guest", "signal": 54, "security": "", "inuse": False},
                                 {"ssid": "eduroam", "signal": 40, "security": "WPA2 802.1X", "inuse": False}]}
        data: dict = {"wifi": out("nmcli", "-t", "radio", "wifi") == "enabled"}
        rf = out("rfkill", "list")
        data["airplane"] = bool(rf) and "Soft blocked: no" not in rf
        devs = [nm_split(line) for line in out("nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device").splitlines()]
        data["active"], data["wired"], data["hotspot"] = {}, {}, False
        for d in devs:
            if len(d) < 4:
                continue
            dev, kind, state, conn = d[:4]
            if kind == "wifi" and state.startswith("connect") and conn:
                if conn.lower().startswith("hotspot"):
                    data["hotspot"] = True
                else:
                    data["active"] = {"name": conn, "device": dev, "state": state}
            elif kind == "ethernet" and not data["wired"]:
                data["wired"] = {"device": dev, "state": state, "name": conn}
        # Saved Wi-Fi networks by SSID -> profile name (they can differ: "Home 1").
        data["profiles"] = {}
        for f in (nm_split(l) for l in out("nmcli", "-t", "-f", "NAME,TYPE", "connection").splitlines()):
            if len(f) > 1 and "wireless" in f[1]:
                ssid = out("nmcli", "-g", "802-11-wireless.ssid", "connection", "show", "id", f[0]) or f[0]
                data["profiles"].setdefault(ssid, f[0])
        data["known"] = set(data["profiles"])
        nets: dict[str, dict] = {}
        for line in out("nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list", "--rescan", "no").splitlines():
            f = nm_split(line)
            if len(f) < 4 or not f[3]:
                continue
            n = {"inuse": f[0] == "*", "signal": int(f[1] or 0), "security": "" if f[2] in ("", "--") else f[2], "ssid": f[3]}
            if n["ssid"] not in nets or n["inuse"] or n["signal"] > nets[n["ssid"]]["signal"] and not nets[n["ssid"]]["inuse"]:
                nets[n["ssid"]] = n
        data["networks"] = sorted(nets.values(), key=lambda n: (not n["inuse"], -n["signal"]))
        if data["active"]:
            match = nets.get(data["active"]["name"]) or next((n for n in nets.values() if n["inuse"]), None)
            data["active"]["signal"] = match["signal"] if match else 0
        return data

    def refresh(self, rescan: bool = False) -> None:
        if getattr(self, "busy", False):  # the last refresh is still running
            return
        self.busy = True

        def done(data) -> None:
            self.busy = False
            self.apply(data)
            if rescan and data.get("wifi"):
                self.rescan()
        background(self.read, done)

    def apply(self, data: dict) -> None:
        set_chip(self.wifi_chip, data["wifi"])
        set_chip(self.plane_chip, data["airplane"])
        self.hotspot.set_css_classes(["pill", "active"] if data["hotspot"] else ["pill"])
        self.active, self.wired, self.known = data["active"], data["wired"], data["known"]
        self.profiles = data.get("profiles", {})
        self.networks = data["networks"]
        self.fill_connected()
        self.fill_available()
        if not data["wifi"]:
            self.status.set_text("Wi-Fi is off.")
        elif not self.networks:
            self.status.set_text("No networks found yet.")
        else:
            self.status.set_text("")

    def fill_connected(self) -> None:
        clear(self.connected)
        self.speed = None
        rows = 0
        if self.active:
            a = self.active
            state = "Connected" if a["state"] == "connected" else "Configuring interface…"
            self.connected.append(self.network_row(
                signal_icon(a.get("signal", 0)), a["name"], state,
                text_button("Disconnect", lambda n=a["name"]: self.disconnect(n), "network-offline-symbolic"),
                speed=True, current=True))
            rows += 1
        if self.wired and self.wired.get("state") == "connected":
            self.connected.append(self.network_row(
                "network-wired-symbolic", "Wired", "Connected", None, speed=not self.active, current=True))
            rows += 1
        if not rows:
            wired = self.wired.get("state", "")
            note = "Cable unplugged" if wired == "unavailable" else "Not connected"
            self.connected.append(label(note, "dim", margin_start=10))

    def network_row(self, icon: str, name: str, sub: str, button: Gtk.Widget | None,
                    speed: bool = False, current: bool = False) -> Gtk.Widget:
        row = Gtk.Box(spacing=10, css_classes=["netrow", *(["current"] if current else [])])
        row.append(Gtk.Image.new_from_icon_name(icon))
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True)
        text.append(label(name, "name", ellipsize=Pango.EllipsizeMode.END))
        text.append(label(sub, "dim", "small"))
        if speed:
            self.speed = label("↓ —   ↑ —", "speed", "small")
            text.append(self.speed)
        row.append(text)
        if button is not None:
            row.append(button)
        return row

    def fill_available(self) -> None:
        clear(self.available)
        query = self.search.get_text().strip().lower()
        shown = 0
        for n in self.networks:
            if n["inuse"] or (query and query not in n["ssid"].lower()):
                continue
            self.available.append(self.available_row(n))
            shown += 1
        self.available.set_visible(shown > 0)
        self.available_label.set_visible(shown > 0)

    def available_row(self, n: dict) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow(activatable=False, css_classes=["device"])
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        line = Gtk.Box(spacing=10)
        line.append(Gtk.Image.new_from_icon_name(signal_icon(n["signal"])))
        name = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True)
        name.append(label(n["ssid"], "name", ellipsize=Pango.EllipsizeMode.END))
        kind = "Saved" if n["ssid"] in self.known else ("Secured" if n["security"] else "Open")
        name.append(label(f"{kind} · {n['signal']}%", "dim", "small"))
        line.append(name)
        if n["security"]:
            line.append(Gtk.Image.new_from_icon_name("changes-prevent-symbolic"))
        password = Gtk.PasswordEntry(show_peek_icon=True, placeholder_text="Password", hexpand=True)
        reveal = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_DOWN)
        pw_line = Gtk.Box(spacing=8)
        pw_line.append(password)
        go = text_button("Join", lambda: self.connect(n, password.get_text()), None, "suggested")
        pw_line.append(go)
        password.connect("activate", lambda *_: self.connect(n, password.get_text()))
        reveal.set_child(pw_line)

        def clicked() -> None:
            if n["ssid"] in self.known or not n["security"]:
                self.connect(n, None)
            elif "802.1X" in n["security"]:
                self.panel.leave("anarch-wifi")  # school/work login: username and password
            else:
                reveal.set_reveal_child(not reveal.get_reveal_child())
                if reveal.get_reveal_child():
                    password.grab_focus()
        line.append(text_button("Connect", clicked, "network-transmit-receive-symbolic"))
        box.append(line)
        box.append(reveal)
        row.set_child(box)
        return row

    # actions -------------------------------------------------------------------------
    def connect(self, n: dict, password: str | None) -> None:
        ssid = n["ssid"]
        self.status.set_text(f"Connecting to {ssid}…")
        if ssid in self.known and password is None:
            cmd = ["nmcli", "connection", "up", "id", self.profiles.get(ssid, ssid)]
        else:
            cmd = ["nmcli", "device", "wifi", "connect", ssid]
            if password:
                cmd += ["password", password]

        def done(result) -> None:
            good, msg = result
            if good:
                self.status.set_text(f"Connected to {ssid}.")
            else:
                why = "Wrong password?" if "secrets" in msg.lower() or "password" in msg.lower() else msg.splitlines()[-1] if msg else ""
                self.status.set_text(f"Couldn't connect to {ssid}. {why}")
                if password and ssid not in self.known:  # don't keep a profile with a wrong password
                    background(lambda: ok("nmcli", "connection", "delete", "id", ssid))
            self.refresh()
        background(lambda: ok(*cmd, timeout=45), done)

    def disconnect(self, name: str) -> None:
        background(lambda: ok("nmcli", "connection", "down", "id", name), lambda _r: self.refresh())

    def set_wifi(self, on: bool) -> None:
        background(lambda: ok("nmcli", "radio", "wifi", "on" if on else "off"),
                   lambda _r: GLib.timeout_add(800, lambda: (self.refresh(rescan=on), False)[1]))

    def set_airplane(self, on: bool) -> None:
        def work():
            ok("rfkill", "block" if on else "unblock", "all")
            if not on:
                ok("nmcli", "radio", "wifi", "on")
        background(work, lambda _r: GLib.timeout_add(800, lambda: (self.refresh(), False)[1]))

    def toggle_hotspot(self) -> None:
        if "active" in self.hotspot.get_css_classes():
            background(lambda: ok("nmcli", "connection", "down", "id", "Hotspot"),
                       lambda _r: (self.hotspot_info.set_visible(False), self.refresh()))
            return
        name = f"an4rch-{socket.gethostname()}"[:32]
        pw = secrets.token_urlsafe(9)[:10]
        self.status.set_text("Starting the hotspot…")

        def done(result) -> None:
            good, msg = result
            if good:
                self.hotspot_info.set_text(f"Hotspot on: join “{name}” with password {pw}")
                self.hotspot_info.set_visible(True)
                self.status.set_text("")
            else:
                self.status.set_text("Couldn't start a hotspot: " + (msg.splitlines()[-1] if msg else "this Wi-Fi card may not support it."))
            self.refresh()
        background(lambda: ok("nmcli", "device", "wifi", "hotspot", "ssid", name, "password", pw, timeout=30), done)

    # speed ---------------------------------------------------------------------------
    def tick(self) -> bool:
        dev = self.active.get("device") or (self.wired.get("device") if self.wired.get("state") == "connected" else None)
        speed = getattr(self, "speed", None)
        if not dev or speed is None or DEMO:
            if speed is not None and DEMO:
                speed.set_text("↓ 1.2 MB/s   ↑ 84 KB/s")
            return True
        try:
            stats = Path(f"/sys/class/net/{dev}/statistics")
            rx = int((stats / "rx_bytes").read_text())
            tx = int((stats / "tx_bytes").read_text())
        except (OSError, ValueError):
            return True
        now = GLib.get_monotonic_time()
        if self.counters and self.counters[0] == dev:
            secs = max((now - self.counters[3]) / 1e6, 0.001)
            speed.set_text(f"↓ {human_rate((rx - self.counters[1]) / secs)}   ↑ {human_rate((tx - self.counters[2]) / secs)}")
        self.counters = (dev, rx, tx, now)
        return True


# --- Bluetooth -------------------------------------------------------------------------

class BluetoothPage(Gtk.Box):
    def __init__(self, panel: "Panels"):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.panel = panel
        self.scan: subprocess.Popen | None = None
        head = Gtk.Box(spacing=8)
        head.append(label("Bluetooth", "title", hexpand=True))
        self.power = Gtk.Switch(valign=Gtk.Align.CENTER)
        self.power_updating = False
        self.power.connect("notify::active", lambda s, _p: None if self.power_updating else self.set_power(s.get_active()))
        head.append(self.power)
        self.append(head)
        self.lists: dict[str, tuple[Gtk.Label, Gtk.ListBox]] = {}
        for key, title in (("connected", "Connected"), ("paired", "My devices"), ("new", "Devices nearby")):
            lab = label(title, "section")
            box = Gtk.ListBox(css_classes=["devices"], selection_mode=Gtk.SelectionMode.NONE)
            self.append(lab)
            self.append(box)
            self.lists[key] = (lab, box)
        self.status = label("", "dim", wrap=True)
        self.append(self.status)
        foot = Gtk.Box(spacing=8, homogeneous=True, margin_top=4)
        foot.append(text_button("More Bluetooth settings", lambda: self.panel.leave("anarch-bluetooth")))
        self.append(foot)
        self.timer = 0

    @staticmethod
    def read() -> dict:
        if DEMO:
            return {"adapter": True, "powered": True,
                    "devices": [{"mac": "AA", "name": "Headphones", "paired": True, "connected": True, "icon": "audio-headphones", "battery": "80"},
                                {"mac": "BB", "name": "Mouse", "paired": True, "connected": False, "icon": "input-mouse", "battery": ""},
                                {"mac": "CC", "name": "Speaker", "paired": False, "connected": False, "icon": "audio-card", "battery": ""}]}
        show = out("bluetoothctl", "show", timeout=4)
        if not show or "No default controller" in show:
            return {"adapter": False, "powered": False, "devices": []}
        data = {"adapter": True, "powered": "Powered: yes" in show, "devices": []}
        for line in out("bluetoothctl", "devices", timeout=4).splitlines():
            m = re.match(r"Device ([0-9A-F:]{17}) (.+)", line)
            if not m:
                continue
            info = out("bluetoothctl", "info", m.group(1), timeout=4)
            if "Name:" not in info and re.fullmatch(r"[0-9A-F-]{17}", m.group(2).strip()):
                continue  # nameless beacons
            batt = re.search(r"Battery Percentage: \S+ \((\d+)\)", info)
            icon = re.search(r"Icon: (\S+)", info)
            data["devices"].append({"mac": m.group(1), "name": m.group(2),
                                    "paired": "Paired: yes" in info, "connected": "Connected: yes" in info,
                                    "icon": icon.group(1) if icon else "bluetooth", "battery": batt.group(1) if batt else ""})
        return data

    def opened(self) -> None:
        self.refresh()
        if not DEMO and self.scan is None:
            try:  # look for new devices while the panel is open
                self.scan = subprocess.Popen(["bluetoothctl", "--timeout", "60", "scan", "on"],
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError:
                self.scan = None
        if not self.timer:
            self.timer = GLib.timeout_add_seconds(4, lambda: (self.refresh(), True)[1])

    def closed(self) -> None:
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = 0
        if self.scan is not None:
            self.scan.terminate()
            self.scan = None

    def refresh(self) -> None:
        if getattr(self, "busy", False):  # the last refresh is still running
            return
        self.busy = True

        def done(data) -> None:
            self.busy = False
            self.apply(data)
        background(self.read, done)

    def apply(self, data: dict) -> None:
        self.power_updating = True
        self.power.set_active(data["powered"])
        self.power.set_sensitive(data["adapter"])
        self.power_updating = False
        for key, (lab, box) in self.lists.items():
            clear(box)
            items = [d for d in data["devices"]
                     if (key == "connected" and d["connected"])
                     or (key == "paired" and d["paired"] and not d["connected"])
                     or (key == "new" and not d["paired"])]
            for d in items:
                box.append(self.row(d))
            lab.set_visible(bool(items) and data["powered"])
            box.set_visible(bool(items) and data["powered"])
        if not data["adapter"]:
            self.status.set_text("No Bluetooth adapter found. It may be switched off in the computer's settings (BIOS).")
        elif not data["powered"]:
            self.status.set_text("Bluetooth is off.")
        elif not data["devices"]:
            self.status.set_text("Looking for devices… Put yours in pairing mode.")
        else:
            self.status.set_text("")

    def row(self, d: dict) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow(activatable=False, css_classes=["device", *(["current"] if d["connected"] else [])])
        line = Gtk.Box(spacing=10)
        line.append(Gtk.Image.new_from_icon_name(f"{d['icon']}-symbolic" if not d["icon"].endswith("symbolic") else d["icon"]))
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True)
        text.append(label(d["name"], "name", ellipsize=Pango.EllipsizeMode.END))
        sub = "Connected" if d["connected"] else "Paired" if d["paired"] else "Not paired"
        if d["battery"]:
            sub += f" · battery {d['battery']}%"
        text.append(label(sub, "dim", "small"))
        line.append(text)
        if d["connected"]:
            line.append(text_button("Disconnect", lambda m=d["mac"]: self.act(["disconnect", m])))
        elif d["paired"]:
            line.append(icon_button("user-trash-symbolic", "Forget", lambda m=d["mac"]: self.act(["remove", m])))
            line.append(text_button("Connect", lambda m=d["mac"]: self.act(["connect", m])))
        else:
            line.append(text_button("Pair", lambda m=d["mac"], n=d["name"]: self.pair(m, n)))
        row.set_child(line)
        return row

    def act(self, args: list[str]) -> None:
        self.status.set_text("Working…")
        background(lambda: ok("bluetoothctl", *args, timeout=25),
                   lambda r: (self.status.set_text("" if r[0] else "That didn't work: " + (r[1].splitlines()[-1] if r[1] else "")),
                              self.refresh()))

    def pair(self, mac: str, name: str) -> None:
        self.status.set_text(f"Pairing with {name}…")

        def work():
            good, msg = ok("bluetoothctl", "pair", mac, timeout=40)
            if good:
                ok("bluetoothctl", "trust", mac)
                good, msg = ok("bluetoothctl", "connect", mac, timeout=25)
            return good, msg

        def done(result) -> None:
            good, _msg = result
            self.status.set_text(f"Connected to {name}." if good else
                                 f"Couldn't pair with {name}. If it asks for a code, use More Bluetooth settings.")
            self.refresh()
        background(work, done)

    def set_power(self, on: bool) -> None:
        def work():
            if on:
                ok("rfkill", "unblock", "bluetooth")
            return ok("bluetoothctl", "power", "on" if on else "off")
        background(work, lambda _r: self.refresh())


# --- Power -----------------------------------------------------------------------------

class PowerPage(Gtk.Box):
    MODES = (("power-saver", "Power saver", "power-profile-power-saver-symbolic"),
             ("balanced", "Balanced", "power-profile-balanced-symbolic"),
             ("performance", "Performance", "power-profile-performance-symbolic"))

    def __init__(self, panel: "Panels"):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.panel = panel
        head = Gtk.Box(spacing=10)
        self.batt_icon = Gtk.Image.new_from_icon_name("battery-good-symbolic")
        self.batt_icon.set_pixel_size(24)
        head.append(self.batt_icon)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True)
        self.batt_title = label("Power", "title")
        self.batt_sub = label("", "dim", "small")
        text.append(self.batt_title)
        text.append(self.batt_sub)
        head.append(text)
        self.append(head)

        self.mode_label = label("Power mode", "section")
        self.append(self.mode_label)
        self.modes = Gtk.Box(spacing=6, homogeneous=True)
        self.mode_buttons: dict[str, Gtk.Button] = {}
        for key, name, icon in self.MODES:
            b = Gtk.Button(css_classes=["mode"], tooltip_text=name)
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            inner.append(Gtk.Image.new_from_icon_name(icon))
            inner.append(label(name, "small", xalign=0.5))
            b.set_child(inner)
            b.connect("clicked", lambda _b, k=key: self.set_mode(k))
            self.modes.append(b)
            self.mode_buttons[key] = b
        self.append(self.modes)

        self.bright_label = label("Brightness", "section")
        self.append(self.bright_label)
        self.bright = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 5, 100, 1)
        self.bright.set_draw_value(False)
        self.bright_updating = False
        self.bright.connect("value-changed", self.on_bright)
        self.append(self.bright)

        self.append(label("Session", "section"))
        grid = Gtk.Box(spacing=6, homogeneous=True)
        self.actions: dict[str, Gtk.Button] = {}
        for key, name, icon in (("lock", "Lock", "system-lock-screen-symbolic"),
                                ("suspend", "Sleep", "weather-clear-night-symbolic"),
                                ("logout", "Log out", "system-log-out-symbolic"),
                                ("reboot", "Restart", "system-reboot-symbolic"),
                                ("poweroff", "Shut down", "system-shutdown-symbolic")):
            b = Gtk.Button(css_classes=["action", *(["danger"] if key == "poweroff" else [])], tooltip_text=name)
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            inner.append(Gtk.Image.new_from_icon_name(icon))
            inner.append(label(name, "small", xalign=0.5))
            b.set_child(inner)
            b.label = inner.get_last_child()  # type: ignore[attr-defined]
            b.name = name  # type: ignore[attr-defined]
            b.connect("clicked", lambda _b, k=key: self.action(k))
            grid.append(b)
            self.actions[key] = b
        self.append(grid)
        self.armed: str | None = None

    @staticmethod
    def read() -> dict:
        if DEMO:
            return {"battery": 73, "status": "Discharging", "time": "2 h 10 min", "mode": "balanced", "brightness": 60}
        data: dict = {"battery": None, "status": "", "time": "", "mode": "", "brightness": None}
        for bat in sorted(Path("/sys/class/power_supply").glob("BAT*")):
            try:
                data["battery"] = int((bat / "capacity").read_text())
                data["status"] = (bat / "status").read_text().strip()
            except (OSError, ValueError):
                continue
            break
        if data["battery"] is not None:
            dev = next((l for l in out("upower", "-e").splitlines() if "BAT" in l), "")
            m = re.search(r"time to (?:empty|full):\s+([\d.,]+) (\w+)", out("upower", "-i", dev)) if dev else None
            if m:
                data["time"] = f"{m.group(1).replace(',', '.')} {m.group(2)}"
        data["mode"] = out("powerprofilesctl", "get")
        b = out("brightnessctl", "-m")
        m = re.search(r",(\d+)%,", b)
        data["brightness"] = int(m.group(1)) if m else None
        return data

    def opened(self) -> None:
        self.disarm()
        background(self.read, self.apply)

    def closed(self) -> None:
        self.disarm()

    def apply(self, d: dict) -> None:
        if d["battery"] is None:
            self.batt_icon.set_from_icon_name("ac-adapter-symbolic")
            self.batt_title.set_text("Power")
            self.batt_sub.set_text("Plugged in · no battery")
        else:
            level = d["battery"]
            charging = d["status"] in ("Charging", "Full")
            name = "full" if level > 90 else "good" if level > 50 else "low" if level > 20 else "caution"
            self.batt_icon.set_from_icon_name(f"battery-{name}{'-charging' if charging else ''}-symbolic")
            self.batt_title.set_text(f"Battery {level}%")
            when = f" · {d['time']} {'until full' if charging else 'left'}" if d["time"] else ""
            self.batt_sub.set_text(("Charging" if d["status"] == "Charging" else "Fully charged" if d["status"] == "Full"
                                    else "On battery") + when)
        self.mode_label.set_visible(bool(d["mode"]))
        self.modes.set_visible(bool(d["mode"]))
        for key, b in self.mode_buttons.items():
            b.set_css_classes(["mode", "current"] if key == d["mode"] else ["mode"])
        has_bright = d["brightness"] is not None
        self.bright_label.set_visible(has_bright)
        self.bright.set_visible(has_bright)
        if has_bright:
            self.bright_updating = True
            self.bright.set_value(d["brightness"])
            self.bright_updating = False

    def set_mode(self, key: str) -> None:
        background(lambda: ok("powerprofilesctl", "set", key), lambda _r: background(self.read, self.apply))

    def on_bright(self, scale: Gtk.Scale) -> None:
        if not self.bright_updating:
            spawn("brightnessctl", "-q", "set", f"{int(scale.get_value())}%")

    def disarm(self) -> None:
        if self.armed:
            b = self.actions[self.armed]
            b.label.set_text(b.name)  # type: ignore[attr-defined]
            b.remove_css_class("armed")
        self.armed = None

    def action(self, key: str) -> None:
        # Restart and shut down ask for a second click, so a slip doesn't lose work.
        if key in ("reboot", "poweroff", "logout") and self.armed != key:
            self.disarm()
            self.armed = key
            b = self.actions[key]
            b.label.set_text("Sure?")  # type: ignore[attr-defined]
            b.add_css_class("armed")
            GLib.timeout_add_seconds(4, lambda: (self.disarm() if self.armed == key else None, False)[1])
            return
        self.disarm()
        self.panel.close_panel()
        if DEMO:
            return
        if key == "lock":
            spawn("loginctl", "lock-session")
        elif key == "suspend":
            spawn("systemctl", "suspend")
        elif key == "logout":
            lumen("anarch-session", "logout")
        elif key == "reboot":
            spawn("systemctl", "reboot")
        elif key == "poweroff":
            spawn("systemctl", "poweroff")


# --- the window ------------------------------------------------------------------------

class Panels(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application):
        super().__init__(application=app, title="Quick settings")
        self.set_decorated(False)
        self.add_css_class("anarch-audio")  # shares the sound panel's styling
        self.add_css_class("quick-panels")
        display = Gdk.Display.get_default()
        self.providers = []
        for prio in range(3):
            p = Gtk.CssProvider()
            Gtk.StyleContext.add_provider_for_display(display, p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + prio)
            self.providers.append(p)

        if LayerShell is not None and LayerShell.is_supported():
            LayerShell.init_for_window(self)
            LayerShell.set_namespace(self, "anarch-panel")
            LayerShell.set_layer(self, LayerShell.Layer.OVERLAY)
            for edge in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM, LayerShell.Edge.LEFT, LayerShell.Edge.RIGHT):
                LayerShell.set_anchor(self, edge, True)
            LayerShell.set_exclusive_zone(self, 0)  # below the top bar, over everything else
            LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.EXCLUSIVE)
        else:
            self.set_default_size(420, 520)

        overlay = Gtk.Overlay()
        backdrop = Gtk.Box(css_classes=["backdrop"], hexpand=True, vexpand=True)
        click = Gtk.GestureClick()
        click.connect("released", lambda *_: self.close_panel())
        backdrop.add_controller(click)
        overlay.set_child(backdrop)
        self.panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, css_classes=["panel"],
                             halign=Gtk.Align.END, valign=Gtk.Align.START)
        self.panel.set_size_request(440, -1)
        self.panel.add_controller(Gtk.GestureClick())  # clicks inside don't reach the backdrop
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, vhomogeneous=False,
                               interpolate_size=True)
        self.pages = {"network": NetworkPage(self), "bluetooth": BluetoothPage(self), "power": PowerPage(self)}
        for name, page in self.pages.items():
            self.stack.add_named(page, name)
        self.panel.append(self.stack)
        overlay.add_overlay(self.panel)
        self.set_child(overlay)
        self.current: str | None = None

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", lambda _c, kv, *_: (self.close_panel(), True)[1] if kv == Gdk.KEY_Escape else False)
        self.add_controller(keys)

    def load_css(self) -> None:
        for p, path in zip(self.providers, (THEME_CSS, BASE_CSS, STYLE_CSS)):
            if path.exists():
                p.load_from_path(str(path))

    def open_panel(self, page: str) -> None:
        self.load_css()
        if self.current and self.current != page:
            self.pages[self.current].closed()
        self.current = page
        self.stack.set_visible_child_name(page)
        self.pages[page].opened()
        self.present()

    def close_panel(self) -> None:
        if self.current:
            self.pages[self.current].closed()
        self.current = None
        self.set_visible(False)

    def toggle(self, page: str) -> None:
        if self.get_visible() and self.current == page:
            self.close_panel()
        else:
            self.open_panel(page)

    def leave(self, *argv: str) -> None:
        """Close the panel and open a an4rch tool (settings, full menus)."""
        self.close_panel()
        lumen(*argv)


class PanelsApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.window: Panels | None = None
        for page in PAGES:
            action = Gio.SimpleAction.new(page, None)
            action.connect("activate", lambda _a, _p, pg=page: self.win().toggle(pg))
            self.add_action(action)
        hide = Gio.SimpleAction.new("hide", None)
        hide.connect("activate", lambda *_: self.win().close_panel())
        self.add_action(hide)

    def win(self) -> Panels:
        if self.window is None:
            self.window = Panels(self)
        return self.window

    def do_startup(self):
        Gtk.Application.do_startup(self)
        self.hold()  # stay alive while hidden, so the next open is instant

    def do_command_line(self, command_line):
        args = command_line.get_arguments()[1:]
        if "--daemon" in args:
            self.win()
        elif "--quit" in args:
            self.quit()
        else:
            page = next((a for a in args if a in PAGES), "network")
            if "--show" in args:
                self.win().open_panel(page)
            else:
                self.win().toggle(page)
        return 0


if __name__ == "__main__":
    sys.exit(PanelsApp().run(sys.argv))
