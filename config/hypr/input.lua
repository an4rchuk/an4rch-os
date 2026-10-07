-- Keyboard, mouse and touchpad. Anything set here overrides an4rch's defaults.
-- All options: https://wiki.hypr.land/configuring/core/config-options/#input

hl.config({
    input = {
        kb_layout  = "us",
        -- kb_variant = "",
        -- Two layouts, switch with ALT + SHIFT:
        -- kb_layout  = "us,de",
        -- kb_options = "compose:ralt,grp:alt_shift_toggle",
        -- Make Caps Lock a second Escape:
        -- kb_options = "compose:ralt,caps:escape",

        -- sensitivity = 0,          -- -1.0 … 1.0
        -- touchpad = {
        --     natural_scroll = true,
        --     scroll_factor  = 0.4,
        -- },
    },
})

-- Settings for one specific device (names from `hyprctl devices`):
-- hl.device({ name = "logitech-mx-master-3", sensitivity = -0.3 })
