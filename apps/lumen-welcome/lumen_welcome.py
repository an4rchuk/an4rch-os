#!/usr/bin/env python3
"""an4rch Welcome — the first-boot tour: pick a look, set up the essentials,
learn the keys. Opens on first login; reopen it from the Start menu."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

HOME = Path.home()
LUMEN_PATH = Path(os.environ.get("LUMEN_PATH", HOME / ".local/share/lumen"))
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "lumen"
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "lumen"
HERE = Path(__file__).resolve().parent
# Running from the an4rch OS USB stick (archiso), not an installed system.
LIVE = Path("/run/archiso").exists()


def tool(*argv: str) -> None:
    path = LUMEN_PATH / "bin" / argv[0]
    cmd = [str(path), *argv[1:]] if path.exists() else list(argv)
    try:
        subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError as err:
        print(f"lumen-welcome: {err}", file=sys.stderr)


def read_theme(path: Path) -> dict[str, str]:
    data = {}
    for line in path.read_text().splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            data[k.strip()] = v.strip().split()[0] if v.strip() else ""
    data["name"] = next((l.split("=", 1)[1].strip() for l in path.read_text().splitlines() if l.strip().startswith("name")), path.parent.name)
    return data


def themes() -> list[tuple[str, dict]]:
    found = {}
    for root in (LUMEN_PATH / "themes", CONFIG / "themes"):
        if root.is_dir():
            for d in sorted(root.iterdir()):
                if (d / "theme.conf").is_file():
                    found[d.name] = read_theme(d / "theme.conf")
    return list(found.items())


class Welcome(Adw.ApplicationWindow):
    def __init__(self, app: Adw.Application):
        super().__init__(application=app, title="Welcome to an4rch", default_width=820, default_height=640)
        self.load_style()
        view = Adw.ToolbarView()
        header = Adw.HeaderBar(show_title=False)
        view.add_top_bar(header)

        self.carousel = Adw.Carousel(allow_scroll_wheel=False, interactive=True, vexpand=True)
        dots = Adw.CarouselIndicatorDots(carousel=self.carousel, margin_bottom=14)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(self.carousel)
        box.append(dots)
        view.set_content(box)
        self.set_content(view)

        self.carousel.append(self.page_hello())
        self.carousel.append(self.page_look())
        self.carousel.append(self.page_essentials())
        self.carousel.append(self.page_tips())
        self.carousel.append(self.page_learn())

        # LUMEN_WELCOME_PAGE opens straight at a page (used by the docs screenshots).
        start = int(os.environ.get("LUMEN_WELCOME_PAGE", "0") or 0)
        if start:
            GLib.idle_add(lambda: (self.carousel.scroll_to(self.carousel.get_nth_page(start), False), False)[1])

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self.on_key)
        self.add_controller(keys)

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

    def go(self, delta: int) -> None:
        n = round(self.carousel.get_position()) + delta
        if 0 <= n < self.carousel.get_n_pages():
            self.carousel.scroll_to(self.carousel.get_nth_page(n), True)

    def on_key(self, _c, keyval, _code, _state) -> bool:
        if keyval in (Gdk.KEY_Right, Gdk.KEY_Page_Down):
            self.go(1)
            return True
        if keyval in (Gdk.KEY_Left, Gdk.KEY_Page_Up):
            self.go(-1)
            return True
        if keyval == Gdk.KEY_Escape:
            self.close()
            return True
        return False

    def nav(self, back=True, next_label="Next", on_next=None) -> Gtk.Box:
        row = Gtk.Box(spacing=12, halign=Gtk.Align.CENTER, margin_top=18)
        if back:
            b = Gtk.Button(label="Back", css_classes=["pill"])
            b.connect("clicked", lambda *_: self.go(-1))
            row.append(b)
        n = Gtk.Button(label=next_label, css_classes=["pill", "suggested-action"])
        n.connect("clicked", lambda *_: (on_next or (lambda: self.go(1)))())
        row.append(n)
        return row

    def page(self, title: str, subtitle: str, child: Gtk.Widget | None, nav: Gtk.Widget, icon: str | None = None) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, valign=Gtk.Align.CENTER,
                      margin_start=40, margin_end=40, margin_bottom=10)
        if icon:
            img = Gtk.Image.new_from_icon_name(icon)
            img.set_pixel_size(112)
            box.append(img)
        box.append(Gtk.Label(label=title, css_classes=["title-1"], wrap=True, justify=Gtk.Justification.CENTER))
        box.append(Gtk.Label(label=subtitle, css_classes=["dim-label", "welcome-sub"], wrap=True,
                             justify=Gtk.Justification.CENTER, max_width_chars=60))
        if child is not None:
            child.set_margin_top(18)
            box.append(child)
        box.append(nav)
        clamp = Adw.Clamp(maximum_size=680, child=box, hexpand=True)
        return Gtk.ScrolledWindow(child=clamp, hscrollbar_policy=Gtk.PolicyType.NEVER, hexpand=True, vexpand=True)

    # --- pages ---------------------------------------------------------------------

    def page_hello(self) -> Gtk.Widget:
        return self.page(
            "Welcome to an4rch",
            "A calm, fast desktop that's ready for work and play. Let's make it yours — it only takes a minute.",
            None, self.nav(back=False, next_label="Get started"), icon="lumen-logo")

    def page_look(self) -> Gtk.Widget:
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=3, min_children_per_line=2,
                           homogeneous=True, row_spacing=10, column_spacing=10)
        css = []
        for slug, t in themes():
            for key in ("bg", "accent", "accent2", "red", "yellow", "green"):
                css.append(f".sw-{slug}-{key} {{ background: {t.get(key, '#888888')}; }}")
        provider = Gtk.CssProvider()
        provider.load_from_string("\n".join(css)) if hasattr(provider, "load_from_string") else provider.load_from_data("\n".join(css).encode())
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 2)
        for slug, t in themes():
            b = Gtk.Button(css_classes=["theme-tile"])
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            swatches = Gtk.Box(spacing=4, halign=Gtk.Align.CENTER)
            for key in ("bg", "accent", "accent2", "red", "yellow", "green"):
                sw = Gtk.Box(css_classes=["swatch", f"sw-{slug}-{key}"])
                sw.set_size_request(20, 20)
                swatches.append(sw)
            inner.append(swatches)
            inner.append(Gtk.Label(label=t.get("name", slug)))
            b.set_child(inner)
            b.connect("clicked", lambda _b, s=slug: (tool("lumen-theme", "set", s), GLib.timeout_add(700, self.reload_style)))
            flow.append(b)
        return self.page("Pick a look", "Themes restyle everything at once: windows, bar, menus, terminal and apps. "
                         "Change it any time with Super + Ctrl + T.", flow, self.nav())

    def reload_style(self) -> bool:
        self.load_style()
        return False

    def page_essentials(self) -> Gtk.Widget:
        group = Adw.PreferencesGroup()

        def row(title, subtitle, icon, argv):
            r = Adw.ActionRow(title=title, subtitle=subtitle, activatable=True)
            r.add_prefix(Gtk.Image.new_from_icon_name(icon))
            r.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))
            r.connect("activated", lambda *_: tool(*argv))
            group.add(r)

        row("Connect to Wi-Fi", "Or click the network icon in the top bar", "network-wireless-symbolic", ["lumen-wifi"])
        row("Set up gaming", "Steam, Proton, GameMode, MangoHud and drivers in one go", "input-gaming-symbolic", ["lumen-gaming"])
        row("Get apps", "Browse the App Store: Flathub, Arch and the AUR in one place", "system-software-install-symbolic", ["lumen-store"])
        row("Fingerprint login", "Unlock with your finger, if your laptop has a reader", "fingerprint-symbolic", ["lumen-term", "--float", "--hold", "--", "lumen-setup", "fingerprint"])
        row("Printers", "Find printers on your network", "printer-symbolic", ["lumen-setup", "printing"])
        row("Snapshots", "Every update can be undone — see how", "document-revert-symbolic", ["lumen-snapshot", "menu"])
        return self.page("Set up the essentials", "Everything here is also in the Start menu and the an4rch menu.",
                         group, self.nav())

    def page_tips(self) -> Gtk.Widget:
        group = Adw.PreferencesGroup()
        tips = [
            ("emblem-system-symbolic", "Make it yours in Settings",
             "Press ⊞ + I (or Start → Settings): themes, wallpaper, the taskbar, window gaps and corners, "
             "effects, mouse and touchpad, sound, power and default apps."),
            ("software-update-available-symbolic", "Keep it up to date",
             "Click the update icon in the top bar, or press ⊞ + Alt + U. an4rch takes a snapshot first."),
            ("document-revert-symbolic", "Every update can be undone",
             "If something breaks after an update, pick an older snapshot in the boot menu, "
             "or run lumen-rescue from the USB stick."),
            ("network-wireless-symbolic", "Wi-Fi and Bluetooth",
             "Click their icons in the top bar, or press ⊞ + Alt + W and ⊞ + Alt + B."),
            ("audio-volume-high-symbolic", "Sound",
             "Click the volume icon for the sound panel (volume, speakers or headphones, microphone); scroll on it to change the volume."),
            ("battery-good-symbolic", "Battery life",
             "⊞ + Ctrl + P switches between power saver, balanced and performance."),
            ("view-grid-symbolic", "Windows tile by themselves",
             "Drag with ⊞ held to move one; ⊞ + T lets a window float, ⊞ + W closes it."),
            ("computer-symbolic", "Also have Windows?",
             "The menu at start-up picks an4rch or Windows. If a Windows update makes Windows start straight away, "
             "press Esc (ASUS), F9 (HP) or F12 (Dell, Lenovo) at power-on and pick Linux Boot Manager, or move it "
             "to the top of the boot order in the BIOS."),
            ("system-search-symbolic", "Something not working?",
             "Open a terminal (⊞ + Enter) and run: anarch doctor. It checks the system and suggests fixes. For Wi-Fi, Bluetooth or graphics problems, anarch doctor hardware lists your chips, drivers and any errors."),
        ]
        if LIVE:
            tips.insert(0, ("drive-removable-media-symbolic", "You're running from the USB stick",
                            "Apps open more slowly than they will once an4rch is installed, and nothing you "
                            "change here is kept. Use the installer when you're ready."))
        for icon, title, sub in tips:
            r = Adw.ActionRow(title=title, subtitle=sub)
            r.add_prefix(Gtk.Image.new_from_icon_name(icon))
            group.add(r)
        return self.page("Good to know", "A few tips that make an4rch easier to live with.", group, self.nav())

    def page_learn(self) -> Gtk.Widget:
        grid = Gtk.Grid(column_spacing=18, row_spacing=10, halign=Gtk.Align.CENTER)
        tips = [
            ("⊞", "Tap the Windows key", "Start menu: apps, search, power"),
            ("⊞ + Space", "Quick launcher", "Type a few letters, press Enter"),
            ("⊞ + Alt + Space", "an4rch menu", "Every setting and tool"),
            ("⊞ + /", "All shortcuts", "Searchable list"),
            ("⊞ + A", "App Store", "Install apps and games"),
            ("Print", "Screenshot", "Drag to select, then annotate"),
        ]
        for i, (keys, title, sub) in enumerate(tips):
            k = Gtk.Label(label=keys, css_classes=["keycap"], xalign=0.5)
            grid.attach(k, 0, i, 1, 1)
            texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            texts.append(Gtk.Label(label=title, xalign=0, css_classes=["heading"]))
            texts.append(Gtk.Label(label=sub, xalign=0, css_classes=["dim-label"]))
            grid.attach(texts, 1, i, 1, 1)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        box.append(grid)
        startup = Gtk.CheckButton(label="Show this window when I log in", halign=Gtk.Align.CENTER)
        startup.set_active(not (STATE / "welcome-done").exists())
        startup.connect("toggled", self.on_startup_toggle)
        box.append(startup)
        manual = Gtk.Button(label="Open the manual", css_classes=["flat"], halign=Gtk.Align.CENTER)
        manual.connect("clicked", lambda *_: tool("lumen-manual"))
        box.append(manual)
        return self.page("You're all set", "The Windows key is your home base. A few more to remember:",
                         box, self.nav(next_label="Start using an4rch", on_next=self.finish))

    def on_startup_toggle(self, check: Gtk.CheckButton) -> None:
        STATE.mkdir(parents=True, exist_ok=True)
        flag = STATE / "welcome-done"
        if check.get_active():
            flag.unlink(missing_ok=True)
        else:
            flag.touch()

    def finish(self) -> None:
        STATE.mkdir(parents=True, exist_ok=True)
        (STATE / "welcome-done").touch()
        self.close()


class WelcomeApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="org.lumen.Welcome", flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_activate(self):
        (self.get_active_window() or Welcome(self)).present()


if __name__ == "__main__":
    sys.exit(WelcomeApp().run(sys.argv))
