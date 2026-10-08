-- Look and feel: gaps, borders, blur, shadows and motion.
-- Colours are set by the active theme (see `anarch-theme`).

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 12,
        border_size = 2,
        layout      = "dwindle",

        resize_on_border       = true,
        extend_border_grab_area = 12,
        hover_icon_on_border   = true,
        allow_tearing          = false,

        snap = {
            enabled     = true,
            window_gap  = 12,
            monitor_gap = 12,
        },
    },

    decoration = {
        rounding       = 12,
        rounding_power = 2.4,

        active_opacity   = 1.0,
        inactive_opacity = 0.97,

        dim_special  = 0.25,

        shadow = {
            enabled      = true,
            range        = 18,
            render_power = 3,
            offset       = "0 6",
            color        = "rgba(0000005a)",
            color_inactive = "rgba(00000030)",
        },

        blur = {
            enabled           = true,
            size              = 6,
            passes            = 2,
            vibrancy          = 0.18,
            noise             = 0.012,
            new_optimizations = true,
            popups            = true,
            special           = true,
        },
    },

    group = {
        groupbar = {
            font_family  = "Inter",
            font_size    = 11,
            height       = 18,
            rounding     = 6,
            gradients    = true,
            indicator_height = 0,
            gaps_in      = 4,
            gaps_out     = 4,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
        smart_resizing = true,
    },

    master = {
        new_status = "master",
        mfact      = 0.55,
    },

    scrolling = {
        fullscreen_on_one_column = true,
    },

    misc = {
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        focus_on_activate       = true,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms  = true,
        animate_manual_resizes  = true,
        enable_swallow          = false,
        font_family             = "Inter",
    },

    cursor = {
        hide_on_key_press = true,
        inactive_timeout  = 8,
    },

    binds = {
        workspace_back_and_forth  = true,
        allow_workspace_cycles    = true,
        hide_special_on_workspace_change = true,
    },

    ecosystem = {
        no_update_news  = true,
        no_donation_nag = true,
    },
})

-- Motion: quick, soft and never bouncy. Speed is in tenths of a second, so
-- windows open in about a quarter of a second, as on Windows and macOS.
-- Only bezier curves are used, which keeps this file valid across Hyprland
-- releases.
hl.curve("lumenOut",  { type = "bezier", points = { {0.16, 1},   {0.3, 1} } })
hl.curve("lumenIn",   { type = "bezier", points = { {0.7, 0},    {0.84, 0} } })
hl.curve("lumenSoft", { type = "bezier", points = { {0.25, 0.1}, {0.25, 1} } })
hl.curve("linear",    { type = "bezier", points = { {0, 0},      {1, 1} } })

hl.animation({ leaf = "global",          enabled = true, speed = 4,   bezier = "lumenSoft" })
hl.animation({ leaf = "windowsIn",       enabled = true, speed = 2.4, bezier = "lumenOut", style = "popin 92%" })
hl.animation({ leaf = "windowsOut",      enabled = true, speed = 1.6, bezier = "lumenIn",  style = "popin 92%" })
hl.animation({ leaf = "windowsMove",     enabled = true, speed = 2.6, bezier = "lumenOut" })
hl.animation({ leaf = "border",          enabled = true, speed = 3,   bezier = "lumenSoft" })
hl.animation({ leaf = "fade",            enabled = true, speed = 2,   bezier = "lumenSoft" })
hl.animation({ leaf = "layersIn",        enabled = true, speed = 1.8, bezier = "lumenOut", style = "fade" })
hl.animation({ leaf = "layersOut",       enabled = true, speed = 1.4, bezier = "lumenIn",  style = "fade" })
hl.animation({ leaf = "workspaces",      enabled = true, speed = 2.8, bezier = "lumenOut", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2.6, bezier = "lumenOut", style = "slidevert" })
hl.animation({ leaf = "zoomFactor",      enabled = true, speed = 5,   bezier = "lumenOut" })
