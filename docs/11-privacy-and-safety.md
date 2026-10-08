# Privacy, safety and accessibility

Tools most desktops leave to add-ons, built into an4rch OS. They're all in the an4rch menu under **Privacy and safety** (<kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SPACE</kbd>), in Start's search, and on the command line as `anarch <name>`.

## The panic key: <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>Esc</kbd>

One key press, and everything is hidden at once:

- the screen locks, on an empty workspace (unlocking doesn't put your windows straight back on show);
- every [vault](#vaults-encrypted-folders-anarch-vault) closes, so its files can't be read even after unlocking;
- the microphone and speakers mute and media pauses;
- the clipboard and its history are wiped;
- notifications are cleared.

`anarch panic --radios` also turns Wi-Fi and Bluetooth off; put `LUMEN_PANIC_RADIOS=yes` in `~/.config/lumen/settings.conf` to make the key do that too.

## Network privacy: `anarch privacy`

| Command | What it does |
| --- | --- |
| `anarch privacy on` | All three below |
| `anarch privacy mac on` | Shows each network a made-up hardware (MAC) address instead of your computer's real one: a different one per network, the same one each time you go back to it, so sign-in pages and router settings still work. Wi-Fi scans use random addresses too. |
| `anarch privacy dns on [quad9\|mullvad\|adblock\|cloudflare]` | Encrypted DNS (DNS-over-TLS): the network you're on can't see or change which sites you look up. Quad9 by default; `adblock` is Mullvad's ad-blocking resolver. |
| `anarch privacy block on` | Blocks known ad, tracker and malware sites for every app (the [StevenBlack](https://github.com/StevenBlack/hosts) list, tens of thousands of sites). `anarch privacy block update` fetches the newest list. |
| `anarch privacy` | What's on. <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>P</kbd> opens the same as a menu. |

On a hotel or café network with a sign-in page, run `anarch privacy dns off` until you've signed in.

## Vaults (encrypted folders): `anarch vault`

A vault is a folder that is only readable after you type its password. Its files are stored encrypted in `~/.vaults/NAME` (fine to back up or sync to the cloud: only scrambled names and contents are there) and appear in `~/Vaults/NAME` while it's open.

```sh
anarch vault new private      # asks for a password twice
anarch vault open private     # files in ~/Vaults/private
anarch vault close private
anarch vault                  # list them
```

An open vault closes itself after 30 minutes unused (`LUMEN_VAULT_IDLE=1h` in settings.conf to change, `0` for never), and the panic key closes them all. When you make a vault, write down the master key it shows: it's the only way in if you forget the password.

## Sandboxed apps: `anarch sandbox`

Runs an app walled off from your files, with a throwaway home folder: it can't read your documents, and whatever it saves is gone when it closes.

```sh
anarch sandbox some-app             # no access to your files
anarch sandbox --offline some-app   # and no internet
anarch sandbox browser              # a browser that remembers nothing
anarch sandbox --keep some-app      # your files, but the app's own restrictions
```

It uses [firejail](https://firejail.wordpress.com), which is installed the first time.

## Removing hidden data: `anarch scrub`

Photos from phones record where they were taken; documents record their author and edit history. `anarch scrub` strips all of that (with [mat2](https://0xacab.org/jvoisin/mat2)) from images, PDFs, office documents, audio and video.

- In Files: select files, right-click → **Scripts** → **Remove hidden data**.
- `anarch scrub photo.jpg` makes a clean copy (`photo.cleaned.jpg`); `--inplace` cleans the file itself; `--show` lists what's hidden in it.

## Your setup on another computer: `anarch carry`

```sh
anarch carry export                     # ~/an4rch-carry-HOST-DATE.tar.gz
anarch carry import an4rch-carry-….tar.gz
```

One file with your settings, themes, key bindings, look and feel, top bar, web apps, git settings and the list of apps you installed. Importing backs up what's already there (to `~/.local/state/lumen/before-carry-…`), then offers to install the missing apps. Screen layout is left alone (different screens) unless you add `--all`. Passwords, keys and documents are never included.

## Computer health: `anarch health`

A report with a verdict for each part: every drive's health and wear (SMART), filesystem errors and the last btrfs scrub, free space, battery wear, failed services and temperatures.

an4rch OS watches the drives (smartd) and scrubs btrfs once a month, finding silently damaged data (and repairing it wherever btrfs keeps a second copy). A daily check notifies you if anything needs attention. `anarch health setup` turns all of that on for an install made before 1.1.0 (updating does it too).

## Focus sessions: `anarch focus`

<kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>F</kbd> starts 25 minutes of focus: notifications are held back and the top bar counts down. When it's over, notifications come back and a chime says take a break. `anarch focus 50` for longer, the same key or `anarch focus stop` to end early.

## Accessibility: `anarch a11y`

| Command | |
| --- | --- |
| `anarch a11y reader on` | The Orca screen reader (installed the first time). <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>R</kbd> turns it on and off. |
| `anarch a11y text bigger` / `smaller` / `reset` | Text in apps from 100% to 200% |
| `anarch a11y cursor big` / `huge` / `normal` | A larger mouse pointer |
| `anarch a11y motion reduce` | No window animations |
| `anarch a11y contrast on` | The **High contrast** theme: black, white and bright yellow; `off` goes back to your theme |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>Z</kbd> | Zoom in around the cursor |

Choices are remembered and come back at every login. The camera, microphone and screen-sharing indicators at the top right show whenever an app is using them.
