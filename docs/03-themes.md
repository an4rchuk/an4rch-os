# Themes and wallpapers

One palette styles the whole desktop: window borders, the bar, the launcher and menus, notifications, the lock screen, the terminal, `btop`, `fzf`, the shell prompt, and GTK apps (light or dark, with matching icons). Switching is instant and nothing needs restarting.

## Switching themes

- <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>T</kbd> opens the theme picker.
- <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>SHIFT</kbd> + <kbd>T</kbd> moves to the next theme.
- From a terminal: `anarch theme set ancom`, `anarch theme list`, `anarch theme next`.
- `anarch anarch` opens the picker too.

Fifteen themes come with an4rch: the signature look, its light version, one per school of anarchism (black with that school's colour, and wallpapers painted from its gradient), and high contrast.

| Theme | Look |
| --- | --- |
| `an4rch` | The signature look: black, with the red of the an4rch logo, and its own logo wallpapers |
| `an4rch-light` | The an4rch red on white: the light theme, and the one `anarch auto` uses by day |
| `ancom` | Anarcho-communism: black and red |
| `ansyn` | Anarcho-syndicalism: black and red with industrial grey |
| `mutualism` | Mutualism: black and orange |
| `individualist` | Individualist: black and steel |
| `ancap` | Anarcho-capitalism: black and yellow |
| `green-anarchism` | Green anarchism: black and green |
| `primitivism` | Anarcho-primitivism: earth and moss |
| `anfem` | Anarcha-feminism: black and purple |
| `pacifism` | Anarcho-pacifism: black and white |
| `queer` | Queer anarchism: black and pink |
| `insurrection` | Insurrectionary: black and ember |
| `no-adjectives` | Without adjectives: plain black |
| `high-contrast` | Black and white with bright yellow focus, for low vision (`anarch a11y contrast on`) |

The palettes from before 1.1.1 (Cachy, Tokyo Night, Catppuccin, Gruvbox, Nord, Rosé Pine, Everforest, Kanagawa and the violet an4rch) are retired: if you were using one, updating switched you to `an4rch` (or `an4rch-light` from Catppuccin Latte). A theme you made yourself in `~/.config/lumen/themes/` is never touched.

### Theme packs

More themes can come in packs added with one command (`anarch theme packs` lists them, `anarch theme get PACK` adds one, `anarch theme drop PACK` removes it). Packs live in `themes-extra/` in an4rch's folder; see its README to make one.

## Wallpapers

Every theme comes with nine original wallpapers painted from its own colours: five long, smooth gradients (*sweep* corner to corner, *glow* from a corner, *horizon*, *rise* and *mesh*) and four abstract ones (*aurora*, *dunes*, *orbit* and *silk*). They're painted on your machine the first time you use a theme and stored in `~/.local/share/backgrounds/lumen/<theme>/`.

A theme can set its own gradient, CSS-style, in its `theme.conf`:

```ini
gradient       = #0b0b0b 0%, #2a070d 40%, #7a0a1c 70%, #c8102e 100%
gradient_angle = 135
```

Without one, the gradient runs from the theme's background to its accent.

- <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>W</kbd> shows the next wallpaper.
- <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>SHIFT</kbd> + <kbd>W</kbd> picks one from a list.
- `anarch wallpaper set ~/Pictures/photo.jpg` uses any image.

an4rch remembers the wallpaper you chose for each theme, so switching themes back and forth keeps your pick.

**Adding your own wallpapers:**

- Images in `~/Pictures/Wallpapers/` are offered with every theme.
- Images in `~/.config/lumen/backgrounds/<theme>/` are offered with that theme only.

To repaint the generated set (for example after editing a theme's colours), run `anarch wallpaper generate` (every theme; takes a minute). For a different resolution use `anarch-wallgen --all --size 2560x1440 --out ~/.local/share/backgrounds/lumen`.

## Making your own theme

```sh
anarch theme new sunrise        # copies the active theme to ~/.config/lumen/themes/sunrise
$EDITOR ~/.config/lumen/themes/sunrise/theme.conf
anarch theme set sunrise
```

You can also do this from the an4rch menu: **Style → Make my own theme**.

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
| `accent_fg` | Text on accent-coloured buttons: `bg` (set it to a light colour for a dark accent) |
| `gradient`, `gradient_angle` | The wallpaper gradient (see [Wallpapers](#wallpapers)): `bg` to `accent`, 135° |

After editing, run `anarch theme render` to apply the changes.

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

## Installing someone else's theme

Themes can be shared as git repositories: `anarch theme install URL` downloads one and switches to it, and `anarch theme remove NAME` deletes it. See [Power tools](10-power-tools.md#sharing-themes-anarch-theme-install).

## Fonts

The interface uses **Inter**; terminals and code use **JetBrains Mono Nerd Font**, which also supplies the icons in the bar and menus. To change them:

- Terminal: `font-family` in `~/.config/ghostty/config`
- Bar: `font-family` at the top of `~/.config/waybar/style.css`
- Menus: `font=` in `~/.config/fuzzel/fuzzel.ini`
- Notifications: `font=` in `~/.config/mako/config`
- GTK apps: `gsettings set org.gnome.desktop.interface font-name 'Inter 11'`
