-- Hand slot: equipping with retries, weapon categories and the weapon number keys.

local Util = require("combatinv/util")

local HandSlot = {}

-- Preferred order within each weapon category, best first.
-- Weapons not listed come after these, sorted by name.
local PRIORITY =
{
    melee =
    {
        "sword_lunarplant", "ruins_bat", "nightsword", "glasscutter", "hambat",
        "batbat", "nightstick", "tentaclespike", "spear_wathgrithr_lightning",
        "spear_wathgrithr", "whip", "trident", "spear", "bullkelp_root",
    },
    ranged =
    {
        "houndstooth_blowpipe", "voidcloth_boomerang", "slingshot", "blowdart_fire",
        "blowdart_pipe", "blowdart_yellow", "blowdart_sleep", "boomerang",
    },
    magic =
    {
        "staff_lunarplant", "firestaff", "icestaff", "icestaff2", "icestaff3",
        "opalstaff", "yellowstaff", "telestaff", "greenstaff", "orangestaff",
    },
}

local PRIORITY_INDEX = {}
for category, list in pairs(PRIORITY) do
    PRIORITY_INDEX[category] = {}
    for i, prefab in ipairs(list) do
        PRIORITY_INDEX[category][prefab] = i
    end
end

-- Hand items faster than this are travel items, not melee weapons.
-- The Thulecite Club (1.1) stays a weapon; the cane (1.25) does not.
local TRAVEL_SPEED_MIN = 1.15

local EXCLUDED_TAGS = { "tool", "torch", "lighter", "fishingrod" }

local function GetCategory(item)
    if not Util.IsHandItem(item) then
        return nil
    end
    for _, tag in ipairs(EXCLUDED_TAGS) do
        if item:HasTag(tag) then
            return nil
        end
    end
    if item.prefab:find("staff") ~= nil then
        return "magic"
    end
    if item:HasTag("rangedweapon") or item:HasTag("projectile") or item:HasTag("thrown")
        or item:HasTag("blowdart") or item:HasTag("slingshot") then
        return "ranged"
    end
    if item:HasTag("weapon") and Util.GetWalkSpeedMult(item) < TRAVEL_SPEED_MIN then
        return "melee"
    end
    return nil
end

--------------------------------------------------------------------------
-- Equipping with retries
--------------------------------------------------------------------------

-- Vanilla drops inventory actions while the player is busy (mid-swing, mid-eat).
-- Keep trying for a short while until the server confirms the item is in hand.
local RETRY_PERIOD = 0.1
local RESEND_DELAY = 0.35
local GIVE_UP_AFTER = 2

local pending_task = nil
local pending_target = nil

local function CancelPending()
    if pending_task ~= nil then
        pending_task:Cancel()
        pending_task = nil
    end
    pending_target = nil
end

local function IsCarried(player, item)
    return item:IsValid() and player.replica.inventory:IsHolding(item, true)
end

-- target nil means "empty hand".
local function SetHand(player, target)
    CancelPending()
    local start = GetTime()
    local last_send = -math.huge

    local function attempt()
        local current = Util.GetHandItem(player)
        if current == target then
            CancelPending()
            return
        end
        if GetTime() - start > GIVE_UP_AFTER then
            CancelPending()
            return
        end
        if target ~= nil and not IsCarried(player, target) then
            CancelPending()
            return
        end
        if Util.IsBusy(player) or GetTime() - last_send < RESEND_DELAY then
            return
        end
        last_send = GetTime()
        if target ~= nil then
            Util.Equip(player, target)
        elseif not player.replica.inventory:IsFull() then
            -- Unequip into the inventory. Skipped when full so the item isn't dropped.
            Util.UseItem(player, current)
        else
            CancelPending()
        end
    end

    attempt()
    if Util.GetHandItem(player) ~= target then
        pending_task = player:DoPeriodicTask(RETRY_PERIOD, attempt)
        pending_target = target
    end
end

--------------------------------------------------------------------------
-- Travel item lookup (used by travel.lua)
--------------------------------------------------------------------------

function HandSlot.FindTravelItem(player)
    local best, best_speed = nil, 1
    local candidates = Util.GetCarriedItems(player)
    table.insert(candidates, Util.GetHandItem(player))
    for _, item in ipairs(candidates) do
        if Util.IsHandItem(item) then
            local speed = Util.GetWalkSpeedMult(item)
            if speed >= TRAVEL_SPEED_MIN and (speed > best_speed or (speed == best_speed and item.prefab == "cane")) then
                best, best_speed = item, speed
            end
        end
    end
    return best
end

HandSlot.SetHand = SetHand
HandSlot.CancelPending = CancelPending
HandSlot.IsCarried = IsCarried
HandSlot.GetCategory = GetCategory

function HandSlot.IsPending()
    return pending_task ~= nil
end

-- The item SetHand is still trying to equip, or nil.
function HandSlot.GetPendingTarget()
    return pending_task ~= nil and pending_target or nil
end

-- Set by travel.lua: called when a number key takes over the hand slot.
HandSlot.on_weapon_key = nil

--------------------------------------------------------------------------
-- Weapon number keys
--------------------------------------------------------------------------

local preferred = {} -- category -> prefab last chosen

local function SortCandidates(category, items)
    local index = PRIORITY_INDEX[category]
    table.sort(items, function(a, b)
        local ia, ib = index[a.prefab] or math.huge, index[b.prefab] or math.huge
        if ia ~= ib then
            return ia < ib
        end
        return a.prefab < b.prefab
    end)
end

HandSlot.SortCandidates = SortCandidates

-- One item per prefab: the equipped one if it's that prefab, otherwise the most worn,
-- so half-used weapons get finished before fresh ones are started.
local function GetCandidates(player, category)
    local equipped = Util.GetHandItem(player)
    local by_prefab = {}
    local items = Util.GetCarriedItems(player)
    if equipped ~= nil then
        table.insert(items, equipped)
    end
    for _, item in ipairs(items) do
        if GetCategory(item) == category then
            local chosen = by_prefab[item.prefab]
            if chosen == nil or item == equipped then
                by_prefab[item.prefab] = item
            elseif chosen ~= equipped then
                local a, b = Util.GetUsesPercent(item), Util.GetUsesPercent(chosen)
                if a ~= nil and b ~= nil and a < b then
                    by_prefab[item.prefab] = item
                end
            end
        end
    end
    local list = {}
    for _, item in pairs(by_prefab) do
        table.insert(list, item)
    end
    SortCandidates(category, list)
    return list
end

-- The item a number key would equip from scratch: last used, else the best.
function HandSlot.GetBest(player, category)
    local first, ordered = Util.FirstInOrder(function(item)
        return GetCategory(item) == category
    end)
    if ordered then
        return first
    end
    local candidates = GetCandidates(player, category)
    for _, item in ipairs(candidates) do
        if item.prefab == preferred[category] then
            return item
        end
    end
    return candidates[1]
end

local CATEGORY_LABEL = { melee = "melee weapon", ranged = "ranged weapon", magic = "staff" }

function HandSlot.EquipCategory(category)
    if not Util.CanUseHotkeys() then
        return false
    end
    local player = ThePlayer
    local candidates = GetCandidates(player, category)
    if #candidates == 0 then
        Util.Say(player, "I don't have a " .. CATEGORY_LABEL[category] .. ".")
        return true
    end

    local current = Util.GetHandItem(player)
    local choice = nil
    if current ~= nil and GetCategory(current) == category then
        -- Already in this category: cycle to the next one.
        for i, item in ipairs(candidates) do
            if item == current then
                choice = candidates[i % #candidates + 1]
                break
            end
        end
    end
    if choice == nil then
        for _, item in ipairs(candidates) do
            if item.prefab == preferred[category] then
                choice = item
                break
            end
        end
    end
    choice = choice or candidates[1]
    preferred[category] = choice.prefab

    -- A weapon key during travel ends travel: the weapon stays in hand.
    if HandSlot.on_weapon_key ~= nil then
        HandSlot.on_weapon_key()
    end

    if choice ~= current then
        Util.ReturnActiveItem(player)
        SetHand(player, choice)
    end
    return true
end

return HandSlot
