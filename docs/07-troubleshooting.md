# Troubleshooting

## Start with the doctor

```sh
lumen doctor
```

It checks every component Lumen relies on, the session services, system services, fonts and the Hyprland config, and prints the exact command to fix each problem. You can also run it from **Lumen menu → Setup → Health check**.

## Hardware report

```sh
lumen doctor hardware
```

Shows the computer's model, graphics, Wi-Fi and Bluetooth chips with the driver each one uses, whether Wi-Fi or Bluetooth is switched off, the boot mode (UEFI or legacy BIOS, Secure Boot on or off) and any firmware or driver errors since startup. It's saved to `~/lumen-hardware-report.txt`; when reporting a problem with Wi-Fi, Bluetooth, sound or graphics, include it (or a photo of the screen). Also in **Lumen menu → Setup → Hardware report**.

## Logs

| What | Where |
| --- | --- |
| The installer | `~/.local/state/lumen/install.log` |
| Hyprland | `hyprctl rollinglog`, or `$XDG_RUNTIME_DIR/hypr/*/hyprland.log` |
| Hyprland config errors | `hyprctl configerrors` |
| Session startup (wallpaper, bar, Start menu) | `~/.local/state/lumen/session.log` |
| The session (bar, notifications, apps started by Lumen) | `journalctl --user -b` |
| Login screen | `journalctl -u greetd -b` |
| System | `journalctl -b -p warning` |

## Common problems

**The bar is missing, or shows old colours.**
`lumen-session restart bar`. If it doesn't appear, run `waybar` in a terminal to see the error. A JSON mistake in `config.jsonc` is the usual cause.

**Clicking a workspace in the bar does nothing.**
Waybar releases up to 0.15.0 send old-style commands that Hyprland's Lua config ignores. The installer offers to build `waybar-git`, which has the fix. You can do it later with `lumen pkg add waybar-git`. Keyboard shortcuts work either way.

**Hyprland shows a red error banner after I edited a config file.**
The banner names the file and line. Hyprland keeps running with the rest of your config, so fix the line and save; it reloads by itself. `hyprctl configerrors` shows the full message.

**I broke my config and can't get a usable desktop.**
Switch to a text console with <kbd>CTRL</kbd> + <kbd>ALT</kbd> + <kbd>F2</kbd>, log in, and move the file you changed aside:

```sh
mv ~/.config/hypr/bindings.lua ~/.config/hypr/bindings.lua.broken
cp ~/.local/share/lumen/config/hypr/bindings.lua ~/.config/hypr/
```

Every file in `~/.local/share/lumen/config/` is the pristine version of a file in your `~/.config`. To reset *all* configs, run `~/.local/share/lumen/install.sh --configs-only` after removing `~/.config/lumen/.installed`; your current files are backed up first.

**Notifications don't appear.**
Check Do Not Disturb (a bell in the bar, <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>D</kbd>). Then `lumen-session restart notifications`.

**The screen doesn't lock or sleep.**
Check *keep awake* (a coffee cup in the bar). A browser tab playing video also keeps the screen on; that's intentional. `lumen-session restart idle` restarts the idle daemon.

**No sound.**
`systemctl --user status pipewire wireplumber`. Pick the right output in **Lumen menu → Setup → Audio output**. Some laptops need `sof-firmware` (`lumen pkg add sof-firmware`, then reboot).

**Wi-Fi is missing after install.**
The installer switches networking to NetworkManager on the next boot. If the Wi-Fi menu says NetworkManager isn't running: `sudo systemctl enable --now NetworkManager`. If you used `iwd` before, make sure it's disabled: `sudo systemctl disable --now iwd`.

**Screen sharing in the browser or video calls shows nothing.**
`systemctl --user status xdg-desktop-portal-hyprland`. Then restart the browser. Pick the screen or window in the dialog Hyprland shows.

**NVIDIA: black screen or flickering.**
Make sure the open kernel modules are installed (`pacman -Q nvidia-open-dkms`) and that `cat /sys/module/nvidia_drm/parameters/modeset` prints `Y`. Older GPUs (before the GTX 16 / RTX 20 series) need different drivers: see <https://wiki.archlinux.org/title/NVIDIA>.

**An app looks blurry on a scaled display.**
It's probably running under XWayland. Electron apps (VS Code, Discord, Slack, …) are told to use Wayland through `ELECTRON_OZONE_PLATFORM_HINT=auto`. If one still looks blurry, add `--ozone-platform=wayland` to its launcher.

**An app opens in the wrong size, or should float.**
Add a window rule in `~/.config/hypr/rules.lua`. `lumen doctor windows` prints the class to match.

## Starting over

Your old configs from before Lumen are in `~/.config/lumen-backup-<date>/`. To uninstall Lumen's session while keeping the packages:

```sh
sudo systemctl disable greetd           # and re-enable your previous login manager
rm -rf ~/.local/share/lumen ~/.config/lumen
```
