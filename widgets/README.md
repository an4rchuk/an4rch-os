# an4rch widgets

Small add-ons for the top bar. Each folder here is one widget:

| File | What it is |
| --- | --- |
| `widget.conf` | `name`, `description`, `interval` (seconds between updates), and optionally `on-click` (a command) and `json = yes` |
| `run` | An executable script that prints what to show. Plain text, or with `json = yes` a line like `{"text": "…", "tooltip": "…", "class": "…"}` |

```sh
anarch widget                 # what's on your bar, and what you can add
anarch widget add weather     # add one from this collection
anarch widget add https://github.com/someone/an4rch-widget-clock   # a community widget
anarch widget new my-widget   # make your own in ~/.config/lumen/widgets/my-widget
anarch widget remove weather
```

Widgets in this collection: **weather**, **cpu-temp**, **disk-free**, **uptime** and **countdown**.

## Sharing a widget

Put `widget.conf` and `run` (and a `README.md` if you like) in a git repository, ideally named
`an4rch-widget-<name>`, and share the link: `anarch widget add <link>` installs it. Adding a
widget shows its script first, because widgets run on your computer: only add ones you trust.

To get a widget into this collection, open a pull request adding its folder here. Keep the
script short and readable, avoid sudo, and don't send anything off the computer unless that's
the point of the widget (like the weather).

## Styling

Widgets are `#custom-w-<name>` in the top bar's CSS. A widget printing JSON can set a `class`
(`cpu-temp` uses `hot` above 85 °C). Add your own rules in `~/.config/waybar/style.css`.
