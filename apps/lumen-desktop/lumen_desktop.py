#!/usr/bin/env python3
"""anarch-desktop — icons on the desktop (top left, under the windows).

The icons are listed in ~/.config/lumen/desktop-icons.json:
    [{"id": "lumen-installer.desktop", "label": "Install An4rch OS"}, ...]
(an "id" is a .desktop file name; "label" is optional). The live USB shows
"Install An4rch OS" and the Welcome guide here. A single click opens an icon.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

try:
    gi.require_version("Gtk4LayerShell", "1.0")
    from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402
except (ValueError, ImportError):
    LayerShell = None

LUMEN_PATH = Path(os.environ.get("LUMEN_PATH", Path.home() / ".local/share/lumen"))
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lumen" / "desktop-icons.json"

CSS = b"""
window.anarch-desktop { background: transparent; }
.icon-button {
  background: transparent; border: none; border-radius: 12px; padding: 8px 6px;
  min-width: 96px; transition: background 120ms;
}
.icon-button:hover { background: alpha(white, 0.14); }
.icon-button:active { background: alpha(white, 0.24); }
.icon-label {
  color: white; font-weight: 600; font-size: 10.5pt;
  text-shadow: 0 1px 3px alpha(black, 0.9), 0 0 2px alpha(black, 0.8);
}
"""


def load_icons() -> list[dict]:
    try:
        data = json.loads(CONFIG.read_text())
    except (OSError, ValueError):
        return []
    out = []
    for item in data if isinstance(data, list) else []:
        if isinstance(item, str):
            item = {"id": item}
        if isinstance(item, dict) and item.get("id"):
            out.append(item)
    return out


def open_app(info: Gio.DesktopAppInfo) -> None:
    path = info.get_filename() or info.get_id()
    env = {**os.environ, "LUMEN_LAUNCH_NAME": info.get_display_name() or path}
    tool = LUMEN_PATH / "bin" / "anarch-launch"
    argv = [str(tool), "--", "gio", "launch", path] if tool.exists() else ["gio", "launch", path]
    try:
        subprocess.Popen(argv, start_new_session=True, env=env,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError as err:
        print(f"anarch-desktop: {err}", file=sys.stderr)


class Desktop(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application):
        super().__init__(application=app, title="an4rch desktop")
        self.add_css_class("anarch-desktop")
        if LayerShell is not None and LayerShell.is_supported():
            LayerShell.init_for_window(self)
            LayerShell.set_namespace(self, "anarch-desktop")
            # Above the wallpaper, below every window; out of the bars' way.
            LayerShell.set_layer(self, LayerShell.Layer.BOTTOM)
            LayerShell.set_anchor(self, LayerShell.Edge.TOP, True)
            LayerShell.set_anchor(self, LayerShell.Edge.LEFT, True)
            LayerShell.set_margin(self, LayerShell.Edge.TOP, 12)
            LayerShell.set_margin(self, LayerShell.Edge.LEFT, 12)
            LayerShell.set_exclusive_zone(self, 0)
            LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.NONE)
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.set_child(self.box)
        self.refresh()

    def refresh(self) -> None:
        while (child := self.box.get_first_child()) is not None:
            self.box.remove(child)
        for item in load_icons():
            try:
                info = Gio.DesktopAppInfo.new(item["id"])
            except TypeError:
                info = None
            if info is None:
                continue
            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            image = Gtk.Image.new_from_gicon(info.get_icon() or Gio.ThemedIcon.new("application-x-executable"))
            image.set_pixel_size(56)
            label = Gtk.Label(label=item.get("label") or info.get_display_name(), justify=Gtk.Justification.CENTER)
            label.set_wrap(True)
            label.set_max_width_chars(12)
            label.add_css_class("icon-label")
            content.append(image)
            content.append(label)
            button = Gtk.Button(child=content, tooltip_text=info.get_description() or None)
            button.add_css_class("icon-button")
            button.connect("clicked", lambda _b, i=info: open_app(i))
            self.box.append(button)


class DesktopApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.lumen.Desktop", flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.window: Desktop | None = None

    def do_startup(self) -> None:
        Gtk.Application.do_startup(self)
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        # Pick up changes to the icon list without a restart.
        self.monitor = Gio.File.new_for_path(str(CONFIG)).monitor_file(Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect("changed", lambda *_: self.window and GLib.idle_add(self.window.refresh))

    def do_activate(self) -> None:
        if self.window is None:
            self.window = Desktop(self)
        self.window.present()


if __name__ == "__main__":
    if "--check" in sys.argv:
        print(json.dumps(load_icons()))
        sys.exit(0)
    sys.exit(DesktopApp().run([sys.argv[0]]))
