-- Every key the mod uses comes from the slot list (slots.lua): each tool and
-- consumable slot's key, and the drawers and cane keys. One raw key handler
-- looks them up on every press, so a key changed in the slot editor works
-- straight away.
--
-- When two slots share a key, the first one wins, in this order: drawers,
-- cane, tool slots, consumable slots.

local Slots = require("combatinv/slots")

local Keys = {}

-- Keys that are only ever held with another key; they don't block vanilla's
-- inventory hotkeys (see Keys.OwnsHeldKey).
local MODIFIERS = { KEY_LSHIFT = true, KEY_RSHIFT = true, KEY_LALT = true, KEY_RALT = true,
    KEY_LCTRL = true, KEY_RCTRL = true, KEY_TAB = true, KEY_CAPSLOCK = true }

local actions = {}  -- set by Keys.Install
local held = {}     -- key code -> true while a tool slot key is down

local function Code(name)
    return name ~= nil and rawget(_G, name) or nil
end

-- What `code` is bound to: kind ("drawers", "cane", "tool", "food") and slot.
local function Lookup(code)
    if Code(Slots.Key("drawers")) == code then
        return "drawers"
    end
    if Code(Slots.Key("cane")) == code then
        return "cane"
    end
    for c, slot in ipairs(Slots.List("tools")) do
        if Code(slot.key) == code then
            return "tool", c, slot
        end
    end
    for c, slot in ipairs(Slots.List("food")) do
        if Code(slot.key) == code then
            return "food", c, slot
        end
    end
    return nil
end

-- The raw key handler: TheInput:AddKeyHandler(Keys.OnKey).
function Keys.OnKey(code, down)
    local kind, c, slot = Lookup(code)
    if kind == nil then
        return
    end
    if kind == "drawers" then
        if down and actions.drawers ~= nil then
            actions.drawers()
        end
    elseif kind == "cane" then
        if down and actions.cane_down ~= nil then
            actions.cane_down()
        elseif not down and actions.cane_up ~= nil then
            actions.cane_up()
        end
    elseif kind == "tool" then
        if not down then
            held[code] = nil
            return
        end
        -- Once per press (no key repeat), and Ctrl + number is left for
        -- vanilla's crafting pins.
        if held[code] or actions.tool == nil or actions.crafting_modifier() then
            return
        end
        held[code] = true
        actions.tool(c)
    elseif kind == "food" then
        if down and actions.food ~= nil then
            actions.food(c, slot.type)
        end
    end
end

-- Is one of the mod's keys held right now? Vanilla's inventory hotkeys
-- (CONTROL_INV_1...) are skipped while it is, so pressing a slot's key doesn't
-- also use whatever sits in that vanilla inventory slot. Shift, Alt and the
-- like don't count: they're held alongside other keys.
function Keys.OwnsHeldKey(is_key_down)
    local names = { Slots.Key("drawers"), Slots.Key("cane") }
    for _, section in ipairs({ "tools", "food" }) do
        for _, slot in ipairs(Slots.List(section)) do
            table.insert(names, slot.key or false)
        end
    end
    for _, name in ipairs(names) do
        local code = name and not MODIFIERS[name] and Code(name) or nil
        if code ~= nil and is_key_down(code) then
            return true
        end
    end
    return false
end

-- actions: { drawers = fn(), cane_down = fn(), cane_up = fn(), tool = fn(c),
-- food = fn(c, type), crafting_modifier = fn() -> bool }. Leave one out to
-- ignore that kind of key.
function Keys.Install(new_actions)
    actions = new_actions
    actions.crafting_modifier = actions.crafting_modifier or function() return false end
    held = {}
end

return Keys
