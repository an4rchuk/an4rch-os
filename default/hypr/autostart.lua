-- Session services started with Hyprland.
-- Add your own in ~/.config/hypr/autostart.lua. Apps with an XDG autostart
-- entry (~/.config/autostart/*.desktop) are started by uwsm automatically.

local cmd = lumen.cmd

hl.on("hyprland.start", function()
    hl.exec_cmd(cmd("session", "start"))
end)
