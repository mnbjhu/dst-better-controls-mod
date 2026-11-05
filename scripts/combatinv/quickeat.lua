-- Quick-eat: one key per stat eats the food that best fills what's missing.

local Util = require("combatinv/util")
local FoodDB = require("combatinv/fooddb")

local QuickEat = {}

local STATS = { "health", "sanity", "hunger" }

-- Never eaten automatically, whatever the numbers say.
local BAD_PREFABS =
{
    spoiled_food = true,
    spoiled_fish = true,
    spoiled_fish_small = true,
    rottenegg = true,
    humanmeat = true,
    humanmeat_cooked = true,
    humanmeat_dried = true,
}

-- Diets the client can't see. Vanilla offers these characters the EAT action
-- for anything their tags allow, then the server spits out what they refuse
-- (eater.lua PrefersToEat), so the tag check alone lets the food through.
local REFUSES =
{
    -- Wigfrid: meat and sweets only (no veggies, berries, seeds...).
    wathgrithr = function(item)
        return not (item:HasTag("edible_MEAT") or item:HasTag("edible_GOODIES"))
    end,
    -- Warly: cooked dishes only (crock pot food, candy, festival food).
    warly = function(item)
        return not (item:HasTag("preparedfood") or item:HasTag("pre-preparedfood"))
    end,
}

-- How much of each stat a character actually gets from food.
-- Wormwood heals nothing from eating (healing items still work).
local ABSORPTION =
{
    wormwood = { health = 0, sanity = 1, hunger = 1 },
}

-- Same diet check vanilla uses to offer the EAT action (componentactions.lua),
-- plus the server-side refusals above.
local function CanEat(player, item)
    -- Fruitcake: no player will eat it (eater.lua).
    if item.prefab == "winter_food4" then
        return false
    end
    local refuses = REFUSES[player.prefab]
    if refuses ~= nil and refuses(item) then
        return false
    end
    for _, group in pairs(FOODGROUP) do
        if player:HasTag(group.name .. "_eater") then
            for _, foodtype in ipairs(group.types) do
                if item:HasTag("edible_" .. foodtype) then
                    return true
                end
            end
        end
    end
    for _, foodtype in pairs(FOODTYPE) do
        if item:HasTag("edible_" .. foodtype) and player:HasTag(foodtype .. "_eater") then
            return true
        end
    end
    return false
end

-- What eating the item gives this character (freshness and absorption applied).
local function FoodValues(player, item, food)
    local values = FoodDB.ApplyFreshness(item, food)
    local absorption = ABSORPTION[player.prefab]
    if absorption ~= nil then
        local scaled = {}
        for stat, value in pairs(values) do
            scaled[stat] = value * (absorption[stat] or 1)
        end
        values = scaled
    end
    return values
end

local function IsBadFood(item, values)
    return BAD_PREFABS[item.prefab]
        or item:HasTag("monstermeat")
        or values.health < -TUNING.HEALING_SMALL
        or values.sanity < -TUNING.SANITY_MED
end

local function GetNeed(player, stat)
    local replica = player.replica[stat]
    if replica == nil then
        return 0
    end
    local max = replica.MaxWithPenalty ~= nil and replica:MaxWithPenalty() or replica:Max()
    return math.max(0, max - replica:GetCurrent())
end

-- What eating or using this item would do, or nil if quick-eat shouldn't touch it.
local function GetEffect(player, item)
    local heal = FoodDB.GetHealAmount(item.prefab)
    if heal ~= nil then
        if player.replica.health ~= nil and player.replica.health:CanHeal() then
            return { health = heal, hunger = 0, sanity = 0 }
        end
        return nil
    end

    local food = FoodDB.Get(item.prefab)
    if food == nil or not CanEat(player, item) then
        return nil
    end
    local values = FoodValues(player, item, food)
    if IsBadFood(item, values) then
        return nil
    end
    return values
end

-- Higher is better. Rewards filling the need, punishes overshoot and side effects,
-- and nudges towards food that is about to spoil.
local function Score(item, effect, stat, need)
    local gain = effect[stat]
    local used = math.min(gain, need)
    local waste = gain - used

    local side = 0
    for _, other in ipairs(STATS) do
        if other ~= stat and effect[other] < 0 then
            side = side + effect[other]
        end
    end

    local freshness = Util.GetPerishPercent(item)
    local spoil_bonus = freshness ~= nil and (1 - freshness) * 5 or 0

    return used - 0.5 * waste + 1.5 * side + spoil_bonus
end

function QuickEat.FindBest(player, stat)
    local need = GetNeed(player, stat)
    local best, best_score = nil, nil
    for _, item in ipairs(Util.GetCarriedItems(player)) do
        local effect = GetEffect(player, item)
        if effect ~= nil and effect[stat] > 0 then
            local score = Score(item, effect, stat, need)
            if best_score == nil or score > best_score then
                best, best_score = item, score
            end
        end
    end
    return best, need
end

local STAT_LABEL = { health = "health", sanity = "sanity", hunger = "hunger" }

local last_eat_time = 0

function QuickEat.Eat(stat)
    if not Util.CanUseHotkeys() then
        return
    end
    -- Ignore key repeat while the key is held.
    local now = GetTime()
    if now - last_eat_time < 0.3 then
        return
    end
    last_eat_time = now

    local player = ThePlayer
    local item, need = QuickEat.FindBest(player, stat)
    if need <= 0 then
        Util.Say(player, "My " .. STAT_LABEL[stat] .. " is already full.")
        return
    end
    if item == nil then
        Util.Say(player, "I have nothing for my " .. STAT_LABEL[stat] .. ".")
        return
    end
    Util.ReturnActiveItem(player)
    Util.UseItem(player, item)
end

-- Which food box an item belongs in: "health", "sanity", "hunger" or "bad".
-- nil means it isn't food as far as the HUD is concerned: seeds, unknown
-- edibles, and anything this character can't eat (it goes in generic).
function QuickEat.GetFoodGroup(player, item)
    if FoodDB.GetHealAmount(item.prefab) ~= nil then
        return "health"
    end
    if not CanEat(player, item) then
        return nil
    end
    local food = FoodDB.Get(item.prefab)
    if food == nil then
        if BAD_PREFABS[item.prefab] or item:HasTag("monstermeat") then
            return "bad"
        end
        return nil
    end
    local values = FoodValues(player, item, food)
    if IsBadFood(item, values) then
        return "bad"
    end
    -- The stat it restores most. Raw numbers are fine: they share a scale in-game.
    local best, best_value = nil, 0
    for _, stat in ipairs(STATS) do
        if values[stat] > best_value then
            best, best_value = stat, values[stat]
        end
    end
    return best or "bad"
end

-- Which food column an item goes in: "health", "sanity" or "hunger", or nil if
-- it isn't food (seeds, unknown edibles). Bad food (monster meat, rot...) goes
-- by the stat it changes most, which for most of it is hunger.
function QuickEat.GetFoodColumn(player, item)
    local group = QuickEat.GetFoodGroup(player, item)
    if group == nil or group ~= "bad" then
        return group
    end
    local food = FoodDB.Get(item.prefab)
    if food ~= nil then
        local values = FoodValues(player, item, food)
        local best, best_value = "hunger", 0
        for _, stat in ipairs(STATS) do
            if values[stat] > best_value then
                best, best_value = stat, values[stat]
            end
        end
        return best
    end
    return "hunger"
end

function QuickEat.EatItem(player, item)
    Util.ReturnActiveItem(player)
    Util.UseItem(player, item)
end

-- Console helper: ci_food() prints what quick-eat knows about the food you carry.
function QuickEat.Debug()
    local player = ThePlayer
    if player == nil then
        return
    end
    for _, stat in ipairs(STATS) do
        local item, need = QuickEat.FindBest(player, stat)
        print(string.format("[CombatInventory] %s: need %.0f, best %s", stat, need, item ~= nil and item.prefab or "none"))
    end
    for _, item in ipairs(Util.GetCarriedItems(player)) do
        if item:HasTag("edible_" .. FOODTYPE.MEAT) or item:HasTag("edible_" .. FOODTYPE.VEGGIE)
            or item:HasTag("edible_" .. FOODTYPE.GENERIC) or item:HasTag("edible_" .. FOODTYPE.GOODIES)
            or FoodDB.GetHealAmount(item.prefab) ~= nil then
            local effect = GetEffect(player, item)
            local known = FoodDB.Get(item.prefab) ~= nil or FoodDB.GetHealAmount(item.prefab) ~= nil
            if effect ~= nil then
                print(string.format("  %-24s hp %5.1f  san %5.1f  hun %5.1f", item.prefab, effect.health, effect.sanity, effect.hunger))
            else
                print(string.format("  %-24s %s", item.prefab, known and "skipped (bad food or diet)" or "UNKNOWN - not in food table"))
            end
        end
    end
end

return QuickEat
