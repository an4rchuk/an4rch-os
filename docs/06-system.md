# System and hardware

## Wi-Fi and networking

<kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>W</kbd>, or click the network icon in the bar.

The menu scans and lists networks, strongest first: 󰌾 marks secured ones and *connected* marks the current one. Pick a network to join (an4rch asks for the password if needed). Pick the connected one to disconnect. The menu can also turn Wi-Fi on or off.

- **Network settings** opens the connection editor: VPNs (WireGuard, OpenVPN), static IPs, proxies, hotspots.
- **Advanced** opens `nmtui` in a terminal.

Networking is handled by NetworkManager, so `nmcli` works too:

```sh
nmcli dev wifi list
nmcli dev wifi connect "Network" password "secret"
nmcli con import type wireguard file ~/wg0.conf
```

## Bluetooth

<kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>B</kbd>, or click the Bluetooth icon, opens [bluetui](https://github.com/pythops/bluetui). Use the arrow keys to move, <kbd>Space</kbd> to toggle scanning, <kbd>Enter</kbd> to pair or connect, <kbd>?</kbd> for help. an4rch powers the adapter on and unblocks it first. Connected devices show their battery level in the bar when they report it.

## Sound

- The volume keys change volume with an on-screen indicator; hold <kbd>ALT</kbd> for 1 % steps.
- Scroll on the volume icon to change it. Right-click mutes.
- <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>A</kbd> (or click the icon) opens the mixer: per-app volume, input and output devices.
- **an4rch menu → Setup → Audio output** switches speakers and headphones quickly.
- The microphone-mute key works too, and an orange pill appears in the bar whenever an app is using your microphone or sharing your screen.

Audio runs on PipeWire, so PulseAudio and JACK apps work unchanged.

## Displays

<kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>D</kbd> lists your displays. Pick one to change its resolution and refresh rate, scale, rotation or position, to mirror another display, or to turn it off. With a laptop and one external screen there are presets too: *extend*, *external only*, *laptop only* and *mirror*.

Every change applies at once and asks **Keep these settings?**. If you don't answer within 15 seconds, the previous layout comes back, so a bad mode can't leave you stuck on a black screen.

Settings are saved in `~/.config/hypr/monitors.lua`. Each display is matched by make, model and serial rather than by port, so a dock that renames ports doesn't lose your layout. You can edit the file by hand:

```lua
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1.5 })
hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "auto-right", scale = 1, vrr = 1 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })  -- everything else
```

New displays plugged in later get their best mode and are placed to the right automatically.

## Brightness and night light

Brightness keys adjust the screen in smooth steps, and the keyboard backlight keys work if you have them. <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>N</kbd> turns on the night light.

## Idle, lock and sleep

Out of the box:

| After | What happens |
| --- | --- |
| 2.5 minutes | Screen dims, keyboard backlight turns off |
| 5 minutes | Screen locks |
| 5.5 minutes | Screen turns off |
| 30 minutes | Computer suspends, unless someone is connected over SSH or audio is playing |

Nothing dims or sleeps while a video or game is fullscreen, or while an app asks to stay awake (video calls, presentations). <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>I</kbd> (*keep awake*) pauses all of it.

- Change the timings in `~/.config/hypr/hypridle.conf`, then run `lumen-session restart idle`.
- Set `LUMEN_IDLE_SUSPEND=battery` in `settings.conf` to only suspend on battery, or `never` to stop idle suspend entirely.

Closing the laptop lid suspends, and the screen is always locked before the computer sleeps. The **power button** opens the power menu instead of cutting power; holding it for a few seconds still forces a shutdown.

<kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>L</kbd> locks right away. <kbd>SUPER</kbd> + <kbd>Esc</kbd> opens the power menu: lock, suspend, log out, restart, shut down, and hibernate or restart into firmware setup when your machine supports them.

## Logging in, passwords and the keyring

an4rch's login screen is **greetd** with the graphical **ReGreet** greeter, showing your wallpaper and your theme's colours (both follow you when you change them: `lumen-login sync`). It remembers the last user, so you usually just type your password. If it can't start on your graphics hardware, the text login screen (tuigreet) appears instead; `lumen-login text on` always uses the text one, and `lumen-login preview` shows the graphical one in a window.

- Your login password also unlocks the **GNOME keyring**, where browsers, Git and other apps store secrets. You won't get a second password prompt.
- When an app needs administrator rights (changing the time zone, mounting a disk), a centred password dialog appears. This is the Hyprland polkit agent.
- With full-disk encryption you already type a password at boot. `anarch setup autologin on` skips the login screen; the lock screen still protects your session. `anarch setup autologin off` turns it back on.

## Fingerprint

**an4rch menu → Setup → Fingerprint login** (or `anarch setup fingerprint`) installs `fprintd`, enrols a finger and tests it. It then allows the fingerprint, alongside your password, for the lock screen, `sudo` and administrator prompts. Supported readers are listed at <https://fprint.freedesktop.org/supported-devices.html>.

## Time zone and keyboard

**an4rch menu → Setup → Time zone** has a searchable list and a *Detect automatically* option. The clock is kept accurate over the network.

**an4rch menu → Setup → Keyboard layout** picks a layout, a variant and an optional second layout (<kbd>ALT</kbd> + <kbd>SHIFT</kbd> switches between them). The lock screen shows the active layout in the corner.

## Printing

**an4rch menu → Setup → Printers** (or `anarch setup printing`) installs CUPS, turns on discovery of network printers, and opens the printer settings. Most network printers then just appear in every app's print dialog.

## Firewall

The installer turns on `ufw`, which blocks incoming connections and allows outgoing ones. If you installed over SSH, SSH stays reachable. To open a port:

```sh
sudo ufw allow 22000/tcp     # e.g. Syncthing
sudo ufw status
```

## Installing and removing apps

| How | For |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>I</kbd> | Search every package in the Arch repositories and the AUR. <kbd>Tab</kbd> selects several, <kbd>Enter</kbd> installs |
| **an4rch menu → Install → Popular apps** | A hand-picked list: browsers, chat, music, office, design, password managers, editors, games |
| **an4rch menu → Install → Flatpak apps** | Search Flathub (sets Flatpak up on first use) |
| **an4rch menu → Install → Development tools** | Git, GitHub CLI, lazygit, mise, Docker, Python, Node, Go, Rust, … |
| **an4rch menu → Install → Gaming** | Steam (enables multilib), GameMode, MangoHud, gamescope |
| **an4rch menu → Remove** | Pick installed apps to remove |
| `anarch pkg add NAME…` | Install by name from a terminal: repos first, then the AUR |

Installed apps appear in the launcher immediately.

## Updates

<kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>U</kbd> (or click the update count in the bar, or run `update`) updates, in order:

1. **an4rch itself.** It pulls the latest version, shows what changed, adds any new config files and runs one-off migrations. Your own files are never overwritten.
2. **System packages**, official and AUR, through `yay`.
3. **Flatpak apps**, if you have any.
4. **Firmware**, through `fwupd`, after asking first.

Afterwards it tells you if a new kernel needs a restart, and lists any `.pacnew` config files waiting for review. The bar checks for updates every hour.
