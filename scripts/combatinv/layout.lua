-- Where every carried item sits in the HUD's drawers.
--
-- The game's inventory is 15 slots plus a backpack, and a client-only mod
-- can't change that. So the drawers are a layout the mod remembers: each item
-- is given a cell when it arrives and keeps it until it's used up, moved by
-- the player, or leaves the inventory. Nothing is re-sorted.
--
-- Every section is a set of columns, and every column is a gapless queue: the
-- top item is the active one (number keys, auto-tools), and when it's used up
-- the rest move up. The player's slot list (slots.lua) says how many columns
-- each section has and what type each one is. Sections:
--   tools    one column per tool slot. A typed slot (weapon, axe...) keeps its
--            type; an Any slot takes on the type of whatever lands in it first.
--   food     one column per consumable slot: health, sanity or hunger.
--   gear     hand, body, head. The top row is what's worn (not part of the
--            queue); carried armour and hats queue underneath.
--   generic  anything. (New food is placed in the food columns, but the
--            player can move it here.)
--
-- Arriving items (Sync) are placed by these rules:
--   hand items: a non-empty tool column of the same type, else an empty
--     column whose set type fits (an Any column fits anything),
--     else generic
--   food: a food column already holding the same food, else the first column
--     for its best stat, else generic
--   gear: under its equip slot
--   everything else: the shortest generic column
-- An item that left recently (thrown boomerang, dropped and picked up again)
-- goes back to where it was instead.

local Util = require("combatinv/util")
local HandSlot = require("combatinv/handslot")
local QuickEat = require("combatinv/quickeat")
local ToolTypes = require("combatinv/tooltypes")
local Slots = require("combatinv/slots")

local Layout = {}

local FOOD_LABELS = { health = "HP", sanity = "San", hunger = "Hun" }
local GEAR_SLOTS = { EQUIPSLOTS.HANDS, EQUIPSLOTS.BODY, EQUIPSLOTS.HEAD }
local GHOST_TIME = 60       -- seconds an item's old cell is remembered

local columns = nil         -- section -> list of columns (lists of items)
local where = {}            -- item -> { section = s, col = c }
local ghosts = {}           -- item -> { section, col, index, time }
local pending = nil         -- { item, section, col, index }: where an incoming item goes
local last_hand = nil
local version = 0

local function Reset()
    columns = { tools = {}, food = {}, gear = {}, generic = {} }
    for c = 1, ToolTypes.SlotCount() do columns.tools[c] = {} end
    for c = 1, #Slots.List("food") do columns.food[c] = {} end
    for c = 1, #GEAR_SLOTS do columns.gear[c] = {} end
    for c = 1, Slots.GenericColumns() do columns.generic[c] = {} end
    where = {}
    ghosts = {}
    pending = nil
    last_hand = nil
    version = version + 1
end

-- Rebuilds the columns from the slot list (all items are placed afresh).
function Layout.Configure()
    Reset()
end

function Layout.Version()
    return version
end

local function Changed()
    version = version + 1
end

--------------------------------------------------------------------------
-- Columns and what they accept
--------------------------------------------------------------------------

-- The type a tool column was given, or nil for a generic tool column.
local function SetToolType(c)
    return ToolTypes.GetSlots()[c]
end

local function HasType(item, key)
    for _, k in ipairs(ToolTypes.Of(item)) do
        if k == key then
            return true
        end
    end
    return false
end

local function SharesType(a, b)
    for _, k in ipairs(ToolTypes.Of(a)) do
        if HasType(b, k) then
            return true
        end
    end
    return false
end

local function IsFood(player, item)
    return QuickEat.GetFoodColumn(player, item) ~= nil
end

local function GearColumnOf(item)
    local equippable = item.replica.equippable
    if equippable == nil then
        return nil
    end
    local eslot = equippable:EquipSlot()
    for c, slot in ipairs(GEAR_SLOTS) do
        if slot == eslot and slot ~= EQUIPSLOTS.HANDS then
            return c
        end
    end
    return nil
end

-- Can the player put this item in this column?
function Layout.Accepts(player, section, c, item)
    if section == "tools" then
        return Util.IsHandItem(item)
    elseif section == "food" then
        return IsFood(player, item)
    elseif section == "gear" then
        return GearColumnOf(item) == c
    elseif section == "generic" then
        return true
    end
    return false
end

--------------------------------------------------------------------------
-- Placing and removing
--------------------------------------------------------------------------

local function Insert(item, section, c, index)
    local column = columns[section][c]
    index = math.max(1, math.min(index or (#column + 1), #column + 1))
    table.insert(column, index, item)
    where[item] = { section = section, col = c }
    Changed()
end

-- Removes the item; returns where it was.
local function Remove(item)
    local at = where[item]
    if at == nil then
        return nil
    end
    local column = columns[at.section][at.col]
    for i, other in ipairs(column) do
        if other == item then
            table.remove(column, i)
            where[item] = nil
            Changed()
            return { section = at.section, col = at.col, index = i }
        end
    end
    where[item] = nil
    return nil
end

local function ShortestGeneric()
    local best = 1
    for c, column in ipairs(columns.generic) do
        if #column < #columns.generic[best] then
            best = c
        end
    end
    return best
end

local function PlaceTool(item)
    -- A column already holding this type of tool.
    for c, column in ipairs(columns.tools) do
        if #column > 0 then
            local key = SetToolType(c)
            if (key ~= nil and HasType(item, key)) or (key == nil and SharesType(column[1], item)) then
                return "tools", c
            end
        end
    end
    -- An empty column set to this type, or an empty generic tool column.
    for c, column in ipairs(columns.tools) do
        if #column == 0 then
            local key = SetToolType(c)
            if key == nil or HasType(item, key) then
                return "tools", c
            end
        end
    end
    return "generic", ShortestGeneric()
end

local function PlaceFood(player, item)
    for c, column in ipairs(columns.food) do
        for _, other in ipairs(column) do
            if other.prefab == item.prefab then
                return "food", c
            end
        end
    end
    local key = QuickEat.GetFoodColumn(player, item)
    for c, slot in ipairs(Slots.List("food")) do
        if slot.type == key then
            return "food", c
        end
    end
    -- No slot for its stat (or no food slots at all).
    return "generic", ShortestGeneric()
end

local function AutoPlace(player, item)
    if Util.IsHandItem(item) then
        return PlaceTool(item)
    elseif IsFood(player, item) then
        return PlaceFood(player, item)
    end
    local gear = GearColumnOf(item)
    if gear ~= nil then
        return "gear", gear
    end
    return "generic", ShortestGeneric()
end

local function Add(player, item)
    if pending ~= nil and pending.item == item then
        local p = pending
        pending = nil
        if Layout.Accepts(player, p.section, p.col, item) then
            Insert(item, p.section, p.col, p.index)
            return
        end
    end
    local ghost = ghosts[item]
    if ghost ~= nil then
        ghosts[item] = nil
        if GetTime() - ghost.time < GHOST_TIME and Layout.Accepts(player, ghost.section, ghost.col, item) then
            Insert(item, ghost.section, ghost.col, ghost.index)
            return
        end
    end
    local section, c = AutoPlace(player, item)
    Insert(item, section, c)
end

--------------------------------------------------------------------------
-- Keeping up with the real inventory
--------------------------------------------------------------------------

-- Items that belong in the queues: everything in the inventory and backpack,
-- the hand item (it keeps its cell while equipped), and an item the player
-- lifted out to move (it keeps its cell until put down somewhere).
local function CarriedItems(player, lifted)
    local inventory = player.replica.inventory
    local list = {}
    for slot = 1, inventory:GetNumSlots() do
        local item = Util.Real(inventory:GetItemInSlot(slot))
        if item ~= nil then
            table.insert(list, item)
        end
    end
    local backpack = inventory:GetOverflowContainer()
    if backpack ~= nil then
        for slot = 1, backpack:GetNumSlots() do
            local item = Util.Real(backpack:GetItemInSlot(slot))
            if item ~= nil then
                table.insert(list, item)
            end
        end
    end
    local hand = Util.GetHandItem(player)
    if hand ~= nil then
        table.insert(list, hand)
    end
    if lifted ~= nil and where[lifted] ~= nil then
        table.insert(list, lifted)
    end
    return list
end

-- Brings the layout in line with what the player carries. lifted: the item
-- on the cursor, if the player took it out of the drawers to move it.
function Layout.Sync(player, lifted)
    if columns == nil then
        Reset()
    end
    local carried = CarriedItems(player, lifted)
    local is_carried = {}
    for _, item in ipairs(carried) do
        is_carried[item] = true
    end

    local refill = nil
    local gone = {}
    for item in pairs(where) do
        if not is_carried[item] then
            table.insert(gone, item)
        end
    end
    for _, item in ipairs(gone) do
        local at = Remove(item)
        if at ~= nil then
            if item:IsValid() then
                at.time = GetTime()
                ghosts[item] = at
            elseif item == last_hand then
                refill = at -- broke or used up in hand
            end
        end
    end

    for _, item in ipairs(carried) do
        if where[item] == nil then
            Add(player, item)
        end
    end

    -- Food columns only hold what this character will eat: anything else
    -- (veggies for Wigfrid, raw food for Warly...) moves to generic.
    for _, column in ipairs(columns.food) do
        for i = #column, 1, -1 do
            local item = column[i]
            if not IsFood(player, item) then
                Remove(item)
                Insert(item, "generic", ShortestGeneric())
            end
        end
    end

    for item, ghost in pairs(ghosts) do
        if not item:IsValid() or GetTime() - ghost.time > GHOST_TIME then
            ghosts[item] = nil
        end
    end

    -- The hand item broke: equip the next one in its column.
    local hand = Util.GetHandItem(player)
    if refill ~= nil and hand == nil then
        local next_item = columns[refill.section][refill.col][refill.index]
        if next_item ~= nil and Util.IsHandItem(next_item) then
            HandSlot.SetHand(player, next_item)
        end
    end
    last_hand = hand
end

--------------------------------------------------------------------------
-- Moves made by the player
--------------------------------------------------------------------------

-- Puts an item that's already in the layout at (section, c, index). Dropped on
-- another item, the two swap if that item fits the vacated cell, otherwise it
-- goes in front of it. Returns false if the column doesn't take it.
function Layout.Move(player, item, section, c, index)
    if where[item] == nil or not Layout.Accepts(player, section, c, item) then
        return false
    end
    -- An empty typed tool column takes on the type of the tool put in it.
    if section == "tools" and #columns.tools[c] == 0 and SetToolType(c) ~= nil then
        ToolTypes.SetType(c, ToolTypes.TypeForDrop(item, c))
    end
    local column = columns[section][c]
    local occupant = column[index]
    local from = where[item]
    local from_column = columns[from.section][from.col]
    local from_index = nil
    for i, other in ipairs(from_column) do
        if other == item then
            from_index = i
        end
    end
    if occupant ~= nil and occupant ~= item and from_index ~= nil
        and Layout.Accepts(player, from.section, from.col, occupant) then
        from_column[from_index] = occupant
        column[index] = item
        where[occupant] = { section = from.section, col = from.col }
        where[item] = { section = section, col = c }
        Changed()
        return true
    end
    Remove(item)
    Insert(item, section, c, index)
    return true
end

-- Shift-click with no chest open: an item in a use column (tools, food, gear)
-- moves to the bottom of the shortest generic column; an item in generic moves
-- to where a pickup of it would go. Returns false if it has nowhere to go.
function Layout.QuickMove(player, item)
    local at = where[item]
    if at == nil then
        return false
    end
    local section, c
    if at.section ~= "generic" then
        section, c = "generic", ShortestGeneric()
    elseif Util.IsHandItem(item) then
        section, c = PlaceTool(item)
    elseif IsFood(player, item) then
        section, c = PlaceFood(player, item)
    else
        section, c = "gear", GearColumnOf(item)
    end
    if section == "generic" and at.section == "generic" or c == nil then
        return false
    end
    return Layout.Move(player, item, section, c, #columns[section][c] + 1)
end

-- An item arriving from outside (the ground, a chest) should land here.
function Layout.Expect(item, section, c, index)
    pending = { item = item, section = section, col = c, index = index }
end

function Layout.Has(item)
    return where[item] ~= nil
end

--------------------------------------------------------------------------
-- Reading the layout
--------------------------------------------------------------------------

function Layout.Columns(section)
    if columns == nil then
        Reset()
    end
    return columns[section]
end

-- Rows every drawer shows: the tallest column, plus one free row to drop into.
function Layout.Height()
    local tallest = 1
    for section, list in pairs(columns or {}) do
        for _, column in ipairs(list) do
            local length = #column + (section == "gear" and 1 or 0)
            tallest = math.max(tallest, length)
        end
    end
    return tallest + 1
end

function Layout.ToolColumnLabel(c)
    local column = columns ~= nil and columns.tools[c] or nil
    local key = SetToolType(c)
    if key ~= nil then
        return ToolTypes.Label(key)
    end
    if column ~= nil and column[1] ~= nil then
        return ToolTypes.Label(ToolTypes.Of(column[1])[1], column[1])
    end
    return "Tool"
end

-- Food column c's stat ("health", "sanity", "hunger") and its short label.
function Layout.FoodColumn(c)
    local slot = Slots.List("food")[c]
    if slot == nil then
        return nil, nil
    end
    return slot.type, FOOD_LABELS[slot.type]
end

Layout.GEAR_SLOTS = GEAR_SLOTS

-- Carried items in drawer order: tool columns left to right, top to bottom,
-- then generic. Auto-tools and attack switching pick the first that fits, so
-- the order you set is the order they're used in.
function Layout.Ordered()
    local list = {}
    if columns == nil then
        return list
    end
    for _, section in ipairs({ "tools", "generic" }) do
        for _, column in ipairs(columns[section]) do
            for _, item in ipairs(column) do
                table.insert(list, item)
            end
        end
    end
    return list
end

-- Number keys: equip the top of tool column c; pressed again, the next one
-- down (wrapping round).
function Layout.EquipColumn(c)
    if not Util.CanUseHotkeys() then
        return false
    end
    local player = ThePlayer
    local column = Layout.Columns("tools")[c]
    if column == nil then
        return false
    end
    if #column == 0 then
        Util.Say(player, "I don't have a " .. Layout.ToolColumnLabel(c):lower() .. ".")
        return true
    end
    local hand = Util.GetHandItem(player)
    local choice = column[1]
    for i, item in ipairs(column) do
        if item == hand then
            choice = column[i % #column + 1]
            break
        end
    end
    -- A number key during travel ends travel: the item stays in hand.
    if HandSlot.on_weapon_key ~= nil then
        HandSlot.on_weapon_key()
    end
    if choice ~= hand then
        Util.ReturnActiveItem(player)
        HandSlot.SetHand(player, choice)
    end
    return true
end

return Layout
