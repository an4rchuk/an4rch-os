-- an4rch key bindings.
--
-- The layout of the keyboard map:
--   SUPER + key            apps and windows
--   SUPER + SHIFT + key    move things / capture tools
--   SUPER + CTRL + key     system toggles and style
--   SUPER + ALT + key      setup panels (network, bluetooth, audio, displays)
--
-- Every bind has a description: SUPER + / lists them all.
-- Override or remove any of them in ~/.config/hypr/bindings.lua, e.g.
--   hl.unbind("SUPER + B")
--   hl.bind("SUPER + B", hl.dsp.exec_cmd("chromium"), { description = "Browser" })

local cmd    = lumen.cmd
local launch = lumen.launch
local exec   = hl.dsp.exec_cmd

local function bind(keys, action, description, opts)
    opts = opts or {}
    opts.description = description
    hl.bind(keys, action, opts)
end

---------------------------------------------------------------------------
-- Apps
---------------------------------------------------------------------------
bind("SUPER + Return",        exec(launch("terminal")),                "Terminal")
-- Tap the Windows key on its own for the Start menu. As a release bind it
-- only fires when no other shortcut was used while Super was held.
bind("SUPER + SUPER_L",       exec(cmd("start")),                      "Start menu (tap the Windows key)", { release = true })
bind("SUPER + SUPER_R",       exec(cmd("start")),                      "Start menu (right Windows key)", { release = true })
bind("SUPER + SPACE",         exec(cmd("launcher")),                   "Quick app launcher")
bind("SUPER + A",             exec(cmd("store")),                      "App Store")
bind("SUPER + ALT + SPACE",   exec(cmd("menu")),                       "an4rch menu")
bind("SUPER + B",             exec(launch("browser")),                 "Browser")
bind("SUPER + SHIFT + B",     exec(launch("browser --private")),       "Browser (private window)")
bind("SUPER + E",             exec(launch("files")),                   "File manager")
bind("SUPER + C",             exec(launch("editor")),                  "Code editor")
bind("SUPER + SHIFT + Return", exec(cmd("term", "--float")),           "Floating terminal")
bind("SUPER + grave",         exec(cmd("windows")),                    "Find an open window")
bind("SUPER + slash",         exec(cmd("keys")),                       "Show all key bindings")
bind("SUPER + F1",            exec(cmd("manual")),                     "Open the an4rch manual")
bind("SUPER + I",             exec(cmd("settings")),                   "Settings")
bind("CTRL + SHIFT + Escape",  exec(launch("monitor")),                 "Task Manager (like Windows)")

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------
bind("SUPER + W",          hl.dsp.window.close(),                                 "Close window")
bind("SUPER + SHIFT + Q",  hl.dsp.window.kill(),                                  "Force quit window")
bind("SUPER + F",          hl.dsp.window.fullscreen({ mode = "fullscreen" }),     "Fullscreen")
bind("SUPER + M",          hl.dsp.window.fullscreen({ mode = "maximized" }),      "Maximise (keep bar and gaps)")
bind("SUPER + comma",      exec(cmd("window", "minimize")),                        "Minimise window")
bind("SUPER + SHIFT + M",  exec(cmd("window", "restore-menu")),                    "Restore a minimised window")
bind("SUPER + T",          hl.dsp.window.float({ action = "toggle" }),            "Toggle floating")
bind("SUPER + P",          hl.dsp.window.pin({ action = "toggle" }),              "Pin floating window to all workspaces")
bind("SUPER + J",          hl.dsp.layout("togglesplit"),                          "Toggle split direction")
bind("SUPER + G",          hl.dsp.group.toggle(),                                 "Group windows into tabs")
bind("SUPER + ALT + G",    hl.dsp.window.move({ out_of_group = true }),           "Move window out of group")
bind("SUPER + bracketleft",  hl.dsp.group.prev(),                                 "Previous tab in group")
bind("SUPER + bracketright", hl.dsp.group.next(),                                 "Next tab in group")
bind("SUPER + R",          hl.dsp.submap("resize"),                               "Resize mode (arrows/hjkl, Esc to leave)")

bind("ALT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
end, "Cycle windows")
bind("ALT + SHIFT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next({ next = false }))
    hl.dispatch(hl.dsp.window.bring_to_top())
end, "Cycle windows backwards")

-- Focus with arrows or vim keys, move with SHIFT.
local directions = {
    { "left", "h", "left" }, { "right", "l", "right" },
    { "up", "k", "up" },     { "down", "j", "down" },
}
for _, d in ipairs(directions) do
    local arrow, vim, dir = d[1], d[2], d[3]
    bind("SUPER + " .. arrow,          hl.dsp.focus({ direction = dir }),       "Focus " .. dir)
    bind("SUPER + SHIFT + " .. arrow,  hl.dsp.window.move({ direction = dir }), "Move window " .. dir)
    if vim ~= "j" then -- SUPER + J is "toggle split"
        bind("SUPER + " .. vim,         hl.dsp.focus({ direction = dir }),       "Focus " .. dir)
    end
    bind("SUPER + SHIFT + " .. vim,    hl.dsp.window.move({ direction = dir }), "Move window " .. dir)
end

-- Mouse: SUPER + drag to move, SUPER + right-drag to resize.
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Drag window" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

hl.define_submap("resize", function()
    local step = 40
    local keys = {
        { "left",  "h", -step, 0 }, { "right", "l", step, 0 },
        { "up",    "k", 0, -step }, { "down",  "j", 0, step },
    }
    for _, k in ipairs(keys) do
        local action = hl.dsp.window.resize({ x = k[3], y = k[4], relative = true })
        hl.bind(k[1], action, { repeating = true })
        hl.bind(k[2], action, { repeating = true })
    end
    hl.bind("escape", hl.dsp.submap("reset"))
    hl.bind("Return", hl.dsp.submap("reset"))
    hl.bind("SUPER + R", hl.dsp.submap("reset"))
end)

---------------------------------------------------------------------------
-- Workspaces
---------------------------------------------------------------------------
for i = 1, 10 do
    local key = tostring(i % 10)
    bind("SUPER + " .. key,         hl.dsp.focus({ workspace = i }),                         "Go to workspace " .. i)
    bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }),                   "Move window to workspace " .. i)
    bind("SUPER + CTRL + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }), "Send window to workspace " .. i .. " silently")
end

bind("SUPER + Tab",            hl.dsp.focus({ workspace = "previous" }),     "Previous workspace")
bind("SUPER + CTRL + right",   hl.dsp.focus({ workspace = "r+1" }),          "Next workspace")
bind("SUPER + CTRL + left",    hl.dsp.focus({ workspace = "r-1" }),          "Previous workspace (by number)")
bind("SUPER + mouse_down",     hl.dsp.focus({ workspace = "e+1" }),          "Next workspace")
bind("SUPER + mouse_up",       hl.dsp.focus({ workspace = "e-1" }),          "Previous workspace")
bind("SUPER + S",              hl.dsp.workspace.toggle_special("scratch"),   "Toggle scratchpad")
bind("SUPER + SHIFT + S",      hl.dsp.window.move({ workspace = "special:scratch" }), "Move window to scratchpad")
bind("SUPER + period",         hl.dsp.focus({ monitor = "+1" }),             "Focus next monitor")
bind("SUPER + SHIFT + period", hl.dsp.window.move({ monitor = "+1" }),       "Move window to next monitor")

---------------------------------------------------------------------------
-- Capture and utilities (SUPER + SHIFT)
---------------------------------------------------------------------------
bind("Print",                  exec(cmd("screenshot", "region")),  "Screenshot a region")
bind("SHIFT + Print",          exec(cmd("screenshot", "window")),  "Screenshot the active window")
bind("CTRL + Print",           exec(cmd("screenshot", "screen")),  "Screenshot the whole screen")
bind("SUPER + SHIFT + X",      exec(cmd("screenshot", "region")),  "Screenshot a region")
bind("SUPER + SHIFT + E",      exec(cmd("screenshot", "edit")),    "Screenshot a region and annotate")
bind("SUPER + SHIFT + R",      exec(cmd("record", "region")),      "Record a region (again to stop)")
bind("SUPER + CTRL + SHIFT + R", exec(cmd("record", "screen")),    "Record the screen (again to stop)")
bind("SUPER + SHIFT + C",      exec(cmd("pick-color")),            "Pick a colour from the screen")
bind("SUPER + SHIFT + T",      exec(cmd("ocr")),                   "Copy text from a screen region (OCR)")
bind("SUPER + V",              exec(cmd("clipboard")),             "Clipboard history")
bind("SUPER + SHIFT + V",      exec(cmd("clipboard", "clear")),    "Clear clipboard history")
bind("SUPER + semicolon",      exec(cmd("emoji")),                 "Emoji picker")
bind("SUPER + equal",          exec(cmd("calc")),                  "Calculator")
bind("SUPER + SHIFT + A",      exec(cmd("remind")),                "New reminder")
bind("SUPER + SHIFT + W",      exec(cmd("search")),                "Search the web")
bind("SUPER + N",              exec("makoctl dismiss"),            "Dismiss notification")
bind("SUPER + SHIFT + N",      exec("makoctl dismiss --all"),      "Dismiss all notifications")
bind("SUPER + ALT + N",        exec("makoctl restore"),            "Bring back last notification")
bind("SUPER + CTRL + period",  exec("makoctl invoke"),             "Open notification (default action)")

---------------------------------------------------------------------------
-- System (SUPER + CTRL)
---------------------------------------------------------------------------
bind("SUPER + Escape",         exec(cmd("power")),                 "Power menu")
bind("SUPER + SHIFT + Escape", exec(cmd("panic")),                 "Panic: hide everything, close vaults, lock")
bind("SUPER + CTRL + L",       exec("loginctl lock-session"),      "Lock screen")
bind("SUPER + CTRL + T",       exec(cmd("theme")),                 "Pick a theme")
bind("SUPER + CTRL + SHIFT + T", exec(cmd("theme", "next")),       "Next theme")
bind("SUPER + CTRL + W",       exec(cmd("wallpaper", "next")),     "Next wallpaper")
bind("SUPER + CTRL + SHIFT + W", exec(cmd("wallpaper", "pick")),   "Pick a wallpaper")
bind("SUPER + CTRL + N",       exec(cmd("toggle", "nightlight")),  "Toggle night light")
bind("SUPER + CTRL + I",       exec(cmd("toggle", "idle")),        "Keep awake (pause screen lock)")
bind("SUPER + CTRL + D",       exec(cmd("toggle", "dnd")),         "Toggle Do Not Disturb")
bind("SUPER + CTRL + F",       exec(cmd("focus")),                 "Start / stop a 25-minute focus session")
bind("SUPER + CTRL + B",       exec(cmd("toggle", "bar")),         "Show or hide the top bar")
bind("SUPER + CTRL + G",       exec(cmd("toggle", "gaps")),        "Toggle gaps and rounding")
bind("SUPER + CTRL + S",       exec(cmd("toggle", "layout")),      "Switch tiling / scrolling layout")
bind("SUPER + CTRL + P",       exec(cmd("power-profile", "next")), "Cycle power profile")
bind("SUPER + CTRL + Z", function()
    local zoom = hl.get_config("cursor.zoom_factor") or 1
    hl.config({ cursor = { zoom_factor = (zoom > 1) and 1 or 2 } })
end, "Zoom in / out around the cursor")

---------------------------------------------------------------------------
-- Setup panels (SUPER + ALT)
---------------------------------------------------------------------------
bind("SUPER + ALT + W", exec(cmd("wifi")),       "Wi-Fi")
bind("SUPER + ALT + B", exec(cmd("bluetooth")),  "Bluetooth")
bind("SUPER + ALT + A", exec(cmd("audio")),      "Sound panel: volume and devices")
bind("SUPER + ALT + D", exec(cmd("display")),    "Displays")
bind("SUPER + ALT + T", exec(launch("monitor")), "System monitor")
bind("SUPER + ALT + I", exec(cmd("pkg", "install")), "Install apps")
bind("SUPER + ALT + U", exec(cmd("update")),     "Update the system")
bind("SUPER + ALT + R", exec(cmd("a11y", "reader")), "Screen reader on / off")
bind("SUPER + ALT + P", exec(cmd("privacy")),    "Privacy (hidden MAC, encrypted DNS, tracker blocking)")

---------------------------------------------------------------------------
-- Hardware keys (work on the lock screen too)
---------------------------------------------------------------------------
local hw = { locked = true, repeating = true }
bind("XF86AudioRaiseVolume",  exec(cmd("osd", "volume up")),        "Volume up",     hw)
bind("XF86AudioLowerVolume",  exec(cmd("osd", "volume down")),      "Volume down",   hw)
bind("XF86AudioMute",         exec(cmd("osd", "volume mute")),      "Mute",          { locked = true })
bind("XF86AudioMicMute",      exec(cmd("osd", "mic mute")),         "Mute microphone", { locked = true })
bind("XF86MonBrightnessUp",   exec(cmd("osd", "brightness up")),    "Brightness up", hw)
bind("XF86MonBrightnessDown", exec(cmd("osd", "brightness down")),  "Brightness down", hw)
bind("XF86KbdBrightnessUp",   exec(cmd("osd", "keyboard up")),      "Keyboard light up", hw)
bind("XF86KbdBrightnessDown", exec(cmd("osd", "keyboard down")),    "Keyboard light down", hw)
bind("ALT + XF86AudioRaiseVolume", exec(cmd("osd", "volume up-fine")),   "Volume up (fine)", hw)
bind("ALT + XF86AudioLowerVolume", exec(cmd("osd", "volume down-fine")), "Volume down (fine)", hw)
bind("XF86AudioPlay",  exec("playerctl play-pause"), "Play / pause",   { locked = true })
bind("XF86AudioPause", exec("playerctl play-pause"), "Play / pause",   { locked = true })
bind("XF86AudioNext",  exec("playerctl next"),       "Next track",     { locked = true })
bind("XF86AudioPrev",  exec("playerctl previous"),   "Previous track", { locked = true })
bind("XF86PowerOff",   exec(cmd("power")),           "Power menu")
bind("XF86Calculator", exec(cmd("calc")),            "Calculator")
-- More laptop keys (Fn + F-row on ASUS, HP, Lenovo, Dell, …).
bind("XF86KbdLightOnOff",   exec(cmd("osd", "keyboard cycle")), "Keyboard light (step / off)", { locked = true })
bind("XF86TouchpadToggle",  exec(cmd("toggle", "touchpad")),    "Touchpad on/off")
bind("XF86TouchpadOn",      exec(cmd("toggle", "touchpad", "on")),  "Touchpad on")
bind("XF86TouchpadOff",     exec(cmd("toggle", "touchpad", "off")), "Touchpad off")
bind("XF86Display",         exec(cmd("display")),               "Displays (projector / second screen)")
bind("XF86ScreenSaver",     exec("loginctl lock-session"),      "Lock screen")
bind("XF86Sleep",           exec("systemctl suspend"),          "Sleep")
bind("XF86Explorer",        exec(launch("files")),              "File manager")
bind("XF86MyComputer",      exec(launch("files")),              "File manager")
bind("XF86HomePage",        exec(launch("browser")),            "Browser")
bind("XF86WWW",             exec(launch("browser")),            "Browser")
bind("XF86Search",          exec(cmd("start")),                 "Start menu (search)")
bind("XF86Tools",           exec(cmd("settings")),              "Settings")
bind("XF86AudioStop",       exec("playerctl stop"),             "Stop playback", { locked = true })
