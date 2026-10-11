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

## Future fixes (not urgent)

| Found | Machine | Problem | Notes |
|---|---|---|---|

## Already fixed this week (found by VM tests)

- Notifications never showed (`notify-send -an`), every machine. Fixed 45a5e87.
- Live USB desktop never started (`.wants` link turned into a file). Fixed 45a5e87.
- Apps ticked in the installer (VS Code) weren't installed. Now installed on first start, f559e54.
- ISO build stopped (git "dubious ownership" on the copy). Fixed a889367.
- Install stopped at the very end with an AUR app ticked (busy unmount). Fixed 1082942.
