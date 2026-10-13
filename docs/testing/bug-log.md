# VM test bug log

Every problem the VM test machines find goes here. **Urgent** bugs are fixed
straight away and retested on a fresh machine; the rest wait in
*Future fixes* below.

Urgent means: the install fails, the computer doesn't start, the desktop or
login doesn't appear, data could be lost, or something most people use is
broken (network, sound, updates, notifications, the App Store).

## Test session 2026-10-11 (15:20–21:00 UK)

Code under test: `claude/confident-darwin-o3ue0s` (from f559e54).
Machines: brutal (20), scenarios (14), features (8), standard (5).

| Time (UK) | Machine | What failed | Urgent? | Status |
|---|---|---|---|---|
| 13 Oct | standard (5/5, twice), scenarios (14/14 bar Chromium), brutal (19/20), features (8/8) | Retests of every 1.1.3 installer change on fresh machines, including dual boot, legacy BIOS, encrypted, manual partitions and NVIDIA. Only failure: on b-1cpu-2gb the panic key did not start anarch-panic within 20 s | — | Install changes pass; panic key on 1 CPU moved to future fixes |
| 13 Oct | (bug hunt, 1.1.2) | Password-free sudo could outlive the install: the installer's temporary rule stayed on the new system if the install stopped between adding and removing it, and the first-start app installer's rule survived a power cut and stayed active for up to 3 minutes on the next start | Yes (security) | Fixed: the installer removes its rule however it ends; the first-start one is removed when it starts and right after each AUR build |
| 13 Oct | (bug hunt, 1.1.2) | Graphical installer: a full name with `:` `"` `$` or a backquote, or the username `root` (or one the system uses, like `git`), passed straight to the engine and failed the install at the very end (the name is written into the new system's setup script) | Yes (install fails after everything is copied) | Fixed: the engine cleans the name and refuses reserved usernames before touching the disk, for both installers; the graphical one also says so on the account page |
| 13 Oct | (bug hunt, 1.1.2) | Graphical installer's failure page said "Nothing else on your computer was changed" even after the disk had been erased; it also only appeared once the engine's output closed | Yes (misleading after data loss) | Fixed: honest wording; the page appears as soon as the engine reports the failure |
| 13 Oct | (bug hunt, 1.1.2) | Manual partitioning didn't check that the chosen partitions weren't on the USB stick | Yes (could erase the stick) | Fixed: refused, with a message |
| 13 Oct | Real laptop (ASUS Vivobook), "erase the whole disk" | Install stopped at "Formatting": `/dev/sda2 is mounted`, and the kernel kept the old partition table. The installer erased and repartitioned the disk without first letting go of partitions still in use (mounted by the live desktop, swap, or volumes left from an earlier system). The stick was a Ventoy USB: the USB stick was only hidden from the disk list when written in DD mode, so the Ventoy stick itself was offered as a target (on a laptop whose own drive is NVMe, /dev/sda is the stick) | Yes (install fails on real hardware; possible risk to the USB stick) | Fixed: before erasing or resizing, the installer swaps off, unmounts and closes everything on the chosen disk, and stops with a clear message if something still holds it; it refuses to format unless the new partition table is in use; the USB stick is found through Ventoy/loop/device-mapper layers in both installers |
| 21:52 | features retest (8/8) | AUR fix (b81893d) retested on fresh machines, including f-fish-zen-apps: all pass | — | Done |
| 20:05 | f-fish-zen-apps | Install stopped at "Fetching the yay AUR helper": the AUR (aur.archlinux.org) didn't answer. The USB normally carries yay, but the AUR was also unreachable while that ISO was built, so the installer fell back to downloading it and treated the failure as fatal. The whole desktop install was abandoned over one optional tool | Yes (install fails whenever the AUR is down) | Fixed: the download is retried 3 times, and if the AUR still doesn't answer the install carries on without yay (AUR apps skipped, with a message saying how to add yay later). The ISO build also retries AUR downloads. Retest passed 8/8 |
| 20:05 | scenarios (all pass), standard (5/5), features (7/8) | Everything else passes on the latest code (Chromium is still known, see below) | — | — |
| 17:35 | retest (6 of 7) | Backup fix confirmed on all offline machines; uk-laptop and f-manual-encrypted pass (panic key didn't repeat there) | — | Done |
| 17:35 | b-offline-encrypted | Stops at the disk-unlock prompt every time. Not an OS bug: the machine uses a French (AZERTY) keyboard, the unlock prompt correctly uses it, but the test typed the password as on a UK/US keyboard (a, m and 1 sit on other keys) | No (test) | Test password changed to one that types the same on both layouts |
| 16:05 | b-offline-bios, b-offline-gamer, b-offline-dualboot, b-offline-encrypted, offline | Backups don't work on installs made without internet: restic (the backup tool) wasn't installed or on the USB, so `anarch backup setup` tried to download it and hung until killed | Yes (feature broken, command freezes) | Fixed: restic + fuse3 installed by default and carried on the USB; installing a missing tool without internet now says so at once instead of hanging. Retest queued |
| 16:05 | uk-laptop | Test machine died after 4 minutes, before building anything | No (test infrastructure) | Rerun in the retest set |
| 19:11 | features (8/8), standard (5/5) | All pass, including low-spec, where the panic key now passes too (it failed there in round 1) | — | — |
| 18:40 | brutal (20/20) | Every brutal machine passes on the latest code, including the French encrypted machine with the corrected test password, 1 CPU / 2 GB, 800×600, offline, dual boot and NVIDIA | — | — |
| 18:07 | brand (8/8), scenarios (13/14) | Second round on the latest code: everything passes except Chromium (known); panic key passed on every machine | — | — |
| 15:35 | (code review) | Login-screen upgrade for older installs looked for "Welcome to An4rch" (capital A after the rename), so installs still showing the old lowercase text would never get the new login screen | Yes (upgrade silently skipped) | Fixed: matches any case, and the old Lumen wording |

## Future fixes (not urgent)

| Found | Machine | Problem | Notes |
|---|---|---|---|
| 13 Oct | b-1cpu-2gb | Panic key again: on 1 CPU / 2 GB the key press did not start anarch-panic within 20 s (the test now tells "did not start" apart from "slow lock") | So it is the key binding, or Hyprland too busy on one CPU, not a slow lock screen. Next: check the bind fires (hyprctl binds) and time it on a 1-CPU VM |
| 16:05 | f-manual-encrypted, low-spec | Panic key didn't lock the screen or wipe the clipboard, only on slower machines right after closing several windows | Test now waits up to 20 s and records whether anarch-panic ran. Has passed on every machine since (including low-spec): most likely a slow lock screen. Keep watching |
| 16:05, 18:07 | chromium | With Chromium as the browser no window appears within 90 s. Chromium 153 starts (GPU and network processes on /dev/dri/renderD128, Wayland) but never maps a window; Brave, same engine and flags, works | Known issue in the test set. Next: try --ozone-platform=x11 or --disable-gpu as a fallback and check on real hardware. Firefox (default), Brave and Zen pass |
| 20:05 | — | When the AUR is down the installer now skips yay, and nothing installs it later on its own | Add yay to the first-start catch-up (lumen-pending-apps) so it arrives once the AUR is back |

## Already fixed this week (found by VM tests)

- Notifications never showed (`notify-send -an`), every machine. Fixed 45a5e87.
- Live USB desktop never started (`.wants` link turned into a file). Fixed 45a5e87.
- Apps ticked in the installer (VS Code) weren't installed. Now installed on first start, f559e54.
- ISO build stopped (git "dubious ownership" on the copy). Fixed a889367.
- Install stopped at the very end with an AUR app ticked (busy unmount). Fixed 1082942.
