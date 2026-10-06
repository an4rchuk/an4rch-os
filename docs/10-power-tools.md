# Power tools

Four commands for the things a fresh desktop doesn't do on its own: tuning the system, one-step setups for popular extras, a development environment, and sharing themes. Each one is also in the Lumen menu (<kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SPACE</kbd>) and in Start's search.

They borrow from three distributions: performance tuning from [CachyOS](https://cachyos.org), one-command extras from [Bazzite](https://bazzite.gg)'s `ujust`, and the development setup from [Omarchy](https://omarchy.org).

## Performance: `lumen tune`

Lumen OS already applies the low-risk tweaks at install time:

| Tweak | Why |
| --- | --- |
| zram swap with tuned `vm.swappiness` | Compressed swap in RAM instead of a slow disk |
| `vm.vfs_cache_pressure`, smaller dirty-page batches | Snappier file browsing, no stalls when copying to slow USB sticks |
| Per-disk I/O scheduler | `none` for NVMe, `mq-deadline` for SATA SSDs, `bfq` for hard drives |
| `kernel.split_lock_mitigate = 0`, a high `vm.max_map_count` | Some Windows games run faster under Proton, and big games don't run out of memory maps |
| NTSYNC | Kernel support Wine and Proton use for smoother frame pacing (Linux 6.14+) |
| 15-second service stop timeout, 200 MB journal | Shutdowns never hang for 90 seconds |

The opt-in ones:

```sh
lumen tune status              # kernel, CPU scheduler, governor, zram, I/O, gaming tweaks
lumen tune scheduler bpfland   # a sched-ext CPU scheduler; switch live, no reboot
lumen tune scheduler off       # back to the kernel's default
lumen tune kernel zen          # add linux-zen to the boot menu (optionally as default)
lumen tune mirrors             # rank Arch mirrors by speed, and again every week
```

The schedulers come from the [scx project](https://github.com/sched-ext/scx) and run as BPF programs inside the regular Arch kernel:

| Scheduler | Best for |
| --- | --- |
| `bpfland` | Everyday desktop responsiveness (recommended) |
| `lavd` | Gaming and low latency (the Steam Deck's scheduler) |
| `rusty` | Heavy workloads such as compiling |
| `flash` | Audio work and other latency-critical tasks |

If something feels wrong, `lumen tune scheduler off` puts the default back immediately.

## Extras: `lumen extras`

Ready-made setups, each one command. They install the packages, turn on the services, open firewall ports where needed and tell you the next step.

| Command | What you get |
| --- | --- |
| `lumen extras sunshine` | Stream games from this PC to a phone, TV or laptop with Moonlight |
| `lumen extras decky` | Decky Loader plugins in Steam's Game Mode |
| `lumen extras controllers` | udev rules for 8BitDo, PlayStation, Switch and other controllers |
| `lumen extras handheld` | Handheld Daemon for ROG Ally, Legion Go and similar: buttons, TDP, RGB |
| `lumen extras openrgb` | OpenRGB, to control RGB lighting from any brand |
| `lumen extras lact` | LACT: GPU fan curves, clocks and power limits |
| `lumen extras distrobox` | Ubuntu, Fedora and other distributions in containers, plus BoxBuddy |
| `lumen extras waydroid` | Android apps in a window |
| `lumen extras virt` | Virtual machines with virt-manager and QEMU/KVM |
| `lumen extras tailscale` | A private network between all your devices |
| `lumen extras phone` | Phone link (KDE Connect): notifications, files and clipboard with your phone |
| `lumen extras localsend` | LocalSend: send files to nearby phones and computers |
| `lumen extras backup` | Déjà Dup: scheduled backups of your files to a drive or the cloud |
| `lumen extras office` | LibreOffice: documents, spreadsheets, presentations (Word/Excel files too) |

`lumen extras list` shows them all; `lumen extras` on its own opens a menu.

## Development: `lumen dev`

```sh
lumen dev lang node python go   # languages, managed by mise
lumen dev docker                # Docker, Compose and Buildx; no sudo needed after logging back in
lumen dev db postgres redis     # databases in Docker, on localhost only
lumen dev status                # what's installed and running
```

Languages: `node`, `python`, `go`, `rust`, `ruby`, `java`, `bun`, `deno`, `zig`, `elixir`, `php`, `dotnet`. They come from [mise](https://mise.jdx.dev), so each project can pin its own versions: run `mise use node@20` inside the project, and mise switches versions automatically when you `cd` into it.

Databases: `postgres`, `mysql`, `redis`, `mongo`. Each runs as a container called `lumen-<name>` with its data in a Docker volume, restarts with the computer, and accepts connections from this computer only, without a password.

## Sharing themes: `lumen theme install`

Anyone can publish a Lumen theme as a git repository with a `theme.conf` at the top (see [Making your own theme](03-themes.md#making-your-own-theme)), plus an optional `backgrounds/` folder of wallpapers.

```sh
lumen theme install https://github.com/someone/lumen-frosty-theme
lumen theme remove frosty
```

The theme's name comes from the repository name, without `lumen-` and `-theme`. Themes without wallpapers get painted ones. Run the same install command again to update a theme. From the desktop: Lumen menu → Style → *Install a theme from git*.

## Battery warnings

On laptops, Lumen warns at 20% and again at 10%, and suspends at 4% so nothing is lost. Change the levels in `~/.config/lumen/settings.conf`:

```sh
LUMEN_BATTERY_LOW=25
LUMEN_BATTERY_CRITICAL=10
LUMEN_BATTERY_SUSPEND=0   # 0: never suspend automatically
```

`lumen battery` prints the current charge.
