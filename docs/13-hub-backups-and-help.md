# The Hub, backups and getting help

New in 1.1.1: one window for every setting, backups to a drive, your phone linked to the computer, the right graphics driver, Secure Boot, and help when something goes wrong.

## The an4rch Hub

**Start → an4rch Hub**, or `anarch hub [page]`. Every setting that used to be a command is a page with switches: appearance, the desktop, privacy and safety, backups, phone, accessibility, screen time, hardware and drivers, updates and snapshots. `anarch settings` opens the same window.

## The login screen

Your name is filled in: type the password and press <kbd>Enter</kbd>. The list under the password picks a session (the an4rch desktop, or Steam's Game Mode when it is installed), and the buttons at the bottom restart or shut down. The logo stays where the boot screen left it, so starting up looks like one smooth motion.

`anarch login wallpaper on` puts your wallpaper behind it instead of black.

## Display scaling

High-resolution screens are scaled when you log in so text is a comfortable size: 150% on a 4K monitor, 160–200% on a sharp laptop panel, 100% on 1080p. The size comes from the screen's real dimensions where it reports them. A display you have set up yourself (`anarch display`, <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>D</kbd>) keeps your choice; run `anarch display autoscale` to apply the automatic one again.

## Backups: `anarch backup`

Time Machine for an4rch. Plug in a USB drive or an external disk and run `anarch backup setup` (or use the Hub's **Backups** page). Your home folder is backed up every hour, encrypted, whenever the drive is plugged in.

| Command | What it does |
| --- | --- |
| `anarch backup` | What's backed up, where, and when it last ran |
| `anarch backup now` | Back up now |
| `anarch backup list` | The versions you can go back to |
| `anarch backup browse` | Open the backups in Files, one folder per date |
| `anarch backup restore [FILE] [VERSION]` | Bring back a file, folder or everything into `~/Restored/<date>`. Nothing is overwritten |
| `anarch backup key` | The recovery key, needed to read the backups on another computer: keep a copy somewhere safe |
| `anarch backup auto on\|off` | The hourly backup |
| `anarch backup off` | Stop backing up (the backups stay on the drive) |

Versions are kept every hour for a day, every day for a week, every week for two months and every month for a year. A folder works as well as a drive: `anarch backup setup /mnt/nas`.

Snapshots and backups do different jobs: snapshots undo a bad update; backups save your files from a dead drive or a lost laptop.

## Your phone: `anarch phone`

Notifications from your phone, files both ways, a shared clipboard and the phone as a remote, using KDE Connect. Nothing goes through the internet.

1. `anarch phone setup` installs it, opens the firewall for it, and shows a QR code for the phone app.
2. Install **KDE Connect** on the phone and join the same Wi-Fi.
3. `anarch phone pair`, then accept on the phone.

Then: `anarch phone send FILE` (or right-click in Files → **Scripts → Send to phone**), `anarch phone ring` to find it, `anarch phone off` to stop.

## Graphics drivers: `anarch drivers`

Shows each graphics card, the driver it uses and the one recommended. Intel and AMD need nothing extra. For NVIDIA, `anarch drivers install` picks:

- GTX 16xx, RTX 20xx and newer: NVIDIA's open kernel modules;
- GTX 750 to 10xx: the 580 legacy driver; GTX 600/700: the 470 legacy driver (both from the AUR);
- older cards: the open-source nouveau driver.

On laptops with two graphics chips it also installs `prime-run`: start a game on the NVIDIA chip with `prime-run %command%` in Steam. `anarch drivers nouveau` goes back to the open-source driver. `anarch doctor` tells you when a better driver is available.

## Secure Boot: `anarch secureboot`

Some anti-cheat games and work laptops need Secure Boot on. an4rch signs its boot files with your own keys (Microsoft's are enrolled too, so Windows and graphics cards keep working):

1. `anarch secureboot firmware` restarts into the firmware settings. Find Secure Boot, choose **Reset to Setup Mode** (or *Clear keys*), leave Secure Boot off, save.
2. Back in an4rch: `anarch secureboot setup`.
3. Restart into the firmware again and turn Secure Boot on.

Kernel updates sign themselves after that. `anarch secureboot` shows the state.

## When something goes wrong

**Automatic recovery.** After a kernel update the boot menu counts start-ups: if an4rch fails to start three times, the menu falls back to the entry that worked. If the desktop crashes straight after logging in twice in a row, the login screen offers **Undo update**: type your password and it rolls back to the snapshot from before the update and restarts.

**`anarch report`** collects what's needed to fix a problem (an4rch's version, the hardware, failed services, this boot's errors, `anarch doctor`) into one file, removes your user and computer names, home folder, network addresses, Wi-Fi names and email addresses, and opens a new GitHub issue to attach it to. `anarch report --print` shows it first. It is also in the Hub under **System → Report a problem**.

## The Game edition

Pick **Game** in the installer and the computer starts straight into Steam's Big Picture, like a Steam Deck. Steam → Power → **Switch to Desktop** goes to the login screen, where the an4rch desktop is one click away. On any install: `anarch gaming game-mode on` adds the session and `anarch gaming game-mode boot on|off` turns starting in it on or off.
