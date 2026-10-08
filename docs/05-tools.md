# Built-in tools

All of these are in the an4rch menu (<kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SPACE</kbd>), and each one is also a plain command (`anarch <tool>`) you can script or bind to other keys.

## Screenshots

| Keys | Captures |
| --- | --- |
| <kbd>Print</kbd> or <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>X</kbd> | A region: drag a box, or click a window to snap to it |
| <kbd>SHIFT</kbd> + <kbd>Print</kbd> | The active window |
| <kbd>CTRL</kbd> + <kbd>Print</kbd> | The whole screen you're on |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>E</kbd> | A region, opened straight in the editor |

Every screenshot is copied to the clipboard and saved to `~/Pictures/Screenshots`. The notification has **Annotate** (arrows, boxes, text, blur, highlighter in [Satty](https://github.com/gabm/Satty)) and **Show in folder** buttons. Press the key again to cancel a selection.

## Screen recording

- <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>R</kbd> records a region.
- <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>SHIFT</kbd> + <kbd>R</kbd> records the whole screen.
- Press the same keys again, or click the red **REC** pill in the bar, to stop.
- `anarch record screen --audio` includes desktop sound.

Videos are saved as MP4 to `~/Videos/Recordings`.

## Clipboard history

<kbd>SUPER</kbd> + <kbd>V</kbd> shows everything you've copied, text and images. Pick an entry to copy it again, then paste as usual.

- `anarch clipboard delete` forgets one entry.
- <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>V</kbd> clears the whole history.

Text copied from password managers that mark it as sensitive isn't stored.

## Reminders

<kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>A</kbd> asks what and when:

```
25m Stretch
1h30m Take the bread out
at 17:30 Call Alex
at tomorrow 9:00 Standup notes
```

When it's due, a notification stays on screen until you dismiss it, with a soft chime. Reminders get through Do Not Disturb. Pending reminders show next to the clock; click the count to add one, right-click to see or cancel them. From a terminal:

```sh
anarch remind 10m "Tea is ready"
anarch remind at 14:00 "Dentist"
anarch remind list
```

Reminders are systemd user timers, so they keep running when you close the terminal. They don't survive a reboot.

## Emoji and symbols

<kbd>SUPER</kbd> + <kbd>;</kbd> searches emoji, arrows and symbols by name ("thumbs", "arrow right", "check"). The one you pick is copied, and recently used ones move to the top.

## Calculator

<kbd>SUPER</kbd> + <kbd>=</kbd> evaluates whatever you type and copies the result. It's powered by [qalculate](https://qalculate.github.io/), so it understands units, currencies and percentages:

```
18% of 240
5 km to miles
100 usd to eur
sqrt(2) * pi
2^64
```

## Colour picker

<kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>C</kbd>, then click anywhere. The hex code is copied, and the notification shows a swatch.

## Copy text from the screen (OCR)

<kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>T</kbd>, then select an area: a screenshot of text, a video frame, an error dialog that won't let you copy. The recognised text is copied. For other languages, install `tesseract-data-<lang>` and set `LUMEN_OCR_LANG=eng+deu` in `settings.conf`.

## Web search

<kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>W</kbd> searches from anywhere. Type an address to open it directly. DuckDuckGo bangs work: `!aw hyprland` (Arch Wiki), `!gh an4rch` (GitHub), `!yt lofi`, `!w Lisbon`.

## Web apps

Turn any website into an app with its own launcher entry and window: **an4rch menu → Install → Web app**, or:

```sh
anarch webapp add "Music" https://music.youtube.com
anarch webapp remove
```

With a Chromium-family browser installed, web apps open without tabs or an address bar. Otherwise they open in a new browser window.

## Find a window

<kbd>SUPER</kbd> + <kbd>`</kbd> lists every open window on every workspace. Type a few letters to jump to it. <kbd>ALT</kbd> + <kbd>Tab</kbd> cycles through windows on the current workspace.

## Desktop toggles

| Keys | Toggle |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>I</kbd> | **Keep awake**: no dimming, locking or sleeping until you turn it off |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>N</kbd> | **Night light**: warmer colours (strength in `settings.conf`) |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>D</kbd> | **Do Not Disturb**: notifications wait quietly (right-click the bell to see the last one) |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>B</kbd> | Hide or show the top bar |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>G</kbd> | No gaps and square corners, handy on small screens |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>S</kbd> | Tiling ↔ scrolling layout |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>Z</kbd> | Zoom in around the mouse pointer |

Night light and Do Not Disturb are remembered across logins.

## Notifications

Notifications slide in at the top right. Click one to open it, right-click to dismiss it.

- <kbd>SUPER</kbd> + <kbd>N</kbd> dismisses the newest one, <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>N</kbd> dismisses all.
- <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>N</kbd> brings back the last dismissed notification.
