# Getting started

There are two ways to get an4rch:

- **An4rch OS**: boot the installer ISO and it sets up the whole computer, including disk encryption, snapshots and the boot loader. See [An4rch OS](09-lumen-os.md).
- **On an existing Arch install**: the steps below. You get the same desktop, Start menu, App Store and tools on top of the system you already have.

## What you need

- A computer with a fresh [Arch Linux](https://wiki.archlinux.org/title/Installation_guide) install. `archinstall` with the **minimal** profile is perfect. Arch-based distributions (EndeavourOS, CachyOS) work too.
- A normal user account with `sudo` rights (the `wheel` group).
- An internet connection. On a fresh install, Wi-Fi is connected with `iwctl` (`station wlan0 connect "Network name"`).
- About 6 GB of free disk space.

Any Intel, AMD or recent NVIDIA (Turing / GTX 16-series or newer) graphics card works. The installer detects the GPU and installs the right drivers.

## Installing

Log in as your user on the text console and run:

```sh
curl -fsSL https://raw.githubusercontent.com/an4rchuk/an4rch-os/HEAD/boot.sh | bash
```

This clones An4rch to `~/.local/share/lumen` and starts the installer. If you'd rather look first:

```sh
git clone https://github.com/an4rchuk/an4rch-os ~/.local/share/lumen
~/.local/share/lumen/install.sh
```

The installer asks three questions (browser, terminal, code editor), then works through nine steps. Each step logs its output to `~/.local/state/lumen/install.log`.

| Step | What happens |
| --- | --- |
| Checking this computer | Arch, sudo, internet and disk space |
| Choosing your apps | Browser, terminal and editor; everything else is chosen for you |
| Preparing the package manager | Parallel downloads, a full system update, the `yay` AUR helper |
| Installing the desktop | Hyprland and its tools, audio, networking, fonts, GPU drivers |
| Installing your apps and tools | Your choices plus screenshot, recording, OCR and media tools |
| Writing configuration | Configs into `~/.config`, anything already there is backed up first |
| Setting up system services | NetworkManager, Bluetooth, firewall, power profiles, login screen |
| Styling | Fonts, cursor, default apps, the theme, and wallpapers painted for every theme |
| Finishing up | A summary and an offer to restart |

Useful options (pass them after `bash -s --` when piping, e.g. `… | bash -s -- --yes`):

| Option | Effect |
| --- | --- |
| `--yes` | Accept all defaults, no questions |
| `--browser chromium` | Pick the browser up front (`firefox`, `chromium`, `brave`, `zen-browser`) |
| `--terminal alacritty` | `ghostty`, `alacritty` or `kitty` |
| `--editor zed` | `code`, `zed` or `nvim` |
| `--theme ancom` | Start with a different theme |
| `--autologin` | Skip the login screen. Only sensible with full-disk encryption |
| `--no-greeter` | No login screen; logging in on the first console starts the desktop |
| `--gaming` | Also install the gaming stack (Steam, Proton tools, GameMode, MangoHud) |
| `--distro` | Apply the An4rch OS system layer (branding, snapshots, boot splash, zram) |
| `--configs-only` | Refresh configs and styling without touching packages |

The installer is safe to run again. Packages already installed are skipped. On later runs your configs are only added when missing, never overwritten.

## The first login

After the restart you'll see the login screen. Sign in, and the **Welcome** tour opens: pick a theme, connect Wi-Fi, set up gaming, get apps, and learn the keys. Reopen it any time from Start.

The top bar, from left to right:

- **󰣇** opens Start (right-click opens the An4rch menu).
- **Workspace dots.** Click one to switch, scroll to move through them.
- **The active window's title.**
- **Clock** in the centre. Hover for a calendar, scroll it to change month. Pending reminders show next to it.
- **Status icons:** screen sharing or microphone in use, recording, media playing, *keep awake*, night light, Do Not Disturb, available updates.
- **Background apps** behind the 󰅁 arrow.
- **Volume, Bluetooth, network, power profile, battery and power.** Click any of them to open its panel.

## Ten keys worth learning first

| Keys | Does |
| --- | --- |
| <kbd>SUPER</kbd> (tap) | Start menu |
| <kbd>SUPER</kbd> + <kbd>A</kbd> | App Store |
| <kbd>SUPER</kbd> + <kbd>Enter</kbd> | Terminal |
| <kbd>SUPER</kbd> + <kbd>B</kbd> | Browser |
| <kbd>SUPER</kbd> + <kbd>W</kbd> | Close the window |
| <kbd>SUPER</kbd> + <kbd>1</kbd> … <kbd>0</kbd> | Go to a workspace (add <kbd>SHIFT</kbd> to take the window along) |
| <kbd>SUPER</kbd> + arrows | Move focus (add <kbd>SHIFT</kbd> to move the window) |
| <kbd>SUPER</kbd> + <kbd>T</kbd> | Float / tile the window |
| <kbd>Print</kbd> | Screenshot a region |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SPACE</kbd> | The An4rch menu |
| <kbd>SUPER</kbd> + <kbd>/</kbd> | All key bindings |

## How tiling works

New windows split the space with the window that has focus, so you rarely move or resize anything by hand.

- <kbd>SUPER</kbd> + <kbd>J</kbd> flips a split between side-by-side and stacked.
- <kbd>SUPER</kbd> + <kbd>R</kbd> enters resize mode (arrow keys, <kbd>Esc</kbd> to leave). You can also drag window edges, or hold <kbd>SUPER</kbd> and right-drag.
- <kbd>SUPER</kbd> + <kbd>G</kbd> groups windows into tabs. <kbd>SUPER</kbd> + <kbd>[</kbd> / <kbd>]</kbd> switch between them.
- <kbd>SUPER</kbd> + <kbd>S</kbd> shows the **scratchpad**, a hidden workspace that slides over the current one. It's a good place for a music player or notes.
- <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>S</kbd> switches to the **scrolling** layout: windows sit side by side on an endless strip, like niri or PaperWM.

## Title bars, window buttons and a taskbar

Every window has a title bar with **close**, **maximise/restore** and **minimise** buttons (right to left). Double-click the bar to maximise, drag it to move a floating window. Minimised windows wait out of sight: bring one back with <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>M</kbd>, or from the taskbar. <kbd>SUPER</kbd> + <kbd>,</kbd> minimises from the keyboard.

The **taskbar** along the bottom of the screen is on by default; turn it off or on again from An4rch menu → Toggle → *Taskbar at the bottom* (or `anarch taskbar off` / `on`). Click an app to switch to it, click the active one to minimise it, middle-click to close it.

Prefer the opposite, a clean edge-to-edge tiling look? `anarch titlebars off` removes the title bars. Both choices are saved in `~/.config/lumen/settings.conf` (`LUMEN_TITLEBARS`, `LUMEN_TASKBAR`) and can also be made in the installer.

The title bars come from Hyprland's official *hyprbars* plugin, built for your exact Hyprland version when An4rch is installed; `anarch update` rebuilds it after Hyprland updates.

## Getting help

- `anarch doctor` checks that everything is installed and running.
- `anarch help` lists every An4rch command.
- `anarch manual themes` (or any chapter name) opens a chapter in the terminal.
