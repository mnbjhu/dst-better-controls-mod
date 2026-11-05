-- Shared helpers. Loaded with require, so this runs in the game's global environment.

local Util = {}

-- On clients, while an inventory change is being predicted, the inventory
-- hands out proxy wrappers (EntityScriptProxy) instead of the real items. A
-- proxy is a different table, so it never matches the real item as a table
-- key, and it goes stale once the server confirms. Always unwrap.
function Util.Real(item)
    if type(item) == "table" then
        return rawget(item, "_") or item
    end
    return item
end

-- True when the player is in normal gameplay: no menu, chat or console has focus.
function Util.CanUseHotkeys()
    local player = ThePlayer
    if player == nil or player.HUD == nil or player.replica.inventory == nil then
        return false
    end
    if player.HUD:HasInputFocus() or not player.HUD.shown then
        return false
    end
    if player:HasTag("playerghost") or (player.replica.health ~= nil and player.replica.health:IsDead()) then
        return false
    end
    return player.replica.inventory:IsVisible()
end

-- Mirrors the checks vanilla makes before sending an inventory action.
function Util.IsBusy(player)
    return player:HasTag("busy") or (player.sg ~= nil and player.sg:HasStateTag("busy"))
end

-- Set by the grouped HUD: carried items in the order the player arranged them.
-- Auto-tools and attack switching take the first that fits, instead of
-- ranking items themselves.
Util.order_source = nil

-- The first carried item (in the player's order) that passes test, or nil if
-- there's no player order.
function Util.FirstInOrder(test)
    if Util.order_source == nil then
        return nil, false
    end
    for _, item in ipairs(Util.order_source()) do
        if item:IsValid() and test(item) then
            return item, true
        end
    end
    return nil, true
end

-- Every item the player can use: main inventory plus a worn backpack.
function Util.GetCarriedItems(player)
    local items = {}
    local inventory = player.replica.inventory
    for _, item in pairs(inventory:GetItems()) do
        table.insert(items, Util.Real(item))
    end
    local backpack = inventory:GetOverflowContainer()
    if backpack ~= nil then
        for _, item in pairs(backpack:GetItems()) do
            table.insert(items, Util.Real(item))
        end
    end
    return items
end

function Util.GetHandItem(player)
    return Util.Real(player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS))
end

function Util.IsHandItem(item)
    local equippable = item.replica.equippable
    return equippable ~= nil and equippable:EquipSlot() == EQUIPSLOTS.HANDS
end

function Util.GetWalkSpeedMult(item)
    local inventoryitem = item.replica.inventoryitem
    return inventoryitem ~= nil and inventoryitem:GetWalkSpeedMult() or 1
end

-- Freshness from 1 (fresh) to 0 (spoiled), or nil if the item doesn't perish.
function Util.GetPerishPercent(item)
    if item.components.perishable ~= nil then
        return item.components.perishable:GetPercent()
    end
    local classified = item.replica.inventoryitem ~= nil and item.replica.inventoryitem.classified or nil
    if classified ~= nil and classified.perish ~= nil then
        local value = classified.perish:value()
        if value ~= 63 then
            return value / 62
        end
    end
    return nil
end

-- Durability from 1 (new) to 0, or nil if the item has no durability.
function Util.GetUsesPercent(item)
    if item.components.finiteuses ~= nil then
        return item.components.finiteuses:GetPercent()
    end
    local classified = item.replica.inventoryitem ~= nil and item.replica.inventoryitem.classified or nil
    if classified ~= nil and classified.percentused ~= nil then
        local value = classified.percentused:value()
        if value ~= 255 then
            return value / 100
        end
    end
    return nil
end

-- Could this item go into the inventory or backpack without being dropped?
-- (Vanilla's ReturnActiveItem drops it on the ground when there's no room.)
function Util.HasRoomFor(player, item)
    local inventory = player.replica.inventory
    if not inventory:IsFull() then
        return true
    end
    local backpack = inventory:GetOverflowContainer()
    if backpack ~= nil and not backpack:IsFull() then
        return true
    end
    local stackable = item.replica.stackable
    if stackable ~= nil then
        for _, other in ipairs(Util.GetCarriedItems(player)) do
            local s = other.replica.stackable
            if other.prefab == item.prefab and s ~= nil and not s:IsFull() and s:CanStackWith(item) then
                return true
            end
        end
    end
    return false
end

-- Hotkeys put away whatever is held on the cursor before acting. If there's
-- no room for it (picked up with a full inventory), it stays on the cursor
-- rather than being dropped.
function Util.ReturnActiveItem(player)
    local inventory = player.replica.inventory
    local active = Util.Real(inventory:GetActiveItem())
    if active ~= nil and Util.HasRoomFor(player, active) then
        inventory:ReturnActiveItem()
    end
end

function Util.Say(player, text)
    if player.components.talker ~= nil then
        player.components.talker:Say(text)
    end
end

-- Vanilla reads modifier keys when using an inventory item: Shift turns "use" into
-- "drop" (playeractionpicker.lua), and the held modifiers are sent to the server
-- with the request. Our hotkeys are often pressed with Shift held (travel key), so
-- hide the modifiers for the duration of the call and let the item be used plainly.
local MODIFIER_CONTROLS =
{
    [CONTROL_FORCE_TRADE] = true,
    [CONTROL_FORCE_STACK] = true,
    [CONTROL_FORCE_INSPECT] = true,
    [CONTROL_FORCE_ATTACK] = true,
}

function Util.UseItem(player, item)
    local inventory = player.replica.inventory
    local controller = player.components.playercontroller
    if controller == nil then
        inventory:UseItemFromInvTile(item)
        return
    end

    local had_is_pressed = rawget(controller, "IsControlPressed")
    local had_encode = rawget(controller, "EncodeControlMods")
    local IsControlPressed = controller.IsControlPressed
    controller.IsControlPressed = function(self, control)
        if MODIFIER_CONTROLS[control] then
            return false
        end
        return IsControlPressed(self, control)
    end
    controller.EncodeControlMods = function() return nil end

    local ok, err = pcall(inventory.UseItemFromInvTile, inventory, item)

    controller.IsControlPressed = had_is_pressed
    controller.EncodeControlMods = had_encode
    if not ok then
        print("[CombatInventory] UseItem failed: " .. tostring(err))
    end
end

-- Equip a hand item straight from the inventory or backpack. Unlike "use item",
-- this isn't queued as an action: the server swaps it immediately, mid-walk included.
function Util.Equip(player, item)
    if TheWorld.ismastersim then
        player.components.inventory:EquipActionItem(item)
    else
        SendRPCToServer(RPC.EquipActionItem, item)
    end
end

return Util
