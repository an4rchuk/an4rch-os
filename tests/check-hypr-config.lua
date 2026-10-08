-- Load an4rch's Hyprland config against a stub `hl` API generated from the
-- Hyprland source (tests/hypr-api.lua) and report anything Hyprland would
-- reject: unknown options, rule fields, dispatchers, events or bind flags,
-- plus duplicate key bindings.
--
--   lua5.4 tests/check-hypr-config.lua <main-config.lua> <tests-dir>
--
-- Run through tests/run.sh, which prepares a throwaway $HOME first.

local main_config, tests_dir = arg[1], arg[2]
local api = dofile(tests_dir .. "/hypr-api.lua")

local function set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

local CONFIG       = set(api.config)
local WIN_EFFECTS  = set(api.window_effects)
local LAYER_EFFECTS = set(api.layer_effects)
local WS_FIELDS    = set(api.workspace_fields)
local MON_FIELDS   = set(api.monitor_fields)
local DEV_FIELDS   = set(api.device_fields)
local MATCH        = set(api.match_props)
local ANIMS        = set(api.animations)
local BIND_OPTS    = set(api.bind_options)
local EVENTS       = set(api.events)
local GESTURE_KEYS = set({ "fingers", "direction", "action", "mods", "scale", "disable_inhibit",
                            "workspace_name", "zoom_level", "mode" })
local GESTURE_ACTIONS = set({ "workspace", "resize", "move", "special", "close", "float",
                              "fullscreen", "cursor_zoom", "scroll_move", "unset" })

local errors, stats = {}, { binds = 0, window_rules = 0, layer_rules = 0, config_keys = 0 }

-- The first stack frame outside this harness is the config line to blame.
local self_src = debug.getinfo(1, "S").short_src
local function where()
    for level = 2, 20 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end
        if info.short_src ~= self_src and info.what ~= "C" then
            return info.short_src .. ":" .. (info.currentline or "?")
        end
    end
    return "?"
end

local function err(msg)
    errors[#errors + 1] = where() .. ": " .. msg
end

-- hl.config walks nested tables exactly like Hyprland: a dotted path that is a
-- known option is a value, otherwise a table is descended into.
-- The hyprbars plugin's options and Lua API (hyprland-plugins, Lua-config
-- era). The stub behaves as if the plugin is loaded, so titlebars.lua is
-- checked too.
for _, k in ipairs({ "enabled", "bar_color", "col.text", "inactive_button_color", "bar_height",
    "bar_text_size", "bar_text_weight", "bar_title_enabled", "bar_blur", "bar_text_font",
    "bar_text_align", "bar_part_of_window", "bar_precedence_over_border", "bar_buttons_alignment",
    "bar_padding", "bar_button_padding", "icon_on_hover", "buttons_on_hover", "on_double_click" }) do
    CONFIG["plugin.hyprbars." .. k] = true
end
local HYPRBARS_BUTTON = { bg_color = true, fg_color = true, size = true, icon = true, action = true }

local function walk(prefix, t)
    for k, v in pairs(t) do
        local key = prefix == "" and k or (prefix .. "." .. k)
        if CONFIG[key] then
            stats.config_keys = stats.config_keys + 1
        elseif type(v) == "table" then
            walk(key, v)
        else
            errors[#errors + 1] = "unknown config key '" .. key .. "'"
        end
    end
end

local function check_fields(fn, t, allowed, extra)
    for k, _ in pairs(t) do
        if not allowed[k] and not (extra and extra[k]) then
            err(fn .. ": unknown field '" .. tostring(k) .. "'")
        end
    end
end

local function check_match(fn, t)
    if type(t.match) ~= "table" then
        err(fn .. ": missing match table")
        return
    end
    for k, v in pairs(t.match) do
        if not MATCH[k] then err(fn .. ": unknown match property '" .. k .. "'") end
        if type(v) == "string" and not pcall(string.find, "", v) then
            -- Lua patterns are not regexes, but a malformed pattern usually
            -- means an unbalanced bracket in the regex too.
            err(fn .. ": suspicious pattern '" .. v .. "'")
        end
    end
end

-- Dispatchers return tagged tables so binds can verify their action.
local DSP_TAG = {}
local function make_dsp()
    local dsp = {}
    for _, name in ipairs(api.dispatchers) do
        local parent, leaf = name:match("^(%w+)%.([%w_]+)$")
        local target = dsp
        if parent then
            dsp[parent] = dsp[parent] or {}
            target = dsp[parent]
        else
            leaf = name
        end
        target[leaf] = function(...) return { [DSP_TAG] = name, args = { ... } } end
    end
    return setmetatable(dsp, {
        __index = function(_, k) err("unknown dispatcher hl.dsp." .. tostring(k)) return {} end,
    })
end

local seen_binds, current_submap = {}, ""
local handlers = {}

local function normalise_keys(keys)
    local parts = {}
    for p in keys:gmatch("[^+]+") do parts[#parts + 1] = (p:gsub("^%s+", ""):gsub("%s+$", "")) end
    local key = table.remove(parts)
    table.sort(parts)
    return table.concat(parts, "+"):upper() .. "+" .. (key or "")
end

hl = {
    dsp = make_dsp(),

    config = function(t)
        if type(t) ~= "table" then return err("hl.config: argument must be a table") end
        walk("", t)
    end,

    get_config = function(key)
        if not CONFIG[key] then err("hl.get_config: unknown key '" .. tostring(key) .. "'") end
        return 1
    end,

    bind = function(keys, action, opts)
        stats.binds = stats.binds + 1
        if type(keys) ~= "string" or keys == "" then return err("hl.bind: bad key string") end
        if type(action) ~= "function" and not (type(action) == "table" and action[DSP_TAG]) then
            err("hl.bind(" .. keys .. "): action must be a dispatcher or function")
        end
        if opts ~= nil then
            if type(opts) ~= "table" then return err("hl.bind(" .. keys .. "): options must be a table") end
            check_fields("hl.bind(" .. keys .. ")", opts, BIND_OPTS)
        end
        local id = current_submap .. "|" .. normalise_keys(keys)
        if seen_binds[id] then
            err("duplicate binding '" .. keys .. "' (first at " .. seen_binds[id] .. ")")
        else
            seen_binds[id] = where()
        end
        return { set_enabled = function() end }
    end,

    unbind = function(keys)
        seen_binds[current_submap .. "|" .. normalise_keys(keys)] = nil
    end,

    define_submap = function(name, fn)
        local previous = current_submap
        current_submap = name
        fn()
        current_submap = previous
    end,

    window_rule = function(t)
        stats.window_rules = stats.window_rules + 1
        check_match("hl.window_rule", t)
        check_fields("hl.window_rule", t, WIN_EFFECTS, set({ "name", "enabled", "match" }))
        return { set_enabled = function() end, is_enabled = function() return true end }
    end,

    layer_rule = function(t)
        stats.layer_rules = stats.layer_rules + 1
        check_match("hl.layer_rule", t)
        check_fields("hl.layer_rule", t, LAYER_EFFECTS, set({ "name", "enabled", "match" }))
        return { set_enabled = function() end }
    end,

    workspace_rule = function(t)
        if type(t.workspace) ~= "string" then err("hl.workspace_rule: 'workspace' must be a string") end
        check_fields("hl.workspace_rule", t, WS_FIELDS, set({ "workspace", "enabled", "layout_opts" }))
    end,

    monitor = function(t)
        if type(t.output) ~= "string" then err("hl.monitor: 'output' must be a string") end
        check_fields("hl.monitor", t, MON_FIELDS, set({ "output" }))
    end,

    device = function(t)
        if type(t.name) ~= "string" then err("hl.device: 'name' is required") end
        check_fields("hl.device", t, DEV_FIELDS, set({ "name" }))
    end,

    gesture = function(t)
        check_fields("hl.gesture", t, GESTURE_KEYS)
        if type(t.action) == "string" and not GESTURE_ACTIONS[t.action] then
            err("hl.gesture: unknown action '" .. t.action .. "'")
        end
        if t.action == "special" and not t.workspace_name then
            err("hl.gesture: special needs workspace_name")
        end
    end,

    curve = function(name, t)
        if type(name) ~= "string" or type(t) ~= "table" then return err("hl.curve: expected (name, table)") end
        if t.type == "bezier" then
            if type(t.points) ~= "table" or #t.points ~= 2 then err("hl.curve(" .. name .. "): bezier needs two points") end
        elseif t.type ~= "spring" then
            err("hl.curve(" .. name .. "): unknown type '" .. tostring(t.type) .. "'")
        end
    end,

    animation = function(t)
        if not ANIMS[t.leaf] then err("hl.animation: unknown leaf '" .. tostring(t.leaf) .. "'") end
        check_fields("hl.animation", t, set({ "leaf", "enabled", "speed", "bezier", "spring", "style" }))
    end,

    env = function(k, v)
        if type(k) ~= "string" or type(v) ~= "string" then err("hl.env: name and value must be strings") end
    end,

    on = function(event, fn)
        if not EVENTS[event] then err("hl.on: unknown event '" .. tostring(event) .. "'") end
        handlers[event] = handlers[event] or {}
        table.insert(handlers[event], fn)
    end,

    exec_cmd = function(cmd)
        if type(cmd) ~= "string" or cmd == "" then err("hl.exec_cmd: expected a command") end
    end,

    dispatch = function(d)
        if not (type(d) == "table" and d[DSP_TAG]) then err("hl.dispatch: expected a dispatcher") end
    end,

    plugin = {
        load = function(path)
            if type(path) ~= "string" or path == "" then err("hl.plugin.load: expected a path") end
        end,
        hyprbars = {
            add_button = function(t)
                if type(t) ~= "table" then return err("hl.plugin.hyprbars.add_button: expected a table") end
                for k in pairs(t) do
                    if not HYPRBARS_BUTTON[k] then err("hl.plugin.hyprbars.add_button: unknown field '" .. tostring(k) .. "'") end
                end
                for k in pairs(HYPRBARS_BUTTON) do
                    if t[k] == nil then err("hl.plugin.hyprbars.add_button: '" .. k .. "' is required") end
                end
                if type(t.size) ~= "number" then err("hl.plugin.hyprbars.add_button: size must be a number") end
            end,
        },
    },

    timer = function() return {} end,
    permission = function() end,
    notification = { create = function() end, get = function() return {} end },
}

setmetatable(hl, {
    __index = function(_, k) err("unknown function hl." .. tostring(k)) return function() end end,
})

-- Hyprland's require: explicit paths ("/x", "./x", "~/x") resolve against
-- the main config's directory and may omit ".lua"; errors in a required
-- file are reported but do not stop the caller.
local config_dir = main_config:match("^(.*)/[^/]*$") or "."
local loaded = {}
local original_require = require

local function resolve(name)
    local base = name
    if name:sub(1, 2) == "~/" then
        base = os.getenv("HOME") .. name:sub(2)
    elseif name:sub(1, 2) == "./" or name:sub(1, 3) == "../" then
        base = config_dir .. "/" .. name
    end
    for _, candidate in ipairs({ base, base .. ".lua", base .. "/init.lua" }) do
        local f = io.open(candidate, "r")
        if f then f:close() return candidate end
    end
end

require = function(name)
    if name:sub(1, 1) == "/" or name:sub(1, 2) == "./" or name:sub(1, 3) == "../" or name:sub(1, 2) == "~/" then
        local path = resolve(name)
        if not path then error("module '" .. name .. "' not found") end
        if loaded[path] == nil then
            local chunk, load_err = loadfile(path)
            if not chunk then
                errors[#errors + 1] = load_err
                loaded[path] = false
            else
                local ok, result = pcall(chunk)
                if not ok then errors[#errors + 1] = path .. ": " .. tostring(result) end
                loaded[path] = ok and (result == nil and true or result) or false
            end
        end
        return loaded[path]
    end
    return original_require(name)
end

local chunk, load_err = loadfile(main_config)
if not chunk then
    print("FAIL " .. load_err)
    os.exit(1)
end
local ok, run_err = pcall(chunk)
if not ok then errors[#errors + 1] = tostring(run_err) end

-- Fire the start handlers too: they run Lua at login.
for _, fn in ipairs(handlers["hyprland.start"] or {}) do
    local hok, herr = pcall(fn)
    if not hok then errors[#errors + 1] = "hyprland.start handler: " .. tostring(herr) end
end

print(string.format("Checked against Hyprland %s: %d config keys, %d binds, %d window rules, %d layer rules",
    api.version, stats.config_keys, stats.binds, stats.window_rules, stats.layer_rules))
if #errors > 0 then
    for _, e in ipairs(errors) do print("  ✗ " .. e) end
    os.exit(1)
end
print("  ✓ no problems found")
