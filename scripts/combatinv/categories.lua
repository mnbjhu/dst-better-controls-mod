-- Where each carried item really lives (inventory slot, backpack slot or equip
-- slot), plus pickup totals for the popups. Which drawer cell an item shows in
-- is layout.lua's job.

local Util = require("combatinv/util")

local Categories = {}

local EQUIP_SLOTS = { EQUIPSLOTS.HANDS, EQUIPSLOTS.BODY, EQUIPSLOTS.HEAD }

local function StackSize(item)
    local stackable = item.replica.stackable
    return stackable ~= nil and stackable:StackSize() or 1
end

-- Every item and where it lives, so the HUD can pick it up from the right slot.
-- where: "inv" (main inventory), "pack" (worn backpack) or "equip".
-- Items are unwrapped: see Util.Real.
function Categories.GetEntries(player)
    local inventory = player.replica.inventory
    local entries = {}
    for slot, item in pairs(inventory:GetItems()) do
        table.insert(entries, { item = Util.Real(item), where = "inv", slot = slot })
    end
    local backpack = inventory:GetOverflowContainer()
    if backpack ~= nil then
        for slot, item in pairs(backpack:GetItems()) do
            table.insert(entries, { item = Util.Real(item), where = "pack", slot = slot })
        end
    end
    for _, eslot in ipairs(EQUIP_SLOTS) do
        local item = Util.Real(inventory:GetEquippedItem(eslot))
        if item ~= nil then
            table.insert(entries, { item = item, where = "equip", slot = eslot })
        end
    end
    return entries
end

-- locations: item -> entry. totals / materials / examples feed the pickup
-- popups. space: inventory and backpack slots used and available.
function Categories.Build(player)
    local inventory = player.replica.inventory
    local model =
    {
        locations = {},
        totals = {},
        materials = {},
        examples = {},
        space = { used = 0, total = 0 },
    }
    for _, entry in ipairs(Categories.GetEntries(player)) do
        local item = entry.item
        model.locations[item] = entry
        model.totals[item.prefab] = (model.totals[item.prefab] or 0) + StackSize(item)
        model.examples[item.prefab] = item
        if entry.where ~= "equip" then
            model.space.used = model.space.used + 1
            if item.replica.stackable ~= nil and item.replica.equippable == nil then
                model.materials[item.prefab] = true
            end
        end
    end

    -- The item on the cursor still counts as carried, so moving things around
    -- doesn't look like a pickup.
    local active = Util.Real(inventory:GetActiveItem())
    if active ~= nil then
        model.totals[active.prefab] = (model.totals[active.prefab] or 0) + StackSize(active)
    end

    model.space.total = inventory:GetNumSlots()
    local backpack = inventory:GetOverflowContainer()
    if backpack ~= nil then
        model.space.total = model.space.total + backpack:GetNumSlots()
    end
    return model
end

Categories.EQUIP_SLOTS = EQUIP_SLOTS
Categories.StackSize = StackSize

return Categories
