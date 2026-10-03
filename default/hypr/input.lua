-- Keyboard, mouse and touchpad defaults.
-- Change your layout in ~/.config/hypr/input.lua, e.g. kb_layout = "us,de".

hl.config({
    input = {
        kb_layout  = "us",
        kb_options = "compose:ralt",

        repeat_delay = 280,
        repeat_rate  = 40,
        numlock_by_default = true,

        follow_mouse = 1,
        sensitivity  = 0,
        accel_profile = "adaptive",

        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
            clickfinger_behavior = true,
            scroll_factor        = 0.4,
            tap_button_map       = "lrm",
        },
    },

    gestures = {
        workspace_swipe_create_new = true,
        workspace_swipe_forever    = false,
    },
})

-- Three-finger swipe moves between workspaces.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
-- Three-finger swipe up shows the scratchpad, down hides it.
hl.gesture({ fingers = 3, direction = "up", action = "special", workspace_name = "scratch" })
