-- Displays. Run `hyprctl monitors` to see names, or use SUPER + ALT + D,
-- which writes this file for you (your previous version is kept as
-- monitors.lua.bak).
--
-- Fields: output, mode ("preferred", "highrr", "2560x1440@144"), position
-- ("auto", "auto-right", "0x0"), scale (1, 1.25, 1.5, 2 or "auto"),
-- transform (0-7, rotation), mirror, vrr, bitdepth.

-- Any display without its own rule: best mode, sensible scale, placed to the right.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- Examples:
-- hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1.5 })
-- hl.monitor({ output = "DP-1",  mode = "2560x1440@144", position = "auto-right", scale = 1 })
-- hl.monitor({ output = "desc:Dell Inc. DELL U2723QE", mode = "preferred", position = "auto-left", scale = 1.5 })
-- hl.monitor({ output = "HDMI-A-1", mirror = "eDP-1" })
