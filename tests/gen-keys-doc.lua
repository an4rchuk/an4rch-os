-- Print Lumen's key bindings as Markdown, straight from default/hypr/binds.lua,
-- so the manual never drifts from the real bindings.
--   lua5.4 tests/gen-keys-doc.lua > docs/02-keybindings.md
local root = arg[1] or "."

local sections, current = {}, nil
local function section(title)
    current = { title = title, rows = {} }
    sections[#sections + 1] = current
end

-- Stub just enough of `hl` to record binds with descriptions.
local any = setmetatable({}, { __index = function(t) return function() return t end end, __call = function(t) return t end })
local dsp = setmetatable({}, { __index = function() return any end })
hl = setmetatable({
    dsp = dsp,
    bind = function(keys, _, opts)
        if opts and opts.description and current then
            table.insert(current.rows, { keys, opts.description })
        end
    end,
    define_submap = function() end,
    get_config = function() return 1 end,
}, { __index = function() return function() return any end end })
lumen = { cmd = function() return "" end, launch = function() return "" end }

-- Section headers come from the "-- Title" banners in binds.lua.
local src = io.open(root .. "/default/hypr/binds.lua"):read("a")
local chunks = {}
local previous = ""
for line in src:gmatch("[^\n]*\n?") do
    -- A section title is the comment line right after a "-----" banner.
    local title = previous:match("^%-%-%-%-%-") and line:match("^%-%- ([%w][^%-]*[%w%)])%s*$")
    if title then
        chunks[#chunks + 1] = ("section(%q)\n"):format(title)
    else
        chunks[#chunks + 1] = line
    end
    previous = line
end
local code = table.concat(chunks)
local env = setmetatable({ section = section }, { __index = _G })
assert(load(code, "binds.lua", "t", env))()

local function pretty(k)
    if k:match("^SUPER %+ SUPER_[LR]$") then
        return "<kbd>SUPER</kbd> tap" .. (k:match("R$") and " (right)" or "")
    end
    local map = { Return = "Enter", SPACE = "Space", grave = "`", slash = "/", period = ".", comma = ",",
        semicolon = ";", equal = "=", bracketleft = "[", bracketright = "]", Escape = "Esc", escape = "Esc",
        ["mouse:272"] = "Left-drag", ["mouse:273"] = "Right-drag", mouse_down = "Scroll down", mouse_up = "Scroll up",
        Print = "Print Screen", Tab = "Tab" }
    local parts = {}
    for p in k:gmatch("[^+]+") do
        p = p:gsub("^%s+", ""):gsub("%s+$", "")
        parts[#parts + 1] = "<kbd>" .. (map[p] or ((#p == 1) and p:upper() or p)) .. "</kbd>"
    end
    return table.concat(parts, " + ")
end

print("# Key bindings\n")
print("Generated from `default/hypr/binds.lua`. Press <kbd>SUPER</kbd> + <kbd>/</kbd> for a searchable version on your desktop.\n")
print("The modifiers follow one pattern: <kbd>SUPER</kbd> alone for apps and windows, <kbd>SHIFT</kbd> to move or capture, <kbd>CTRL</kbd> for system toggles and style, <kbd>ALT</kbd> for setup panels.\n")
for _, s in ipairs(sections) do
    if #s.rows > 0 then
        print("## " .. s.title .. "\n")
        print("| Keys | Action |")
        print("| --- | --- |")
        local seen = {}
        for _, r in ipairs(s.rows) do
            local keys, desc = r[1], r[2]
            -- Collapse the ten numbered workspace binds into one row each.
            if desc:match("workspace %d+") then
                keys = keys:gsub("%d$", "1 … 0")
                desc = desc:gsub("workspace %d+", "workspace 1 … 10")
            end
            local line = "| " .. pretty(keys) .. " | " .. desc .. " |"
            if not seen[line] then print(line) seen[line] = true end
        end
        print("")
    end
end
print("## Resize mode\n")
print("<kbd>SUPER</kbd> + <kbd>R</kbd> enters resize mode: arrows or <kbd>H</kbd> <kbd>J</kbd> <kbd>K</kbd> <kbd>L</kbd> resize the window, <kbd>Esc</kbd> or <kbd>Enter</kbd> leaves.\n")
print("## Touchpad\n")
print("| Gesture | Action |\n| --- | --- |\n| Three-finger swipe left/right | Switch workspace |\n| Three-finger swipe up | Toggle the scratchpad |")
