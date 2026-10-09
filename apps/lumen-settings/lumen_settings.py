#!/usr/bin/env python3
"""an4rch Hub — one window for everything you can change: look, desktop,
windows and effects, sound, network, displays, keyboard and mouse, power,
default apps, privacy and safety, backups, your phone, accessibility,
wellbeing, hardware and the system.

Most pages drive an4rch's own commands (anarch-theme, anarch-taskbar, …), so
the Settings app, the an4rch menu and the command line always agree. Window
and input choices are saved to ~/.config/lumen/desktop.json and written out
as ~/.config/lumen/desktop.lua, which Hyprland loads after an4rch's defaults.

    anarch-settings [PAGE]          open (at PAGE: look, desktop, windows, sound,
                                   network, displays, input, power, apps, privacy,
                                   backups, phone, a11y, wellbeing, hardware, system)
    anarch-settings --write-desktop regenerate desktop.lua from desktop.json
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
LUMEN_PATH = Path(os.environ.get("LUMEN_PATH", HOME / ".local/share/lumen"))
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "lumen"
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "lumen"
SETTINGS = CONFIG / "settings.conf"
DESKTOP_JSON = CONFIG / "desktop.json"
DESKTOP_LUA = CONFIG / "desktop.lua"
HERE = Path(__file__).resolve().parent

# Window and input choices, with an4rch's defaults (default/hypr/looks.lua and
# input.lua). Only these keys are written to desktop.lua.
DESKTOP_DEFAULTS = {
    "gaps_in": 5, "gaps_out": 12, "border_size": 2, "rounding": 12,
    "inactive_opacity": 0.97, "blur": True, "shadow": True, "animations": True,
    "sensitivity": 0.0, "natural_scroll": True, "tap_to_click": True,
    "disable_while_typing": True, "scroll_factor": 0.4,
    "repeat_delay": 280, "repeat_rate": 40,
}


# --- desktop.json → desktop.lua (no GTK needed: also used by tests) ---------------
def load_desktop() -> dict:
    data = dict(DESKTOP_DEFAULTS)
    try:
        saved = json.loads(DESKTOP_JSON.read_text())
        data.update({k: v for k, v in saved.items() if k in DESKTOP_DEFAULTS})
    except (OSError, ValueError):
        pass
    return data


def lua_value(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return f"{v:.2f}"
    return str(int(v))


# Where each choice lives in Hyprland's config (dotted path).
DESKTOP_KEYS = {
    "gaps_in": "general.gaps_in", "gaps_out": "general.gaps_out", "border_size": "general.border_size",
    "rounding": "decoration.rounding", "inactive_opacity": "decoration.inactive_opacity",
    "blur": "decoration.blur.enabled", "shadow": "decoration.shadow.enabled",
    "animations": "animations.enabled",
    "sensitivity": "input.sensitivity", "repeat_delay": "input.repeat_delay", "repeat_rate": "input.repeat_rate",
    "natural_scroll": "input.touchpad.natural_scroll", "tap_to_click": "input.touchpad.tap_to_click",
    "disable_while_typing": "input.touchpad.disable_while_typing", "scroll_factor": "input.touchpad.scroll_factor",
}


def desktop_lua(d: dict) -> str:
    """Only the choices that differ from an4rch's defaults are written, so the
    file stays small and everything else follows an4rch's own config."""
    tree: dict = {}
    for key, path in DESKTOP_KEYS.items():
        if key in d and d[key] != DESKTOP_DEFAULTS[key]:
            node = tree
            *parents, leaf = path.split(".")
            for p in parents:
                node = node.setdefault(p, {})
            node[leaf] = d[key]

    def emit(node: dict, depth: int) -> list[str]:
        pad = "    " * depth
        lines = []
        for k, v in node.items():
            if isinstance(v, dict):
                lines += [f"{pad}{k} = {{", *emit(v, depth + 1), f"{pad}}},"]
            else:
                lines.append(f"{pad}{k} = {lua_value(v)},")
        return lines

    head = ("-- Written by an4rch Settings: change these there (or delete this file to go\n"
            "-- back to an4rch's defaults). Your files in ~/.config/hypr/ load after it.\n")
    if not tree:
        return head
    return head + "hl.config({\n" + "\n".join(emit(tree, 1)) + "\n})\n"


def write_desktop(d: dict) -> None:
    CONFIG.mkdir(parents=True, exist_ok=True)
    DESKTOP_JSON.write_text(json.dumps(d, indent=2) + "\n")
    DESKTOP_LUA.write_text(desktop_lua(d))


if __name__ == "__main__" and "--write-desktop" in sys.argv:
    write_desktop(load_desktop())
    print(DESKTOP_LUA)
    sys.exit(0)


import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Adw, Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402


# --- helpers ------------------------------------------------------------------------------
def out(*cmd: str, timeout: int = 5) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def ok(*cmd: str, timeout: int = 10) -> bool:
    try:
        return subprocess.run(cmd, capture_output=True, timeout=timeout).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def has(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def lumen_cmd(name: str) -> str:
    path = LUMEN_PATH / "bin" / name
    return str(path) if path.exists() else name


def tool(*argv: str) -> None:
    """Start a an4rch command (or any program) in the background."""
    cmd = [lumen_cmd(argv[0]), *argv[1:]] if argv[0].startswith("anarch") else list(argv)
    try:
        subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError as err:
        print(f"anarch-settings: {err}", file=sys.stderr)


def edit_file(path: Path) -> None:
    """Open a config file in the chosen editor (a terminal one in a terminal)."""
    editor = read_settings().get("LUMEN_EDITOR", "code") or "code"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch(exist_ok=True)
    if editor.split()[0] in ("nvim", "vim", "hx", "helix", "nano"):
        tool("anarch-term", "--", editor, str(path))
    elif has(editor.split()[0]):
        tool(editor, str(path))
    else:
        tool("xdg-open", str(path))


def read_settings() -> dict[str, str]:
    data = {}
    try:
        for line in SETTINGS.read_text().splitlines():
            m = re.match(r"^([A-Z_]+)=(.*)$", line.strip())
            if m:
                data[m.group(1)] = m.group(2).split("#")[0].strip().strip('"')
    except OSError:
        pass
    return data


def set_setting(key: str, value: str) -> None:
    CONFIG.mkdir(parents=True, exist_ok=True)
    lines = SETTINGS.read_text().splitlines() if SETTINGS.exists() else []
    if " " in value:
        value = f'"{value}"'
    for i, line in enumerate(lines):
        if line.startswith(f"{key}="):
            lines[i] = f"{key}={value}"
            break
    else:
        lines.append(f"{key}={value}")
    SETTINGS.write_text("\n".join(lines) + "\n")


def read_theme(path: Path) -> dict[str, str]:
    data = {}
    for line in path.read_text().splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            data[k.strip()] = v.strip().split()[0] if v.strip() else ""
    data["title"] = next((l.split("=", 1)[1].strip() for l in path.read_text().splitlines()
                          if l.strip().startswith("name")), path.parent.name)
    return data


def themes() -> list[tuple[str, dict]]:
    found = {}
    for root in (LUMEN_PATH / "themes", CONFIG / "themes"):
        if root.is_dir():
            for d in sorted(root.iterdir()):
                if (d / "theme.conf").is_file():
                    found[d.name] = read_theme(d / "theme.conf")
    return list(found.items())


def current_theme() -> str:
    try:
        name = (CONFIG / "current/theme.name").read_text().strip()
    except OSError:
        return "an4rch"
    return "an4rch" if name in ("", "lumen") else name


# Sound through pactl (PipeWire's PulseAudio server): stable device names
# and human descriptions.
def pactl_json(kind: str) -> list[dict]:
    try:
        return json.loads(out("pactl", "-f", "json", "list", kind) or "[]")
    except ValueError:
        return []


def volume_of(kind: str) -> tuple[int, bool]:
    m = re.search(r"(\d+)%", out("pactl", f"get-{kind}-volume", f"@DEFAULT_{kind.upper()}@"))
    mute = "yes" in out("pactl", f"get-{kind}-mute", f"@DEFAULT_{kind.upper()}@")
    return (int(m.group(1)) if m else 0), mute


def row(title: str, subtitle: str = "", icon: str | None = None) -> Adw.ActionRow:
    r = Adw.ActionRow(title=title, subtitle=subtitle)
    if icon:
        r.add_prefix(Gtk.Image.new_from_icon_name(icon))
    return r


def button_row(title: str, subtitle: str, icon: str, action) -> Adw.ActionRow:
    r = row(title, subtitle, icon)
    r.set_activatable(True)
    r.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))
    r.connect("activated", lambda *_: action())
    return r


def switch_row(title: str, subtitle: str, active: bool, on_change) -> Adw.SwitchRow:
    r = Adw.SwitchRow(title=title, subtitle=subtitle, active=active)
    r.connect("notify::active", lambda w, *_: on_change(w.get_active()))
    return r


def spin_row(title: str, subtitle: str, lo: float, hi: float, step: float, value: float, on_change,
             digits: int = 0) -> Adw.SpinRow:
    r = Adw.SpinRow.new_with_range(lo, hi, step)
    r.set_title(title)
    r.set_subtitle(subtitle)
    r.set_digits(digits)
    r.set_value(value)
    r.connect("notify::value", lambda w, *_: on_change(w.get_value()))
    return r


def combo_row(title: str, subtitle: str, labels: list[str], selected: int, on_change) -> Adw.ComboRow:
    r = Adw.ComboRow(title=title, subtitle=subtitle, model=Gtk.StringList.new(labels))
    r.set_selected(max(0, selected))
    r.connect("notify::selected", lambda w, *_: on_change(w.get_selected()))
    return r


def slider(lo: float, hi: float, value: float, on_change, width: int = 220) -> Gtk.Scale:
    s = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, lo, hi, 1)
    s.set_value(value)
    s.set_draw_value(False)
    s.set_size_request(width, -1)
    s.set_valign(Gtk.Align.CENTER)
    s.connect("value-changed", lambda w: on_change(w.get_value()))
    return s


# --- the window ------------------------------------------------------------------------------
PAGES = [
    ("look", "Appearance", "preferences-desktop-appearance-symbolic"),
    ("desktop", "Desktop", "user-desktop-symbolic"),
    ("windows", "Windows and effects", "preferences-system-windows-symbolic"),
    ("sound", "Sound", "audio-volume-high-symbolic"),
    ("network", "Network and Bluetooth", "network-wireless-symbolic"),
    ("displays", "Displays", "video-display-symbolic"),
    ("input", "Keyboard, mouse and touchpad", "input-keyboard-symbolic"),
    ("power", "Power", "battery-good-symbolic"),
    ("apps", "Default apps", "applications-other-symbolic"),
    ("privacy", "Privacy and safety", "security-high-symbolic"),
    ("backups", "Backups", "drive-harddisk-symbolic"),
    ("phone", "Phone", "phone-symbolic"),
    ("a11y", "Accessibility", "preferences-desktop-accessibility-symbolic"),
    ("wellbeing", "Focus and wellbeing", "alarm-symbolic"),
    ("hardware", "Hardware and drivers", "cpu-symbolic"),
    ("system", "System", "computer-symbolic"),
]


def in_term(title: str, *argv: str) -> None:
    """Run an an4rch command in a small terminal (for questions and passwords)."""
    tool("anarch-term", "--float", "--hold", "--title", title, "--", lumen_cmd(argv[0]), *argv[1:])


def status_lines(*cmd: str) -> dict[str, str]:
    """'  Name   value' lines from an an4rch status command, as a dict."""
    found = {}
    for line in out(lumen_cmd(cmd[0]), *cmd[1:]).splitlines():
        m = re.match(r"^\s+(\S.*?)\s{2,}(\S.*)$", line)
        if m:
            found[m.group(1).strip()] = m.group(2).strip()
    return found


class Settings(Adw.ApplicationWindow):
    def __init__(self, app: Adw.Application, page: str):
        super().__init__(application=app, title="an4rch Hub", default_width=980, default_height=700)
        self.desktop = load_desktop()
        self.settings = read_settings()
        self.reload_source = 0
        self.load_style()

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120)
        self.built: set[str] = set()
        for key, title, _icon in PAGES:
            self.stack.add_titled(Gtk.Box(), key, title)

        sidebar_list = Gtk.ListBox(css_classes=["navigation-sidebar"])
        for key, title, icon in PAGES:
            box = Gtk.Box(spacing=12, margin_top=6, margin_bottom=6, margin_start=6)
            box.append(Gtk.Image.new_from_icon_name(icon))
            box.append(Gtk.Label(label=title, xalign=0))
            r = Gtk.ListBoxRow(child=box)
            r.page_key = key
            sidebar_list.append(r)
        sidebar_list.connect("row-selected", lambda _l, r: r and self.show_page(r.page_key))

        sidebar_view = Adw.ToolbarView()
        sidebar_view.add_top_bar(Adw.HeaderBar(title_widget=Gtk.Label(label="an4rch Hub", css_classes=["heading"])))
        sidebar_view.set_content(Gtk.ScrolledWindow(child=sidebar_list, hscrollbar_policy=Gtk.PolicyType.NEVER))

        self.content_title = Adw.WindowTitle(title="")
        content_view = Adw.ToolbarView()
        content_view.add_top_bar(Adw.HeaderBar(title_widget=self.content_title))
        content_view.set_content(self.stack)

        split = Adw.NavigationSplitView(min_sidebar_width=250, max_sidebar_width=290)
        split.set_sidebar(Adw.NavigationPage(title="an4rch Hub", child=sidebar_view))
        split.set_content(Adw.NavigationPage(title="an4rch Hub", child=content_view))
        self.set_content(split)

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", lambda _c, kv, *_: kv == Gdk.KEY_Escape and (self.close() or True))
        self.add_controller(keys)

        # Tests: build every page now, so a broken one shows up straight away.
        if os.environ.get("LUMEN_SETTINGS_ALL_PAGES"):
            for key, _title, _icon in PAGES:
                self.show_page(key)
        index = next((i for i, p in enumerate(PAGES) if p[0] == page), 0)
        sidebar_list.select_row(sidebar_list.get_row_at_index(index))

    def load_style(self) -> None:
        display = Gdk.Display.get_default()
        for path, prio in ((CONFIG / "current/theme/apps.css", 0), (HERE / "style.css", 1)):
            if path.exists():
                provider = Gtk.CssProvider()
                provider.load_from_path(str(path))
                Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + prio)
        env = CONFIG / "current/theme/theme.env"
        light = env.exists() and 'LUMEN_THEME_MODE="light"' in env.read_text()
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_LIGHT if light else Adw.ColorScheme.FORCE_DARK)

    # Pages are built the first time they're shown, so the window opens at once.
    def show_page(self, key: str) -> None:
        if key not in self.built:
            self.built.add(key)
            old = self.stack.get_child_by_name(key)
            title = self.stack.get_page(old).get_title()
            self.stack.remove(old)
            self.stack.add_titled(getattr(self, f"page_{key}")(), key, title)
        self.stack.set_visible_child_name(key)
        self.content_title.set_title(next(t for k, t, _ in PAGES if k == key))

    # Window and input changes: save, then reload Hyprland once the user
    # has stopped clicking.
    def set_desktop(self, key: str, value) -> None:
        if isinstance(DESKTOP_DEFAULTS[key], bool):
            value = bool(value)
        elif isinstance(DESKTOP_DEFAULTS[key], int):
            value = int(round(value))
        else:
            value = round(float(value), 2)
        self.desktop[key] = value
        write_desktop(self.desktop)
        if self.reload_source:
            GLib.source_remove(self.reload_source)
        self.reload_source = GLib.timeout_add(350, self.reload_hyprland)

    def reload_hyprland(self) -> bool:
        self.reload_source = 0
        tool("hyprctl", "reload")
        return False

    def set_conf(self, key: str, value: str) -> None:
        set_setting(key, value)
        self.settings[key] = value

    # --- Appearance ---------------------------------------------------------------------------
    def page_look(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup(title="Theme", description="Restyles windows, bars, menus, the terminal, "
                                     "apps, the lock screen and the login screen at once.")
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=5, min_children_per_line=2,
                           homogeneous=True, row_spacing=10, column_spacing=10)
        css = []
        for slug, t in themes():
            for k in ("bg", "accent", "accent2", "red", "yellow", "green"):
                css.append(f".sw-{slug}-{k} {{ background: {t.get(k, '#888888')}; }}")
        provider = Gtk.CssProvider()
        provider.load_from_string("\n".join(css))
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 2)
        self.theme_buttons: dict[str, Gtk.Button] = {}
        for slug, t in themes():
            b = Gtk.Button(css_classes=["theme-tile"])
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            sw = Gtk.Box(spacing=3, halign=Gtk.Align.CENTER)
            for k in ("bg", "accent", "accent2", "red", "yellow", "green"):
                dot = Gtk.Box(css_classes=["swatch", f"sw-{slug}-{k}"])
                dot.set_size_request(16, 16)
                sw.append(dot)
            inner.append(sw)
            inner.append(Gtk.Label(label=t.get("title", slug)))
            b.set_child(inner)
            b.connect("clicked", lambda _b, s=slug: self.pick_theme(s))
            self.theme_buttons[slug] = b
            flow.append(b)
        self.mark_theme(current_theme())
        group.add(flow)
        page.add(group)

        walls = Adw.PreferencesGroup(title="Wallpaper", description="This theme's wallpapers, and your own "
                                     "pictures from ~/Pictures/Wallpapers.")
        self.wall_flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=4,
                                     min_children_per_line=2, homogeneous=True, row_spacing=8, column_spacing=8)
        walls.add(self.wall_flow)
        own = Gtk.Button(label="Choose a picture…", css_classes=["pill"], halign=Gtk.Align.START, margin_top=10)
        own.connect("clicked", lambda *_: self.choose_wallpaper())
        walls.add(own)
        page.add(walls)
        GLib.idle_add(self.fill_wallpapers)

        more = Adw.PreferencesGroup(title="Make it yours")
        more.add(button_row("Make my own theme", "Copy the current theme and change its colours", "applications-graphics-symbolic",
                            lambda: tool("anarch-menu", "style")))
        more.add(button_row("Install a theme", "From any git repository with a theme.conf", "folder-download-symbolic",
                            lambda: tool("anarch-menu", "style")))
        more.add(button_row("Edit the top bar", "Waybar's modules and style", "document-edit-symbolic",
                            lambda: edit_file(HOME / ".config/waybar/config.jsonc")))
        more.add(button_row("Edit window look by hand", "Everything Hyprland can do: ~/.config/hypr/looks.lua",
                            "document-edit-symbolic", lambda: edit_file(HOME / ".config/hypr/looks.lua")))
        page.add(more)
        return page

    def mark_theme(self, slug: str) -> None:
        for s, b in self.theme_buttons.items():
            (b.add_css_class if s == slug else b.remove_css_class)("theme-tile-active")

    def pick_theme(self, slug: str) -> None:
        self.mark_theme(slug)
        tool("anarch-theme", "set", slug)
        GLib.timeout_add(900, lambda: (self.load_style(), self.fill_wallpapers(), False)[2])

    def fill_wallpapers(self) -> bool:
        child = self.wall_flow.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self.wall_flow.remove(child)
            child = nxt
        files = [f for f in out(lumen_cmd("anarch-wallpaper"), "list").splitlines() if f][:16]
        for f in files:
            try:
                pix = GdkPixbuf.Pixbuf.new_from_file_at_scale(f, 200, 112, False)
            except GLib.Error:
                continue
            pic = Gtk.Picture.new_for_paintable(Gdk.Texture.new_for_pixbuf(pix))
            pic.set_size_request(160, 90)
            b = Gtk.Button(child=pic, css_classes=["wall-tile"], tooltip_text=Path(f).name)
            b.connect("clicked", lambda _b, p=f: tool("anarch-wallpaper", "set", p))
            self.wall_flow.append(b)
        return False

    def choose_wallpaper(self) -> None:
        dialog = Gtk.FileDialog(title="Choose a wallpaper")
        filt = Gtk.FileFilter(name="Pictures")
        filt.add_mime_type("image/*")
        store = Gio.ListStore.new(Gtk.FileFilter)
        store.append(filt)
        dialog.set_filters(store)

        def done(d, res):
            try:
                f = d.open_finish(res)
            except GLib.Error:
                return
            if f and f.get_path():
                tool("anarch-wallpaper", "set", f.get_path())
        dialog.open(self, None, done)

    # --- Desktop ------------------------------------------------------------------------------
    def page_desktop(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        s = self.settings
        bars = Adw.PreferencesGroup(title="Bars")
        top_running = any("taskbar" not in l for l in out("pgrep", "-af", "waybar").splitlines() if l)
        bars.add(switch_row("Top bar", "Clock, Wi-Fi, sound, battery and more", top_running,
                            lambda on: tool("anarch-toggle", "bar")))
        bars.add(switch_row("Taskbar along the bottom", "Your open windows; click to switch or minimise",
                            s.get("LUMEN_TASKBAR", "no") == "yes",
                            lambda on: tool("anarch-taskbar", "on" if on else "off")))
        page.add(bars)

        wins = Adw.PreferencesGroup(title="Windows")
        wins.add(switch_row("Title bars with buttons", "Close, maximise and minimise on every window",
                            s.get("LUMEN_TITLEBARS", "yes") == "yes",
                            lambda on: tool("anarch-titlebars", "on" if on else "off")))
        layout = out("hyprctl", "getoption", "general:layout", "-j")
        wins.add(combo_row("Window layout", "Tiling splits the screen; scrolling lines windows up side by side",
                           ["Tiling", "Scrolling"], 1 if '"scrolling"' in layout else 0,
                           lambda i: tool("anarch-toggle", "layout")))
        page.add(wins)

        evening = Adw.PreferencesGroup(title="Night light and notifications")
        evening.add(switch_row("Night light", "Warmer colours, easier on the eyes in the evening",
                               bool(out("pgrep", "-x", "hyprsunset")),
                               lambda on: tool("anarch-toggle", "nightlight", "on" if on else "off")))
        temp = int(s.get("LUMEN_NIGHTLIGHT_TEMP", "4300") or 4300)
        evening.add(spin_row("Night light warmth", "Lower is warmer (kelvin)", 2500, 6000, 100, temp,
                             lambda v: self.set_nightlight_temp(int(v))))
        evening.add(switch_row("Do Not Disturb", "Silence notifications (reminders still show)",
                               "do-not-disturb" in out("makoctl", "mode"),
                               lambda on: tool("anarch-toggle", "dnd", "on" if on else "off")))
        page.add(evening)

        start = Adw.PreferencesGroup(title="Start menu and shortcuts")
        start.add(button_row("Keyboard shortcuts", "Every key binding, searchable", "preferences-desktop-keyboard-shortcuts-symbolic",
                             lambda: tool("anarch-keys")))
        start.add(button_row("Edit key bindings", "Add or change your own", "document-edit-symbolic",
                             lambda: edit_file(HOME / ".config/hypr/bindings.lua")))
        start.add(button_row("Apps that start when you log in", "~/.config/hypr/autostart.lua", "system-run-symbolic",
                             lambda: edit_file(HOME / ".config/hypr/autostart.lua")))
        page.add(start)
        return page

    def set_nightlight_temp(self, k: int) -> None:
        self.set_conf("LUMEN_NIGHTLIGHT_TEMP", str(k))
        if out("pgrep", "-x", "hyprsunset"):
            subprocess.run(["pkill", "-x", "hyprsunset"], check=False)
            GLib.timeout_add(300, lambda: (tool("anarch-toggle", "nightlight", "on"), False)[1])

    # --- Windows and effects ------------------------------------------------------------------
    def page_windows(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        d = self.desktop
        shape = Adw.PreferencesGroup(title="Shape and spacing")
        shape.add(spin_row("Gap between windows", "Pixels", 0, 40, 1, d["gaps_in"], lambda v: self.set_desktop("gaps_in", v)))
        shape.add(spin_row("Gap at the screen edge", "Pixels", 0, 60, 1, d["gaps_out"], lambda v: self.set_desktop("gaps_out", v)))
        shape.add(spin_row("Border width", "Pixels; the active window's border uses the theme's accent", 0, 8, 1,
                           d["border_size"], lambda v: self.set_desktop("border_size", v)))
        shape.add(spin_row("Rounded corners", "Radius in pixels (0 for square)", 0, 30, 1, d["rounding"],
                           lambda v: self.set_desktop("rounding", v)))
        page.add(shape)

        fx = Adw.PreferencesGroup(title="Effects", description="Turning effects off makes older or low-power "
                                  "computers feel quicker.")
        fx.add(switch_row("Animations", "Windows and workspaces glide into place", d["animations"],
                          lambda on: self.set_desktop("animations", on)))
        fx.add(switch_row("Blur", "Frosted glass behind the bars, menus and see-through windows", d["blur"],
                          lambda on: self.set_desktop("blur", on)))
        fx.add(switch_row("Shadows", "Soft shadows under windows", d["shadow"],
                          lambda on: self.set_desktop("shadow", on)))
        opac = row("Background windows", "Fade windows you're not using a little")
        opac.add_suffix(slider(70, 100, d["inactive_opacity"] * 100,
                               lambda v: self.set_desktop("inactive_opacity", v / 100)))
        fx.add(opac)
        page.add(fx)

        reset = Adw.PreferencesGroup()
        b = Gtk.Button(label="Reset to an4rch's defaults", css_classes=["pill"], halign=Gtk.Align.CENTER)
        b.connect("clicked", lambda *_: self.reset_desktop())
        reset.add(b)
        page.add(reset)
        return page

    def reset_desktop(self) -> None:
        for p in (DESKTOP_JSON, DESKTOP_LUA):
            p.unlink(missing_ok=True)
        self.desktop = load_desktop()
        tool("hyprctl", "reload")
        for key in ("windows", "input"):
            if key in self.built:
                self.built.discard(key)
        self.show_page("windows")

    # --- Sound --------------------------------------------------------------------------------
    def page_sound(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        for kind, title, icon in (("sink", "Output", "audio-speakers-symbolic"),
                                  ("source", "Input", "audio-input-microphone-symbolic")):
            group = Adw.PreferencesGroup(title=title)
            devices = [d for d in pactl_json(kind + "s") if not d.get("name", "").endswith(".monitor")]
            default = out("pactl", f"get-default-{kind}")
            if devices:
                names = [d["name"] for d in devices]
                labels = [d.get("description") or d["name"] for d in devices]
                group.add(combo_row("Device", "", labels, names.index(default) if default in names else 0,
                                    lambda i, k=kind, n=names: ok("pactl", f"set-default-{k}", n[i])))
            vol, mute = volume_of(kind)
            r = row("Volume", "", icon)
            r.add_suffix(slider(0, 150 if kind == "sink" else 100, vol,
                                lambda v, k=kind: ok("pactl", f"set-{k}-volume", f"@DEFAULT_{k.upper()}@", f"{int(v)}%")))
            group.add(r)
            group.add(switch_row("Mute", "", mute,
                                 lambda on, k=kind: ok("pactl", f"set-{k}-mute", f"@DEFAULT_{k.upper()}@", "1" if on else "0")))
            if not devices:
                group.set_description("No devices found. Is PipeWire running?")
            page.add(group)
        more = Adw.PreferencesGroup()
        more.add(button_row("Volume for each app", "The full mixer", "multimedia-volume-control-symbolic",
                            lambda: tool("anarch-audio", "mixer")))
        page.add(more)
        return page

    # --- Network and Bluetooth ---------------------------------------------------------------
    def page_network(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        wifi = Adw.PreferencesGroup(title="Wi-Fi")
        radio = out("nmcli", "-t", "radio", "wifi") == "enabled"
        current = [l.split(":", 1)[1] for l in out("nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi").splitlines()
                   if l.startswith("yes:")]
        wifi.add(switch_row("Wi-Fi", f"Connected to {current[0]}" if current else "Not connected", radio,
                            lambda on: ok("nmcli", "radio", "wifi", "on" if on else "off")))
        wifi.add(button_row("Choose a network", "Also: click the Wi-Fi icon in the top bar", "network-wireless-symbolic",
                            lambda: tool("anarch-wifi")))
        wifi.add(button_row("Advanced network settings", "VPNs, static addresses, hotspots", "preferences-system-network-symbolic",
                            lambda: tool("nm-connection-editor") if has("nm-connection-editor") else tool("anarch-term", "--float", "--", "nmtui")))
        page.add(wifi)

        bt = Adw.PreferencesGroup(title="Bluetooth")
        show = out("bluetoothctl", "show", timeout=3)
        if show and "Powered" in show:
            bt.add(switch_row("Bluetooth", "", "Powered: yes" in show,
                              lambda on: ok("bluetoothctl", "power", "on" if on else "off")))
            paired = [l.split(" ", 2)[2] for l in out("bluetoothctl", "devices", "Paired", timeout=3).splitlines()
                      if l.startswith("Device ")]
            for name in paired[:8]:
                bt.add(row(name, "Paired", "bluetooth-symbolic"))
        else:
            bt.set_description("No Bluetooth adapter found (it may be off in this computer's BIOS settings).")
        bt.add(button_row("Pair a new device", "Headphones, mice, keyboards, controllers", "bluetooth-symbolic",
                          lambda: tool("anarch-bluetooth")))
        page.add(bt)
        return page

    # --- Displays -----------------------------------------------------------------------------
    def page_displays(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup(title="Displays")
        try:
            mons = json.loads(out("hyprctl", "monitors", "-j") or "[]")
        except ValueError:
            mons = []
        for m in mons:
            group.add(row(m.get("description") or m.get("name", "Display"),
                          f'{m.get("width")}×{m.get("height")} at {round(m.get("refreshRate", 0))} Hz, '
                          f'scale {m.get("scale")}', "video-display-symbolic"))
        group.add(button_row("Resolution, scale and arrangement", "If a change goes wrong, the old layout comes back "
                             "after 15 seconds", "preferences-desktop-display-symbolic", lambda: tool("anarch-display")))
        page.add(group)
        night = Adw.PreferencesGroup()
        night.add(button_row("Night light", "On the Desktop page", "night-light-symbolic", lambda: self.show_page("desktop")))
        page.add(night)
        return page

    # --- Keyboard, mouse and touchpad --------------------------------------------------------
    def page_input(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        d = self.desktop
        kb = Adw.PreferencesGroup(title="Keyboard")
        kb.add(button_row("Keyboard layout", "Languages and layouts", "input-keyboard-symbolic",
                          lambda: tool("anarch-setup", "keyboard")))
        kb.add(spin_row("Repeat delay", "Milliseconds before a held key repeats", 150, 1000, 10, d["repeat_delay"],
                        lambda v: self.set_desktop("repeat_delay", v)))
        kb.add(spin_row("Repeat rate", "Characters per second while held", 10, 80, 1, d["repeat_rate"],
                        lambda v: self.set_desktop("repeat_rate", v)))
        page.add(kb)

        mouse = Adw.PreferencesGroup(title="Mouse")
        speed = row("Pointer speed", "Slower ← → faster")
        speed.add_suffix(slider(-100, 100, d["sensitivity"] * 100, lambda v: self.set_desktop("sensitivity", v / 100)))
        mouse.add(speed)
        page.add(mouse)

        tp = Adw.PreferencesGroup(title="Touchpad")
        tp.add(switch_row("Tap to click", "", d["tap_to_click"], lambda on: self.set_desktop("tap_to_click", on)))
        tp.add(switch_row("Natural scrolling", "Content follows your fingers, like a phone", d["natural_scroll"],
                          lambda on: self.set_desktop("natural_scroll", on)))
        tp.add(switch_row("Ignore while typing", "", d["disable_while_typing"],
                          lambda on: self.set_desktop("disable_while_typing", on)))
        sc = row("Scrolling speed", "")
        sc.add_suffix(slider(10, 150, d["scroll_factor"] * 100, lambda v: self.set_desktop("scroll_factor", v / 100)))
        tp.add(sc)
        page.add(tp)
        return page

    # --- Power --------------------------------------------------------------------------------
    def page_power(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup(title="Power")
        if has("powerprofilesctl"):
            profiles = ["power-saver", "balanced", "performance"]
            labels = ["Power saver", "Balanced", "Performance"]
            cur = out("powerprofilesctl", "get")
            group.add(combo_row("Power mode", "Also: SUPER + CTRL + P", labels,
                                profiles.index(cur) if cur in profiles else 1,
                                lambda i: ok("powerprofilesctl", "set", profiles[i])))
        modes = ["always", "battery", "never"]
        cur = self.settings.get("LUMEN_IDLE_SUSPEND", "always")
        group.add(combo_row("Sleep after 30 idle minutes", "", ["Always", "Only on battery", "Never"],
                            modes.index(cur) if cur in modes else 0,
                            lambda i: self.set_conf("LUMEN_IDLE_SUSPEND", modes[i])))
        group.add(switch_row("Keep awake", "Pause the screen lock and sleep for now",
                             not out("pgrep", "-x", "hypridle"),
                             lambda on: tool("anarch-toggle", "idle", "on" if on else "off")))
        bat = out(lumen_cmd("anarch-battery"))
        if bat:
            group.add(row("Battery", bat, "battery-good-symbolic"))
        page.add(group)
        return page

    # --- Default apps -------------------------------------------------------------------------
    def page_apps(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup(title="Default apps", description="Used by the keyboard shortcuts, the Start "
                                     "menu and links. Install more from the App Store.")
        choices = [
            ("LUMEN_BROWSER", "Web browser", ["firefox", "chromium", "brave", "zen-browser", "google-chrome-stable", "librewolf"]),
            ("LUMEN_TERMINAL", "Terminal", ["ghostty", "alacritty", "kitty", "foot"]),
            ("LUMEN_EDITOR", "Code editor", ["code", "zed", "nvim", "helix", "cursor", "subl"]),
            ("LUMEN_FILES", "Files", ["nautilus", "thunar", "dolphin", "nemo"]),
        ]
        for key, title, options in choices:
            found = [o for o in options if has(o)]
            cur = self.settings.get(key, "")
            if cur and cur not in found and has(cur.split()[0]):
                found.insert(0, cur)
            if not found:
                continue
            group.add(combo_row(title, "", found, found.index(cur) if cur in found else 0,
                                lambda i, k=key, f=found: self.set_default(k, f[i])))
        page.add(group)
        store = Adw.PreferencesGroup()
        store.add(button_row("App Store", "Install apps and games", "system-software-install-symbolic", lambda: tool("anarch-store")))
        page.add(store)
        return page

    def set_default(self, key: str, value: str) -> None:
        self.set_conf(key, value)
        if key == "LUMEN_BROWSER":
            for root in (Path("/usr/share/applications"), HOME / ".local/share/applications"):
                hits = sorted(root.glob(f"*{value.split('-')[0]}*.desktop")) if root.is_dir() else []
                if hits:
                    desktop = hits[0].name
                    ok("xdg-settings", "set", "default-web-browser", desktop)
                    ok("xdg-mime", "default", desktop, "x-scheme-handler/http", "x-scheme-handler/https", "text/html")
                    break

    # --- System -------------------------------------------------------------------------------
    def page_system(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        about = Adw.PreferencesGroup(title="About this computer")
        osr = {}
        try:
            for line in Path("/etc/os-release").read_text().splitlines():
                if "=" in line:
                    k, v = line.split("=", 1)
                    osr[k] = v.strip('"')
        except OSError:
            pass
        version = ""
        try:
            version = (LUMEN_PATH / "VERSION").read_text().strip()
        except OSError:
            pass
        cpu = next((l.split(":", 1)[1].strip() for l in Path("/proc/cpuinfo").read_text().splitlines()
                    if l.startswith("model name")), "") if Path("/proc/cpuinfo").exists() else ""
        mem = 0
        try:
            mem = int(next(l.split()[1] for l in Path("/proc/meminfo").read_text().splitlines() if l.startswith("MemTotal")))
        except (OSError, StopIteration, ValueError):
            pass
        gpu = ", ".join(re.sub(r"^.*?: ", "", l) for l in out("lspci").splitlines()
                        if re.search(r"VGA|3D|Display", l))[:120]
        disk = shutil.disk_usage("/")
        for title, value, icon in (
            ("System", f'{osr.get("PRETTY_NAME", "an4rch OS")}{f"  ·  version {version}" if version else ""}', "computer-symbolic"),
            ("Processor", cpu, "cpu-symbolic"),
            ("Memory", f"{mem / 1048576:.1f} GB" if mem else "", "memory-symbolic"),
            ("Graphics", gpu, "video-display-symbolic"),
            ("Storage", f"{disk.free / 1e9:.0f} GB free of {disk.total / 1e9:.0f} GB", "drive-harddisk-symbolic"),
            ("Kernel", os.uname().release, "system-run-symbolic"),
        ):
            if value:
                r = row(title, value, icon)
                r.set_subtitle_selectable(True)
                about.add(r)
        page.add(about)

        upkeep = Adw.PreferencesGroup(title="Keep it running well")
        upkeep.add(button_row("Update everything", "an4rch takes a snapshot first, so updates can be undone",
                              "software-update-available-symbolic", lambda: tool("anarch-update")))
        upkeep.add(button_row("Snapshots and rollback", "Go back to how things were", "document-revert-symbolic",
                              lambda: tool("anarch-snapshot", "menu")))
        upkeep.add(button_row("Health check", "Find and fix common problems", "emblem-ok-symbolic",
                              lambda: tool("anarch-term", "--float", "--hold", "--title", "an4rch doctor", "--", lumen_cmd("anarch-doctor"))))
        upkeep.add(button_row("Performance tuning", "Gaming and responsiveness tweaks", "power-profile-performance-symbolic",
                              lambda: tool("anarch-tune")))
        page.add(upkeep)

        more = Adw.PreferencesGroup(title="More")
        for title, sub, icon, argv in (
            ("Gaming", "Steam, Proton, GameMode, MangoHud and drivers", "input-gaming-symbolic", ["anarch-gaming"]),
            ("Extras", "Streaming, RGB, Android, virtual machines…", "list-add-symbolic", ["anarch-extras"]),
            ("Time zone", "", "preferences-system-time-symbolic", ["anarch-setup", "timezone"]),
            ("Fingerprint login", "", "fingerprint-symbolic", ["anarch-term", "--float", "--hold", "--", lumen_cmd("anarch-setup"), "fingerprint"]),
            ("Printers", "", "printer-symbolic", ["anarch-term", "--float", "--hold", "--", lumen_cmd("anarch-setup"), "printing"]),
            ("Welcome tour and tips", "", "help-about-symbolic", ["anarch-welcome"]),
            ("an4rch manual", "", "help-browser-symbolic", ["anarch-manual"]),
        ):
            more.add(button_row(title, sub, icon, lambda a=argv: tool(*a)))
        more.add(button_row("Report a problem", "Collects what's needed to fix it (private details removed)",
                            "dialog-warning-symbolic", lambda: in_term("Report a problem", "anarch-report")))
        page.add(more)
        return page

    # --- Privacy and safety ---------------------------------------------------------------
    def page_privacy(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        st = status_lines("anarch-privacy", "status")
        net = Adw.PreferencesGroup(title="Network privacy",
                                   description="Each needs your password once; they stay on until you turn them off.")
        for key, title, sub, arg in (
            ("Hidden hardware address", "Hidden hardware address", "A made-up address on every network", "mac"),
            ("Encrypted DNS", "Encrypted DNS", "The network can't see or change which sites you look up", "dns"),
            ("Tracker blocking", "Block ads and trackers", "For every app, from a list of tens of thousands of sites", "block"),
        ):
            on = st.get(key, "off").startswith("on")
            r = row(title, f"{sub} · {st.get(key, 'off')}", "security-high-symbolic")
            b = Gtk.Button(label="Turn off" if on else "Turn on", valign=Gtk.Align.CENTER)
            b.connect("clicked", lambda _b, a=arg, o=on: in_term("Privacy", "anarch-privacy", a, "off" if o else "on"))
            r.add_suffix(b)
            net.add(r)
        page.add(net)
        safe = Adw.PreferencesGroup(title="Keeping things safe")
        safe.add(row("Panic key: ⊞ + Shift + Esc", "Locks the screen on an empty desktop, closes vaults, mutes, "
                     "pauses media and clears the clipboard", "system-lock-screen-symbolic"))
        safe.add(button_row("Vaults", "Encrypted folders that open with a password", "folder-locked-symbolic",
                            lambda: in_term("Vaults", "anarch-vault")))
        safe.add(button_row("Run an app in a sandbox", "It can't see your files and forgets everything it saved",
                            "applications-system-symbolic", lambda: in_term("Sandbox", "anarch-sandbox", "--help")))
        safe.add(button_row("Remove hidden data from files", "Where a photo was taken, a document's author… "
                            "(also when you right-click files in Files)", "edit-clear-all-symbolic",
                            lambda: in_term("Remove hidden data", "anarch-scrub", "--help")))
        page.add(safe)
        return page

    # --- Backups -------------------------------------------------------------------------------
    def page_backups(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        info = out(lumen_cmd("anarch-backup"), "status", timeout=15)
        on = info.startswith("Backups: on")
        group = Adw.PreferencesGroup(title="Backups",
                                     description="Your home folder, every hour, encrypted, to a drive you choose. "
                                                 "Versions are kept for up to a year.")
        group.add(row("Status", info.replace("\n", " · ").replace("  ", " ") or "Off", "drive-harddisk-symbolic"))
        if on:
            group.add(button_row("Back up now", "", "document-save-symbolic", lambda: in_term("Backup", "anarch-backup", "now")))
            group.add(button_row("Browse old versions", "Opens them in Files, by date", "folder-open-symbolic",
                                 lambda: tool("anarch-backup", "browse")))
            group.add(button_row("Restore everything", "Into ~/Restored (nothing is overwritten)", "document-revert-symbolic",
                                 lambda: in_term("Restore", "anarch-backup", "restore")))
            group.add(button_row("Show the recovery key", "Needed to read the backups on another computer",
                                 "dialog-password-symbolic", lambda: in_term("Recovery key", "anarch-backup", "key")))
            group.add(button_row("Stop backing up", "The backups already made stay on the drive", "process-stop-symbolic",
                                 lambda: in_term("Backup", "anarch-backup", "off")))
        else:
            group.add(button_row("Set up backups", "Plug in a drive first", "list-add-symbolic",
                                 lambda: in_term("Set up backups", "anarch-backup", "setup")))
        page.add(group)
        snaps = Adw.PreferencesGroup(title="System snapshots",
                                     description="Separate from backups: taken before every update, so an update can be undone.")
        snaps.add(button_row("Snapshots and rollback", "", "document-revert-symbolic", lambda: tool("anarch-snapshot", "menu")))
        page.add(snaps)
        return page

    # --- Phone ---------------------------------------------------------------------------------
    def page_phone(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        info = out(lumen_cmd("anarch-phone"), "status", timeout=10)
        on = info.startswith("Phone link: on")
        group = Adw.PreferencesGroup(title="Your phone",
                                     description="Notifications, files both ways and a shared clipboard, over your "
                                                 "Wi-Fi (KDE Connect; the phone needs its app).")
        for line in info.splitlines()[1:] or ["Off"]:
            group.add(row(line.strip(), "", "phone-symbolic"))
        if on:
            group.add(button_row("Pair a phone", "", "list-add-symbolic", lambda: in_term("Pair a phone", "anarch-phone", "pair")))
            group.add(button_row("Make the phone ring", "To find it", "audio-volume-high-symbolic",
                                 lambda: tool("anarch-phone", "ring")))
            group.add(button_row("Turn off", "", "process-stop-symbolic", lambda: in_term("Phone", "anarch-phone", "off")))
        else:
            group.add(button_row("Set up", "Installs it and shows where to get the phone app", "list-add-symbolic",
                                 lambda: in_term("Phone link", "anarch-phone", "setup")))
        page.add(group)
        return page

    # --- Accessibility -------------------------------------------------------------------------
    def page_a11y(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        st = status_lines("anarch-a11y", "status")
        group = Adw.PreferencesGroup(title="Seeing and hearing")
        group.add(switch_row("Screen reader", "Reads out what's on screen (also ⊞ + Alt + R)",
                             st.get("Screen reader") == "on",
                             lambda on: tool("anarch-a11y", "reader", "on" if on else "off")))
        group.add(switch_row("High contrast", "Black and white with bright yellow", st.get("High contrast") == "on",
                             lambda on: tool("anarch-a11y", "contrast", "on" if on else "off")))
        group.add(switch_row("Reduce motion", "No window animations", st.get("Animations") == "off",
                             lambda on: tool("anarch-a11y", "motion", "reduce" if on else "normal")))
        sizes = ["normal", "big", "huge"]
        cur = st.get("Cursor size", "normal")
        group.add(combo_row("Pointer size", "", ["Normal", "Big", "Huge"], sizes.index(cur) if cur in sizes else 0,
                            lambda i: tool("anarch-a11y", "cursor", sizes[i])))
        text = Adw.ActionRow(title="Text size", subtitle=st.get("Text size", "100%"))
        for label, arg in (("Smaller", "smaller"), ("Bigger", "bigger"), ("Reset", "reset")):
            b = Gtk.Button(label=label, valign=Gtk.Align.CENTER)
            b.connect("clicked", lambda _b, a=arg: tool("anarch-a11y", "text", a))
            text.add_suffix(b)
        group.add(text)
        page.add(group)
        return page

    # --- Focus and wellbeing -------------------------------------------------------------------
    def page_wellbeing(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        focus = Adw.PreferencesGroup(title="Focus", description="No notifications, with a countdown in the top bar "
                                                                 "(also ⊞ + Ctrl + F).")
        for mins in (25, 50, 90):
            focus.add(button_row(f"Focus for {mins} minutes", "", "alarm-symbolic",
                                 lambda m=mins: tool("anarch-focus", str(m))))
        focus.add(button_row("Stop focusing", "", "process-stop-symbolic", lambda: tool("anarch-focus", "stop")))
        page.add(focus)
        st = Adw.PreferencesGroup(title="Screen time")
        st.add(button_row("Today and this week", "Time per app, with optional daily limits", "view-list-symbolic",
                          lambda: in_term("Screen time", "anarch-screentime", "week")))
        page.add(st)
        auto_on = out(lumen_cmd("anarch-auto")).startswith("Automatic light/dark: on")
        day = Adw.PreferencesGroup(title="Light and dark")
        day.add(switch_row("Light by day, dark at night", "Follows sunrise and sunset where you are, with night light",
                           bool(auto_on), lambda on: tool("anarch-auto", "on" if on else "off")))
        page.add(day)
        return page

    # --- Hardware and drivers ------------------------------------------------------------------
    def page_hardware(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        gfx = Adw.PreferencesGroup(title="Graphics")
        report = out(lumen_cmd("anarch-drivers"), timeout=10)
        rec = next((l for l in report.splitlines() if l.startswith(("Recommended", "✓ No NVIDIA"))), "")
        gfx.add(row("Graphics driver", rec or "Intel and AMD drivers are built in", "video-display-symbolic"))
        if not ok(lumen_cmd("anarch-drivers"), "check"):
            gfx.add(button_row("Install the recommended driver", "", "software-update-available-symbolic",
                               lambda: in_term("Graphics driver", "anarch-drivers", "install")))
        gfx.add(button_row("Details", "", "dialog-information-symbolic", lambda: in_term("Graphics", "anarch-drivers")))
        page.add(gfx)
        health = Adw.PreferencesGroup(title="Health")
        health.add(button_row("Health report", "Drives, filesystem, space, battery and temperatures",
                              "emblem-ok-symbolic", lambda: in_term("an4rch health", "anarch-health")))
        health.add(button_row("Free up space", "Old downloads of updates, caches, old Trash", "edit-clear-symbolic",
                              lambda: in_term("Tidy up", "anarch-tidy")))
        page.add(health)
        bat = Adw.PreferencesGroup(title="Battery")
        bat.add(switch_row("Stop charging at 80%", "So the battery lasts years longer (on laptops that support it)",
                           "80" in out(lumen_cmd("anarch-battery"), "limit"),
                           lambda on: in_term("Battery", "anarch-battery", "limit", "80" if on else "off")))
        page.add(bat)
        sb = Adw.PreferencesGroup(title="Secure Boot", description="Needed by some anti-cheat games and work laptops.")
        sb.add(button_row("Secure Boot", "Check it, or set it up with your own keys", "security-high-symbolic",
                          lambda: in_term("Secure Boot", "anarch-secureboot")))
        page.add(sb)
        return page


class SettingsApp(Adw.Application):
    def __init__(self, page: str):
        super().__init__(application_id="org.lumen.Settings", flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.page = page

    def do_activate(self):
        win = self.get_active_window()
        if win is None:
            win = Settings(self, self.page)
        elif self.page:
            win.show_page(self.page)
        win.present()


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    sys.exit(SettingsApp(args[0] if args else "look").run(sys.argv[:1]))
