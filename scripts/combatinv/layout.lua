-- Where every carried item sits in the HUD's drawers.
--
-- The game's inventory is 15 slots plus a backpack, and a client-only mod
-- can't change that. So the drawers are a layout the mod remembers: each item
-- is given a cell when it arrives and keeps it until it's used up, moved by
-- the player, or leaves the inventory. Nothing is re-sorted.
--
-- Tools, food and gear are sets of columns, and every column is a gapless
-- queue: the top item is the active one (number keys, auto-tools), and when
-- it's used up the rest move up. The player's slot list (slots.lua) says how
-- many columns each section has and what type each one is. Sections:
--   tools    one column per tool slot. A typed slot (weapon, axe...) takes the
--            type of a tool dropped in it while empty, until it's emptied
--            again; an Any slot takes on the type of whatever lands in it first.
--   food     one column per consumable slot: health, sanity, hunger or other.
--   gear     hand, body, head. The top row is what's worn (not part of the
--            queue); carried armour and hats queue underneath.
--   generic  Supplies: anything. (New food is placed in the food columns, but
--            the player can move it here.) Not columns but one list, shown
--            row by row across its columns. While the drawers are open it
--            can have gaps, so items stay where the player drops them; when
--            they close, the gaps are squeezed out (Layout.SetOpen).
--
-- Arriving items (Sync) are placed by these rules:
--   hand items: a non-empty tool column of the same type, else an empty
--     column whose set type fits (an Any column fits anything),
--     else generic
--   food: a food column already holding the same food; else food with a
--     downside goes in the first Other column; else the first column for its
--     best stat; else the first Other column; else generic
--   gear: under its equip slot
--   everything else: generic, in its first gap or on the end
-- An item that left recently (thrown boomerang, dropped and picked up again)
-- goes back to where it was instead.

local Util = require("combatinv/util")
local HandSlot = require("combatinv/handslot")
local QuickEat = require("combatinv/quickeat")
local ToolTypes = require("combatinv/tooltypes")
local Slots = require("combatinv/slots")

local Layout = {}

local FOOD_LABELS = { health = "HP", sanity = "San", hunger = "Hun", other = "Other" }
local GEAR_SLOTS = { EQUIPSLOTS.HANDS, EQUIPSLOTS.BODY, EQUIPSLOTS.HEAD }
local GHOST_TIME = 60       -- seconds an item's old cell is remembered

local columns = nil         -- section -> list of columns (lists of items); not generic
local supplies = {}         -- generic: items in reading order; false is a gap (only while open)
local drawers_open = false
local where = {}            -- item -> { section = s, col = c } (generic: no col)
local ghosts = {}           -- item -> { section, col, index, time }
local pending = nil         -- { item, section, col, index }: where an incoming item goes
local last_hand = nil
local version = 0

local function Reset()
    columns = { tools = {}, food = {}, gear = {} }
    for c = 1, ToolTypes.SlotCount() do columns.tools[c] = {} end
    for c = 1, #Slots.List("food") do columns.food[c] = {} end
    for c = 1, #GEAR_SLOTS do columns.gear[c] = {} end
    supplies = {}
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

-- Items in a column that's going away: forgotten here, so the next Sync
-- places them again by the usual rules.
local function Forget(column)
    for _, item in ipairs(column) do
        where[item] = nil
        ghosts[item] = nil
    end
end

-- The slot editor changed the slot list: change the columns to match, keeping
-- every other item where it is.
Slots.OnChanged(function(change)
    if columns == nil then
        return
    end
    local list = change.section ~= nil and columns[change.section] or nil
    if change.op == "reset" then
        Reset()
        return
    elseif change.op == "add" then
        table.insert(list, change.index, {})
    elseif change.op == "remove" then
        Forget(list[change.index])
        table.remove(list, change.index)
    elseif change.op == "move" then
        list[change.index], list[change.to] = list[change.to], list[change.index]
    end
    -- (A new Supplies column count just rewraps the list: nothing to do.)
    -- Column numbers moved: fix up where items think they are. Remembered
    -- cells of items that left may point at the wrong column now.
    if change.op ~= "type" and change.op ~= "key" then
        ghosts = {}
    end
    for section, cols in pairs(columns) do
        for c, column in ipairs(cols) do
            for _, item in ipairs(column) do
                where[item] = { section = section, col = c }
            end
        end
    end
    pending = nil
    version = version + 1
end)

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

--------------------------------------------------------------------------
-- Supplies (generic): one list, shown row by row
--------------------------------------------------------------------------

local function SuppliesWidth()
    return math.max(1, Slots.GenericColumns())
end

-- The list position of the cell in column c, row `row`.
local function SuppliesPos(c, row)
    return (row - 1) * SuppliesWidth() + c
end

local function SuppliesIndexOf(item)
    for i = 1, #supplies do
        if supplies[i] == item then
            return i
        end
    end
    return nil
end

-- Gaps at the end are just empty cells: drop them.
local function TrimSupplies()
    while #supplies > 0 and not supplies[#supplies] do
        supplies[#supplies] = nil
    end
end

-- Puts an item in Supplies at list position `pos` (nil: the first gap, or the
-- end). While the drawers are closed it's inserted, so the list stays gapless.
-- While open, an empty cell takes it as it is; on an item, the items from
-- there shift along as far as the next gap.
local function InsertSupplies(item, pos)
    if not drawers_open then
        pos = math.max(1, math.min(pos or (#supplies + 1), #supplies + 1))
        table.insert(supplies, pos, item)
        return
    end
    if pos == nil then
        pos = #supplies + 1
        for i = 1, #supplies do
            if not supplies[i] then
                pos = i
                break
            end
        end
    end
    pos = math.max(1, pos)
    for i = #supplies + 1, pos - 1 do
        supplies[i] = false
    end
    if supplies[pos] then
        local gap = pos
        while supplies[gap] do
            gap = gap + 1
        end
        for i = gap, pos + 1, -1 do
            supplies[i] = supplies[i - 1]
        end
    end
    supplies[pos] = item
end

-- Takes an item out of Supplies; returns its position. While the drawers are
-- open it leaves a gap.
local function RemoveSupplies(item)
    local i = SuppliesIndexOf(item)
    if i == nil then
        return nil
    end
    if drawers_open then
        supplies[i] = false
        TrimSupplies()
    else
        table.remove(supplies, i)
    end
    return i
end

-- Supplies as columns, for drawing: column c holds positions c, c + width,
-- ... A gap is false.
local function SuppliesColumns()
    local width = SuppliesWidth()
    local list = {}
    for c = 1, width do
        list[c] = {}
    end
    for i = 1, #supplies do
        table.insert(list[(i - 1) % width + 1], supplies[i])
    end
    return list
end

-- The drawers opened or closed. Closing squeezes the gaps out of Supplies.
function Layout.SetOpen(open)
    open = open and true or false
    if open == drawers_open then
        return
    end
    drawers_open = open
    if not open then
        local list = {}
        for i = 1, #supplies do
            if supplies[i] then
                table.insert(list, supplies[i])
            end
        end
        if #list ~= #supplies then
            supplies = list
            Changed()
        end
    end
end

--------------------------------------------------------------------------
-- Placing and removing
--------------------------------------------------------------------------

-- index: the place in the column, or for generic the list position.
local function Insert(item, section, c, index)
    if section == "generic" then
        InsertSupplies(item, index)
        where[item] = { section = "generic" }
        Changed()
        return
    end
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
    if at.section == "generic" then
        local i = RemoveSupplies(item)
        where[item] = nil
        if i == nil then
            return nil
        end
        Changed()
        return { section = "generic", index = i }
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
    return "generic", nil
end

local function PlaceFood(player, item)
    for c, column in ipairs(columns.food) do
        for _, other in ipairs(column) do
            if other.prefab == item.prefab then
                return "food", c
            end
        end
    end
    local slots = Slots.List("food")
    local function FirstOfType(food_type)
        for c, slot in ipairs(slots) do
            if slot.type == food_type then
                return c
            end
        end
        return nil
    end
    -- Food with a downside (the food quick-eat never eats: monster meat, rot,
    -- anything that costs health or sanity) goes in an Other slot if there is one.
    local other = FirstOfType("other")
    if other ~= nil and QuickEat.GetFoodGroup(player, item) == "bad" then
        return "food", other
    end
    local c = FirstOfType(QuickEat.GetFoodColumn(player, item)) or other
    if c ~= nil then
        return "food", c
    end
    -- No slot for its stat and no Other slot (or no food slots at all).
    return "generic", nil
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
    return "generic", nil
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
                Insert(item, "generic", nil)
            end
        end
    end

    for item, ghost in pairs(ghosts) do
        if not item:IsValid() or GetTime() - ghost.time > GHOST_TIME then
            ghosts[item] = nil
        end
    end

    -- A typed tool column that's been emptied goes back to its slot's type
    -- (a tool put in an empty column gives it that tool's type until then).
    for c, column in ipairs(columns.tools) do
        if #column == 0 and ToolTypes.Restore(c) then
            Changed()
        end
    end

    -- The hand item broke: equip the next one in its column.
    local hand = Util.GetHandItem(player)
    if refill ~= nil and hand == nil and refill.section ~= "generic" then
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

-- Moves an item to Supplies list position `pos` (nil: the first gap, or the
-- end). Within Supplies, dropped on another item the two swap; from another
-- section it goes in there, pushing items along to the next gap.
local function MoveToSupplies(item, pos)
    local from = where[item]
    if from.section == "generic" and pos ~= nil then
        local i = SuppliesIndexOf(item)
        if i == pos then
            return true
        end
        if i ~= nil and supplies[pos] then
            supplies[i], supplies[pos] = supplies[pos], supplies[i]
            Changed()
            return true
        end
    end
    Remove(item)
    Insert(item, "generic", nil, pos)
    return true
end

-- Puts an item that's already in the layout at (section, c, index); for
-- generic, (c, index) is the cell's column and row, or nil for the first gap.
-- Dropped on another item, the two swap if that item fits the vacated cell,
-- otherwise it goes in front of it. Returns false if the column doesn't take it.
function Layout.Move(player, item, section, c, index)
    if where[item] == nil or not Layout.Accepts(player, section, c, item) then
        return false
    end
    if section == "generic" then
        return MoveToSupplies(item, c ~= nil and index ~= nil and SuppliesPos(c, index) or nil)
    end
    -- An empty typed tool column takes on the type of the tool put in it.
    if section == "tools" and #columns.tools[c] == 0 and SetToolType(c) ~= nil then
        ToolTypes.SetType(c, ToolTypes.TypeForDrop(item, c))
    end
    local column = columns[section][c]
    local occupant = column[index]
    local from = where[item]
    -- From Supplies onto an item: that item takes its place there.
    if from.section == "generic" and occupant ~= nil then
        local i = SuppliesIndexOf(item)
        if i ~= nil then
            supplies[i] = occupant
            column[index] = item
            where[occupant] = { section = "generic" }
            where[item] = { section = section, col = c }
            Changed()
            return true
        end
    end
    -- (Supplies has no columns: from there it's a plain remove and insert.)
    local from_column = from.section ~= "generic" and columns[from.section][from.col] or {}
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
-- moves to the first gap in Supplies, or its end; an item in generic moves
-- to where a pickup of it would go. Returns false if it has nowhere to go.
function Layout.QuickMove(player, item)
    local at = where[item]
    if at == nil then
        return false
    end
    local section, c
    if at.section ~= "generic" then
        section, c = "generic", nil
    elseif Util.IsHandItem(item) then
        section, c = PlaceTool(item)
    elseif IsFood(player, item) then
        section, c = PlaceFood(player, item)
    else
        section, c = "gear", GearColumnOf(item)
    end
    if section == "generic" then
        if at.section == "generic" then
            return false
        end
        return Layout.Move(player, item, "generic", nil, nil)
    end
    if c == nil then
        return false
    end
    return Layout.Move(player, item, section, c, #columns[section][c] + 1)
end

-- An item arriving from outside (the ground, a chest) should land here. For
-- generic, (c, index) is a cell's column and row, or nil for the first gap.
function Layout.Expect(item, section, c, index)
    if section == "generic" then
        index = c ~= nil and index ~= nil and SuppliesPos(c, index) or nil
        c = nil
    end
    pending = { item = item, section = section, col = c, index = index }
end

function Layout.Has(item)
    return where[item] ~= nil
end

--------------------------------------------------------------------------
-- Reading the layout
--------------------------------------------------------------------------

-- A section's columns. Supplies is a list, so its columns are made from it:
-- column c holds its items in row order, and a gap is false.
function Layout.Columns(section)
    if columns == nil then
        Reset()
    end
    if section == "generic" then
        return SuppliesColumns()
    end
    return columns[section]
end

-- Rows every drawer shows: the tallest column, plus one free row to drop into.
function Layout.Height()
    local tallest = 1
    local sections = {}
    for section, list in pairs(columns or {}) do
        sections[section] = list
    end
    sections.generic = SuppliesColumns()
    for section, list in pairs(sections) do
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

-- Food column c's type ("health", "sanity", "hunger", "other") and its short label.
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
    for _, column in ipairs(columns.tools) do
        for _, item in ipairs(column) do
            table.insert(list, item)
        end
    end
    for i = 1, #supplies do
        if supplies[i] then
            table.insert(list, supplies[i])
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
