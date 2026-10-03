# How Lumen works

This chapter is for anyone changing Lumen itself, or curious how the pieces fit together.

## Repository layout

```
lumen/
├── boot.sh                 curl-able bootstrap: clone, then run install.sh
├── install.sh              the installer (nine idempotent steps)
├── install/
│   ├── lib.sh              output, spinners, package and config helpers
│   ├── packages.sh         package sets (required vs best-effort)
│   ├── migrate.sh          runs after updates: new configs + one-off migrations
│   └── migrations/         dated, run-once scripts
├── bin/                    every `lumen-*` command (bash; one Python tool)
├── lib/lumen.sh            shared shell library: paths, settings, menus, terminals
├── default/                Lumen-managed defaults, loaded before user config
│   ├── hypr/*.lua          Hyprland: env, looks, input, rules, binds, autostart
│   └── zsh/rc.zsh          shell defaults
├── config/                 the user's starting configs, copied to ~/.config once
├── themes/<name>/theme.conf   palettes
├── templates/*.tpl         per-app theme templates
├── docs/                   this manual
└── tests/                  test suite and the Hyprland API snapshot
```

## Defaults versus user config

`~/.config/hypr/hyprland.lua` requires `default/hypr/init.lua` from the checkout first, then the user's own files. Hyprland's Lua `hl.config()` calls merge, so later settings win key by key. Bindings can be removed with `hl.unbind()`. As a result:

- `lumen update` can change defaults without touching anything the user edited.
- A user file can be deleted to fall back to the defaults.
- The installer copies `config/` only on the first install. Later runs, and `migrate.sh`, add files that are missing but never replace existing ones.

Every other app follows the same pattern through its own include mechanism: Waybar `@import`, fuzzel and mako `include=`, ghostty `config-file`, hyprlock `source`, alacritty `import`. Each reads its colours from `~/.config/lumen/current/theme/`.

## The theme engine

`lumen-theme set NAME`:

1. reads `themes/NAME/theme.conf` (or `~/.config/lumen/themes/NAME/`) and derives missing values (terminal colours, GTK theme, icon theme);
2. renders every `templates/*.tpl` into `~/.config/lumen/current/theme.new/`, substituting `{{key}}`, `{{key.hex}}` and `{{key.rgb}}`; files in the theme's `overrides/` are copied instead;
3. swaps the new directory into place, so readers never see a half-written theme;
4. signals each app to reload (Hyprland, Waybar `SIGUSR2`, `makoctl reload`, Ghostty `SIGUSR2`), sets GTK preferences, and switches to the theme's remembered wallpaper.

To add support for a new app, drop a template in `templates/`. It's rendered for every theme automatically. Then point the app's config at `~/.config/lumen/current/theme/<file>`.

## Session start

Hyprland runs under [uwsm](https://github.com/Vladimir-csp/uwsm), so the session is a set of systemd units with a clean environment and clean shutdown. On `hyprland.start`, Lumen runs `lumen-session start`, which:

- renders a theme if none exists and restores the wallpaper (`swaybg`);
- starts Waybar, mako, hypridle and the clipboard watchers, each as its own systemd scope via `uwsm app`;
- starts the polkit agent;
- restores night light and Do Not Disturb;
- shows the welcome notification on the first login.

Apps launched from the launcher or key bindings go through `lumen-launch`, which uses `uwsm app` too. That way every app gets its own scope, and its logs land in `journalctl --user`.

## Menus

Every menu is fuzzel in dmenu mode, through the `menu`, `ask`, `ask_secret` and `confirm` helpers in `lib/lumen.sh`. Opening a menu while another is open closes it, so every menu hotkey doubles as a toggle. Bar modules are custom Waybar modules fed by `lumen-status`. Scripts refresh them instantly with real-time signals through `bar_signal` in `lib/lumen.sh`.

## Tests

```sh
tests/run.sh
```

runs on any Linux machine, without a GPU or Hyprland:

- **Hyprland config:** `tests/check-hypr-config.lua` loads the real config against a stub `hl` API generated from Hyprland's source (`tests/hypr-api.lua`). It rejects unknown options, window/layer/workspace rule fields, match properties, dispatchers, events, animation names and bind flags, and reports duplicate key bindings. It points at the exact file and line.
- **Themes:** every theme renders, with no unresolved placeholders.
- **Scripts:** `shellcheck` and `bash -n` on every shell script.
- **Waybar:** `config.jsonc` parses and every listed module has a config block.
- **Wallpapers:** the generator runs.

When Hyprland releases a new version, refresh the API snapshot:

```sh
git clone --depth 1 --branch v0.57.0 https://github.com/hyprwm/Hyprland /tmp/hl
python3 tests/gen-hypr-api.py /tmp/hl/src v0.57.0 > tests/hypr-api.lua
tests/run.sh
```

The key bindings chapter is generated from `default/hypr/binds.lua`:

```sh
lua tests/gen-keys-doc.lua . > docs/02-keybindings.md
```

## Design rules

- **One way to do each thing.** One launcher and menu system (fuzzel), one notification daemon (mako), one palette.
- **Never strand the user.** Display changes revert unless confirmed. Configs are backed up before replacement. A broken theme or missing wallpaper falls back gracefully. Hardware keys work on the lock screen.
- **Plain files.** Every setting is a readable file with comments. Every feature is a small command you can run, script or bind.
- **Upstream formats.** Lumen uses each tool's native config and documents it, rather than inventing its own layer on top.
