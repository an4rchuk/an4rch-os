#!/usr/bin/env python3
"""An4rch sound panel — drops down from the volume icon in the top bar:
volume, mute, which speakers or headphones to use, the microphone, and
links to the full mixer and Sound settings.

It stays running hidden after the first open (like the Start menu), so
clicking the volume icon shows it at once. Click outside it or press Esc
to close it.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

try:  # Layer shell turns the window into a proper overlay on Wayland.
    gi.require_version("Gtk4LayerShell", "1.0")
    from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402
except (ValueError, ImportError):
    LayerShell = None

APP_ID = "org.lumen.Audio"
HOME = Path.home()
LUMEN_PATH = Path(os.environ.get("LUMEN_PATH", HOME / ".local/share/lumen"))
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "lumen"
THEME_CSS = CONFIG / "current/theme/apps.css"
STYLE_CSS = Path(__file__).with_name("style.css")


def out(*cmd: str) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=4).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def run(*cmd: str) -> None:
    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError as err:
        print(f"anarch-audio: {err}", file=sys.stderr)


def lumen(*argv: str) -> None:
    path = LUMEN_PATH / "bin" / argv[0]
    run(str(path) if path.exists() else argv[0], *argv[1:])


def devices(kind: str) -> list[tuple[str, str]]:
    """(name, description) for each sink or source; monitors left out."""
    try:
        data = json.loads(out("pactl", "-f", "json", "list", kind + "s") or "[]")
    except ValueError:
        return []
    return [(d["name"], d.get("description") or d["name"]) for d in data
            if not d.get("name", "").endswith(".monitor")]


def volume(kind: str) -> tuple[int, bool]:
    target = f"@DEFAULT_{kind.upper()}@"
    m = re.search(r"(\d+)%", out("pactl", f"get-{kind}-volume", target))
    return (int(m.group(1)) if m else 0), "yes" in out("pactl", f"get-{kind}-mute", target)


def volume_icon(level: int, muted: bool) -> str:
    if muted or level == 0:
        return "audio-volume-muted-symbolic"
    if level < 34:
        return "audio-volume-low-symbolic"
    if level < 67:
        return "audio-volume-medium-symbolic"
    return "audio-volume-high-symbolic"


class Channel(Gtk.Box):
    """Mute button, slider and percentage for the default output or input."""

    def __init__(self, kind: str, maximum: int):
        super().__init__(spacing=10, css_classes=["channel"])
        self.kind = kind
        self.updating = False
        self.mute = Gtk.Button(css_classes=["flat", "circular", "mute"], valign=Gtk.Align.CENTER)
        self.mute.connect("clicked", lambda *_: self.toggle_mute())
        self.scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, maximum, 1)
        self.scale.set_hexpand(True)
        self.scale.set_draw_value(False)
        if maximum > 100:
            self.scale.add_mark(100, Gtk.PositionType.BOTTOM, None)
        self.scale.connect("value-changed", self.on_value)
        self.label = Gtk.Label(width_chars=4, xalign=1, css_classes=["percent"])
        for w in (self.mute, self.scale, self.label):
            self.append(w)
        self.muted = False

    def refresh(self) -> None:
        level, self.muted = volume(self.kind)
        self.updating = True
        self.scale.set_value(level)
        self.updating = False
        self.show_state(level)

    def show_state(self, level: int) -> None:
        self.label.set_text(f"{level}%")
        if self.kind == "sink":
            self.mute.set_icon_name(volume_icon(level, self.muted))
        else:
            self.mute.set_icon_name("microphone-sensitivity-muted-symbolic" if self.muted
                                    else "audio-input-microphone-symbolic")
        self.mute.set_tooltip_text("Unmute" if self.muted else "Mute")

    def on_value(self, scale: Gtk.Scale) -> None:
        level = int(scale.get_value())
        self.show_state(level)
        if not self.updating:
            run("pactl", f"set-{self.kind}-volume", f"@DEFAULT_{self.kind.upper()}@", f"{level}%")

    def toggle_mute(self) -> None:
        self.muted = not self.muted
        run("pactl", f"set-{self.kind}-mute", f"@DEFAULT_{self.kind.upper()}@", "1" if self.muted else "0")
        self.show_state(int(self.scale.get_value()))


class SoundPanel(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application):
        super().__init__(application=app, title="Sound")
        self.set_decorated(False)
        self.add_css_class("anarch-audio")
        display = Gdk.Display.get_default()
        self.theme_css = Gtk.CssProvider()
        self.css = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(display, self.theme_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        Gtk.StyleContext.add_provider_for_display(display, self.css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)

        if LayerShell is not None and LayerShell.is_supported():
            LayerShell.init_for_window(self)
            LayerShell.set_namespace(self, "anarch-audio")
            LayerShell.set_layer(self, LayerShell.Layer.OVERLAY)
            for edge in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM, LayerShell.Edge.LEFT, LayerShell.Edge.RIGHT):
                LayerShell.set_anchor(self, edge, True)
            LayerShell.set_exclusive_zone(self, 0)  # below the top bar, over everything else
            LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.EXCLUSIVE)
        else:
            self.set_default_size(380, 420)

        # A clear backdrop over the rest of the screen: clicking it closes the panel.
        overlay = Gtk.Overlay()
        backdrop = Gtk.Box(css_classes=["backdrop"], hexpand=True, vexpand=True)
        click = Gtk.GestureClick()
        click.connect("released", lambda *_: self.close_panel())
        backdrop.add_controller(click)
        overlay.set_child(backdrop)

        self.panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, css_classes=["panel"],
                             halign=Gtk.Align.END, valign=Gtk.Align.START)
        self.panel.set_size_request(360, -1)
        self.panel.add_controller(Gtk.GestureClick())  # clicks inside don't reach the backdrop
        overlay.add_overlay(self.panel)
        self.set_child(overlay)

        self.panel.append(Gtk.Label(label="Sound", xalign=0, css_classes=["title"]))
        self.output = Channel("sink", 150)
        self.panel.append(self.output)
        self.panel.append(Gtk.Label(label="Play sound through", xalign=0, css_classes=["section"]))
        self.sinks = Gtk.ListBox(css_classes=["devices"], selection_mode=Gtk.SelectionMode.NONE)
        self.sinks.connect("row-activated", lambda _l, r: self.pick("sink", r.device))
        self.panel.append(self.sinks)

        self.mic_label = Gtk.Label(label="Microphone", xalign=0, css_classes=["section"])
        self.panel.append(self.mic_label)
        self.input = Channel("source", 100)
        self.panel.append(self.input)
        self.sources = Gtk.ListBox(css_classes=["devices"], selection_mode=Gtk.SelectionMode.NONE)
        self.sources.connect("row-activated", lambda _l, r: self.pick("source", r.device))
        self.panel.append(self.sources)

        footer = Gtk.Box(spacing=8, homogeneous=True, margin_top=6)
        for label, argv in (("Mixer", ["anarch-audio", "mixer"]), ("Sound settings", ["anarch-settings", "sound"])):
            b = Gtk.Button(label=label, css_classes=["footer-button"])
            b.connect("clicked", lambda _b, a=argv: (self.close_panel(), lumen(*a)))
            footer.append(b)
        self.panel.append(footer)

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self.on_key)
        self.add_controller(keys)

    def on_key(self, _c, keyval, _code, _state) -> bool:
        if keyval == Gdk.KEY_Escape:
            self.close_panel()
            return True
        step = {Gdk.KEY_Up: 5, Gdk.KEY_Right: 5, Gdk.KEY_Down: -5, Gdk.KEY_Left: -5}.get(keyval)
        if step:
            self.output.scale.set_value(self.output.scale.get_value() + step)
            return True
        if keyval in (Gdk.KEY_m, Gdk.KEY_M):
            self.output.toggle_mute()
            return True
        return False

    def load_css(self) -> None:
        if THEME_CSS.exists():
            self.theme_css.load_from_path(str(THEME_CSS))
        if STYLE_CSS.exists():
            self.css.load_from_path(str(STYLE_CSS))

    def fill(self, box: Gtk.ListBox, kind: str) -> None:
        while (child := box.get_first_child()) is not None:
            box.remove(child)
        default = out("pactl", f"get-default-{kind}")
        found = devices(kind)
        for name, desc in found:
            r = Gtk.ListBoxRow(css_classes=["device"])
            r.device = name
            line = Gtk.Box(spacing=10)
            icon = "audio-speakers-symbolic" if kind == "sink" else "audio-input-microphone-symbolic"
            if re.search(r"headphone|headset|bluez|bluetooth|usb", name + desc, re.I):
                icon = "audio-headphones-symbolic" if kind == "sink" else icon
            line.append(Gtk.Image.new_from_icon_name(icon))
            line.append(Gtk.Label(label=desc, xalign=0, hexpand=True, ellipsize=Pango.EllipsizeMode.END))
            if name == default:
                line.append(Gtk.Image.new_from_icon_name("object-select-symbolic"))
                r.add_css_class("current")
            r.set_child(line)
            box.append(r)
        box.set_visible(len(found) > 1 or kind == "sink")
        if not found and kind == "sink":
            r = Gtk.ListBoxRow(activatable=False)
            r.set_child(Gtk.Label(label="No sound devices found", xalign=0, css_classes=["dim"]))
            r.device = ""
            box.append(r)

    def pick(self, kind: str, name: str) -> None:
        if not name:
            return
        subprocess.run(["pactl", f"set-default-{kind}", name], capture_output=True, timeout=4, check=False)
        self.refresh()

    def refresh(self) -> None:
        self.output.refresh()
        self.input.refresh()
        self.fill(self.sinks, "sink")
        self.fill(self.sources, "source")
        has_input = self.sources.get_first_child() is not None
        self.input.set_visible(has_input)
        self.mic_label.set_visible(has_input)

    def open_panel(self) -> None:
        self.load_css()
        self.refresh()
        self.present()

    def close_panel(self) -> None:
        self.set_visible(False)

    def toggle(self) -> None:
        if self.get_visible():
            self.close_panel()
        else:
            self.open_panel()


class AudioApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.window: SoundPanel | None = None
        for name, cb in (("toggle", lambda *_: self.win().toggle()),
                         ("show", lambda *_: self.win().open_panel()),
                         ("hide", lambda *_: self.win().close_panel())):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", cb)
            self.add_action(action)

    def win(self) -> SoundPanel:
        if self.window is None:
            self.window = SoundPanel(self)
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
        elif "--show" in args:
            self.win().open_panel()
        else:
            self.win().toggle()
        return 0


if __name__ == "__main__":
    sys.exit(AudioApp().run(sys.argv))
