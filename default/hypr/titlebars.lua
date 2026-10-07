-- Title bars with close, maximise and minimise buttons on every window.
--
-- Drawn by Hyprland's official hyprbars plugin, built and loaded by
-- `anarch titlebars` (on by default; `anarch titlebars off` removes them).
-- Until the plugin is loaded this file does nothing.
--
-- Buttons, right to left: close, maximise/restore, minimise. Double-click
-- the bar to maximise; drag it to move a floating window.

if not (hl.plugin and hl.plugin.hyprbars) then
    return
end

local t = lumen.theme or {}
local function rgb(hex, fallback) return "rgb(" .. (hex or fallback) .. ")" end

hl.config({
    plugin = {
        hyprbars = {
            bar_height = 28,
            bar_color = rgb(t.bg_alt, "1a1b26"),
            col = { text = rgb(t.fg, "c0caf5") },
            bar_text_font = "Inter",
            bar_text_size = 10,
            bar_text_weight = "medium",
            bar_text_align = "center",
            bar_title_enabled = true,
            bar_part_of_window = true,
            bar_precedence_over_border = true,
            bar_buttons_alignment = "right",
            bar_padding = 10,
            bar_button_padding = 8,
            icon_on_hover = false,
            inactive_button_color = rgb(t.bg_hl, "3b4261"),
            on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
        },
    },
})

local button = hl.plugin.hyprbars.add_button
button({
    bg_color = rgb(t.red, "f7768e"), fg_color = rgb(t.bg, "1a1b26"), size = 14, icon = "󰅖",
    action = [[hyprctl dispatch 'hl.dsp.window.close()']],
})
button({
    bg_color = rgb(t.green, "9ece6a"), fg_color = rgb(t.bg, "1a1b26"), size = 14, icon = "󰊓",
    action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
})
button({
    bg_color = rgb(t.yellow, "e0af68"), fg_color = rgb(t.bg, "1a1b26"), size = 14, icon = "󰖰",
    action = lumen.cmd("window", "minimize"),
})
