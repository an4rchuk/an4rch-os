#!/usr/bin/env python3
"""an4rch's login screen. greetd starts it (in the cage kiosk compositor, as the
"greeter" user, through /usr/local/bin/lumen-greeter).

The clock at the top, the an4rch logo where the boot screen leaves it (the
background, drawn by `anarch-login sync`), and below it the user name and
password together: type the password, press Enter.

    lumen_greeter.py           log in through greetd ($GREETD_SOCK)
    lumen_greeter.py --demo    try it out: any password but "wrong" works
"""
from __future__ import annotations

import grp
import json
import os
import pwd
import subprocess
import sys
import threading
import time
from configparser import ConfigParser
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from greetd import Greetd, GreetdError, Result  # noqa: E402

LOGIN = Path(os.environ.get("LUMEN_LOGIN_DIR", "/var/lib/lumen/login"))
CACHE = Path(os.environ.get("LUMEN_GREETER_CACHE", "/var/cache/lumen-greeter"))
SESSION_DIRS = ["/usr/local/share/lumen/wayland-sessions", "/usr/share/wayland-sessions"]
DEFAULT_SESSION = ("an4rch", ["uwsm", "start", "--", "hyprland.desktop"])
DEMO = "--demo" in sys.argv


def people() -> list[tuple[str, str]]:
    """(login, display name) for every person on this computer."""
    found = []
    for p in pwd.getpwall():
        if 1000 <= p.pw_uid < 60000 and not p.pw_shell.endswith(("nologin", "false")):
            name = p.pw_gecos.split(",")[0].strip() or p.pw_name
            found.append((p.pw_name, name))
    return sorted(found)


def sessions() -> list[tuple[str, list[str]]]:
    """(name, command) for each desktop session; an4rch's own come first."""
    seen, found = set(), []
    for d in SESSION_DIRS:
        for f in sorted(Path(d).glob("*.desktop")) if Path(d).is_dir() else []:
            if f.name in seen:
                continue
            seen.add(f.name)
            cp = ConfigParser(interpolation=None)
            try:
                cp.read(f)
                entry = cp["Desktop Entry"]
            except (KeyError, OSError, ValueError):
                continue
            if entry.get("Hidden", "").lower() == "true" or entry.get("NoDisplay", "").lower() == "true":
                continue
            cmd = entry.get("Exec", "").split()
            if cmd:
                found.append((entry.get("Name", f.stem), cmd))
    return found or [DEFAULT_SESSION]


def remembered() -> dict:
    try:
        return json.loads((CACHE / "state.json").read_text())
    except (OSError, ValueError):
        return {}


# The desktop "crashed" when the login screen is back within this many
# seconds of starting it; twice in a row, it offers to undo the last update.
CRASH_SECONDS = 30


def crashes_so_far() -> int:
    state = remembered()
    started = state.get("started", 0)
    n = state.get("crashes", 0) + 1 if started and time.time() - started < CRASH_SECONDS else 0
    remember(crashes=n, started=0)
    return n


def remember(**kv) -> None:
    try:
        state = remembered() | kv
        CACHE.mkdir(parents=True, exist_ok=True)
        (CACHE / "state.json").write_text(json.dumps(state))
    except OSError:
        pass


class Greeter(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application):
        super().__init__(application=app, title="an4rch")
        self.people = people()
        self.sessions = sessions()
        self.crashes = 0 if DEMO and "--crashed" not in sys.argv else (2 if DEMO else crashes_so_far())
        self.state = remembered()
        self.greetd: Greetd | None = None
        self.busy = False
        self.pending_prompt = False

        display = Gdk.Display.get_default()
        mons = display.get_monitors() if display else None
        geo = mons.get_item(0).get_geometry() if mons and mons.get_n_items() else None
        self.W, self.H = (geo.width, geo.height) if geo else (1920, 1080)
        # Everything follows the screen: 1 on a 1080p screen.
        self.k = max(0.85, min(2.4, self.H / 1080))
        self.load_style()

        overlay = Gtk.Overlay()
        self.set_child(overlay)
        bg = Gtk.Picture()
        bg.set_content_fit(Gtk.ContentFit.COVER)
        if (LOGIN / "wallpaper").exists():
            bg.set_filename(str(LOGIN / "wallpaper"))
        bg.add_css_class("backdrop")
        overlay.set_child(bg)

        self.clock = Gtk.Label(css_classes=["clock"], halign=Gtk.Align.CENTER, valign=Gtk.Align.START)
        self.clock.set_margin_top(int(14 * self.k))
        overlay.add_overlay(self.clock)
        self.tick()
        GLib.timeout_add_seconds(5, self.tick)

        # The card sits under the logo (which ends at 42% of the height).
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=int(12 * self.k), css_classes=["card"],
                       halign=Gtk.Align.CENTER, valign=Gtk.Align.START)
        card.set_margin_top(int(self.H * 0.47))
        card.set_size_request(int(380 * self.k), -1)
        overlay.add_overlay(card)

        self.user = Gtk.Entry(placeholder_text="User name", css_classes=["field"])
        self.user.set_input_purpose(Gtk.InputPurpose.FREE_FORM)
        last = self.state.get("user") or (self.people[0][0] if len(self.people) == 1 else "")
        self.user.set_text(last)
        completion_names = [p[0] for p in self.people]
        if len(completion_names) > 1:
            self.user.set_tooltip_text("People on this computer: " + ", ".join(completion_names))
        self.user.connect("activate", lambda *_: self.password.grab_focus())
        self.user.connect("changed", lambda *_: self.who.set_label(self.display_name()))

        # The desktop didn't start, twice: offer the way back.
        if self.crashes >= 2:
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=int(8 * self.k), css_classes=["trouble"])
            box.append(Gtk.Label(label="The desktop didn't start.", css_classes=["who"]))
            box.append(Gtk.Label(label="If this began after an update, you can undo it: type an administrator's "
                                       "password below, then choose Undo update. Your files are kept.",
                                 wrap=True, justify=Gtk.Justification.CENTER, css_classes=["message"]))
            self.undo = Gtk.Button(label="Undo update", css_classes=["go"], halign=Gtk.Align.CENTER)
            self.undo.connect("clicked", self.undo_update)
            box.append(self.undo)
            card.append(box)

        self.who = Gtk.Label(css_classes=["who"])
        self.who.set_label(self.display_name())
        card.append(self.who)
        card.append(self.user)

        self.password = Gtk.PasswordEntry(placeholder_text="Password", show_peek_icon=True, css_classes=["field"])
        self.password.connect("activate", self.submit)
        card.append(self.password)

        self.message = Gtk.Label(css_classes=["message"], wrap=True, justify=Gtk.Justification.CENTER)
        self.message.set_visible(False)
        card.append(self.message)

        row = Gtk.Box(spacing=int(10 * self.k))
        if len(self.sessions) > 1:
            names = [s[0] for s in self.sessions]
            self.session = Gtk.DropDown.new_from_strings(names)
            want = self.state.get("session")
            if want in names:
                self.session.set_selected(names.index(want))
            self.session.set_tooltip_text("Desktop to start")
            row.append(self.session)
        else:
            self.session = None
        spacer = Gtk.Box(hexpand=True)
        row.append(spacer)
        self.go = Gtk.Button(label="Log in", css_classes=["suggested-action", "go"])
        self.go.connect("clicked", self.submit)
        row.append(self.go)
        card.append(row)

        power = Gtk.Box(spacing=int(10 * self.k), halign=Gtk.Align.END, valign=Gtk.Align.END)
        power.set_margin_end(int(18 * self.k))
        power.set_margin_bottom(int(16 * self.k))
        for label, cmd in (("Restart", ["systemctl", "reboot"]), ("Shut down", ["systemctl", "poweroff"])):
            b = Gtk.Button(label=label, css_classes=["power"])
            b.connect("clicked", lambda _b, c=cmd: self.power(c))
            power.append(b)
        overlay.add_overlay(power)

        (self.password if self.user.get_text() else self.user).grab_focus()

    # --- looks ---------------------------------------------------------------
    def load_style(self) -> None:
        provider = Gtk.CssProvider()
        here = Path(__file__).resolve().parent
        # Default colours, then the theme's (later definitions win), then the rules.
        css = (here / "colors.css").read_text()
        theme = LOGIN / "greeter.css"
        if theme.exists():
            css += "\n" + theme.read_text()
        css += "\n" + (here / "style.css").read_text()
        # Sizes scale with the screen (see self.k).
        k = self.k
        css += f"""
        window {{ font-size: {15 * k:.1f}px; }}
        .clock {{ font-size: {14 * k:.1f}px; padding: {6 * k:.0f}px {14 * k:.0f}px; border-radius: {12 * k:.0f}px; }}
        .card {{ padding: {22 * k:.0f}px; border-radius: {22 * k:.0f}px; }}
        .who {{ font-size: {18 * k:.1f}px; }}
        .field {{ min-height: {40 * k:.0f}px; border-radius: {12 * k:.0f}px; font-size: {15 * k:.1f}px; }}
        .go, .power, dropdown > button {{ min-height: {36 * k:.0f}px; border-radius: {12 * k:.0f}px; padding: 0 {16 * k:.0f}px; }}
        """
        provider.load_from_string(css) if hasattr(provider, "load_from_string") else provider.load_from_data(css.encode())
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def tick(self) -> bool:
        self.clock.set_label(GLib.DateTime.new_now_local().format("%A %-d %B   %H:%M"))
        return True

    def display_name(self) -> str:
        login = self.user.get_text().strip()
        for name, full in self.people:
            if name == login:
                return f"Welcome back, {full.split()[0]}" if full != name else "Welcome back"
        return "Welcome"

    def say(self, text: str, error: bool = True) -> None:
        self.message.set_label(text)
        self.message.set_visible(bool(text))
        (self.message.add_css_class if error else self.message.remove_css_class)("error")

    def set_busy(self, busy: bool) -> None:
        self.busy = busy
        for w in (self.user, self.password, self.go):
            w.set_sensitive(not busy)
        self.go.set_label("Logging in…" if busy else "Log in")

    # --- logging in ----------------------------------------------------------
    # --- undoing an update --------------------------------------------------
    def undo_update(self, *_):
        login, secret = self.user.get_text().strip(), self.password.get_text()
        if not login or not secret:
            self.say("Type an administrator's user name and password first.")
            return
        try:
            admins = grp.getgrnam("wheel").gr_mem
        except KeyError:
            admins = []
        if login not in admins:
            self.say(f"{login} isn't an administrator of this computer.")
            return
        self.set_busy(True)
        self.undo.set_sensitive(False)
        threading.Thread(target=self.undo_check, args=(login, secret), daemon=True).start()

    def undo_check(self, login: str, secret: str) -> None:
        try:
            if DEMO:
                result = Result(ok=secret != "wrong", error="Wrong password. Try again.")
            else:
                if self.greetd is None:
                    self.greetd = Greetd()
                result = self.greetd.login(login, secret)
                if result.ok:
                    self.greetd.cancel()      # the password is right; no session
        except (OSError, GreetdError, ValueError) as err:
            result = Result(error=f"The login service didn't answer ({err}).")
            self.greetd = None
        GLib.idle_add(self.undo_go, login, result)

    def undo_go(self, login: str, result: Result) -> bool:
        if not result.ok:
            self.set_busy(False)
            self.undo.set_sensitive(True)
            self.password.set_text("")
            self.say(result.error or "Couldn't confirm the password.")
            return False
        try:
            CACHE.mkdir(parents=True, exist_ok=True)
            (CACHE / "undo-request").write_text(f"user={login}\ntime={int(time.time())}\n")
        except OSError as err:
            self.set_busy(False)
            self.say(f"Couldn't ask for the undo ({err}).")
            return False
        remember(crashes=0)
        self.say("Undoing the last update… the computer restarts by itself in a minute.", error=False)
        return False

    def chosen_session(self) -> tuple[str, list[str]]:
        if self.session is None:
            return self.sessions[0]
        return self.sessions[self.session.get_selected()]

    def submit(self, *_):
        if self.busy:
            return
        login, secret = self.user.get_text().strip(), self.password.get_text()
        if not login:
            self.say("Type your user name.")
            self.user.grab_focus()
            return
        self.set_busy(True)
        self.say("")
        threading.Thread(target=self.authenticate, args=(login, secret), daemon=True).start()

    def authenticate(self, login: str, secret: str) -> None:
        try:
            if DEMO:
                import time
                time.sleep(0.6)
                result = Result(ok=secret != "wrong", error="" if secret != "wrong" else "Wrong password. Try again.")
            else:
                if self.greetd is None:
                    self.greetd = Greetd()
                result = self.greetd.answer(secret) if self.pending_prompt else self.greetd.login(login, secret)
        except (OSError, GreetdError, ValueError) as err:
            result = Result(error=f"The login service didn't answer ({err}).")
            self.greetd = None
        GLib.idle_add(self.finish, login, result)

    def finish(self, login: str, result: Result) -> bool:
        self.pending_prompt = False
        if result.ok:
            name, cmd = self.chosen_session()
            remember(user=login, session=name, started=time.time())
            if DEMO:
                self.say(f"Logged in: {name} would start now.", error=False)
                self.set_busy(False)
                return False
            try:
                self.greetd.start(cmd)
            except (OSError, GreetdError) as err:
                self.say(f"Couldn't start {name}: {err}")
                self.set_busy(False)
                return False
            self.get_application().quit()
            return False
        self.set_busy(False)
        if result.prompt:
            # A second question (another factor, a new password…).
            self.pending_prompt = True
            self.password.set_text("")
            self.say(result.prompt.text or "Answer:", error=False)
            self.password.grab_focus()
            return False
        self.say(" ".join(result.messages + [result.error]).strip())
        self.password.set_text("")
        self.password.grab_focus()
        return False

    def power(self, cmd: list[str]) -> None:
        if DEMO:
            self.say(" ".join(cmd) + " (demo)", error=False)
            return
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> int:
    app = Gtk.Application(application_id="os.an4rch.Greeter")

    def activate(app):
        win = Greeter(app)
        if not DEMO:
            win.fullscreen()
        else:
            win.set_default_size(1280, 720)
        win.present()

    app.connect("activate", activate)
    return app.run([sys.argv[0]])


if __name__ == "__main__":
    sys.exit(main())
