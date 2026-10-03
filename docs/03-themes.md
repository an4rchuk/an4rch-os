# Themes and wallpapers

One palette styles the whole desktop: window borders, the bar, the launcher and menus, notifications, the lock screen, the terminal, `btop`, `fzf`, the shell prompt, and GTK apps (light or dark, with matching icons). Switching is instant and nothing needs restarting.

## Switching themes

- <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>T</kbd> opens the theme picker.
- <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>SHIFT</kbd> + <kbd>T</kbd> moves to the next theme.
- From a terminal: `lumen theme set nord`, `lumen theme list`, `lumen theme next`.

Bundled themes:

| Theme | Mood |
| --- | --- |
| `lumen` | The signature look: deep indigo night, violet and cyan light |
| `tokyo-night` | Neon city blues |
| `catppuccin-mocha` | Soft pastels on dark |
| `catppuccin-latte` | Soft pastels on light, the bundled light theme |
| `gruvbox` | Warm retro browns and yellows |
| `nord` | Arctic, muted blue-grey |
| `rose-pine` | Muted rose, gold and pine |
| `everforest` | Gentle forest greens |
| `kanagawa` | Ink-wash blues inspired by Hokusai |

## Wallpapers

Every theme comes with four original wallpapers painted from its own colours: *aurora*, *dunes*, *orbit* and *silk*. They're generated on your machine at install time and stored in `~/.local/share/backgrounds/lumen/<theme>/`.

- <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>W</kbd> shows the next wallpaper.
- <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>SHIFT</kbd> + <kbd>W</kbd> picks one from a list.
- `lumen wallpaper set ~/Pictures/photo.jpg` uses any image.

Lumen remembers the wallpaper you chose for each theme, so switching themes back and forth keeps your pick.

**Adding your own wallpapers:**

- Images in `~/Pictures/Wallpapers/` are offered with every theme.
- Images in `~/.config/lumen/backgrounds/<theme>/` are offered with that theme only.

To repaint the generated set (for example after editing a theme's colours), run `lumen wallpaper generate`. For a different resolution use `lumen-wallgen --all --size 2560x1440 --out ~/.local/share/backgrounds/lumen`.

## Making your own theme

```sh
lumen theme new sunrise        # copies the active theme to ~/.config/lumen/themes/sunrise
$EDITOR ~/.config/lumen/themes/sunrise/theme.conf
lumen theme set sunrise
```

You can also do this from the Lumen menu: **Style → Make my own theme**.

A theme is one small file of colours:

```ini
name        = Sunrise
mode        = dark          # dark or light: sets GTK apps and icons
bg          = #1b1720       # main background
bg_alt      = #231e2a       # panels, menus, notifications
bg_hl       = #352d3f       # selection, inactive borders
fg          = #f2e9e4       # text
fg_dim      = #9a8c98       # secondary text
accent      = #ff9e64       # active border, highlights
accent2     = #f6c177       # second accent (border gradient, matches)
red         = #eb6f92
orange      = #ff9e64
yellow      = #f6c177
green       = #9ccfd8
cyan        = #9ccfd8
blue        = #7aa2f7
purple      = #c4a7e7
```

Optional keys:

| Key | Default |
| --- | --- |
| `term_black`, `term_bright_black`, `term_white`, `term_bright_white` | Derived from `bg_hl`, `fg_dim` and `fg` |
| `gtk_theme` | `adw-gtk3-dark` / `adw-gtk3` by mode |
| `icon_theme` | `Papirus-Dark` / `Papirus-Light` by mode |
| `color_scheme` | `prefer-dark` / `prefer-light` by mode |

After editing, run `lumen theme render` to apply the changes.

### Overriding a single app

To hand-style one app, put a finished file in the theme's `overrides/` folder. It's used as-is instead of being generated:

```
~/.config/lumen/themes/sunrise/
├── theme.conf
├── overrides/
│   └── waybar.css          # replaces the generated waybar colours
└── backgrounds/            # optional: wallpapers that ship with the theme
```

The files a theme produces are listed below. They're rendered from `templates/*.tpl` into `~/.config/lumen/current/theme/`:

| File | Used by |
| --- | --- |
| `hyprland.lua` | Window borders and group colours |
| `waybar.css` | The top bar (`@define-color` variables) |
| `fuzzel.ini` | Launcher and every menu |
| `mako.ini` | Notifications |
| `hyprlock.conf` | Lock screen (`$bg`, `$fg`, `$accent`, … variables) |
| `ghostty.conf`, `alacritty.toml` | Terminals |
| `btop.theme` | System monitor |
| `fzf.sh` | Fuzzy finder colours in the shell |
| `starship.toml` | Shell prompt |
| `theme.env` | GTK theme, icon theme and colour scheme |

In templates, `{{accent}}` becomes `#9d8cff`, `{{accent.hex}}` becomes `9d8cff` and `{{accent.rgb}}` becomes `157, 140, 255`. This works for every palette key.

## Fonts

The interface uses **Inter**; terminals and code use **JetBrains Mono Nerd Font**, which also supplies the icons in the bar and menus. To change them:

- Terminal: `font-family` in `~/.config/ghostty/config`
- Bar: `font-family` at the top of `~/.config/waybar/style.css`
- Menus: `font=` in `~/.config/fuzzel/fuzzel.ini`
- Notifications: `font=` in `~/.config/mako/config`
- GTK apps: `gsettings set org.gnome.desktop.interface font-name 'Inter 11'`
