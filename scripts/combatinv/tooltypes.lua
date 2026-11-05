-- Tool types and the tool drawer's slots.
--
-- Every hand item belongs to one or more types (a Pick/Axe is both "axe" and
-- "pick"). Each tool slot shows one type, or is an Any slot. Dropping a hand
-- item on an empty typed slot gives that slot the item's type until it's emptied.
-- The slots themselves are saved by slots.lua.

local Util = require("combatinv/util")
local HandSlot = require("combatinv/handslot")
local Tools = require("combatinv/tools")
local Slots = require("combatinv/slots")

local ToolTypes = {}

-- Hand items faster than this are travel items (matches handslot.lua).
local TRAVEL_SPEED_MIN = 1.15

-- Known types, in the order the defaults use them.
-- weapon: a HandSlot weapon category. action: a tool action id ("CHOP").
local TYPES =
{
    { key = "melee", label = "Weapon", weapon = "melee" },
    { key = "ranged", label = "Ranged", weapon = "ranged" },
    { key = "magic", label = "Staff", weapon = "magic" },
    { key = "axe", label = "Axe", action = "CHOP" },
    { key = "pick", label = "Pickaxe", action = "MINE" },
    { key = "shovel", label = "Shovel", action = "DIG" },
    { key = "hammer", label = "Hammer", action = "HAMMER" },
    { key = "light", label = "Light" },
    { key = "travel", label = "Cane" },
    { key = "net", label = "Net", action = "NET" },
    { key = "pitchfork", label = "Pitchfork", action = "TERRAFORM" },
    { key = "scythe", label = "Scythe", action = "SCYTHE" },
    { key = "rod", label = "Rod" },
    { key = "umbrella", label = "Umbrella" },
}

local BY_KEY = {}
for _, t in ipairs(TYPES) do
    BY_KEY[t.key] = t
end

local LIGHT_TAGS = { "light", "lighter", "torch" }

local function HasAnyTag(item, tags)
    for _, tag in ipairs(tags) do
        if item:HasTag(tag) then
            return true
        end
    end
    return false
end

-- The types an item belongs to, most specific first. Hand items that fit no
-- known type get their own: "item:<prefab>".
function ToolTypes.Of(item)
    if not Util.IsHandItem(item) then
        return {}
    end
    local category = HandSlot.GetCategory(item)
    if category ~= nil then
        return { category }
    end
    local keys = {}
    for _, t in ipairs(TYPES) do
        if t.action ~= nil and item:HasTag(t.action .. "_tool") then
            table.insert(keys, t.key)
        end
    end
    if #keys > 0 then
        return keys
    end
    if Util.GetWalkSpeedMult(item) >= TRAVEL_SPEED_MIN then
        return { "travel" }
    end
    if HasAnyTag(item, LIGHT_TAGS) then
        return { "light" }
    end
    if item:HasTag("fishingrod") or item.prefab:find("fishingrod") ~= nil then
        return { "rod" }
    end
    if item:HasTag("umbrella") then
        return { "umbrella" }
    end
    return { "item:" .. item.prefab }
end

function ToolTypes.Label(key, example)
    local t = BY_KEY[key]
    if t ~= nil then
        return t.label
    end
    if example ~= nil and example:IsValid() then
        return example:GetDisplayName()
    end
    return (key:gsub("^item:", ""))
end

-- Every known type as { key, label }, in order (for the slot editor).
function ToolTypes.All()
    local list = {}
    for _, t in ipairs(TYPES) do
        table.insert(list, { key = t.key, label = t.label })
    end
    return list
end

-- Number keys equip tool slots by position: 1 is the first slot, 0 the tenth.
local number_keys = false

function ToolTypes.SetNumberKeys(enabled)
    number_keys = enabled
end

function ToolTypes.SlotHotkey(index)
    if not number_keys or index > 10 then
        return nil
    end
    return tostring(index % 10)
end

function ToolTypes.IsWeapon(key)
    local t = BY_KEY[key]
    return t ~= nil and t.weapon ~= nil
end

-- Sorts a type's items best first, the way hotkeys and auto-tools pick them.
function ToolTypes.Sort(player, key, items)
    local t = BY_KEY[key]
    if t ~= nil and t.weapon ~= nil then
        HandSlot.SortCandidates(t.weapon, items)
    elseif t ~= nil and t.action ~= nil then
        table.sort(items, Tools.Better)
    else
        table.sort(items, function(a, b)
            if a.prefab ~= b.prefab then
                return a.prefab < b.prefab
            end
            return a.GUID < b.GUID
        end)
    end
end

-- The item a slot shows: what's in hand if it belongs, else what a click picks.
function ToolTypes.Representative(player, key, items, hand)
    for _, item in ipairs(items) do
        if item == hand then
            return item
        end
    end
    local t = BY_KEY[key]
    if t ~= nil and t.weapon ~= nil then
        return HandSlot.GetBest(player, t.weapon) or items[1]
    elseif t ~= nil and t.action ~= nil then
        return Tools.FindTool(player, t.action) or items[1]
    end
    return items[1]
end

--------------------------------------------------------------------------
-- Tool slots (saved in slots.lua)
--------------------------------------------------------------------------

-- The type each tool slot shows now, by index: the type a dropped tool gave it,
-- else its own type, or nil for an Any slot (which takes the type of the first
-- tool put in it). Not a sequence: use numeric indices up to
-- ToolTypes.SlotCount(), not ipairs.
function ToolTypes.GetSlots()
    local list = {}
    for i, slot in ipairs(Slots.List("tools")) do
        list[i] = slot.dropped or (slot.type ~= "any" and slot.type or nil)
    end
    return list
end

function ToolTypes.SlotCount()
    return #Slots.List("tools")
end

-- Typed tool slot `index` shows type `key` until its column is emptied (see
-- ToolTypes.Restore). Any slots are left alone.
function ToolTypes.SetType(index, key)
    return Slots.SetDropped(index, key)
end

-- Tool slot `index` goes back to its own type. Returns true if it changed.
function ToolTypes.Restore(index)
    return Slots.SetDropped(index, nil)
end

-- The type to give a slot when this item is dropped on it: the first of the
-- item's types that isn't already in another slot, else its first type.
function ToolTypes.TypeForDrop(item, index)
    local keys = ToolTypes.Of(item)
    local list = ToolTypes.GetSlots()
    for _, key in ipairs(keys) do
        local taken = false
        for i = 1, ToolTypes.SlotCount() do
            if list[i] == key and i ~= index then
                taken = true
            end
        end
        if not taken then
            return key
        end
    end
    return keys[1]
end

return ToolTypes
