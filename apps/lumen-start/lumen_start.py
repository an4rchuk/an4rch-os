#!/usr/bin/env python3
"""an4rch Start — the app menu that opens when you tap the Windows (Super) key.

Runs as a small background service so it appears instantly: `lumen-start`
toggles it over D-Bus. Pinned apps, recently used apps, all apps A–Z, and a
search that also finds settings, does maths and searches the web.
"""

from __future__ import annotations

import ast
import json
import math
import operator
import os
import shlex
import subprocess
import sys
import time
import unicodedata
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

try:  # Layer shell turns the window into a proper overlay on Wayland.
    gi.require_version("Gtk4LayerShell", "1.0")
    from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402
except (ValueError, ImportError):
    LayerShell = None

APP_ID = "org.lumen.Start"
HOME = Path.home()
LUMEN_PATH = Path(os.environ.get("LUMEN_PATH", HOME / ".local/share/lumen"))
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "lumen"
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "lumen"
PINS_FILE = CONFIG / "start-pins.json"
RECENT_FILE = STATE / "start-recent.json"
THEME_CSS = CONFIG / "current/theme/apps.css"
STYLE_CSS = Path(__file__).with_name("style.css")

DEFAULT_PINS = [
    # The first installed match of each group is pinned on first run.
    ["firefox.desktop", "chromium.desktop", "brave-browser.desktop", "zen.desktop"],
    ["org.gnome.Nautilus.desktop", "thunar.desktop"],
    ["com.mitchellh.ghostty.desktop", "Alacritty.desktop", "kitty.desktop"],
    ["code-oss.desktop", "code.desktop", "dev.zed.Zed.desktop"],
    ["lumen-store.desktop"],
    ["lumen-settings.desktop"],
    ["steam.desktop"],
    ["spotify.desktop", "com.spotify.Client.desktop"],
    ["org.gnome.Loupe.desktop"],
    ["mpv.desktop"],
    ["org.gnome.Calculator.desktop"],
    ["btop.desktop"],
]

# Settings and actions reachable from search: (title, keywords, icon, command).
ACTIONS = [
    ("Settings", "settings preferences control panel customise customize options", "emblem-system-symbolic", ["lumen-settings"]),
    ("Windows and effects", "gaps rounding corners border blur shadows animations transparency opacity", "preferences-system-windows-symbolic", ["lumen-settings", "windows"]),
    ("Mouse and touchpad", "mouse touchpad pointer speed tap click scroll natural", "input-mouse-symbolic", ["lumen-settings", "input"]),
    ("Default apps", "default browser terminal editor files apps", "applications-other-symbolic", ["lumen-settings", "apps"]),
    ("About this computer", "about system info memory processor graphics storage version", "computer-symbolic", ["lumen-settings", "system"]),
    ("Wi-Fi", "wifi wireless network internet", "network-wireless-symbolic", ["lumen-wifi"]),
    ("Bluetooth", "bluetooth headphones pair", "bluetooth-symbolic", ["lumen-bluetooth"]),
    ("Sound", "audio volume speaker microphone output", "audio-volume-high-symbolic", ["lumen-audio"]),
    ("Displays", "display monitor screen resolution scale", "video-display-symbolic", ["lumen-display"]),
    ("Theme", "theme colours colors appearance dark light", "applications-graphics-symbolic", ["lumen-theme"]),
    ("Wallpaper", "wallpaper background", "image-x-generic-symbolic", ["lumen-wallpaper", "pick"]),
    ("Power profile", "power battery performance saver", "battery-good-symbolic", ["lumen-power-profile"]),
    ("Keyboard layout", "keyboard layout language input", "input-keyboard-symbolic", ["lumen-setup", "keyboard"]),
    ("Time zone", "time zone clock date", "preferences-system-time-symbolic", ["lumen-setup", "timezone"]),
    ("Update system", "update upgrade software", "software-update-available-symbolic", ["lumen-update"]),
    ("App Store", "store install apps software games", "system-software-install-symbolic", ["lumen-store"]),
    ("System snapshots", "snapshot backup restore rollback undo", "document-revert-symbolic", ["lumen-snapshot", "menu"]),
    ("Gaming setup", "games steam gaming controller", "input-gaming-symbolic", ["lumen-gaming"]),
    ("Extras", "extras sunshine stream moonlight decky rgb openrgb lact gpu waydroid android distrobox virtual machine vm tailscale handheld controller", "list-add-symbolic", ["lumen-extras"]),
    ("Performance tuning", "performance tune cpu scheduler sched-ext kernel zen mirrors speed", "power-profile-performance-symbolic", ["lumen-tune"]),
    ("Development environment", "development dev programming node python go rust ruby java docker postgres mysql redis database mise", "applications-engineering-symbolic", ["lumen-dev"]),
    ("Key bindings", "keys shortcuts keyboard help", "preferences-desktop-keyboard-shortcuts-symbolic", ["lumen-keys"]),
    ("an4rch manual", "help manual docs guide", "help-browser-symbolic", ["lumen-manual"]),
    ("Taskbar", "taskbar bottom bar dock windows panel", "view-app-grid-symbolic", ["lumen-taskbar", "toggle"]),
    ("Window title bars", "title bars window buttons close minimise minimize maximise maximize decorations", "window-new-symbolic", ["lumen-titlebars", "toggle"]),
    ("Night light", "night light warm blue", "weather-clear-night-symbolic", ["lumen-toggle", "nightlight"]),
    ("Do Not Disturb", "notifications dnd quiet", "notifications-disabled-symbolic", ["lumen-toggle", "dnd"]),
    ("Lock screen", "lock", "system-lock-screen-symbolic", ["loginctl", "lock-session"]),
    ("Log out", "logout sign out exit", "system-log-out-symbolic", ["lumen-session", "logout"]),
    ("Restart", "restart reboot", "system-reboot-symbolic", ["systemctl", "reboot"]),
    ("Shut down", "shutdown power off", "system-shutdown-symbolic", ["systemctl", "poweroff"]),
    ("Suspend", "sleep suspend", "weather-clear-night-symbolic", ["systemctl", "suspend"]),
]


# --- helpers ------------------------------------------------------------------

def fold(text: str) -> str:
    """Lower-case and strip accents so 'cafe' finds 'Café'."""
    return "".join(c for c in unicodedata.normalize("NFKD", text.lower()) if not unicodedata.combining(c))


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=1))
    tmp.replace(path)


_OPS = {
    ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul, ast.Div: operator.truediv,
    ast.Pow: operator.pow, ast.Mod: operator.mod, ast.FloorDiv: operator.floordiv,
    ast.USub: operator.neg, ast.UAdd: operator.pos,
}
_NAMES = {k: getattr(math, k) for k in ("pi", "e", "tau", "sqrt", "sin", "cos", "tan", "log", "log10", "log2", "exp", "floor", "ceil")}
_NAMES["abs"] = abs
_NAMES["round"] = round


def calculate(expr: str):
    """Safely evaluate simple arithmetic; returns None when it isn't maths."""
    expr = expr.strip().replace("^", "**").replace("×", "*").replace("÷", "/")
    if not any(c.isdigit() for c in expr) or not any(c in "+-*/%(" for c in expr):
        return None
    try:
        tree = ast.parse(expr, mode="eval")
    except SyntaxError:
        return None

    def ev(node):
        if isinstance(node, ast.Expression):
            return ev(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return node.value
        if isinstance(node, ast.BinOp) and type(node.op) in _OPS:
            left, right = ev(node.left), ev(node.right)
            if isinstance(node.op, ast.Pow) and abs(right) > 1000:
                raise ValueError("too big")
            return _OPS[type(node.op)](left, right)
        if isinstance(node, ast.UnaryOp) and type(node.op) in _OPS:
            return _OPS[type(node.op)](ev(node.operand))
        if isinstance(node, ast.Name) and node.id in _NAMES:
            return _NAMES[node.id]
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in _NAMES:
            return _NAMES[node.func.id](*[ev(a) for a in node.args])
        raise ValueError("unsupported")

    try:
        value = ev(tree)
    except Exception:  # noqa: BLE001 - anything odd simply isn't a calculation
        return None
    if isinstance(value, float):
        if value.is_integer() and abs(value) < 1e15:
            return str(int(value))
        return f"{value:.10g}"
    return str(value)


def ago(ts: float) -> str:
    delta = time.time() - ts
    if delta < 90:
        return "Just now"
    if delta < 3600:
        return f"{int(delta // 60)} minutes ago"
    if delta < 86400:
        hours = int(delta // 3600)
        return "1 hour ago" if hours == 1 else f"{hours} hours ago"
    days = int(delta // 86400)
    return "Yesterday" if days == 1 else f"{days} days ago"


def session_managed() -> bool:
    try:
        return subprocess.run(["systemctl", "--user", "is-active", "-q", "graphical-session.target"],
                              timeout=2).returncode == 0 and bool(GLib.find_program_in_path("systemd-run"))
    except (OSError, subprocess.SubprocessError):
        return False


def run_detached(argv: list[str], env: dict | None = None) -> None:
    tool = LUMEN_PATH / "bin" / argv[0]
    if tool.exists():
        argv = [str(tool), *argv[1:]]
    try:
        subprocess.Popen(argv, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         env=env)
    except OSError as err:
        print(f"lumen-start: cannot run {argv}: {err}", file=sys.stderr)


# --- app model ----------------------------------------------------------------

class App:
    __slots__ = ("info", "id", "name", "haystack", "generic")

    def __init__(self, info: Gio.DesktopAppInfo):
        self.info = info
        self.id = info.get_id() or ""
        self.name = info.get_display_name() or info.get_name() or self.id
        self.generic = info.get_generic_name() or ""
        extra = " ".join(filter(None, [
            self.generic, info.get_description() or "",
            " ".join(info.get_keywords() or []), info.get_categories() or "", info.get_executable() or "",
        ]))
        self.haystack = fold(extra)

    def score(self, query: str) -> int:
        name = fold(self.name)
        if name == query:
            return 100
        if name.startswith(query):
            return 90
        if any(word.startswith(query) for word in name.replace("-", " ").split()):
            return 75
        if query in name:
            return 60
        # Initials: "vsc" → "Visual Studio Code".
        initials = "".join(w[0] for w in name.replace("-", " ").split() if w)
        if initials.startswith(query):
            return 55
        if query in self.haystack:
            return 30
        return 0


def load_apps() -> list[App]:
    apps = []
    for info in Gio.AppInfo.get_all():
        if not isinstance(info, Gio.DesktopAppInfo) or not info.should_show():
            continue
        apps.append(App(info))
    apps.sort(key=lambda a: fold(a.name))
    return apps


# --- widgets ------------------------------------------------------------------

def icon_image(gicon, size: int) -> Gtk.Image:
    image = Gtk.Image.new_from_gicon(gicon) if gicon else Gtk.Image.new_from_icon_name("application-x-executable")
    image.set_pixel_size(size)
    return image


class Tile(Gtk.Button):
    """A pinned app: big icon above its name."""

    def __init__(self, menu: "StartMenu", app: App):
        super().__init__(css_classes=["tile", "flat"])
        self.app = app
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.append(icon_image(app.info.get_icon(), 40))
        label = Gtk.Label(label=app.name, ellipsize=3, max_width_chars=11, justify=Gtk.Justification.CENTER)
        label.add_css_class("tile-label")
        box.append(label)
        self.set_child(box)
        self.set_tooltip_text(app.info.get_description() or app.name)
        self.connect("clicked", lambda *_: menu.launch(app))
        menu.attach_context_menu(self, app)


class Row(Gtk.ListBoxRow):
    """A list entry: icon, title, optional subtitle, and what Enter does."""

    def __init__(self, title: str, subtitle: str = "", gicon=None, icon_name: str = "", activate=None, app: App | None = None):
        super().__init__(css_classes=["result"])
        self.activate_cb = activate
        self.app = app
        box = Gtk.Box(spacing=12, halign=Gtk.Align.FILL)
        if gicon is not None:
            box.append(icon_image(gicon, 32))
        else:
            img = Gtk.Image.new_from_icon_name(icon_name or "application-x-executable")
            img.set_pixel_size(22)
            img.add_css_class("action-icon")
            holder = Gtk.Box(css_classes=["action-icon-box"], halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
            holder.set_size_request(32, 32)
            img.set_halign(Gtk.Align.CENTER)
            img.set_valign(Gtk.Align.CENTER)
            img.set_hexpand(True)
            holder.set_hexpand(False)
            holder.append(img)
            box.append(holder)
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
        t = Gtk.Label(label=title, xalign=0, ellipsize=3, css_classes=["result-title"])
        texts.append(t)
        if subtitle:
            texts.append(Gtk.Label(label=subtitle, xalign=0, ellipsize=3, css_classes=["result-subtitle"]))
        box.append(texts)
        self.set_child(box)


class StartMenu(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application):
        super().__init__(application=app, title="an4rch Start")
        self.set_decorated(False)
        self.add_css_class("lumen-start")
        self.apps: list[App] = []
        self.apps_dirty = True
        self.uwsm = session_managed()

        self.css = Gtk.CssProvider()
        self.theme_css = Gtk.CssProvider()
        display = Gdk.Display.get_default()
        Gtk.StyleContext.add_provider_for_display(display, self.theme_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        Gtk.StyleContext.add_provider_for_display(display, self.css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        self.load_css()

        if LayerShell is not None and LayerShell.is_supported():
            LayerShell.init_for_window(self)
            LayerShell.set_namespace(self, "lumen-start")
            LayerShell.set_layer(self, LayerShell.Layer.OVERLAY)
            for edge in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM, LayerShell.Edge.LEFT, LayerShell.Edge.RIGHT):
                LayerShell.set_anchor(self, edge, True)
            LayerShell.set_exclusive_zone(self, 0)  # sit below the bar, cover the rest
            LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.EXCLUSIVE)
        else:
            self.set_default_size(1280, 800)

        # Full-screen transparent backdrop: clicking outside the panel closes it.
        overlay = Gtk.Overlay()
        backdrop = Gtk.Box(css_classes=["backdrop"], hexpand=True, vexpand=True)
        click = Gtk.GestureClick()
        click.connect("released", lambda *_: self.close_menu())
        backdrop.add_controller(click)
        overlay.set_child(backdrop)

        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, css_classes=["panel"],
                        halign=Gtk.Align.CENTER, valign=Gtk.Align.START)
        panel.set_size_request(660, 0)
        panel.add_controller(Gtk.GestureClick())  # swallow clicks so they don't reach the backdrop
        overlay.add_overlay(panel)
        self.set_child(overlay)

        # Search.
        self.search = Gtk.SearchEntry(placeholder_text="Search apps, settings and the web", css_classes=["search"])
        self.search.connect("search-changed", self.on_search)
        self.search.connect("activate", self.on_enter)
        self.search.connect("stop-search", lambda *_: self.on_escape())
        panel.append(self.search)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120, vhomogeneous=False)
        self.stack.set_size_request(-1, 520)
        panel.append(self.stack)

        # Home page: pinned grid + recent list.
        home = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        head = Gtk.Box(css_classes=["section-head"])
        head.append(Gtk.Label(label="Pinned", xalign=0, hexpand=True, css_classes=["section-title"]))
        all_btn = Gtk.Button(css_classes=["pill"])
        all_btn.set_child(Gtk.Label(label="All apps  ›"))
        all_btn.connect("clicked", lambda *_: self.show_page("all"))
        head.append(all_btn)
        home.append(head)
        self.pinned = Gtk.FlowBox(max_children_per_line=6, min_children_per_line=6, selection_mode=Gtk.SelectionMode.NONE,
                                  homogeneous=True, row_spacing=4, column_spacing=4, css_classes=["pinned"])
        home.append(self.pinned)
        home.append(Gtk.Label(label="Recent", xalign=0, css_classes=["section-title", "recent-title"]))
        self.recent = Gtk.ListBox(css_classes=["results"], selection_mode=Gtk.SelectionMode.NONE)
        self.recent.connect("row-activated", lambda _l, row: row.activate_cb and row.activate_cb())
        home.append(self.recent)
        self.stack.add_named(home, "home")

        # All apps.
        all_page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        head = Gtk.Box(css_classes=["section-head"])
        head.append(Gtk.Label(label="All apps", xalign=0, hexpand=True, css_classes=["section-title"]))
        back = Gtk.Button(css_classes=["pill"])
        back.set_child(Gtk.Label(label="‹  Back"))
        back.connect("clicked", lambda *_: self.show_page("home"))
        head.append(back)
        all_page.append(head)
        self.all_list = Gtk.ListBox(css_classes=["results"], selection_mode=Gtk.SelectionMode.BROWSE)
        self.all_list.set_header_func(self.letter_header)
        self.all_list.connect("row-activated", lambda _l, row: row.activate_cb and row.activate_cb())
        scroll = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER, child=self.all_list)
        all_page.append(scroll)
        self.stack.add_named(all_page, "all")

        # Search results.
        self.results = Gtk.ListBox(css_classes=["results"], selection_mode=Gtk.SelectionMode.BROWSE)
        self.results.connect("row-activated", lambda _l, row: row.activate_cb and row.activate_cb())
        self.stack.add_named(Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER, child=self.results), "search")

        panel.append(self.build_footer())

        keys = Gtk.EventControllerKey()
        keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        keys.connect("key-pressed", self.on_key)
        self.add_controller(keys)

        monitor = Gio.AppInfoMonitor.get()
        monitor.connect("changed", lambda *_: setattr(self, "apps_dirty", True))

    # --- building ------------------------------------------------------------

    def build_footer(self) -> Gtk.Widget:
        footer = Gtk.Box(css_classes=["footer"], spacing=6)
        user = Gtk.Box(spacing=10, hexpand=True, valign=Gtk.Align.CENTER)
        face = HOME / ".face"
        name = GLib.get_real_name()
        if not name or name == "Unknown":
            name = GLib.get_user_name()
        if face.exists():
            avatar = Gtk.Image.new_from_file(str(face))
            avatar.set_pixel_size(32)
            avatar.add_css_class("avatar-image")
        else:
            avatar = Gtk.Label(label=name[:1].upper(), css_classes=["avatar"])
            avatar.set_size_request(32, 32)
        user.append(avatar)
        user.append(Gtk.Label(label=name, css_classes=["user-name"]))
        footer.append(user)

        def tool(icon, tip, argv):
            b = Gtk.Button(icon_name=icon, tooltip_text=tip, css_classes=["footer-button", "flat"])
            b.connect("clicked", lambda *_: (self.close_menu(), run_detached(argv)))
            footer.append(b)

        tool("system-software-install-symbolic", "App Store", ["lumen-store"])
        tool("folder-symbolic", "Files", ["lumen-launch", "files"])
        tool("emblem-system-symbolic", "Settings", ["lumen-settings"])

        power = Gtk.MenuButton(icon_name="system-shutdown-symbolic", tooltip_text="Power", css_classes=["footer-button", "flat", "power"])
        pop = Gtk.Popover(css_classes=["power-popover"])
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        for label, icon, argv in [
            ("Lock", "system-lock-screen-symbolic", ["loginctl", "lock-session"]),
            ("Suspend", "weather-clear-night-symbolic", ["systemctl", "suspend"]),
            ("Log out", "system-log-out-symbolic", ["lumen-session", "logout"]),
            ("Restart", "system-reboot-symbolic", ["systemctl", "reboot"]),
            ("Shut down", "system-shutdown-symbolic", ["systemctl", "poweroff"]),
        ]:
            b = Gtk.Button(css_classes=["flat", "power-item"])
            row = Gtk.Box(spacing=10)
            row.append(Gtk.Image.new_from_icon_name(icon))
            row.append(Gtk.Label(label=label, xalign=0))
            b.set_child(row)
            b.connect("clicked", lambda _b, a=argv: (pop.popdown(), self.close_menu(), run_detached(a)))
            box.append(b)
        pop.set_child(box)
        power.set_popover(pop)
        footer.append(power)
        return footer

    def letter_header(self, row: Gtk.ListBoxRow, before: Gtk.ListBoxRow | None):
        letter = lambda r: (fold(r.app.name)[:1] or "#").upper() if r and r.app else ""  # noqa: E731
        current = letter(row)
        if not current.isalpha():
            current = "#"
        prev = letter(before) if before else None
        if prev is not None and not prev.isalpha():
            prev = "#"
        if current != prev:
            row.set_header(Gtk.Label(label=current, xalign=0, css_classes=["letter"]))
        else:
            row.set_header(None)

    def refresh(self) -> None:
        if self.apps_dirty:
            self.apps = load_apps()
            self.apps_dirty = False
            self.fill_all()
        self.fill_pinned()
        self.fill_recent()

    def by_id(self) -> dict[str, App]:
        return {a.id: a for a in self.apps}

    def pins(self) -> list[str]:
        pins = load_json(PINS_FILE, None)
        if pins is None:
            index = self.by_id()
            pins = [next((c for c in group if c in index), None) for group in DEFAULT_PINS]
            pins = [p for p in pins if p]
            save_json(PINS_FILE, pins)
        return pins

    def fill_pinned(self) -> None:
        while (child := self.pinned.get_first_child()) is not None:
            self.pinned.remove(child)
        index = self.by_id()
        for pid in self.pins():
            if pid in index:
                self.pinned.append(Tile(self, index[pid]))

    def fill_recent(self) -> None:
        while (row := self.recent.get_first_child()) is not None:
            self.recent.remove(row)
        index = self.by_id()
        recent = sorted(load_json(RECENT_FILE, {}).items(), key=lambda kv: -kv[1]["last"])
        shown = 0
        for app_id, data in recent:
            if app_id in index and shown < 4:
                app = index[app_id]
                self.recent.append(Row(app.name, ago(data["last"]), gicon=app.info.get_icon(),
                                       activate=lambda a=app: self.launch(a), app=app))
                shown += 1
        if shown == 0:
            self.recent.append(Row("Apps you open show up here", "Tap Super and start typing to find anything",
                                   icon_name="starred-symbolic"))

    def fill_all(self) -> None:
        while (row := self.all_list.get_first_child()) is not None:
            self.all_list.remove(row)
        for app in self.apps:
            row = Row(app.name, app.generic, gicon=app.info.get_icon(), activate=lambda a=app: self.launch(a), app=app)
            self.attach_context_menu(row, app)
            self.all_list.append(row)

    # --- behaviour -------------------------------------------------------------

    def attach_context_menu(self, widget: Gtk.Widget, app: App) -> None:
        def on_right_click(gesture, _n, x, y):
            pinned = app.id in self.pins()
            pop = Gtk.Popover(has_arrow=False, css_classes=["power-popover"])
            pop.set_parent(widget)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)

            def item(label, cb):
                b = Gtk.Button(label=label, css_classes=["flat", "power-item"])
                b.connect("clicked", lambda *_: (pop.popdown(), cb()))
                box.append(b)

            item("Unpin from Start" if pinned else "Pin to Start", lambda: self.toggle_pin(app))
            item("Open", lambda: self.launch(app))
            item("Uninstall…", lambda: (self.close_menu(), run_detached(["lumen-store", "--uninstall", app.id])))
            pop.set_child(box)
            rect = Gdk.Rectangle()
            rect.x, rect.y, rect.width, rect.height = int(x), int(y), 1, 1
            pop.set_pointing_to(rect)
            pop.connect("closed", lambda p: GLib.idle_add(p.unparent))
            pop.popup()

        gesture = Gtk.GestureClick(button=3)
        gesture.connect("pressed", on_right_click)
        widget.add_controller(gesture)

    def toggle_pin(self, app: App) -> None:
        pins = self.pins()
        if app.id in pins:
            pins.remove(app.id)
        else:
            pins.append(app.id)
        save_json(PINS_FILE, pins[:18])
        self.fill_pinned()

    def launch(self, app: App) -> None:
        self.close_menu()
        recent = load_json(RECENT_FILE, {})
        entry = recent.get(app.id, {"count": 0})
        entry["count"] = entry.get("count", 0) + 1
        entry["last"] = time.time()
        recent[app.id] = entry
        # Keep the file small.
        recent = dict(sorted(recent.items(), key=lambda kv: -kv[1]["last"])[:40])
        save_json(RECENT_FILE, recent)
        if self.uwsm:
            # The app's own scope, like `uwsm app`, but without starting
            # Python each time: gio and systemd-run are quick.
            # Through lumen-launch, which reports an app that can't start
            # instead of failing silently.
            path = app.info.get_filename() or app.id
            run_detached(["lumen-launch", "--", "gio", "launch", path],
                         env={**os.environ, "LUMEN_LAUNCH_NAME": app.info.get_display_name() or app.id})
        else:
            ctx = Gdk.Display.get_default().get_app_launch_context()
            try:
                app.info.launch([], ctx)
            except GLib.Error as err:
                print(f"lumen-start: {err.message}", file=sys.stderr)

    def on_search(self, entry: Gtk.SearchEntry) -> None:
        query = fold(entry.get_text().strip())
        if not query:
            self.show_page("home")
            return
        while (row := self.results.get_first_child()) is not None:
            self.results.remove(row)

        recent = load_json(RECENT_FILE, {})
        scored = []
        for app in self.apps:
            s = app.score(query)
            if s:
                # Apps you use often float up among equally good matches.
                s += min(recent.get(app.id, {}).get("count", 0), 10)
                scored.append((s, app))
        scored.sort(key=lambda t: (-t[0], fold(t[1].name)))
        for _, app in scored[:8]:
            row = Row(app.name, app.generic or "Application", gicon=app.info.get_icon(),
                      activate=lambda a=app: self.launch(a), app=app)
            self.attach_context_menu(row, app)
            self.results.append(row)

        raw = entry.get_text().strip()
        value = calculate(raw)
        if value is not None:
            self.results.prepend(Row(value, f"{raw} =  ·  Enter copies the result", icon_name="accessories-calculator-symbolic",
                                     activate=lambda v=value: self.copy(v)))

        for title, words, icon, argv in ACTIONS:
            if query in fold(title) or any(w.startswith(query) for w in words.split()):
                self.results.append(Row(title, "Settings and actions", icon_name=icon,
                                        activate=lambda a=argv: (self.close_menu(), run_detached(a))))

        self.results.append(Row(f"Search the web for “{raw}”", "Opens your browser", icon_name="web-browser-symbolic",
                                activate=lambda q=raw: (self.close_menu(), run_detached(["lumen-search", "--query", q]))))
        self.results.append(Row(f"Find “{raw}” in the App Store", "Install new apps and games",
                                icon_name="system-software-install-symbolic",
                                activate=lambda q=raw: (self.close_menu(), run_detached(["lumen-store", "--search", q]))))
        first = shlex.split(raw)[0] if raw and not raw.startswith(("'", '"')) else ""
        if first and GLib.find_program_in_path(first):
            self.results.append(Row(f"Run “{raw}”", "In a terminal", icon_name="utilities-terminal-symbolic",
                                    activate=lambda c=raw: (self.close_menu(), run_detached(["lumen-term", "--hold", "--", "sh", "-c", c]))))

        self.results.select_row(self.results.get_row_at_index(0))
        self.stack.set_visible_child_name("search")

    def copy(self, text: str) -> None:
        Gdk.Display.get_default().get_clipboard().set(text)
        run_detached(["notify-send", "-a", "an4rch", "-t", "2000", text, "Copied to the clipboard"])
        GLib.timeout_add(150, lambda: (self.close_menu(), False)[1])

    def on_enter(self, *_):
        page = self.stack.get_visible_child_name()
        if page == "search":
            row = self.results.get_selected_row() or self.results.get_row_at_index(0)
            if row is not None and row.activate_cb:
                row.activate_cb()
        elif page == "home":
            tile = self.pinned.get_child_at_index(0)
            if tile is not None:
                tile.get_child().emit("clicked")

    def on_escape(self) -> None:
        if self.search.get_text():
            self.search.set_text("")
        elif self.stack.get_visible_child_name() != "home":
            self.show_page("home")
        else:
            self.close_menu()

    def on_key(self, _ctrl, keyval, _code, state) -> bool:
        if keyval == Gdk.KEY_Escape:
            self.on_escape()
            return True
        page = self.stack.get_visible_child_name()
        lists = {"search": self.results, "all": self.all_list}
        if keyval in (Gdk.KEY_Down, Gdk.KEY_Up) and page in lists:
            lb = lists[page]
            row = lb.get_selected_row()
            idx = row.get_index() if row else -1
            idx = idx + 1 if keyval == Gdk.KEY_Down else max(idx - 1, 0)
            nxt = lb.get_row_at_index(idx)
            if nxt is not None:
                lb.select_row(nxt)
                nxt.grab_focus()
                self.search.grab_focus_without_selecting()
            return True
        if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) and page == "all":
            row = self.all_list.get_selected_row()
            if row is not None and row.activate_cb:
                row.activate_cb()
            return True
        # Typing anywhere goes to the search box.
        if not self.search.has_focus() and Gdk.keyval_to_unicode(keyval) and not state & Gdk.ModifierType.CONTROL_MASK:
            self.search.grab_focus_without_selecting()
            return False
        return False

    def show_page(self, name: str) -> None:
        self.stack.set_visible_child_name(name)
        if name == "all":
            first = self.all_list.get_row_at_index(0)
            if first:
                self.all_list.select_row(first)

    def load_css(self) -> None:
        if THEME_CSS.exists():
            self.theme_css.load_from_path(str(THEME_CSS))
        self.css.load_from_path(str(STYLE_CSS))

    def open_menu(self) -> None:
        self.load_css()
        self.refresh()
        self.search.set_text("")
        self.show_page("home")
        self.set_visible(True)
        self.present()
        self.search.grab_focus()

    def close_menu(self) -> None:
        self.set_visible(False)

    def toggle(self) -> None:
        if self.get_visible():
            self.close_menu()
        else:
            self.open_menu()


class StartApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.window: StartMenu | None = None
        for name, cb in (("toggle", lambda *_: self.win().toggle()),
                         ("show", lambda *_: self.win().open_menu()),
                         ("hide", lambda *_: self.win().close_menu())):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", cb)
            self.add_action(action)

    def win(self) -> StartMenu:
        if self.window is None:
            self.window = StartMenu(self)
            self.window.refresh()
        return self.window

    def do_startup(self):
        Gtk.Application.do_startup(self)
        self.hold()  # stay alive while hidden

    def do_command_line(self, command_line):
        args = command_line.get_arguments()[1:]
        if "--daemon" in args:
            self.win()  # build everything now so the first open is instant
        elif "--quit" in args:
            self.quit()
        elif "--search" in args:
            idx = args.index("--search")
            query = args[idx + 1] if idx + 1 < len(args) else ""
            self.win().open_menu()
            self.win().search.set_text(query)
            self.win().search.set_position(-1)
        elif "--show" in args:
            self.win().open_menu()
        else:
            self.win().toggle()
        return 0


if __name__ == "__main__":
    sys.exit(StartApp().run(sys.argv))
