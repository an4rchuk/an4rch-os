# an4rch OS

an4rch OS is the an4rch desktop as its own Arch-based distribution. You boot it from a USB stick, answer a few questions, and get a finished system: encrypted disk, snapshots that undo updates, the Start menu on the Windows key, an App Store, and a gaming setup in one click.

It borrows from two projects:

- From **[Omarchy](https://omarchy.org)**: an opinionated Hyprland desktop on plain Arch, keyboard first, every feature a small script, themes that restyle everything, and an ISO that installs it all.
- From **[Bazzite](https://bazzite.gg)**: a system you can always roll back, gaming ready out of the box (Steam, Proton, GameMode, MangoHud, gamescope, Game Mode session), Flathub-first apps through a friendly store, and a welcome tour on first boot.

Under the hood it's still Arch Linux: the official repositories, `pacman`, the AUR and the Arch Wiki all apply.

## Getting the ISO

- **Download:** every [release](https://github.com/an4rchuk/an4rch-os/releases) has the full ISO in parts (GitHub limits release files to 2 GB; join them with `copy /b` on Windows or `cat` elsewhere, as the release notes show) and a smaller *online* ISO that downloads its packages while installing, each with a `.sha256` checksum.
- **Build it yourself on Arch:** `sudo pacman -S archiso`, then `sudo iso/build.sh`. The ISO lands in `out/`. It is about 5 GB because it carries the packages an install needs (`iso/offline.sh`); `sudo LUMEN_OFFLINE=0 iso/build.sh` makes a small ISO that downloads everything while installing.
- **Build it on GitHub:** Actions → *iso* → *Run workflow*. The ISO is attached to the run.

Write it to a USB stick with [Impression](https://flathub.org/apps/io.gitlab.adhami3310.Impression), [Ventoy](https://www.ventoy.net), [Fedora Media Writer](https://flathub.org/apps/org.fedoraproject.MediaWriter), or `dd`:

```sh
sudo dd if=lumen-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## Installing

1. Turn off Secure Boot in your firmware settings (Arch kernels aren't signed by Microsoft), and make sure the computer boots in **UEFI** mode.
2. Boot the USB stick and pick **an4rch OS installer**.
3. You land on a live an4rch desktop, Bazzite-style, with the **Install an4rch OS** app open. Look around first if you like: the Start menu, terminal and App Store work. The installer asks:

| Page | Notes |
| --- | --- |
| Welcome | Keyboard layout |
| Internet | Pick a Wi-Fi network, or plug in a cable. The Wi-Fi network is remembered in the installed system |
| Disk | **Advanced: use partitions I've made myself** — choose the partition for an4rch (20 GB or more; erased), the EFI system partition (kept as it is, other systems' boot files included, unless you ask to format it), and, when the EFI partition is smaller than 900 MB (Windows' usually is), a boot partition of about 1 GB for the kernels (erased). A button opens the partition editor. Otherwise: on a disk with Windows, choose **Alongside Windows**: an4rch shrinks Windows' drive to make room (you pick the size, at least 30 GB), keeps Windows and its files, and a boot menu lets you choose Windows or an4rch at every start. Or **erase the whole disk**: everything on it is deleted, Windows included; disks that aren't empty are marked, and you type ERASE to confirm. At least 20 GB. Optional encryption (recommended for laptops; you type the password at every start) |
| Account | Your name, username, password and computer name. The root account is locked; you use `sudo` |
| Region | Time zone and language, guessed from your internet connection |
| System | **Desktop** or **Server** (no desktop: the system, SSH with the firewall allowing it, and an4rch's command-line tools, for old computers and home servers). The **kernel**: latest (default), long-term support, zen (tuned for desktops and gaming) or hardened (extra security; some apps, like Steam, may not run). A second kernel is always in the boot menu as a fallback, and `anarch tune kernel NAME` adds more later. The **shell**: zsh (default), bash or fish, each set up with an4rch's prompt, aliases and tools |
| Look | Pick a theme from a gallery (including **Cachy**, a CachyOS-inspired teal) and a layout: an4rch (top bar + taskbar, the default), Top bar only or Minimal. The live desktop restyles as you click, so you see it before installing |
| Apps | Browser, terminal and code editor, gaming yes/no, and **extra apps**: tick any from the App Store's list (by category) to have them installed too (from the Arch repositories when possible, then the AUR, then Flathub) |
| Review | A summary, then **Erase and install**, with a progress bar and the live log |

Prefer text? Pick **an4rch OS installer (text mode)** in the boot menu for the original step-by-step console installer.

The stick carries every package a default install needs, and the window title bar plugin ready-built, so installing mostly copies from the stick rather than downloading: expect a few minutes plus the disk's write speed. Choices it doesn't carry (another browser or editor, gaming) are downloaded. An internet connection is still needed for the latest package lists and mirrors. Progress is logged to `/var/log/lumen-os-install.log`, and the log is copied into the installed system.

### What the installer sets up

| | |
| --- | --- |
| Disk | GPT: a 1 GB EFI partition, and the rest as btrfs (inside LUKS2 when encrypted) with zstd compression |
| Subvolumes | `@` (system), `@home`, `@log`, `@pkg` (package cache) and `@snapshots`, so snapshots and rollbacks never touch your files |
| Boot | systemd-boot with two entries: **an4rch OS** and **an4rch OS (LTS kernel)** as a fallback. Plymouth splash and the disk password prompt |
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

Start runs quietly in the background, so it appears instantly. If it ever misbehaves: `anarch-start --quit`, then tap the Windows key again.

## The App Store

Open it with <kbd>SUPER</kbd> + <kbd>A</kbd>, from Start, or with `anarch store`.

- **Explore** has hand-picked apps by category, plus an editor's-picks carousel.
- **Search** covers the hand-picked list, all of **Flathub**, and the **Arch repositories**, with a shortcut to search the AUR.
- **App pages** show screenshots and a description from Flathub, plus **Install**, **Open** and **Remove** buttons. A source switcher lets you choose where the app comes from:

| Source | Good for |
| --- | --- |
| Arch repositories | Open-source apps. Fast, integrated, updated with the system |
| Flathub | Proprietary and fast-moving apps. Sandboxed, published by the developer |
| AUR | Anything else. Built on your computer from a community recipe |

- **Installed** lists what you got from the store, plus any other Flatpak apps.
- **Updates** shows pending updates. **Update everything** runs the full system update (`anarch update`), which takes a snapshot first.

Installing from the Arch repositories asks for your password (polkit). Flathub apps install for your user only and need no password.

To add your own apps to Explore, create `~/.config/lumen/store-catalog.json` in the same format as `apps/lumen-store/catalog.json`.

## Gaming

Pick *gaming* in the installer, or later run **Start → Gaming setup** (`anarch gaming`). It installs:

- **Steam**, with Proton for Windows games. Turn on *Steam Play for all titles* in Steam's Compatibility settings.
- **32-bit graphics drivers** for your GPU (AMD, Intel or NVIDIA).
- **GameMode**, which boosts CPU and GPU while a game runs. Launch option: `gamemoderun %command%`.
- **MangoHud**, an FPS and temperature overlay; <kbd>Right Shift</kbd> + <kbd>F12</kbd> toggles it. Launch option: `mangohud gamemoderun %command%`.
- **gamescope**, Valve's game compositor, for upscaling and frame limiting.
- **ProtonPlus**, which manages extra Proton and Wine versions (e.g. Proton-GE).

For a console-like experience, run `anarch gaming game-mode on`. It adds a **Steam Big Picture** session (gamescope-session, as on the Steam Deck and Bazzite). At the login screen, press <kbd>F3</kbd> to choose it. To get back to the desktop, use Steam's *Power → Switch to Desktop*.

Heroic (Epic and GOG), Lutris, Bottles, Prism Launcher, RetroArch and Moonlight are all in the App Store under **Games**.

## Snapshots and rollback

Every time packages are installed, updated or removed, a snapshot is taken first. So if an update breaks something:

- **Start → System snapshots → Undo the last update**, or `anarch snapshot undo`, restores the system to just before the last update. Restart to finish.
- `anarch snapshot restore N` restores any snapshot (`anarch snapshot` lists them).
- `anarch snapshot create "Before trying X"` takes one by hand.

A rollback swaps the whole system subvolume and keeps the old one as `@broken-<date>`; `anarch snapshot clean` removes those later. It also puts back the matching kernel from the package cache, so the restored system boots with its own kernel modules. Your files in `/home` are never rolled back.

### If the system doesn't start

1. In the boot menu, try **an4rch OS (LTS kernel)**. A broken kernel update is the most common cause, and the LTS kernel usually boots fine.
2. If that fails too, boot the an4rch OS USB stick, press <kbd>Ctrl</kbd> + <kbd>C</kbd> to leave the installer, and run `anarch-rescue`. It unlocks the disk, lists your snapshots, and restores the one you pick.

## Updating

an4rch OS is a rolling release, like Arch: there are no version upgrades, only updates. <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>U</kbd>, the update counter in the bar, or the store's Updates tab all run the same thing: an4rch itself, then packages, Flatpaks and firmware. A snapshot is taken first.

## Already running Arch?

You don't need the ISO. On an existing Arch install, `boot.sh` (see [Getting started](01-getting-started.md)) installs the same desktop, Start menu, App Store and gaming tools. To also get the OS layer (branding, snapshots, splash, zram), run:

```sh
~/.local/share/lumen/install.sh --configs-only   # if an4rch is already installed
sudo LUMEN_PATH=~/.local/share/lumen bash ~/.local/share/lumen/install/distro.sh
```

Snapshots need a btrfs root with an `@snapshots` subvolume mounted at `/.snapshots`, as the ISO creates. The boot splash also needs the `plymouth` hook in your mkinitcpio `HOOKS`.

## Dual boot with Windows

Before installing alongside Windows:

- **Back up** anything important. Resizing is safe, but a power cut in the middle isn't.
- **Turn off Fast Startup** in Windows (Control Panel → Power Options → Choose what the power buttons do) and use **Shut down**, not Restart. A Windows that's only hibernating can't be resized; the installer tells you if that's the case.
- **BitLocker** (device encryption) must be off, or make free space yourself with Windows' Disk Management first; the installer uses free space when there is enough.
- The USB must be started in **UEFI** mode, like Windows.

an4rch uses Windows' EFI partition only for its boot menu, and keeps its kernels on its own 1 GB boot partition. The boot menu (5 seconds) lists an4rch and Windows. Both systems keep the hardware clock in local time, so the clock is right in each.

**Windows starts straight away, without the menu?** A big Windows update can put Windows first in the computer's boot order again. an4rch is still there:

- Once: press the boot-menu key while the computer starts (**Esc** on ASUS, **F9** on HP, **F12** on Dell and Lenovo, **F8** on some) and pick **Linux Boot Manager**.
- For good: in the BIOS/UEFI settings (F2 or Del at start-up) move **Linux Boot Manager** to the top of the boot order. Or from an4rch, run `sudo efibootmgr` to see the entries and `sudo efibootmgr -o XXXX,YYYY` with Linux Boot Manager's number first.

## NVIDIA graphics

The default boot entry uses the open-source nouveau driver. For GTX 16xx, RTX 20xx and newer cards, pick **an4rch OS installer (NVIDIA)** in the boot menu to use NVIDIA's own driver. Installing sets up NVIDIA's driver automatically. On laptops with both Intel/AMD and NVIDIA graphics, the Intel/AMD GPU runs the screen and NVIDIA is available for games and apps that ask for it.
