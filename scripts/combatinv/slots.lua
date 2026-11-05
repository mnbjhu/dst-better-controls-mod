-- The player's drawer layout: which slots each section has, and each slot's
-- type and key. It's saved on this computer, so it's the same in every world
-- and on any server (see "The slot editor" in docs/DESIGN.md).
--
--   tools     list of { type = <tool type key or "any">, key = "KEY_1" or nil,
--                       dropped = <tool type key> or nil }
--             `dropped` is the type a typed slot took from a tool dropped in it
--             while it was empty. It lasts until the column is emptied, then
--             the slot shows its own `type` again.
--   food      list of { type = "health" | "sanity" | "hunger" | "other", key = "KEY_H" or nil }
--             "other" holds food with a downside, and food whose stat has no slot.
--   generic   number of generic columns
--   keys      { drawers = "KEY_B" or nil, cane = "KEY_LSHIFT" or nil }
--
-- Keys are stored but not bound here yet: modmain still binds them from
-- Configure Mod. Until the in-game editor replaces those options, the layout
-- is rebuilt from them whenever they change, keeping each slot's types.

local Slots = {}

local SAVE_NAME = "combatinv_slots"
local OLD_TOOL_SAVE = "combatinv_toolslots" -- tool types only, before slots.lua

local DEFAULT_TOOL_TYPES = { "melee", "ranged", "magic", "axe" }
local DEFAULT_FOOD = { "health", "sanity", "hunger" }
local FOOD_TYPES = { health = true, sanity = true, hunger = true, other = true }

local LIMITS =
{
    tools = { min = 0, max = 10 },
    food = { min = 0, max = 6 },
    generic = { min = 1, max = 8 },
}

-- Configure Mod values the layout is built from (see Slots.SetConfig).
local function DefaultConfig()
    return
    {
        tool_slots = 6,
        number_keys = true,
        eat_keys = { health = "KEY_H", sanity = "KEY_J", hunger = "KEY_K" },
        inventory_key = "KEY_B",
        cane_key = nil,
    }
end
local config = DefaultConfig()

local data = nil -- loaded layout

local function Clamp(n, section)
    local limit = LIMITS[section]
    return math.max(limit.min, math.min(limit.max, math.floor(tonumber(n) or limit.min)))
end

local function KeyOrNil(key)
    return type(key) == "string" and key ~= "" and key or nil
end

-- A string that changes whenever a Configure Mod value the layout uses changes.
local function ConfigStamp()
    return table.concat({
        tostring(config.tool_slots),
        tostring(config.number_keys),
        tostring(config.eat_keys.health),
        tostring(config.eat_keys.sanity),
        tostring(config.eat_keys.hunger),
        tostring(config.inventory_key),
        tostring(config.cane_key),
    }, "|")
end

local function ReadString(name)
    local result = nil
    TheSim:GetPersistentString(name, function(success, str)
        if success and type(str) == "string" and str ~= "" then
            result = str
        end
    end)
    return result
end

-- Tool types from the old save ("melee,ranged,magic,axe"), if there is one.
local function OldToolTypes()
    local str = ReadString(OLD_TOOL_SAVE)
    local list = {}
    if str ~= nil then
        for key in str:gmatch("[^,]+") do
            table.insert(list, key)
        end
    end
    return list
end

-- The layout Configure Mod describes. `keep` is an earlier layout whose slot
-- types are kept, slot by slot.
local function FromConfig(keep, ignore_old_save)
    local layout = { tools = {}, food = {}, generic = 4, keys = {} }

    local kept_tools = keep ~= nil and keep.tools or {}
    local old = (keep == nil and not ignore_old_save) and OldToolTypes() or {}
    for i = 1, Clamp(config.tool_slots, "tools") do
        local slot_type, dropped
        local kept = kept_tools[i]
        if kept ~= nil then
            slot_type, dropped = kept.type, kept.dropped
        else
            -- The first slots are weapon, ranged, staff and axe; the rest are Any.
            slot_type = DEFAULT_TOOL_TYPES[i] or "any"
            -- The old save held each typed slot's current type, which a dropped
            -- tool may have changed: carry that over as the dropped type.
            if old[i] ~= nil and slot_type ~= "any" and old[i] ~= slot_type then
                dropped = old[i]
            end
        end
        local key = nil
        if config.number_keys and i <= 10 then
            key = "KEY_" .. tostring(i % 10)
        end
        layout.tools[i] = { type = slot_type, key = key, dropped = dropped }
    end

    local kept_food = keep ~= nil and keep.food or nil
    local food_types = DEFAULT_FOOD
    if kept_food ~= nil then
        food_types = {}
        for i, slot in ipairs(kept_food) do
            food_types[i] = slot.type
        end
    end
    for i, food_type in ipairs(food_types) do
        layout.food[i] = { type = food_type, key = KeyOrNil(config.eat_keys[food_type]) }
    end

    if keep ~= nil and keep.generic ~= nil then
        layout.generic = keep.generic
    end
    layout.keys.drawers = KeyOrNil(config.inventory_key)
    layout.keys.cane = KeyOrNil(config.cane_key)
    layout.config = ConfigStamp()
    return layout
end

-- Drops anything a hand-edited or older save got wrong.
local function Clean(layout)
    if type(layout) ~= "table" then
        return nil
    end
    local clean = { tools = {}, food = {}, keys = {}, config = layout.config }
    for _, slot in ipairs(type(layout.tools) == "table" and layout.tools or {}) do
        if type(slot) == "table" and type(slot.type) == "string" and #clean.tools < LIMITS.tools.max then
            local dropped = slot.type ~= "any" and KeyOrNil(slot.dropped) or nil
            table.insert(clean.tools, { type = slot.type, key = KeyOrNil(slot.key), dropped = dropped })
        end
    end
    for _, slot in ipairs(type(layout.food) == "table" and layout.food or {}) do
        if type(slot) == "table" and FOOD_TYPES[slot.type] and #clean.food < LIMITS.food.max then
            table.insert(clean.food, { type = slot.type, key = KeyOrNil(slot.key) })
        end
    end
    clean.generic = Clamp(layout.generic or 4, "generic")
    local keys = type(layout.keys) == "table" and layout.keys or {}
    clean.keys.drawers = KeyOrNil(keys.drawers)
    clean.keys.cane = KeyOrNil(keys.cane)
    return clean
end

local function Save()
    TheSim:SetPersistentString(SAVE_NAME, json.encode(data), false)
end

local function Load()
    local str = ReadString(SAVE_NAME)
    local saved = nil
    if str ~= nil then
        local ok, decoded = pcall(json.decode, str)
        saved = ok and Clean(decoded) or nil
    end
    if saved == nil then
        data = FromConfig(nil)
        Save()
    elseif saved.config ~= ConfigStamp() then
        -- Configure Mod changed since the layout was saved: follow it, but keep
        -- the slot types the player picked.
        data = FromConfig(saved)
        Save()
    else
        data = saved
    end
end

local function Get()
    if data == nil then
        Load()
    end
    return data
end

-- The Configure Mod values the layout follows. Call before the layout is used.
-- Values left out (or nil, like no cane key) take their defaults.
function Slots.SetConfig(values)
    config = DefaultConfig()
    for k, v in pairs(values) do
        config[k] = v
    end
    data = nil
end

-- Section "tools" or "food": the list of slots ({ type, key }).
function Slots.List(section)
    return Get()[section]
end

function Slots.GenericColumns()
    return Get().generic
end

function Slots.Key(name)
    return Get().keys[name]
end

--------------------------------------------------------------------------
-- Editing (the slot editor)
--------------------------------------------------------------------------

-- Called with { op = ..., section = ..., index = ..., to = ... } after every
-- edit. ops: "add", "remove", "move", "type", "key", "generic", "reset".
local listeners = {}

function Slots.OnChanged(fn)
    table.insert(listeners, fn)
end

local function Edited(change)
    Save()
    for _, fn in ipairs(listeners) do
        fn(change)
    end
end

-- How many slots (or generic columns) a section can have: min, max.
function Slots.Limits(section)
    return LIMITS[section].min, LIMITS[section].max
end

-- Gives slot `index` of `section` the type `slot_type`. Returns true if it changed.
function Slots.SetType(section, index, slot_type)
    local slot = Get()[section][index]
    if slot == nil or (slot.type == slot_type and slot.dropped == nil) then
        return false
    end
    slot.type = slot_type
    slot.dropped = nil
    Edited({ op = "type", section = section, index = index })
    return true
end

-- Adds a slot at the end: an Any tool slot, or the first stat no consumable
-- slot has yet (else Other). Returns its index, or nil at the limit.
function Slots.Add(section)
    local list = Get()[section]
    if #list >= LIMITS[section].max then
        return nil
    end
    local slot_type = "any"
    if section == "food" then
        slot_type = "other"
        for _, stat in ipairs(DEFAULT_FOOD) do
            local taken = false
            for _, slot in ipairs(list) do
                taken = taken or slot.type == stat
            end
            if not taken then
                slot_type = stat
                break
            end
        end
    end
    table.insert(list, { type = slot_type })
    Edited({ op = "add", section = section, index = #list })
    return #list
end

function Slots.Remove(section, index)
    local list = Get()[section]
    if list[index] == nil or #list <= LIMITS[section].min then
        return false
    end
    table.remove(list, index)
    Edited({ op = "remove", section = section, index = index })
    return true
end

-- Swaps slot `index` with its neighbour `to` (index - 1 or index + 1).
function Slots.Move(section, index, to)
    local list = Get()[section]
    if list[index] == nil or list[to] == nil or math.abs(index - to) ~= 1 then
        return false
    end
    list[index], list[to] = list[to], list[index]
    Edited({ op = "move", section = section, index = index, to = to })
    return true
end

-- A slot's key ("KEY_H"), or nil for no key.
function Slots.SetKey(section, index, key)
    local slot = Get()[section][index]
    if slot == nil or slot.key == KeyOrNil(key) then
        return false
    end
    slot.key = KeyOrNil(key)
    Edited({ op = "key", section = section, index = index })
    return true
end

-- The drawers or cane key ("KEY_B"), or nil for no key.
function Slots.SetNamedKey(name, key)
    local keys = Get().keys
    if keys[name] == KeyOrNil(key) then
        return false
    end
    keys[name] = KeyOrNil(key)
    Edited({ op = "key", name = name })
    return true
end

function Slots.SetGeneric(count)
    local layout = Get()
    count = Clamp(count, "generic")
    if layout.generic == count then
        return false
    end
    local from = layout.generic
    layout.generic = count
    Edited({ op = "generic", index = from, to = count })
    return true
end

-- Back to the default layout (from Configure Mod).
function Slots.Reset()
    data = FromConfig(nil, true)
    Edited({ op = "reset" })
end

-- Slots and named keys sharing a key, for the editor's warnings:
-- key name -> number of uses (only keys used more than once).
function Slots.DuplicateKeys()
    local layout = Get()
    local count = {}
    local function Count(key)
        if key ~= nil then
            count[key] = (count[key] or 0) + 1
        end
    end
    Count(layout.keys.drawers)
    Count(layout.keys.cane)
    for _, section in ipairs({ "tools", "food" }) do
        for _, slot in ipairs(layout[section]) do
            Count(slot.key)
        end
    end
    local dupes = {}
    for key, n in pairs(count) do
        if n > 1 then
            dupes[key] = n
        end
    end
    return dupes
end

-- Tool slot `index` takes the type `key` from a dropped tool, or goes back to
-- its own type when `key` is nil. Returns true if what it shows changed.
function Slots.SetDropped(index, key)
    local slot = Get().tools[index]
    if slot == nil or slot.type == "any" then
        return false
    end
    if key == slot.type then
        key = nil
    end
    if slot.dropped == key then
        return false
    end
    slot.dropped = key
    Save()
    return true
end

-- Console helper: ci_slots() prints the saved layout.
function Slots.Debug()
    local layout = Get()
    local function KeyName(key)
        return key ~= nil and (key:gsub("^KEY_", "")) or "-"
    end
    for i, slot in ipairs(layout.tools) do
        local dropped = slot.dropped ~= nil and (" (showing " .. slot.dropped .. " until emptied)") or ""
        print(string.format("[CombatInventory] tool %d: %-10s key %s%s", i, slot.type, KeyName(slot.key), dropped))
    end
    for i, slot in ipairs(layout.food) do
        print(string.format("[CombatInventory] food %d: %-10s key %s", i, slot.type, KeyName(slot.key)))
    end
    print(string.format("[CombatInventory] generic columns: %d, drawers key %s, cane key %s",
        layout.generic, KeyName(layout.keys.drawers), KeyName(layout.keys.cane)))
end

return Slots
