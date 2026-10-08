-- Environment for apps started inside the session.
-- Under uwsm the same variables are also set in ~/.config/uwsm/env so that
-- systemd-started services see them; keep the two in sync.

hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("HYPRCURSOR_SIZE", "24")

-- Native Wayland for Qt and Electron apps, with X11 as a fallback.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("SDL_VIDEODRIVER", "wayland,x11")

hl.env("LUMEN_PATH", lumen.root)
-- Prepend an4rch's commands once (this file runs again on every reload).
local path = os.getenv("PATH") or "/usr/local/bin:/usr/bin"
local bin = lumen.root .. "/bin"
if not (":" .. path .. ":"):find(":" .. bin .. ":", 1, true) then
    hl.env("PATH", bin .. ":" .. path)
end
