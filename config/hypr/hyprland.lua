-- ~/.config/hypr/hyprland.lua
--
-- Lumen's defaults are loaded first; every file below is yours to edit and is
-- loaded afterwards, so anything set there wins. Hyprland reloads on save.
--
-- Docs: SUPER + F1 (Lumen manual) and https://wiki.hypr.land/

local lumen_root = os.getenv("LUMEN_PATH") or (os.getenv("HOME") .. "/.local/share/lumen")
require(lumen_root .. "/default/hypr/init")

require("./monitors")   -- displays: resolution, scale, position (or SUPER + ALT + D)
require("./input")      -- keyboard layout, touchpad, mouse
require("./looks")      -- gaps, borders, blur, animations
require("./bindings")   -- your own key bindings
require("./rules")      -- your own window rules
require("./autostart")  -- apps to start on login
