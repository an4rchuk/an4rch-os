# Lumen

**A calm, keyboard-driven Linux desktop that is ready the moment you log in.**

Lumen turns a fresh Arch Linux install into a polished [Hyprland](https://hypr.land) desktop. It sets up a clean top bar, a launcher and menus for everything, themes that restyle the whole system at once, and the everyday tools already wired in: screenshots, screen recording, clipboard history, reminders, an emoji picker, a calculator, OCR and web apps. Wi-Fi, Bluetooth, audio, displays, sleep, login, fingerprint, printing, updates and installing apps are each one key away.

![Lumen's nine themes, each with its own generated wallpaper](docs/images/themes.jpg)
<sub>Mock-ups of the nine bundled themes, drawn on the wallpapers Lumen paints for each one at install time.</sub>

## Install

On a fresh [Arch Linux](https://wiki.archlinux.org/title/Installation_guide) install (`archinstall` with the *minimal* profile is ideal), logged in as your user:

```sh
curl -fsSL https://raw.githubusercontent.com/twil09/linux/main/boot.sh | bash
```

Answer three questions (browser, terminal, editor), wait a few minutes, then restart. Details and options: [Getting started](docs/01-getting-started.md).

## What you get

| | |
| --- | --- |
| **Desktop** | Hyprland 0.55+ with its new Lua config, run as a proper systemd session by uwsm. Gentle animations, blur, rounded corners, and a scrolling layout one key away |
| **Top bar** | Waybar: workspaces, window title, clock and calendar, reminders, media, privacy indicators, recording, toggles, tray, audio, Bluetooth, network, power profile, battery. Click anything to open its panel |
| **Launcher and menus** | fuzzel for apps, windows, the Lumen menu, Wi-Fi, displays, power, themes, wallpapers, clipboard and emoji: one consistent look everywhere |
| **Themes** | Nine palettes (Lumen, Tokyo Night, Catppuccin Mocha & Latte, Gruvbox, Nord, Rosé Pine, Everforest, Kanagawa). One key restyles borders, bar, menus, notifications, lock screen, terminal, prompt, `btop`, `fzf` and GTK apps. [Make your own](docs/03-themes.md#making-your-own-theme) in ten lines |
| **Wallpapers** | Original abstract wallpapers painted from each theme's colours on your machine (no downloads, no licensing questions), plus your own |
| **Everyday tools** | Screenshots with annotation, screen recording, clipboard history, reminders, emoji, calculator with units and currencies, colour picker, OCR, web search, web apps |
| **System** | Wi-Fi menu, Bluetooth, audio mixer and output switcher, display arrangement with automatic revert, power profiles, night light, idle and sleep, lock screen, login screen with keyring unlock, fingerprint, printing, firewall |
| **Apps** | Browser, terminal (Ghostty) and code editor of your choice, file manager, image viewer, video player, PDF viewer, plus a searchable installer for the repos, AUR and Flathub, and one-click bundles for development and gaming |
| **Shell** | zsh with autosuggestions, syntax highlighting, the starship prompt, zoxide, fzf, eza and bat |
| **Updates** | One key updates Lumen, packages, Flatpaks and firmware. Your config files are never overwritten |

## The keyboard in one minute

| Keys | |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SPACE</kbd> | Apps |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SPACE</kbd> | Lumen menu: everything else |
| <kbd>SUPER</kbd> + <kbd>/</kbd> | Searchable list of every key binding |
| <kbd>SUPER</kbd> + <kbd>Enter</kbd> / <kbd>B</kbd> / <kbd>E</kbd> / <kbd>C</kbd> | Terminal / browser / files / code editor |
| <kbd>SUPER</kbd> + <kbd>W</kbd> | Close window |
| <kbd>SUPER</kbd> + <kbd>1</kbd>…<kbd>0</kbd> | Workspaces (with <kbd>SHIFT</kbd>: take the window along) |
| <kbd>Print</kbd> | Screenshot a region |
| <kbd>SUPER</kbd> + <kbd>V</kbd> | Clipboard history |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>T</kbd> | Change theme |
| <kbd>SUPER</kbd> + <kbd>Esc</kbd> | Power menu |

The pattern: <kbd>SUPER</kbd> for apps and windows, <kbd>+SHIFT</kbd> to move and capture, <kbd>+CTRL</kbd> for system toggles and style, <kbd>+ALT</kbd> for setup panels. [All key bindings](docs/02-keybindings.md).

## The manual

| | |
| --- | --- |
| [Getting started](docs/01-getting-started.md) | Install, first login, the essentials |
| [Key bindings](docs/02-keybindings.md) | Every shortcut |
| [Themes and wallpapers](docs/03-themes.md) | Switching, wallpapers, making your own |
| [Customising](docs/04-customizing.md) | Where settings live, overriding defaults, Hyprland Lua recipes |
| [Built-in tools](docs/05-tools.md) | Screenshots, recording, clipboard, reminders, emoji, calculator, OCR, web apps |
| [System and hardware](docs/06-system.md) | Network, Bluetooth, audio, displays, sleep, login, fingerprint, printing, updates, apps |
| [Troubleshooting](docs/07-troubleshooting.md) | `lumen doctor`, logs, recovery |
| [How Lumen works](docs/08-architecture.md) | Architecture, theme engine, tests |

On the desktop: <kbd>SUPER</kbd> + <kbd>F1</kbd>, or `lumen manual` in a terminal.

## Principles

- **Your files are yours.** Lumen's defaults live in `~/.local/share/lumen` and load first. Your files in `~/.config` load after them and are never overwritten by updates.
- **Nothing strands you.** Display changes revert unless you confirm them, configs are backed up before replacement, and a broken theme or wallpaper falls back gracefully.
- **Every feature is a command.** `lumen help` lists them all, so you can bind, script or combine any of them.
- **Upstream formats.** Each app keeps its native config format, documented and commented, with no new configuration language on top.

## Development

```sh
tests/run.sh
```

checks the Hyprland Lua config against an API snapshot taken from Hyprland's source (unknown options, rule fields, dispatchers, events, duplicate bindings), renders every theme, runs shellcheck on every script, validates the Waybar config and generates sample wallpapers. See [How Lumen works](docs/08-architecture.md).

Built on [Hyprland](https://hypr.land), [uwsm](https://github.com/Vladimir-csp/uwsm), [Waybar](https://github.com/Alexays/Waybar), [fuzzel](https://codeberg.org/dnkl/fuzzel), [mako](https://github.com/emersion/mako), [Ghostty](https://ghostty.org), [greetd](https://sr.ht/~kennylevinsen/greetd/), [cliphist](https://github.com/sentriz/cliphist), [Satty](https://github.com/gabm/Satty) and the rest of the excellent Wayland ecosystem.
