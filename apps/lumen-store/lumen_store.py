#!/usr/bin/env python3
"""an4rch App Store — find, install, update and remove apps.

One place for every source an4rch supports:
  * Arch repositories (pacman) — fast, integrated, updated with the system
  * Flathub (Flatpak)          — sandboxed apps straight from developers
  * AUR (yay)                  — community packages for everything else

A hand-picked catalogue (catalog.json) powers the Explore page; search also
covers all of Flathub and the Arch repositories. Descriptions and screenshots
come from Flathub's public API.
"""

from __future__ import annotations

import html
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import urllib.parse
import urllib.request
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, GObject, Gtk, Pango  # noqa: E402

APP_ID = "org.lumen.Store"
HOME = Path.home()
HERE = Path(__file__).resolve().parent
LUMEN_PATH = Path(os.environ.get("LUMEN_PATH", HOME / ".local/share/lumen"))
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "lumen"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "lumen/store"
THEME = CONFIG / "current/theme"
FLATHUB_API = "https://flathub.org/api/v2"
FLATHUB_ICON = "https://dl.flathub.org/repo/appstream/x86_64/icons/128x128/{}.png"
FLATHUB_REPO = "https://dl.flathub.org/repo/flathub.flatpakrepo"
SAFE_ID = re.compile(r"^[A-Za-z0-9@._+-]+$")

SOURCE_LABEL = {"pacman": "Arch repositories", "flatpak": "Flathub", "aur": "AUR (community)"}
SOURCE_HINT = {
    "pacman": "Built by Arch Linux, updated together with your system.",
    "flatpak": "Sandboxed and published by the developer on Flathub.",
    "aur": "Built on your computer from a community recipe. Review it if unsure.",
}


# --- small utilities -------------------------------------------------------------

def run(argv: list[str], timeout: int = 60) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as err:
        return subprocess.CompletedProcess(argv, 127, "", str(err))


def http_json(url: str, data: dict | None = None, timeout: int = 10):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json", "User-Agent": "lumen-store/1"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def cached_download(url: str, name: str) -> Path | None:
    """Download once into the cache; returns the local path or None."""
    path = CACHE / name
    if path.exists() and path.stat().st_size > 0:
        return path
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(url, headers={"User-Agent": "lumen-store/1"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read()
        tmp = path.with_suffix(".part")
        tmp.write_bytes(data)
        tmp.replace(path)
        return path
    except Exception:  # noqa: BLE001 - offline or missing: callers fall back
        return None


def in_thread(work, done=None):
    """Run `work()` in a thread and hand its result to `done()` on the UI thread."""
    def runner():
        try:
            result = work()
        except Exception as err:  # noqa: BLE001
            result = err
        if done is not None:
            GLib.idle_add(lambda: (done(result), False)[1])
    threading.Thread(target=runner, daemon=True).start()


def html_to_markup(text: str) -> str:
    """Flathub descriptions are simple HTML: turn them into Pango markup."""
    text = re.sub(r"\s+", " ", text or "")
    text = re.sub(r"<li>\s*", "\n•  ", text)
    text = re.sub(r"</p>|<br\s*/?>|</ul>|</ol>", "\n", text)
    text = re.sub(r"<p>", "\n", text)
    parts = re.split(r"(<em>|</em>|<code>|</code>)", text)
    out = []
    for part in parts:
        if part in ("<em>", "</em>"):
            out.append(part.replace("em", "i"))
        elif part in ("<code>", "</code>"):
            out.append(part.replace("code", "tt"))
        else:
            out.append(GLib.markup_escape_text(html.unescape(re.sub(r"<[^>]+>", "", part))))
    return re.sub(r"\n{3,}", "\n\n", "".join(out)).strip()


def fold(s: str) -> str:
    return s.lower()


# --- data model -----------------------------------------------------------------

class App:
    """One app, possibly available from several sources."""

    def __init__(self, data: dict):
        self.id: str = data["id"]
        self.name: str = data["name"]
        self.summary: str = data.get("summary", "")
        self.category: str = data.get("category", "")
        self.icon: str = data.get("icon", "")
        self.icon_url: str = data.get("icon_url", "")
        self.featured: bool = data.get("featured", False)
        self.sources: list[dict] = [s for s in data.get("sources", []) if SAFE_ID.match(s.get("id", ""))]

    def source(self, kind: str) -> str | None:
        return next((s["id"] for s in self.sources if s["type"] == kind), None)

    @property
    def flatpak_id(self) -> str | None:
        return self.source("flatpak")


def load_catalog() -> tuple[list[dict], list[App]]:
    data = json.loads((HERE / "catalog.json").read_text())
    user = CONFIG / "store-catalog.json"  # optional additions
    if user.exists():
        try:
            extra = json.loads(user.read_text())
            data["apps"].extend(extra.get("apps", []))
        except ValueError:
            pass
    return data["categories"], [App(a) for a in data["apps"]]


class Backend:
    """Knows what's installed and how to install or remove it."""

    def __init__(self):
        self.pkgs: set[str] = set()
        self.flatpaks: dict[str, str] = {}  # id -> installation (user/system)
        self.repo_has: dict[str, bool] = {}
        self.aur_helper = next((h for h in ("yay", "paru") if shutil.which(h)), None)
        self.has_flatpak = bool(shutil.which("flatpak"))
        self.has_pacman = bool(shutil.which("pacman"))

    def refresh(self) -> None:
        if self.has_pacman:
            self.pkgs = set(run(["pacman", "-Qq"]).stdout.split())
        self.has_flatpak = bool(shutil.which("flatpak"))
        if self.has_flatpak:
            out = run(["flatpak", "list", "--app", "--columns=application,installation"]).stdout
            self.flatpaks = dict(line.split("\t")[:2] for line in out.splitlines() if "\t" in line)

    def check_repos(self, names: list[str]) -> None:
        """Which pacman packages exist in the enabled repositories."""
        names = [n for n in names if n not in self.repo_has]
        if not names or not self.has_pacman:
            return
        out = run(["pacman", "-Si", *names], timeout=30).stdout
        found = set(re.findall(r"^Name\s*:\s*(\S+)", out, re.M))
        for n in names:
            self.repo_has[n] = n in found

    def available(self, src: dict) -> bool:
        if src["type"] == "pacman":
            return self.repo_has.get(src["id"], True)
        if src["type"] == "aur":
            return self.aur_helper is not None
        return True  # Flatpak itself can be installed on demand

    def installed_source(self, app: App) -> dict | None:
        for src in app.sources:
            if src["type"] in ("pacman", "aur") and src["id"] in self.pkgs:
                return src
            if src["type"] == "flatpak" and src["id"] in self.flatpaks:
                return src
        return None

    def install_cmds(self, src: dict) -> list[list[str]]:
        sid = src["id"]
        if src["type"] == "pacman":
            return [["pkexec", "pacman", "-S", "--needed", "--noconfirm", sid]]
        if src["type"] == "aur":
            return [[self.aur_helper or "yay", "-S", "--needed", "--noconfirm", "--sudo", "pkexec",
                     "--answerdiff", "None", "--answerclean", "None", "--removemake", sid]]
        cmds = []
        if not self.has_flatpak:
            cmds.append(["pkexec", "pacman", "-S", "--needed", "--noconfirm", "flatpak"])
        cmds.append(["flatpak", "remote-add", "--user", "--if-not-exists", "flathub", FLATHUB_REPO])
        cmds.append(["flatpak", "install", "--user", "-y", "--noninteractive", "flathub", sid])
        return cmds

    def remove_cmds(self, src: dict) -> list[list[str]]:
        sid = src["id"]
        if src["type"] in ("pacman", "aur"):
            return [["pkexec", "pacman", "-Rns", "--noconfirm", sid]]
        scope = "--system" if self.flatpaks.get(sid) == "system" else "--user"
        if scope == "--system":
            return [["pkexec", "flatpak", "uninstall", "--system", "-y", "--noninteractive", sid]]
        return [["flatpak", "uninstall", "--user", "-y", "--noninteractive", sid]]

    def execute(self, cmds: list[list[str]], on_line, on_done) -> None:
        """Run commands in order, streaming output lines; on_done(ok, last_lines)."""
        def work():
            tail: list[str] = []
            for argv in cmds:
                if "remote-add" in argv and not shutil.which("flatpak"):
                    continue
                try:
                    proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                            env={**os.environ, "LC_ALL": "C"})
                except OSError as err:
                    return False, [str(err)]
                for line in proc.stdout:
                    line = line.strip()
                    if line:
                        tail = (tail + [line])[-6:]
                        GLib.idle_add(on_line, line)
                if proc.wait() != 0:
                    return False, tail
            self.refresh()
            return True, tail

        in_thread(work, lambda res: on_done(*res) if isinstance(res, tuple) else on_done(False, [str(res)]))

    def launch(self, app: App, src: dict) -> None:
        desktop = None
        if src["type"] == "flatpak":
            argv = ["flatpak", "run", src["id"]]
        else:
            desktop = find_desktop_for_package(src["id"])
            argv = ["gtk-launch", desktop] if desktop else [src["id"]]
        launcher = LUMEN_PATH / "bin/lumen-launch"
        if launcher.exists():
            argv = [str(launcher), "--", *argv]
        subprocess.Popen(argv, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def find_desktop_for_package(pkg: str) -> str | None:
    out = run(["pacman", "-Qlq", pkg]).stdout.splitlines()
    for f in out:
        if f.startswith("/usr/share/applications/") and f.endswith(".desktop"):
            return Path(f).stem
    return None


# --- widgets --------------------------------------------------------------------

class IconLoader:
    """Theme icon when available, otherwise Flathub's icon, cached on disk."""

    def __init__(self):
        self.theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default())

    def apply(self, image: Gtk.Image, app: App, size: int) -> None:
        image.set_pixel_size(size)
        for name in filter(None, [app.icon, app.flatpak_id, app.source("pacman"), app.source("aur")]):
            if self.theme.has_icon(name):
                image.set_from_icon_name(name)
                return
        image.set_from_icon_name("application-x-executable")
        url = app.icon_url or (FLATHUB_ICON.format(app.flatpak_id) if app.flatpak_id else "")
        if url:
            name = f"icons/{app.flatpak_id or app.id}.png"
            in_thread(lambda: cached_download(url, name),
                      lambda path: image.set_from_file(str(path)) if isinstance(path, Path) else None)


class AppCard(Gtk.Button):
    def __init__(self, win: "StoreWindow", app: App):
        super().__init__(css_classes=["app-card", "card"])
        self.app = app
        box = Gtk.Box(spacing=14)
        icon = Gtk.Image()
        win.icons.apply(icon, app, 56)
        box.append(icon)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER, spacing=2, hexpand=True)
        text.append(Gtk.Label(label=app.name, xalign=0, ellipsize=Pango.EllipsizeMode.END, css_classes=["card-title"]))
        summary = Gtk.Label(label=app.summary, xalign=0, wrap=True, lines=2, ellipsize=Pango.EllipsizeMode.END,
                            css_classes=["card-summary"], max_width_chars=30)
        text.append(summary)
        if win.backend.installed_source(app):
            text.append(Gtk.Label(label="✓ Installed", xalign=0, css_classes=["installed-badge"]))
        box.append(text)
        self.set_child(box)
        self.connect("clicked", lambda *_: win.show_app(app))


class Carousel(Gtk.Box):
    """Featured apps that slide by on their own."""

    def __init__(self, win: "StoreWindow", apps: list[App]):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.carousel = Adw.Carousel(allow_scroll_wheel=False, spacing=16)
        for app in apps:
            slide = Gtk.Button(css_classes=["hero"], hexpand=True)
            box = Gtk.Box(spacing=28, margin_start=36, margin_end=36, margin_top=30, margin_bottom=30)
            icon = Gtk.Image()
            win.icons.apply(icon, app, 112)
            box.append(icon)
            text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER, spacing=6)
            text.append(Gtk.Label(label="EDITOR'S PICK", xalign=0, css_classes=["hero-kicker"]))
            text.append(Gtk.Label(label=app.name, xalign=0, css_classes=["hero-title"]))
            text.append(Gtk.Label(label=app.summary, xalign=0, wrap=True, css_classes=["hero-summary"]))
            box.append(text)
            slide.set_child(box)
            slide.connect("clicked", lambda _b, a=app: win.show_app(a))
            self.carousel.append(slide)
        self.append(self.carousel)
        self.append(Adw.CarouselIndicatorDots(carousel=self.carousel))
        GLib.timeout_add_seconds(6, self.advance)

    def advance(self) -> bool:
        n = self.carousel.get_n_pages()
        if n > 1 and self.get_mapped():
            nxt = (round(self.carousel.get_position()) + 1) % n
            self.carousel.scroll_to(self.carousel.get_nth_page(nxt), True)
        return True


# --- pages ----------------------------------------------------------------------

class DetailPage(Adw.NavigationPage):
    def __init__(self, win: "StoreWindow", app: App, remove: bool = False):
        super().__init__(title=app.name)
        self.win, self.app = win, app
        self.busy = False
        b = win.backend
        b.check_repos([s["id"] for s in app.sources if s["type"] == "pacman"])
        self.sources = [s for s in app.sources if b.available(s)] or app.sources

        view = Adw.ToolbarView()
        view.add_top_bar(Adw.HeaderBar())
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
        clamp = Adw.Clamp(maximum_size=920, margin_top=24, margin_bottom=36, margin_start=24, margin_end=24)
        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        clamp.set_child(body)
        scroll.set_child(clamp)
        view.set_content(scroll)
        self.set_child(view)

        # Header: icon, name, developer, actions.
        head = Gtk.Box(spacing=22)
        icon = Gtk.Image()
        win.icons.apply(icon, app, 112)
        head.append(icon)
        titles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER, spacing=4, hexpand=True)
        titles.append(Gtk.Label(label=app.name, xalign=0, css_classes=["title-1"], wrap=True))
        self.developer = Gtk.Label(label=app.summary, xalign=0, wrap=True, css_classes=["dim-label"])
        titles.append(self.developer)
        head.append(titles)

        actions = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, valign=Gtk.Align.CENTER)
        self.buttons = Gtk.Box(spacing=8, halign=Gtk.Align.END)
        actions.append(self.buttons)
        self.source_dd = Gtk.DropDown.new_from_strings([SOURCE_LABEL[s["type"]] for s in self.sources])
        self.source_dd.add_css_class("flat")
        self.source_dd.set_tooltip_text("Where to install it from")
        self.source_dd.connect("notify::selected", lambda *_: self.update_state())
        actions.append(self.source_dd)
        head.append(actions)
        body.append(head)

        self.progress_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, visible=False)
        self.progress = Gtk.ProgressBar(css_classes=["osd"])
        self.status = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END, css_classes=["dim-label", "caption"])
        self.progress_box.append(self.progress)
        self.progress_box.append(self.status)
        body.append(self.progress_box)

        self.hint = Gtk.Label(xalign=0, wrap=True, css_classes=["dim-label", "caption"])
        body.append(self.hint)

        # Screenshots and description from Flathub.
        self.shots = Adw.Carousel(spacing=16, visible=False, height_request=380)
        self.shots_dots = Adw.CarouselIndicatorLines(carousel=self.shots, visible=False)
        body.append(self.shots)
        body.append(self.shots_dots)
        self.description = Gtk.Label(xalign=0, wrap=True, use_markup=True, visible=False, css_classes=["description"])
        body.append(self.description)

        self.details = Adw.PreferencesGroup(title="Details")
        body.append(self.details)
        self.detail_rows: list[Gtk.Widget] = []

        # Prefer the source that's already installed.
        inst = b.installed_source(app)
        if inst in self.sources:
            self.source_dd.set_selected(self.sources.index(inst))
        self.update_state()
        self.fetch_metadata()
        if remove and inst:
            GLib.idle_add(lambda: (self.confirm_remove(), False)[1])

    def current(self) -> dict:
        return self.sources[self.source_dd.get_selected()]

    def update_state(self) -> None:
        while (child := self.buttons.get_first_child()) is not None:
            self.buttons.remove(child)
        installed = self.win.backend.installed_source(self.app)
        src = self.current()
        self.source_dd.set_sensitive(installed is None and not self.busy and len(self.sources) > 1)
        if self.busy:
            spinner = Gtk.Spinner(spinning=True)
            self.buttons.append(spinner)
        elif installed:
            open_b = Gtk.Button(label="Open", css_classes=["pill", "suggested-action"])
            open_b.connect("clicked", lambda *_: self.win.backend.launch(self.app, installed))
            rm = Gtk.Button(icon_name="user-trash-symbolic", tooltip_text="Remove", css_classes=["circular", "destructive-action"])
            rm.connect("clicked", lambda *_: self.confirm_remove())
            self.buttons.append(open_b)
            self.buttons.append(rm)
        else:
            inst = Gtk.Button(label="Install", css_classes=["pill", "suggested-action"])
            inst.connect("clicked", lambda *_: self.install())
            self.buttons.append(inst)
        shown = installed or src
        self.hint.set_label(f"{SOURCE_LABEL[shown['type']]} · {shown['id']}  —  {SOURCE_HINT[shown['type']]}")
        self.fill_details(shown)

    def fill_details(self, src: dict) -> None:
        for row in self.detail_rows:
            self.details.remove(row)
        self.detail_rows = []

        def add(title, value, link=None):
            row = Adw.ActionRow(title=title, subtitle=value, subtitle_selectable=True)
            if link:
                b = Gtk.Button(icon_name="adw-external-link-symbolic", valign=Gtk.Align.CENTER, css_classes=["flat"])
                b.connect("clicked", lambda *_: Gtk.UriLauncher.new(link).launch(self.win, None, None, None))
                row.add_suffix(b)
            self.details.add(row)
            self.detail_rows.append(row)

        add("Source", SOURCE_LABEL[src["type"]])
        add("Package", src["id"])
        meta = getattr(self, "meta", None) or {}
        if meta.get("developer_name"):
            add("Developer", meta["developer_name"])
        if meta.get("project_license"):
            add("License", meta["project_license"])
        homepage = (meta.get("urls") or {}).get("homepage")
        if homepage:
            add("Website", homepage, homepage)

    def fetch_metadata(self) -> None:
        fid = self.app.flatpak_id
        if not fid:
            return

        def work():
            return http_json(f"{FLATHUB_API}/appstream/{urllib.parse.quote(fid)}")

        def done(meta):
            if isinstance(meta, Exception) or not isinstance(meta, dict):
                return
            self.meta = meta
            if meta.get("developer_name"):
                self.developer.set_label(f"{self.app.summary}\nby {meta['developer_name']}")
            if meta.get("description"):
                self.description.set_markup(html_to_markup(meta["description"]))
                self.description.set_visible(True)
            self.fill_details(self.win.backend.installed_source(self.app) or self.current())
            urls = []
            for shot in (meta.get("screenshots") or [])[:6]:
                sizes = sorted(shot.get("sizes", []), key=lambda s: abs(int(s.get("width", 0) or 0) - 1248))
                if sizes:
                    urls.append(sizes[0]["src"])
            for i, url in enumerate(urls):
                pic = Gtk.Picture(content_fit=Gtk.ContentFit.CONTAIN, can_shrink=True, hexpand=True, css_classes=["shot"])
                self.shots.append(pic)
                name = f"shots/{fid}-{i}{Path(urllib.parse.urlparse(url).path).suffix or '.png'}"
                in_thread(lambda u=url, n=name: cached_download(u, n),
                          lambda p, pic=pic: pic.set_filename(str(p)) if isinstance(p, Path) else None)
            if urls:
                self.shots.set_visible(True)
                self.shots_dots.set_visible(len(urls) > 1)

        in_thread(work, done)

    def set_busy(self, busy: bool, text: str = "") -> None:
        self.busy = busy
        self.progress_box.set_visible(busy)
        self.status.set_label(text)
        if busy:
            GLib.timeout_add(120, self.pulse)
        self.update_state()

    def pulse(self) -> bool:
        if self.busy:
            self.progress.pulse()
        return self.busy

    def install(self) -> None:
        src = self.current()
        self.set_busy(True, f"Installing from {SOURCE_LABEL[src['type']]}…")
        self.win.backend.execute(self.win.backend.install_cmds(src), self.status.set_label,
                                 lambda ok, tail: self.finished(ok, tail, f"{self.app.name} is installed",
                                                                f"Couldn't install {self.app.name}"))

    def confirm_remove(self) -> None:
        inst = self.win.backend.installed_source(self.app)
        if not inst:
            return
        dialog = Adw.AlertDialog(heading=f"Remove {self.app.name}?",
                                 body="The app is removed from this computer. Your own files and documents are kept.")
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("remove", "Remove")
        dialog.set_response_appearance("remove", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")
        dialog.connect("response", lambda _d, r: r == "remove" and self.remove(inst))
        dialog.present(self.win)

    def remove(self, src: dict) -> None:
        self.set_busy(True, "Removing…")
        self.win.backend.execute(self.win.backend.remove_cmds(src), self.status.set_label,
                                 lambda ok, tail: self.finished(ok, tail, f"{self.app.name} was removed",
                                                                f"Couldn't remove {self.app.name}"))

    def finished(self, ok: bool, tail: list[str], ok_text: str, fail_text: str) -> None:
        self.set_busy(False)
        if ok:
            self.win.toast(ok_text)
        else:
            reason = next((l for l in reversed(tail) if "error" in l.lower()), tail[-1] if tail else "")
            if "dismissed" in reason.lower() or "not authorized" in reason.lower():
                reason = "Authentication was cancelled."
            self.win.toast(f"{fail_text}. {reason}"[:180])
        self.win.refresh_lists()


class StoreWindow(Adw.ApplicationWindow):
    def __init__(self, application: Adw.Application):
        super().__init__(application=application, title="App Store", default_width=1140, default_height=800)
        self.set_size_request(380, 500)
        self.backend = Backend()
        self.categories, self.apps = load_catalog()
        self.icons = IconLoader()
        self.search_seq = 0
        self.load_style()

        self.toasts = Adw.ToastOverlay()
        self.nav = Adw.NavigationView()
        self.toasts.set_child(self.nav)
        self.set_content(self.toasts)

        root_view = Adw.ToolbarView()
        header = Adw.HeaderBar()
        self.stack = Adw.ViewStack()
        switcher = Adw.ViewSwitcher(stack=self.stack, policy=Adw.ViewSwitcherPolicy.WIDE)
        header.set_title_widget(switcher)
        self.search_btn = Gtk.ToggleButton(icon_name="system-search-symbolic", tooltip_text="Search (Ctrl+F)")
        header.pack_start(self.search_btn)
        root_view.add_top_bar(header)

        self.search_bar = Gtk.SearchBar(show_close_button=False)
        self.search_entry = Gtk.SearchEntry(placeholder_text="Search apps and games", hexpand=True)
        clamp = Adw.Clamp(maximum_size=640, child=self.search_entry)
        self.search_bar.set_child(clamp)
        self.search_bar.connect_entry(self.search_entry)
        self.search_bar.set_key_capture_widget(self)
        self.search_btn.bind_property("active", self.search_bar, "search-mode-enabled",
                                      GObject.BindingFlags.BIDIRECTIONAL)
        self.search_entry.connect("search-changed", self.on_search)
        root_view.add_top_bar(self.search_bar)

        self.outer = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.outer.add_named(self.stack, "pages")
        self.results_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        self.outer.add_named(self.scrolled(self.results_box), "search")
        root_view.set_content(self.outer)
        self.nav.add(Adw.NavigationPage(title="App Store", child=root_view, tag="root"))

        self.explore_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=28)
        self.stack.add_titled_with_icon(self.scrolled(self.explore_box), "explore", "Explore", "starred-symbolic")
        self.installed_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        self.stack.add_titled_with_icon(self.scrolled(self.installed_box), "installed", "Installed", "object-select-symbolic")
        self.updates_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        page = self.stack.add_titled_with_icon(self.scrolled(self.updates_box), "updates", "Updates", "software-update-available-symbolic")
        self.updates_page = page
        self.stack.connect("notify::visible-child-name", self.on_page)

        self.explore_box.append(Adw.StatusPage(icon_name="system-software-install-symbolic", title="Loading…"))

        def work():
            self.backend.refresh()
            self.backend.check_repos([s["id"] for a in self.apps for s in a.sources if s["type"] == "pacman"])

        in_thread(work, lambda _r: (self.build_explore(), self.build_installed()))
        in_thread(self.count_updates, self.show_update_badge)

        keys = Gtk.ShortcutController()
        keys.add_shortcut(Gtk.Shortcut.new(Gtk.ShortcutTrigger.parse_string("<Control>f"),
                                           Gtk.CallbackAction.new(lambda *_: (self.search_btn.set_active(True), True)[1])))
        keys.add_shortcut(Gtk.Shortcut.new(Gtk.ShortcutTrigger.parse_string("<Control>q|<Control>w"),
                                           Gtk.CallbackAction.new(lambda *_: (self.close(), True)[1])))
        self.add_controller(keys)

    # --- helpers -----------------------------------------------------------------

    def load_style(self) -> None:
        display = Gdk.Display.get_default()
        for path, prio in ((THEME / "apps.css", 0), (HERE / "style.css", 1)):
            if path.exists():
                provider = Gtk.CssProvider()
                provider.load_from_path(str(path))
                Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + prio)
        mode = "dark"
        env = THEME / "theme.env"
        if env.exists():
            m = re.search(r'LUMEN_THEME_MODE="?(\w+)', env.read_text())
            mode = m.group(1) if m else mode
        Adw.StyleManager.get_default().set_color_scheme(
            Adw.ColorScheme.FORCE_LIGHT if mode == "light" else Adw.ColorScheme.FORCE_DARK)

    def scrolled(self, child: Gtk.Widget) -> Gtk.ScrolledWindow:
        clamp = Adw.Clamp(maximum_size=1080, margin_top=24, margin_bottom=36, margin_start=24, margin_end=24, child=child)
        return Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True, child=clamp)

    @staticmethod
    def clear(box: Gtk.Box) -> None:
        while (child := box.get_first_child()) is not None:
            box.remove(child)

    def toast(self, text: str) -> None:
        self.toasts.add_toast(Adw.Toast(title=GLib.markup_escape_text(text), timeout=5))

    def grid(self, apps: list[App]) -> Gtk.FlowBox:
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, homogeneous=True, max_children_per_line=3,
                           min_children_per_line=1, row_spacing=12, column_spacing=12)
        for app in apps:
            flow.append(AppCard(self, app))
        return flow

    def section(self, title: str, apps: list[App], more=None) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        head = Gtk.Box()
        head.append(Gtk.Label(label=title, xalign=0, hexpand=True, css_classes=["title-3"]))
        if more:
            b = Gtk.Button(label="See all", css_classes=["flat"])
            b.connect("clicked", lambda *_: more())
            head.append(b)
        box.append(head)
        box.append(self.grid(apps))
        return box

    # --- pages -------------------------------------------------------------------

    def build_explore(self) -> None:
        self.clear(self.explore_box)
        featured = [a for a in self.apps if a.featured]
        self.explore_box.append(Carousel(self, featured))

        chips = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=8, min_children_per_line=2,
                            column_spacing=8, row_spacing=8, homogeneous=True)
        for cat in self.categories:
            b = Gtk.Button(css_classes=["category-chip"])
            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            img = Gtk.Image.new_from_icon_name(cat["icon"])
            img.set_pixel_size(22)
            content.append(img)
            content.append(Gtk.Label(label=cat["name"]))
            b.set_child(content)
            b.connect("clicked", lambda _b, c=cat: self.show_category(c))
            chips.append(b)
        self.explore_box.append(chips)

        for cat in self.categories:
            apps = [a for a in self.apps if a.category == cat["id"]]
            apps.sort(key=lambda a: (not a.featured, a.name))
            self.explore_box.append(self.section(cat["name"], apps[:6], lambda c=cat: self.show_category(c)))

    def show_category(self, cat: dict) -> None:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        apps = sorted((a for a in self.apps if a.category == cat["id"]), key=lambda a: a.name)
        box.append(self.grid(apps))
        view = Adw.ToolbarView(content=self.scrolled(box))
        view.add_top_bar(Adw.HeaderBar())
        self.nav.push(Adw.NavigationPage(title=cat["name"], child=view))

    def show_app(self, app: App, remove: bool = False) -> None:
        self.nav.push(DetailPage(self, app, remove=remove))

    def build_installed(self) -> None:
        self.clear(self.installed_box)
        b = self.backend
        mine = [a for a in self.apps if b.installed_source(a)]
        group = Adw.PreferencesGroup(title="Apps from the store",
                                     description="Everything here can also be removed from the Start menu (right-click › Uninstall).")
        for app in sorted(mine, key=lambda a: a.name):
            group.add(self.installed_row(app, b.installed_source(app)))
        if not mine:
            group.add(Adw.ActionRow(title="Nothing yet", subtitle="Apps you install from the store appear here."))
        self.installed_box.append(group)

        known = {a.flatpak_id for a in self.apps}
        others = [fid for fid in b.flatpaks if fid not in known]
        if others:
            fgroup = Adw.PreferencesGroup(title="Other Flatpak apps")
            names = {}
            out = run(["flatpak", "list", "--app", "--columns=application,name"]).stdout
            for line in out.splitlines():
                if "\t" in line:
                    k, v = line.split("\t", 1)
                    names[k] = v
            for fid in sorted(others, key=lambda f: names.get(f, f).lower()):
                app = App({"id": fid, "name": names.get(fid, fid), "sources": [{"type": "flatpak", "id": fid}]})
                fgroup.add(self.installed_row(app, {"type": "flatpak", "id": fid}))
            self.installed_box.append(fgroup)

        note = Gtk.Label(wrap=True, xalign=0, css_classes=["dim-label", "caption"],
                         label="Command-line tools and system packages are managed with “anarch pkg” in a terminal.")
        self.installed_box.append(note)

    def installed_row(self, app: App, src: dict) -> Adw.ActionRow:
        row = Adw.ActionRow(title=GLib.markup_escape_text(app.name), subtitle=SOURCE_LABEL[src["type"]], activatable=True)
        icon = Gtk.Image()
        self.icons.apply(icon, app, 40)
        row.add_prefix(icon)
        open_b = Gtk.Button(label="Open", valign=Gtk.Align.CENTER, css_classes=["flat"])
        open_b.connect("clicked", lambda *_: self.backend.launch(app, src))
        row.add_suffix(open_b)
        row.connect("activated", lambda *_: self.show_app(app))
        return row

    def count_updates(self) -> dict:
        res = {"system": [], "flatpak": []}
        if shutil.which("checkupdates"):
            res["system"] = run(["checkupdates"], timeout=120).stdout.splitlines()
        if self.backend.aur_helper:
            res["system"] += run([self.backend.aur_helper, "-Qua"], timeout=120).stdout.splitlines()
        if shutil.which("flatpak"):
            out = run(["flatpak", "remote-ls", "--updates", "--app", "--columns=name,application"], timeout=120).stdout
            res["flatpak"] = [l for l in out.splitlines() if l.strip()]
        return res

    def show_update_badge(self, res) -> None:
        if not isinstance(res, dict):
            res = {"system": [], "flatpak": []}
        self.updates = res
        total = len(res["system"]) + len(res["flatpak"])
        self.updates_page.set_badge_number(total)
        self.updates_page.set_needs_attention(total > 0)
        self.build_updates()

    def build_updates(self) -> None:
        self.clear(self.updates_box)
        res = getattr(self, "updates", {"system": [], "flatpak": []})
        total = len(res["system"]) + len(res["flatpak"])
        if total == 0:
            self.updates_box.append(Adw.StatusPage(icon_name="emblem-ok-symbolic", title="You're up to date",
                                                   description="an4rch checks for updates every hour."))
            return
        status = Adw.StatusPage(icon_name="software-update-available-symbolic",
                                title=f"{total} update{'s' if total != 1 else ''} available",
                                description="A snapshot is taken first, so any update can be undone.")
        btn = Gtk.Button(label="Update everything", halign=Gtk.Align.CENTER, css_classes=["pill", "suggested-action"])
        btn.connect("clicked", lambda *_: self.run_tool(["lumen-update"]))
        status.set_child(btn)
        self.updates_box.append(status)
        for title, items in (("System and apps", res["system"]), ("Flatpak apps", res["flatpak"])):
            if not items:
                continue
            group = Adw.PreferencesGroup(title=title)
            for line in items[:200]:
                parts = line.split()
                name = parts[0] if parts else line
                sub = " ".join(parts[1:]).replace("->", "→")
                group.add(Adw.ActionRow(title=GLib.markup_escape_text(name), subtitle=GLib.markup_escape_text(sub)))
            self.updates_box.append(group)

    def run_tool(self, argv: list[str]) -> None:
        tool = LUMEN_PATH / "bin" / argv[0]
        cmd = [str(tool), *argv[1:]] if tool.exists() else argv
        subprocess.Popen(cmd, start_new_session=True)

    def refresh_lists(self) -> None:
        self.build_installed()
        if self.stack.get_visible_child_name() == "explore":
            self.build_explore()

    def on_page(self, *_):
        if self.stack.get_visible_child_name() == "updates":
            in_thread(self.count_updates, self.show_update_badge)

    # --- search ------------------------------------------------------------------

    def on_search(self, entry: Gtk.SearchEntry) -> None:
        query = entry.get_text().strip()
        self.search_seq += 1
        seq = self.search_seq
        if not query:
            self.outer.set_visible_child_name("pages")
            return
        self.outer.set_visible_child_name("search")
        self.clear(self.results_box)
        q = fold(query)
        cat_names = {c["id"]: fold(c["name"]) for c in self.categories}
        local = [a for a in self.apps
                 if q in fold(a.name) or q in fold(a.summary) or q in a.category or q in cat_names.get(a.category, "")]
        local.sort(key=lambda a: (not fold(a.name).startswith(q), a.name))
        if local:
            self.results_box.append(self.section("Recommended", local[:9]))

        flathub_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        repo_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.results_box.append(flathub_box)
        self.results_box.append(repo_box)
        flathub_box.append(Gtk.Spinner(spinning=True, halign=Gtk.Align.START))

        known_flatpaks = {a.flatpak_id for a in self.apps}
        known_pkgs = {s["id"] for a in self.apps for s in a.sources if s["type"] != "flatpak"}

        def flathub():
            data = http_json(f"{FLATHUB_API}/search", {"query": query, "hits_per_page": 18})
            return [h for h in data.get("hits", []) if h.get("app_id") not in known_flatpaks]

        def show_flathub(hits):
            if seq != self.search_seq:
                return
            self.clear(flathub_box)
            if isinstance(hits, Exception):
                flathub_box.append(Gtk.Label(label="Flathub can't be reached right now.", xalign=0, css_classes=["dim-label"]))
                return
            apps = [App({"id": h["app_id"], "name": h.get("name", h["app_id"]), "summary": h.get("summary", ""),
                         "icon_url": h.get("icon") or "", "sources": [{"type": "flatpak", "id": h["app_id"]}]})
                    for h in hits if SAFE_ID.match(h.get("app_id", ""))]
            if apps:
                flathub_box.append(self.section("From Flathub", apps))

        def repos():
            if not shutil.which("pacman"):
                return []
            out = run(["pacman", "-Ss", "--", query], timeout=20).stdout.splitlines()
            found = []
            for i in range(0, len(out) - 1, 2):
                m = re.match(r"^(\S+)/(\S+)\s", out[i])
                if m and m.group(2) not in known_pkgs:
                    found.append((m.group(2), out[i + 1].strip()))
            # Packages whose name matches come first.
            found.sort(key=lambda t: (q not in t[0].lower(), len(t[0])))
            return found[:12]

        def show_repos(found):
            if seq != self.search_seq or isinstance(found, Exception) or not found:
                return
            apps = [App({"id": f"pkg-{n}", "name": n, "summary": d, "icon": n, "sources": [{"type": "pacman", "id": n}]})
                    for n, d in found]
            repo_box.append(self.section("From the Arch repositories", apps))
            more = Gtk.Button(label="Search the AUR in a terminal…", halign=Gtk.Align.START, css_classes=["flat"])
            more.connect("clicked", lambda *_: self.run_tool(["lumen-pkg", "install"]))
            repo_box.append(more)

        in_thread(flathub, show_flathub)
        in_thread(repos, show_repos)

    def open_search(self, query: str) -> None:
        self.search_btn.set_active(True)
        self.search_entry.set_text(query)
        self.search_entry.set_position(-1)

    def open_uninstall(self, desktop_id: str) -> None:
        """Called from the Start menu's “Uninstall…”: find the owner of a launcher."""
        stem = desktop_id.removesuffix(".desktop")
        for app in self.apps:
            if app.flatpak_id == stem or app.source("pacman") == stem:
                self.show_app(app, remove=True)
                return
        if stem in self.backend.flatpaks:
            self.show_app(App({"id": stem, "name": stem, "sources": [{"type": "flatpak", "id": stem}]}), remove=True)
            return
        for base in ("/usr/share/applications", "/usr/local/share/applications"):
            path = Path(base) / desktop_id
            if path.exists():
                owner = run(["pacman", "-Qqo", str(path)]).stdout.strip()
                if owner:
                    app = next((a for a in self.apps if owner in (a.source("pacman"), a.source("aur"))), None)
                    app = app or App({"id": owner, "name": owner, "icon": stem, "sources": [{"type": "pacman", "id": owner}]})
                    self.show_app(app, remove=True)
                    return
        self.toast("This app wasn't installed from a package, so it can't be removed here.")


class StoreApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)

    def do_command_line(self, command_line):
        args = command_line.get_arguments()[1:]
        win = self.get_active_window() or StoreWindow(self)
        win.present()
        if "--search" in args and args.index("--search") + 1 < len(args):
            win.open_search(args[args.index("--search") + 1])
        elif "--uninstall" in args and args.index("--uninstall") + 1 < len(args):
            target = args[args.index("--uninstall") + 1]
            GLib.timeout_add(600, lambda: (win.open_uninstall(target), False)[1])
        elif "--updates" in args:
            win.stack.set_visible_child_name("updates")
        elif "--app" in args and args.index("--app") + 1 < len(args):
            wanted = args[args.index("--app") + 1]
            app = next((a for a in win.apps if a.id == wanted), None)
            if app:
                win.show_app(app)
        return 0


if __name__ == "__main__":
    sys.exit(StoreApp().run(sys.argv))
