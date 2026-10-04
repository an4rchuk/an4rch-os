# Customising

The quickest way is the **Settings** app (<kbd>SUPER</kbd> + <kbd>I</kbd>, or Start → Settings): theme and wallpaper, the top bar and taskbar, title bars, the window layout, night light, gaps, borders, rounded corners, animations, blur, shadows and transparency, sound devices, Wi-Fi and Bluetooth, displays, keyboard repeat, pointer speed and touchpad behaviour, power and sleep, default apps, and system information. Window and input choices are saved to `~/.config/lumen/desktop.lua`; everything below goes further by hand.

Lumen keeps two kinds of files apart:

- **Lumen's defaults** live in `~/.local/share/lumen` (a git checkout). `lumen update` replaces them, so don't edit them.
- **Your files** live in `~/.config`. They're loaded *after* the defaults, so anything you set there wins. Updates never overwrite them.

## Where things live

| What | File |
| --- | --- |
| Preferred apps, capture folders, night-light warmth, idle suspend | `~/.config/lumen/settings.conf` |
| Displays | `~/.config/hypr/monitors.lua` (or <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>D</kbd>) |
| Keyboard layout, touchpad, mouse | `~/.config/hypr/input.lua` |
| Gaps, borders, blur, animations | `~/.config/hypr/looks.lua` |
| Your key bindings | `~/.config/hypr/bindings.lua` |
| Your window rules | `~/.config/hypr/rules.lua` |
| Apps started at login | `~/.config/hypr/autostart.lua` |
| Idle, dimming, lock and sleep timers | `~/.config/hypr/hypridle.conf` |
| Lock screen layout | `~/.config/hypr/hyprlock.conf` |
| Top bar modules and style | `~/.config/waybar/config.jsonc`, `style.css` |
| Launcher and menus | `~/.config/fuzzel/fuzzel.ini` |
| Notifications | `~/.config/mako/config` |
| Terminal | `~/.config/ghostty/config` |
| Session environment variables | `~/.config/uwsm/env` |
| Shell | `~/.zshrc` (Lumen's defaults are in `default/zsh/rc.zsh`) |

Hyprland, Waybar's style and the theme files reload by themselves when you save. For other changes:

| After changing | Run |
| --- | --- |
| Waybar modules | `lumen-session restart bar` |
| Notifications | `makoctl reload` |
| `hypridle.conf` | `lumen-session restart idle` |
| `settings.conf` | nothing, it's read every time a command runs |
| `uwsm/env` | log out and back in |

## settings.conf

```sh
LUMEN_TERMINAL=ghostty        # ghostty, alacritty, kitty, foot
LUMEN_BROWSER=firefox         # any browser command
LUMEN_EDITOR=code             # code, zed, nvim, helix, …
LUMEN_FILES=nautilus          # nautilus, thunar, "lumen-term -- yazi"
LUMEN_SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
LUMEN_RECORDING_DIR="$HOME/Videos/Recordings"
LUMEN_NIGHTLIGHT_TEMP=4300    # lower is warmer
LUMEN_IDLE_SUSPEND=always     # always | battery | never (after 30 idle minutes)
LUMEN_OCR_LANG=eng            # tesseract languages, e.g. eng+deu
LUMEN_SEARCH_URL="https://duckduckgo.com/?q="
```

**Lumen menu → Setup → Default apps** changes the first four for you and also updates which browser opens links.

## Hyprland in Lua

Hyprland 0.55 and later is configured in **Lua**, and Lumen uses that format. A few patterns cover most needs.

**Change options:**

```lua
-- ~/.config/hypr/looks.lua
hl.config({
    general    = { gaps_in = 3, gaps_out = 6, border_size = 3 },
    decoration = { rounding = 6, blur = { enabled = false } },
})
```

**Add or replace key bindings:**

```lua
-- ~/.config/hypr/bindings.lua
hl.unbind("SUPER + B")                                   -- drop a Lumen default
hl.bind("SUPER + B", hl.dsp.exec_cmd("lumen-launch -- chromium"), { description = "Chromium" })
hl.bind("SUPER + O", hl.dsp.exec_cmd("lumen-launch -- obsidian"), { description = "Notes" })
hl.bind("SUPER + U", hl.dsp.exec_cmd("lumen-webapp https://web.whatsapp.com"), { description = "WhatsApp" })
```

The `description` is what <kbd>SUPER</kbd> + <kbd>/</kbd> shows. Bindings can run Lua too:

```lua
hl.bind("SUPER + CTRL + C", function()
    hl.dispatch(hl.dsp.window.float({ action = "set" }))
    hl.dispatch(hl.dsp.window.resize({ x = 1200, y = 800 }))
    hl.dispatch(hl.dsp.window.center())
end, { description = "Float, size and centre" })
```

**Window rules** (find classes with `lumen doctor windows` or `hyprctl clients`):

```lua
-- ~/.config/hypr/rules.lua
hl.window_rule({ match = { class = "^(spotify)$" }, workspace = "9 silent" })
hl.window_rule({ match = { class = "^(org.gnome.Calculator)$" }, float = true, size = { 400, 600 } })
hl.window_rule({ match = { class = "^(com.mitchellh.ghostty)$" }, opacity = "0.94 0.9" })
```

**Start apps at login:**

```lua
-- ~/.config/hypr/autostart.lua
hl.on("hyprland.start", function()
    hl.exec_cmd("lumen-launch -- signal-desktop --start-in-tray")
end)
```

Apps with an XDG autostart entry (`~/.config/autostart/*.desktop`, what most apps create with a "start at login" checkbox) are started automatically.

**Keyboard layouts:** **Lumen menu → Setup → Keyboard layout**, or edit `input.lua`:

```lua
hl.config({ input = { kb_layout = "us,de", kb_options = "compose:ralt,grp:alt_shift_toggle" } })
```

Lumen also exposes a small helper table for your Lua files: `lumen.cmd("screenshot", "region")` gives the absolute path of a Lumen command, and `lumen.theme.accent` is the current theme's accent colour (hex, no `#`).

Full reference: <https://wiki.hypr.land/configuring/>. Hyprland reports config errors in a banner at the top of the screen, and `hyprctl configerrors` lists them.

## The top bar

`~/.config/waybar/config.jsonc` lists the modules on the left, centre and right. Remove a name from `modules-right` to hide it. `style.css` styles every module as a soft pill and gets its colours from the theme via `@define-color` (`@bg`, `@fg`, `@accent`, …).

Lumen's own modules show status from `lumen-status` and refresh instantly when something changes:

| Module | Shows |
| --- | --- |
| `custom/recording` | A pulsing **REC** pill while recording; click to stop |
| `custom/reminders` | Pending reminders next to the clock |
| `custom/idle` | Coffee cup while *keep awake* is on |
| `custom/nightlight` | Moon while the night light is on |
| `custom/dnd` | Bell while Do Not Disturb is on |
| `custom/updates` | Number of pending updates, checked hourly |

## The shell

Lumen sets up **zsh** with autosuggestions, syntax highlighting, a fast history search, the **starship** prompt and **zoxide** (`cd` learns your folders: `cd proj` jumps to `~/code/project`). There are a few handy aliases:

| Alias | Runs |
| --- | --- |
| `ls`, `ll`, `la`, `lt` | `eza` with icons, git status and a tree view |
| `cat` | `bat` with syntax highlighting |
| `ff` | Fuzzy-find a file with preview |
| `install` / `uninstall` | `lumen-pkg add` / `lumen-pkg rm` |
| `update` | `lumen-update` |
| <kbd>CTRL</kbd> + <kbd>R</kbd> | Fuzzy history search |
| <kbd>CTRL</kbd> + <kbd>T</kbd> | Insert a file path |
| <kbd>ALT</kbd> + <kbd>C</kbd> | Jump into a sub-folder |

Put your own settings at the bottom of `~/.zshrc`. Prefer bash? `chsh -s /bin/bash`; Lumen's commands don't depend on zsh.
