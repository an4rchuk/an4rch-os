# Lumen OS

Lumen OS is the Lumen desktop as its own Arch-based distribution. You boot it from a USB stick, answer a few questions, and get a finished system: encrypted disk, snapshots that undo updates, the Start menu on the Windows key, an App Store, and a gaming setup in one click.

It borrows from two projects:

- From **[Omarchy](https://omarchy.org)**: an opinionated Hyprland desktop on plain Arch, keyboard first, every feature a small script, themes that restyle everything, and an ISO that installs it all.
- From **[Bazzite](https://bazzite.gg)**: a system you can always roll back, gaming ready out of the box (Steam, Proton, GameMode, MangoHud, gamescope, Game Mode session), Flathub-first apps through a friendly store, and a welcome tour on first boot.

Under the hood it's still Arch Linux: the official repositories, `pacman`, the AUR and the Arch Wiki all apply.

## Getting the ISO

- **Download:** every tagged release on GitHub attaches `lumen-<date>-x86_64.iso` with a `.sha256` checksum.
- **Build it yourself on Arch:** `sudo pacman -S archiso`, then `sudo iso/build.sh`. The ISO lands in `out/`.
- **Build it on GitHub:** Actions → *iso* → *Run workflow*. The ISO is attached to the run.

Write it to a USB stick with [Impression](https://flathub.org/apps/io.gitlab.adhami3310.Impression), [Ventoy](https://www.ventoy.net), [Fedora Media Writer](https://flathub.org/apps/org.fedoraproject.MediaWriter), or `dd`:

```sh
sudo dd if=lumen-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## Installing

1. Turn off Secure Boot in your firmware settings (Arch kernels aren't signed by Microsoft), and make sure the computer boots in **UEFI** mode.
2. Boot the USB stick and pick **Lumen OS installer**.
3. The installer starts by itself and walks you through:

| Step | Notes |
| --- | --- |
| Internet | Pick a Wi-Fi network from a list, or plug in a cable. The Wi-Fi network is remembered in the installed system |
| Keyboard | Layout for the console and the disk password |
| Disk | **The whole disk is erased.** At least 20 GB |
| Encryption | Recommended for laptops. You type the password at every start |
| Account | Your name, username, password and computer name. The root account is locked; you use `sudo` |
| Time zone and language | Detected from your internet connection; confirm or pick |
| Apps | Browser, terminal and code editor, gaming yes/no, and a starting theme |
| Review | A summary, then **Erase and install** |

Installing takes 15–30 minutes, mostly downloading. Progress is logged to `/var/log/lumen-os-install.log`, and the log is copied into the installed system.

### What the installer sets up

| | |
| --- | --- |
| Disk | GPT: a 1 GB EFI partition, and the rest as btrfs (inside LUKS2 when encrypted) with zstd compression |
| Subvolumes | `@` (system), `@home`, `@log`, `@pkg` (package cache) and `@snapshots`, so snapshots and rollbacks never touch your files |
| Boot | systemd-boot with two entries: **Lumen OS** and **Lumen OS (LTS kernel)** as a fallback. Plymouth splash and the disk password prompt |
| Memory | zram (compressed RAM swap); no swap partition needed |
| Snapshots | snapper with snap-pac: a snapshot before and after every package change, plus a "Fresh install" snapshot |
| Desktop | Everything in this manual, installed as your user |

## The Start menu

Tap the **Windows key** on its own and Start opens. It also opens from the 󰣇 logo in the top bar.

- **Pinned** apps sit at the top. Right-click any app to pin or unpin it, or to uninstall it.
- **Recent** shows what you opened last.
- **All apps** lists everything A–Z.
- **Just type** to search apps, settings ("wifi", "display", "theme", "update"), do maths (`12*(3+4)/2`), run a command, search the web, or look something up in the App Store.
- The footer has your name, the App Store, Files, Settings and the power menu.

Holding the Windows key for a shortcut (Windows + B, Windows + 1, …) never opens Start. Only a tap on its own does.

Start runs quietly in the background, so it appears instantly. If it ever misbehaves: `lumen-start --quit`, then tap the Windows key again.

## The App Store

Open it with <kbd>SUPER</kbd> + <kbd>A</kbd>, from Start, or with `lumen store`.

- **Explore** has hand-picked apps by category, plus an editor's-picks carousel.
- **Search** covers the hand-picked list, all of **Flathub**, and the **Arch repositories**, with a shortcut to search the AUR.
- **App pages** show screenshots and a description from Flathub, plus **Install**, **Open** and **Remove** buttons. A source switcher lets you choose where the app comes from:

| Source | Good for |
| --- | --- |
| Arch repositories | Open-source apps. Fast, integrated, updated with the system |
| Flathub | Proprietary and fast-moving apps. Sandboxed, published by the developer |
| AUR | Anything else. Built on your computer from a community recipe |

- **Installed** lists what you got from the store, plus any other Flatpak apps.
- **Updates** shows pending updates. **Update everything** runs the full system update (`lumen update`), which takes a snapshot first.

Installing from the Arch repositories asks for your password (polkit). Flathub apps install for your user only and need no password.

To add your own apps to Explore, create `~/.config/lumen/store-catalog.json` in the same format as `apps/lumen-store/catalog.json`.

## Gaming

Pick *gaming* in the installer, or later run **Start → Gaming setup** (`lumen gaming`). It installs:

- **Steam**, with Proton for Windows games. Turn on *Steam Play for all titles* in Steam's Compatibility settings.
- **32-bit graphics drivers** for your GPU (AMD, Intel or NVIDIA).
- **GameMode**, which boosts CPU and GPU while a game runs. Launch option: `gamemoderun %command%`.
- **MangoHud**, an FPS and temperature overlay; <kbd>Right Shift</kbd> + <kbd>F12</kbd> toggles it. Launch option: `mangohud gamemoderun %command%`.
- **gamescope**, Valve's game compositor, for upscaling and frame limiting.
- **ProtonPlus**, which manages extra Proton and Wine versions (e.g. Proton-GE).

For a console-like experience, run `lumen gaming game-mode on`. It adds a **Steam Big Picture** session (gamescope-session, as on the Steam Deck and Bazzite). At the login screen, press <kbd>F3</kbd> to choose it. To get back to the desktop, use Steam's *Power → Switch to Desktop*.

Heroic (Epic and GOG), Lutris, Bottles, Prism Launcher, RetroArch and Moonlight are all in the App Store under **Games**.

## Snapshots and rollback

Every time packages are installed, updated or removed, a snapshot is taken first. So if an update breaks something:

- **Start → System snapshots → Undo the last update**, or `lumen snapshot undo`, restores the system to just before the last update. Restart to finish.
- `lumen snapshot restore N` restores any snapshot (`lumen snapshot` lists them).
- `lumen snapshot create "Before trying X"` takes one by hand.

A rollback swaps the whole system subvolume and keeps the old one as `@broken-<date>`; `lumen snapshot clean` removes those later. It also puts back the matching kernel from the package cache, so the restored system boots with its own kernel modules. Your files in `/home` are never rolled back.

### If the system doesn't start

1. In the boot menu, try **Lumen OS (LTS kernel)**. A broken kernel update is the most common cause, and the LTS kernel usually boots fine.
2. If that fails too, boot the Lumen OS USB stick, press <kbd>Ctrl</kbd> + <kbd>C</kbd> to leave the installer, and run `lumen-rescue`. It unlocks the disk, lists your snapshots, and restores the one you pick.

## Updating

Lumen OS is a rolling release, like Arch: there are no version upgrades, only updates. <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>U</kbd>, the update counter in the bar, or the store's Updates tab all run the same thing: Lumen itself, then packages, Flatpaks and firmware. A snapshot is taken first.

## Already running Arch?

You don't need the ISO. On an existing Arch install, `boot.sh` (see [Getting started](01-getting-started.md)) installs the same desktop, Start menu, App Store and gaming tools. To also get the OS layer (branding, snapshots, splash, zram), run:

```sh
~/.local/share/lumen/install.sh --configs-only   # if Lumen is already installed
sudo LUMEN_PATH=~/.local/share/lumen bash ~/.local/share/lumen/install/distro.sh
```

Snapshots need a btrfs root with an `@snapshots` subvolume mounted at `/.snapshots`, as the ISO creates. The boot splash also needs the `plymouth` hook in your mkinitcpio `HOOKS`.
