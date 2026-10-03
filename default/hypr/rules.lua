-- Window, layer and workspace rules.
-- Find a window's class with `hyprctl clients` or `lumen-doctor windows`.

-- Apps should not maximise themselves; tiling decides their size.
hl.window_rule({
    name  = "lumen-suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Fix focus-stealing ghost windows from XWayland drag-and-drop.
hl.window_rule({
    name  = "lumen-xwayland-drag",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- Lumen dialogs: TUIs opened with `lumen-term --float` (Wi-Fi, Bluetooth,
-- audio, package installer, ...) behave like centred dialogs.
hl.window_rule({
    name  = "lumen-floating",
    match = { class = "^(lumen\\.floating)$" },
    float  = true,
    center = true,
    size   = { "monitor_w*0.55", "monitor_h*0.6" },
})

-- Small utility windows float by default.
local floating = table.concat({
    "org\\.pulseaudio\\.pavucontrol",
    "blueman-manager",
    "nm-connection-editor",
    "org\\.gnome\\.Calculator",
    "xdg-desktop-portal-gtk",
    "hyprland-share-picker",
    "hyprpolkitagent",
    "polkit-gnome-authentication-agent-1",
    "org\\.gnome\\.FileRoller",
    "com\\.gabm\\.satty",
    "imv",
    "mpv",
    "org\\.gnome\\.Loupe",
}, "|")

hl.window_rule({
    name   = "lumen-float-utilities",
    match  = { class = "^(" .. floating .. ")$" },
    float  = true,
    center = true,
})

hl.window_rule({
    name  = "lumen-utility-size",
    match = { class = "^(org\\.pulseaudio\\.pavucontrol|blueman-manager|nm-connection-editor)$" },
    size  = { 860, 560 },
})

-- File pickers and other standard dialogs.
hl.window_rule({
    name   = "lumen-float-dialogs",
    match  = { title = "^(Open File|Open Folder|Save As|Save File|Select a File|Choose Files|File Upload|Library|Confirm to replace files|File Operation Progress)(.*)$" },
    float  = true,
    center = true,
})

hl.window_rule({ name = "lumen-modal-center", match = { modal = true }, float = true, center = true })

-- Authentication prompts get focus and dim everything else.
hl.window_rule({
    name  = "lumen-auth",
    match = { class = "^(hyprpolkitagent|polkit-gnome-authentication-agent-1|gcr-prompter|pinentry-.*)$" },
    float = true,
    center = true,
    dim_around = true,
    stay_focused = true,
})

-- Picture-in-picture stays on top in the corner.
hl.window_rule({
    name  = "lumen-pip",
    match = { title = "^(Picture-in-Picture|Picture in picture)$" },
    float = true,
    pin   = true,
    keep_aspect_ratio = true,
    size  = { "monitor_w*0.25", "monitor_h*0.25" },
    move  = { "monitor_w*0.74", "monitor_h*0.72" },
})

-- Do not let the screen go to sleep while something is fullscreen.
hl.window_rule({ name = "lumen-idle-fullscreen", match = { class = ".*" }, idle_inhibit = "fullscreen" })

-- Video and images look best without transparency or blur.
hl.window_rule({
    name  = "lumen-opaque-media",
    match = { class = "^(mpv|imv|org\\.gnome\\.Loupe|vlc|com\\.obsproject\\.Studio)$" },
    opaque  = true,
    no_blur = true,
})

-- Browsers and editors render their own background, keep them solid.
hl.window_rule({
    name  = "lumen-opaque-apps",
    match = { class = "^(firefox|chromium|google-chrome|brave-browser|zen|code|code-oss|Code|dev\\.zed\\.Zed|org\\.gnome\\.Nautilus)$" },
    opacity = "1.0 override 0.97 override",
})

-- Steam and games: no compositor effects in the way.
hl.window_rule({ name = "lumen-games", match = { content = "game" }, no_blur = true, no_shadow = true, idle_inhibit = "always" })
hl.window_rule({ name = "lumen-steam-float", match = { class = "^(steam)$", title = "^(Friends List|Steam Settings)$" }, float = true })

---------------------------------------------------------------------------
-- Layers (bar, launcher, notifications, OSDs)
---------------------------------------------------------------------------

hl.layer_rule({ name = "lumen-blur-bar",      match = { namespace = "^waybar$" },        blur = true, ignore_alpha = 0.2 })
hl.layer_rule({ name = "lumen-blur-launcher", match = { namespace = "^launcher$" },      blur = true, ignore_alpha = 0.2, animation = "popin 95%" })
hl.layer_rule({ name = "lumen-blur-notify",   match = { namespace = "^notifications$" }, blur = true, ignore_alpha = 0.2, animation = "slide right" })
hl.layer_rule({ name = "lumen-no-anim-selection", match = { namespace = "^(selection|hyprpicker)$" }, no_anim = true })

---------------------------------------------------------------------------
-- Workspaces
---------------------------------------------------------------------------

-- A single tiled window gets slightly larger gaps so it does not look lost.
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 16 })
