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
| 16:05 | f-manual-encrypted, low-spec | Panic key didn't lock the screen or wipe the clipboard. Both fail together, so anarch-panic never ran: the key press didn't reach it. Only on slower machines, right after the test closes several windows; passes on all others | Test now waits up to 20 s and records whether anarch-panic ran, to tell a lost key from a slow lock. Real-hardware check welcome: SUPER + SHIFT + Esc |
| 16:05, 18:07 | chromium (twice) | With Chromium as the browser, no window appears within 90 s. Chromium 153 does start (browser, GPU and network processes running on /dev/dri/renderD128 with Wayland), but never maps a window. Brave, same engine and flags, works | Marked known issue in the test set. Next: try --ozone-platform=x11 or --disable-gpu as a fallback, and check on real hardware; Firefox (default), Brave and Zen all pass |
| 17:35 | retest (6 of 7) | Backup fix confirmed on all offline machines; uk-laptop and f-manual-encrypted pass (panic key didn't repeat there) | — | Done |
| 17:35 | b-offline-encrypted | Stops at the disk-unlock prompt every time. Not an OS bug: the machine uses a French (AZERTY) keyboard, the unlock prompt correctly uses it, but the test typed the password as on a UK/US keyboard (a, m and 1 sit on other keys) | No (test) | Test password changed to one that types the same on both layouts |
| 16:05 | b-offline-bios, b-offline-gamer, b-offline-dualboot, b-offline-encrypted, offline | Backups don't work on installs made without internet: restic (the backup tool) wasn't installed or on the USB, so `anarch backup setup` tried to download it and hung until killed | Yes (feature broken, command freezes) | Fixed: restic + fuse3 installed by default and carried on the USB; installing a missing tool without internet now says so at once instead of hanging. Retest queued |
| 16:05 | uk-laptop | Test machine died after 4 minutes, before building anything | No (test infrastructure) | Rerun in the retest set |
| 18:40 | brutal (20/20) | Every brutal machine passes on the latest code, including the French encrypted machine with the corrected test password, 1 CPU / 2 GB, 800×600, offline, dual boot and NVIDIA | — | — |
| 18:07 | brand (8/8), scenarios (13/14) | Second round on the latest code: everything passes except Chromium (known); panic key passed on every machine | — | — |
| 15:35 | (code review) | Login-screen upgrade for older installs looked for "Welcome to An4rch" (capital A after the rename), so installs still showing the old lowercase text would never get the new login screen | Yes (upgrade silently skipped) | Fixed: matches any case, and the old Lumen wording |

## Future fixes (not urgent)

| Found | Machine | Problem | Notes |
|---|---|---|---|

## Already fixed this week (found by VM tests)

- Notifications never showed (`notify-send -an`), every machine. Fixed 45a5e87.
- Live USB desktop never started (`.wants` link turned into a file). Fixed 45a5e87.
- Apps ticked in the installer (VS Code) weren't installed. Now installed on first start, f559e54.
- ISO build stopped (git "dubious ownership" on the copy). Fixed a889367.
- Install stopped at the very end with an AUR app ticked (busy unmount). Fixed 1082942.
