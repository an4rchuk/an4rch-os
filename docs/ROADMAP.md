# Roadmap

Where an4rch OS is heading. Each release has one theme, so it ships something whole rather than a little of everything. Plans change with what people actually need: open an issue if something here matters to you, or if something is missing.

## 1.1 — Your install, your way (now)

Privacy and safety tools, features borrowed from other systems, and more choices when installing (server edition, kernel, shell, extra apps, your own partitions). See the [release notes](releases/v1.1.0.md).

## 1.2 — Looks like itself

The final artwork everywhere, and the settings in one window.

| Feature | Why |
| --- | --- |
| **The an4rch logo everywhere** | A custom Plymouth boot screen (the logo on black, a pulsing glow while it starts, the disk password in the same style), and the same logo in the boot menu, installer, login and lock screens, About and the app icons. |
| **an4rch Hub** (settings app) | One GTK window for everything that is a command today: appearance, privacy, health, battery, focus, accessibility, updates and snapshots, each a page with switches. Like GNOME Settings or the macOS System Settings, so nobody needs a terminal for the basics. |
| **Backups** (`anarch backup`) | Time Machine for an4rch: plug in a drive and your home folder is backed up every hour, encrypted (restic, or btrfs send to a btrfs drive). Browse and restore any version from Files. Snapshots protect against bad updates; backups protect against a dead drive or a lost laptop. |
| **Phone link** | KDE Connect, set up and themed: notifications from your phone, send files both ways, use the phone as a remote or a touchpad, and the clipboard shared. |
| **Driver manager** | Picks the right NVIDIA driver (open modules on newer cards, legacy for old ones), handles hybrid laptops, and shows what's in use and why. |
| **Login screen polish** | The user's picture, the wallpaper blurred behind it, and the theme's colours. |

## 1.3 — Safe to forget about

Updates that never break things, and help when something does.

| Feature | Why |
| --- | --- |
| **The an4rch package repository** | an4rch's own tools, themes and prebuilt AUR favourites (hyprbars, ProtonPlus…) as signed packages. Installs no longer build from source, and updates arrive through pacman like everything else. Hosted on Cloudflare R2 behind an4rch.uk. |
| **Tested update channels** | *Stable* holds Arch updates for a few days while the e2e VMs install and use them; only a passing set reaches users. *Rolling* gets Arch as it comes. Bazzite's main trick, for Arch. |
| **Secure Boot** | Signs the kernels and boot loader with sbctl so Secure Boot can stay on (needed by some anti-cheat games and company laptops). |
| **`anarch report`** | Collects logs, hardware and versions into one file (private data removed) to attach to an issue, so bugs get fixed on the first reply. |
| **Automatic recovery** | If the desktop fails to start twice after an update, the next boot offers to roll back to the last snapshot that worked. |

## 2.0 — Editions

The same core, built for different machines. The ISO workflow builds each one.

| Edition | For |
| --- | --- |
| **Desktop** | What an4rch OS is today. |
| **Game** | Boots straight into Steam's Big Picture (gamescope session), with the desktop one menu away. For living-room PCs and handhelds (Steam Deck, ROG Ally, Legion Go): Handheld Daemon, TDP control and on-screen keyboard. |
| **Server** | The 1.1 server install, as its own small ISO, plus Cockpit for managing it from a browser and one-command app containers (Jellyfin, Nextcloud, Home Assistant). |
| **Lite** | For old computers and 4 GB of RAM: no blur or animations, lighter apps, zram tuned harder. |

Also in 2.0: **translations** (the installer, menus and manual in other languages, starting with the most-asked-for) and an **on-screen keyboard** for touchscreens.

## Growing the project

Things outside the OS that help it grow:

- **an4rch.uk**: a home page with downloads and checksums, the manual as a website, screenshots, and a **theme gallery** where people share themes (`anarch theme get` already installs from a link).
- **Release routine**: a signed ISO every month, automatic notes from the changes, a GPG key so downloads can be verified, and at least two download mirrors.
- **Community**: issue templates for bugs and ideas, a contributing guide (how to run the tests and the VMs), and a Discord or Matrix room.
- **Hardware testing**: a list of laptops and desktops people have tried, with what works, fed by `anarch report`.
- **Later**: ARM builds (Raspberry Pi 5, Apple Silicon through Asahi).
