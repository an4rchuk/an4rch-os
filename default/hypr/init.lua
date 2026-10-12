-- An4rch — Hyprland defaults.
--
-- This file is managed by An4rch and is replaced on `anarch update`.
-- Do not edit it: everything here can be overridden from the files in
-- ~/.config/hypr/, which are loaded after this one.

local home = os.getenv("HOME")
local root = os.getenv("LUMEN_PATH") or (home .. "/.local/share/lumen")

-- Shared state for the default modules and for your own files.
-- Use it from ~/.config/hypr/*.lua as `lumen.cmd("screenshot")` and so on.
lumen = {
    root  = root,
    home  = home,
    theme = {},
}

-- Absolute path to a bundled lumen command, so binds work even when PATH is
-- not yet set up (first login, broken shell profile, ...).
function lumen.cmd(name, args)
    local path = root .. "/bin/anarch-" .. name
    if args and args ~= "" then
        return path .. " " .. args
    end
    return path
end

-- Launch through anarch-launch, which runs apps as systemd scopes under uwsm.
function lumen.launch(what)
    return lumen.cmd("launch", what)
end

local function load(module)
    require(root .. "/default/hypr/" .. module)
end

load("env")
load("looks")
load("input")
load("rules")
load("binds")
load("autostart")

-- Colours come from the active theme (rendered by anarch-theme). A missing
-- theme must never stop the session from starting, so load it defensively.
local ok, palette = pcall(require, home .. "/.config/lumen/current/theme/hyprland")
if ok and type(palette) == "table" then
    lumen.theme = palette
end

-- Choices made in the Settings app (gaps, rounding, effects, mouse and
-- touchpad). Your own files in ~/.config/hypr/ still load after this.
pcall(require, home .. "/.config/lumen/desktop")

-- Title bars (hyprbars plugin) use the palette, so they load last.
load("titlebars")
