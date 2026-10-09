# Roadmap

Where An4rch OS is heading. Each release has one theme, so it ships something whole rather than a little of everything. Plans change with what people actually need: open an issue if something here matters to you, or if something is missing.

## 1.1 — Your install, your way

Privacy and safety tools, features borrowed from other systems, and more choices when installing (server edition, kernel, shell, extra apps, your own partitions). See the [release notes](releases/v1.1.0.md).

## 1.1.1 — Looks like itself (now)

The red and black An4rch look, a boot screen that flows into a one-step login, the An4rch Hub, display scaling, backups, phone link, the driver manager, Secure Boot, `anarch report`, automatic recovery and the Game edition. See the [release notes](releases/v1.1.1.md).

## 1.2 — Safe to forget about

Updates that never break things, and help when something does.

| Feature | Why |
| --- | --- |
| **The An4rch package repository** | An4rch's own tools, themes and prebuilt AUR favourites (hyprbars, ProtonPlus…) as signed packages. Installs no longer build from source, and updates arrive through pacman like everything else. Hosted on Cloudflare R2 behind an4rch.uk. |
| **Tested update channels** | *Stable* holds Arch updates for a few days while the e2e VMs install and use them; only a passing set reaches users. *Rolling* gets Arch as it comes. Bazzite's main trick, for Arch. |

## 2.0 — Editions

The same core, built for different machines. The ISO workflow builds each one.

| Edition | For |
| --- | --- |
| **Desktop** | What An4rch OS is today. |
| **Game** | (The installer's Game edition arrived in 1.1.1.) Its own ISO that boots straight into Steam's Big Picture (gamescope session), with the desktop one menu away. For living-room PCs and handhelds (Steam Deck, ROG Ally, Legion Go): Handheld Daemon, TDP control and on-screen keyboard. |
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
