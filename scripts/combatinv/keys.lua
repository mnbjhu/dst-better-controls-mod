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
    if down then
        Keys.Log(string.format("key %d: %s%s", code, kind, c ~= nil and (" slot " .. c) or ""))
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

-- Codes of every key the mod uses, except Shift, Alt and the like (they're
-- held alongside other keys, so they never stand in for a vanilla hotkey).
local function OwnCodes()
    local names = {}
    for _, name in ipairs({ "drawers", "cane" }) do
        table.insert(names, Slots.Key(name) or false)
    end
    for _, section in ipairs({ "tools", "food" }) do
        for _, slot in ipairs(Slots.List(section)) do
            table.insert(names, slot.key or false)
        end
    end
    local codes = {}
    for _, name in ipairs(names) do
        local code = name and not MODIFIERS[name] and Code(name) or nil
        if code ~= nil then
            table.insert(codes, code)
        end
    end
    return codes
end

-- Is `code` one of the mod's keys? Vanilla's inventory hotkeys
-- (CONTROL_INV_1...) bound to one are skipped, so pressing a slot's key
-- doesn't also use whatever sits in that vanilla inventory slot.
function Keys.Owns(code)
    for _, own in ipairs(OwnCodes()) do
        if own == code then
            return true
        end
    end
    return false
end

-- Is one of the mod's keys held right now? (A backup for Keys.Owns, in case
-- the control's key can't be looked up.)
function Keys.OwnsHeldKey(is_key_down)
    for _, code in ipairs(OwnCodes()) do
        if is_key_down(code) then
            return true
        end
    end
    return false
end

-- The first few key decisions go to the client log, to check key handling
-- from a player's log without a console.
local log_budget = 12
local last_logged = nil
function Keys.Log(message)
    if log_budget > 0 and message ~= last_logged then
        log_budget = log_budget - 1
        last_logged = message
        print("[CombatInventory] " .. message)
    end
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
