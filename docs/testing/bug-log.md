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
| 13 Oct | Real laptop (ASUS Vivobook), "erase the whole disk" | Install stopped at "Formatting": `/dev/sda2 is mounted`, and the kernel kept the old partition table. The installer erased and repartitioned the disk without first letting go of partitions still in use (mounted by the live desktop, swap, or volumes left from an earlier system). Separately, the USB stick was only hidden from the disk list when written in DD mode; a Ventoy stick could be offered as a target | Yes (install fails on real hardware; possible risk to the USB stick) | Fixed: before erasing or resizing, the installer swaps off, unmounts and closes everything on the chosen disk, and stops with a clear message if something still holds it; it refuses to format unless the new partition table is in use; the USB stick is found through Ventoy/loop/device-mapper layers in both installers |
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
| 16:05 | f-manual-encrypted, low-spec | Panic key didn't lock the screen or wipe the clipboard, only on slower machines right after closing several windows | Test now waits up to 20 s and records whether anarch-panic ran. Has passed on every machine since (including low-spec): most likely a slow lock screen. Keep watching |
| 16:05, 18:07 | chromium | With Chromium as the browser no window appears within 90 s. Chromium 153 starts (GPU and network processes on /dev/dri/renderD128, Wayland) but never maps a window; Brave, same engine and flags, works | Known issue in the test set. Next: try --ozone-platform=x11 or --disable-gpu as a fallback and check on real hardware. Firefox (default), Brave and Zen pass |
| 20:05 | — | When the AUR is down the installer now skips yay, and nothing installs it later on its own | Add yay to the first-start catch-up (lumen-pending-apps) so it arrives once the AUR is back |

## Already fixed this week (found by VM tests)

- Notifications never showed (`notify-send -an`), every machine. Fixed 45a5e87.
- Live USB desktop never started (`.wants` link turned into a file). Fixed 45a5e87.
- Apps ticked in the installer (VS Code) weren't installed. Now installed on first start, f559e54.
- ISO build stopped (git "dubious ownership" on the copy). Fixed a889367.
- Install stopped at the very end with an AUR app ticked (busy unmount). Fixed 1082942.
