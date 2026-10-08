# How an4rch works

This chapter is for anyone changing an4rch itself, or curious how the pieces fit together.

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
├── apps/                   an4rch's own GTK 4 apps (Python + libadwaita)
│   ├── lumen-start/        the Start menu (layer-shell overlay, D-Bus toggled)
│   ├── lumen-store/        the App Store and its curated catalog.json
│   └── lumen-welcome/      the first-boot tour
├── iso/                    an4rch OS: archiso overlay, build.sh, the OS installer and rescue tool
├── system/                 OS-level files (fastfetch logo and layout)
├── share/                  .desktop launchers and icons for an4rch's apps
├── bin/                    every `anarch-*` command (bash; one Python tool), and the obsolete `lumen-*` names that forward to them
├── lib/lumen.sh            shared shell library: paths, settings, menus, terminals
├── default/                an4rch-managed defaults, loaded before user config
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

- `anarch update` can change defaults without touching anything the user edited.
- A user file can be deleted to fall back to the defaults.
- The installer copies `config/` only on the first install. Later runs, and `migrate.sh`, add files that are missing but never replace existing ones.

Every other app follows the same pattern through its own include mechanism: Waybar `@import`, fuzzel and mako `include=`, ghostty `config-file`, hyprlock `source`, alacritty `import`. Each reads its colours from `~/.config/lumen/current/theme/`.

## The theme engine

`anarch-theme set NAME`:

1. reads `themes/NAME/theme.conf` (or `~/.config/lumen/themes/NAME/`) and derives missing values (terminal colours, GTK theme, icon theme);
2. renders every `templates/*.tpl` into `~/.config/lumen/current/theme.new/`, substituting `{{key}}`, `{{key.hex}}` and `{{key.rgb}}`; files in the theme's `overrides/` are copied instead;
3. swaps the new directory into place, so readers never see a half-written theme;
4. signals each app to reload (Hyprland, Waybar `SIGUSR2`, `makoctl reload`, Ghostty `SIGUSR2`), sets GTK preferences, and switches to the theme's remembered wallpaper.

To add support for a new app, drop a template in `templates/`. It's rendered for every theme automatically. Then point the app's config at `~/.config/lumen/current/theme/<file>`.

## Session start

Hyprland runs under [uwsm](https://github.com/Vladimir-csp/uwsm), so the session is a set of systemd units with a clean environment and clean shutdown. On `hyprland.start`, an4rch runs `anarch-session start`, which:

- renders a theme if none exists and restores the wallpaper (`swaybg`);
- starts Waybar, mako, hypridle and the clipboard watchers, each as its own systemd scope via `uwsm app`;
- starts the polkit agent;
- restores night light and Do Not Disturb;
- shows the welcome notification on the first login.

Apps launched from the launcher or key bindings go through `anarch-launch`, which uses `uwsm app` too. That way every app gets its own scope, and its logs land in `journalctl --user`.

## an4rch OS

`iso/build.sh` copies Arch's official `releng` archiso profile and layers `iso/airootfs/` on top: the installer (`anarch-os-install`, a `gum` TUI), `anarch-rescue`, an auto-start on tty1, and a full copy of this repository at `/opt/lumen`. The profile is renamed and the boot menus rebranded. Because releng is copied at build time, the ISO keeps up with upstream archiso.

The installer partitions (1 GB ESP plus btrfs, optionally inside LUKS2), creates the `@`, `@home`, `@log`, `@pkg` and `@snapshots` subvolumes, and `pacstrap`s a base system with both kernels. It configures a systemd-based initramfs (`plymouth` and `sd-encrypt` hooks) and systemd-boot. Then it runs `install.sh --distro` as the new user inside the chroot. `install/distro.sh` adds the OS layer: os-release branding (with a pacman hook so `filesystem` upgrades keep it), Plymouth, zram, multilib, paccache and snapper.

fstab mounts subvolumes **by name, not ID**, which is what makes rollbacks work. `anarch-snapshot restore` renames `@` to `@broken-<date>`, snapshots the chosen snapshot into a new `@`, and reinstalls that snapshot's kernel version from the `@pkg` cache into `/boot`. That last step keeps the kernel on the ESP matching the restored system's `/usr/lib/modules`.

## Start menu and App Store

Both are Python + GTK 4 apps that take their colours from `apps.css`, rendered by the theme engine like every other app.

- **Start** runs as a hidden `Gtk.Application` (`org.lumen.Start`). Tapping Super runs `anarch-start`, which activates the app's `toggle` action over D-Bus with `gdbus`, so no Python starts per tap. With gtk4-layer-shell it's a full-screen overlay below the bar, whose backdrop closes it on click. The Hyprland bind is `hl.bind("SUPER + SUPER_L", …, { release = true })`. Hyprland shadows release binds while another bound key is pressed, so Super shortcuts never open Start.
- **The App Store** keeps a curated `catalog.json` (name, category and an ordered list of `pacman`/`flatpak`/`aur` sources). Repo availability is checked with one `pacman -Si` call. Installs run `pkexec pacman`, `flatpak --user` or `yay --sudo pkexec`, with output streamed to a progress bar. Screenshots and descriptions come from Flathub's `/api/v2/appstream/{id}`, and search uses `/api/v2/search`. Everything is cached under `~/.cache/lumen/store`.

## Menus

Every menu is fuzzel in dmenu mode, through the `menu`, `ask`, `ask_secret` and `confirm` helpers in `lib/lumen.sh`. Opening a menu while another is open closes it, so every menu hotkey doubles as a toggle. Bar modules are custom Waybar modules fed by `anarch-status`. Scripts refresh them instantly with real-time signals through `bar_signal` in `lib/lumen.sh`.

## Tests

```sh
tests/run.sh
```

runs on any Linux machine, without a GPU or Hyprland:

- **Hyprland config:** `tests/check-hypr-config.lua` loads the real config against a stub `hl` API generated from Hyprland's source (`tests/hypr-api.lua`). It rejects unknown options, window/layer/workspace rule fields, match properties, dispatchers, events, animation names and bind flags, and reports duplicate key bindings. It points at the exact file and line.
- **Themes:** every theme renders, with no unresolved placeholders.
- **Scripts:** `shellcheck` and `bash -n` on every shell script.
- **Waybar:** `config.jsonc` parses and every listed module has a config block.
- **an4rch apps:** Python compiles, the store catalogue validates, and the Start menu, App Store and Welcome each launch and render headlessly under Xvfb.
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
- **Upstream formats.** an4rch uses each tool's native config and documents it, rather than inventing its own layer on top.
