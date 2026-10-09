# Borrowed from other systems

The best ideas from macOS, Windows, ChromeOS and Android, rebuilt for an4rch OS. Find them in the an4rch menu under **Tools** (<kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SPACE</kbd>) or as `anarch <name>` in a terminal.

| an4rch | Borrowed from | What it does |
| --- | --- | --- |
| `anarch auto` | macOS Auto appearance and Night Shift | Light theme by day, dark theme and night light after sunset |
| `anarch note` <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>K</kbd> | Windows Sticky Notes, Google Keep | Notes that drop down over everything and save as you type |
| `anarch say` <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>S</kbd> | macOS Speak Selection | Reads the text you've selected aloud |
| `anarch share` | Android Quick Share and Wi-Fi sharing | A QR code your phone scans to download files or join the Wi-Fi |
| `anarch screentime` | iOS Screen Time, Android Digital Wellbeing | Time spent in each app, with optional daily limits |
| `anarch tidy` | Windows Storage Sense | Frees disk space safely |
| `anarch battery limit 80` | macOS optimised charging, Lenovo/ASUS charge limits | Stops charging at 80% so the battery lasts years longer |
| `anarch reset` | ChromeOS Powerwash | Puts the desktop back as it was after installing, keeping files and apps |

## Light by day, dark at night: `anarch auto`

```sh
anarch auto on                         # an4rch-light by day, your dark theme at night
anarch auto on pacifism ancom          # pick both themes
anarch auto times 07:30 20:00          # fixed times instead of the sun
anarch auto times sun                  # back to sunrise and sunset
anarch auto nightlight off             # leave night light alone
```

Sunrise and sunset are worked out from your time zone's location: no internet and no location sharing. If you pick a theme yourself, it stays until the next sunrise or sunset.

## Quick notes: <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>K</kbd>

The same key shows and hides a notes window over whatever you're doing. Notes are plain Markdown in `~/Notes/notes.md` and save a second after you stop typing. `anarch note buy milk` adds a line without opening anything.

## Read aloud: <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>S</kbd>

Select text anywhere and press the key; press it again to stop. `anarch say "hello"` reads anything. It uses eSpeak NG, or [Piper](https://github.com/rhasspy/piper)'s far more natural voices if you install `piper-tts-bin` and put a voice (`.onnx`) in `~/.local/share/piper/`. `LUMEN_SAY_SPEED=1.3` in settings.conf reads faster.

## Share to a phone: `anarch share`

```sh
anarch share holiday.jpg report.pdf    # scan the QR code to download them
anarch share wifi                      # scan to join this Wi-Fi network
anarch share text https://example.com  # any text or link
anarch share clipboard                 # what you've copied
```

Files are shared only with your local network, at an address with a random code in it, for 15 minutes at most or until you close the window. The phone needs no app, just its camera.

## Screen time: `anarch screentime`

Counts how long each app is in front of you (not while the screen is locked), all on this computer.

```sh
anarch screentime                    # today
anarch screentime week               # the last 7 days, with a daily average
anarch screentime limit steam 120    # a reminder after 2 hours a day
anarch screentime off                # stop counting; `forget` deletes it all
```

## Tidy up: `anarch tidy`

Shows what can safely go, then cleans it when you say yes: old package downloads (the newest copy of each stays, so rollbacks work), the AUR build cache, packages nothing needs any more, logs beyond 200 MB, crash dumps, Trash older than 30 days, stale thumbnails and unused Flatpak runtimes. Your files are never touched. `anarch tidy auto on` empties old Trash and thumbnails every month.

## Battery charge limit: `anarch battery limit`

Keeping a lithium battery at 100% wears it out fastest. `anarch battery limit 80` stops charging at 80% (kept across restarts); `anarch battery limit off` before a long trip. Works on laptops whose firmware offers it (most ThinkPads, ASUS, Dell, Framework, Samsung, Huawei and many more).

## Reset the desktop: `anarch reset`

When the desktop's settings have got into a muddle: key bindings, look and feel, top bar, launcher, notifications, terminals, theme, accessibility and automatic light/dark go back to how they were after installing. Your files, apps, Wi-Fi, screens, keyboard layout and default apps stay, and everything replaced is kept in `~/.local/state/lumen/before-reset-…`. `anarch reset --dry-run` lists what would change.
