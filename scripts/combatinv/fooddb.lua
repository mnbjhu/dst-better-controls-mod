-- Food values the client can't read from the item itself.
-- The edible component only exists on the server, so values come from:
--   1. crock pot, Warly and spiced recipes (cooking.lua)
--   2. the VEGGIES table (raw and cooked fruit and vegetables)
--   3. a hand-written table of common raw foods, copied from their prefab files
-- Foods missing from all three are ignored by quick-eat. ci_food() lists them.

local cooking = require("cooking")

local FoodDB = {}

local db = nil

local function Food(health, hunger, sanity)
    return { health = health or 0, hunger = hunger or 0, sanity = sanity or 0 }
end

local function BuildRawFoods(T)
    return
    {
        meat                  = Food(T.HEALING_TINY, T.CALORIES_MED, -T.SANITY_SMALL),
        cookedmeat            = Food(T.HEALING_SMALL, T.CALORIES_MED, 0),
        meat_dried            = Food(T.HEALING_MED, T.CALORIES_MED, T.SANITY_MED),
        smallmeat             = Food(0, T.CALORIES_SMALL, -T.SANITY_SMALL),
        cookedsmallmeat       = Food(T.HEALING_TINY, T.CALORIES_SMALL, 0),
        smallmeat_dried       = Food(T.HEALING_MEDSMALL, T.CALORIES_SMALL, T.SANITY_SMALL),
        drumstick             = Food(0, T.CALORIES_SMALL, -T.SANITY_SMALL),
        drumstick_cooked      = Food(T.HEALING_TINY, T.CALORIES_SMALL, 0),
        fishmeat_small        = Food(T.HEALING_TINY, T.CALORIES_SMALL, 0),
        fishmeat_small_cooked = Food(T.HEALING_TINY, T.CALORIES_SMALL, 0),
        fishmeat_small_dried  = Food(T.HEALING_MOREMEDSMALL, T.CALORIES_SMALL, T.SANITY_MEDLARGE),
        fishmeat              = Food(T.HEALING_MEDSMALL, T.CALORIES_MED, 0),
        fishmeat_cooked       = Food(T.HEALING_MEDSMALL, T.CALORIES_MED, 0),
        fishmeat_dried        = Food(T.HEALING_MEDLARGE, T.CALORIES_MED, T.SANITY_MED),
        batwing               = Food(T.HEALING_SMALL, T.CALORIES_SMALL, -T.SANITY_SMALL),
        batwing_cooked        = Food(T.HEALING_MEDSMALL, T.CALORIES_MEDSMALL, 0),
        plantmeat             = Food(0, T.CALORIES_SMALL, -T.SANITY_SMALL),
        plantmeat_cooked      = Food(T.HEALING_TINY, T.CALORIES_MEDSMALL, 0),
        barnacle              = Food(0, T.CALORIES_SMALL, -T.SANITY_TINY),
        barnacle_cooked       = Food(T.HEALING_TINY, T.CALORIES_SMALL, 0),
        batnose               = Food(T.HEALING_SMALL, T.CALORIES_SMALL, -T.SANITY_SMALL),
        batnose_cooked        = Food(T.HEALING_MEDSMALL, T.CALORIES_MEDSMALL, 0),
        bird_egg              = Food(0, T.CALORIES_TINY, 0),
        bird_egg_cooked       = Food(0, T.CALORIES_SMALL, 0),
        tallbirdegg           = Food(T.HEALING_SMALL, T.CALORIES_MED, 0),
        tallbirdegg_cooked    = Food(0, T.CALORIES_LARGE, 0),
        honey                 = Food(T.HEALING_SMALL, T.CALORIES_TINY, 0),
        butterflywings        = Food(T.HEALING_MEDSMALL, T.CALORIES_TINY, 0),
        moonbutterflywings    = Food(T.HEALING_MEDSMALL, T.CALORIES_TINY, T.SANITY_MED),
        petals                = Food(T.HEALING_TINY, 0, 0),
        foliage               = Food(T.HEALING_TINY, 0, 0),
        lightbulb             = Food(T.HEALING_TINY, 0, 0),
        cutlichen             = Food(T.HEALING_SMALL, T.CALORIES_SMALL, -T.SANITY_TINY),
        red_cap               = Food(-T.HEALING_MED, T.CALORIES_SMALL, 0),
        red_cap_cooked        = Food(T.HEALING_TINY, 0, -T.SANITY_SMALL),
        green_cap             = Food(0, T.CALORIES_SMALL, -T.SANITY_HUGE),
        green_cap_cooked      = Food(-T.HEALING_TINY, 0, T.SANITY_MED),
        blue_cap              = Food(T.HEALING_MED, T.CALORIES_SMALL, -T.SANITY_MED),
        blue_cap_cooked       = Food(-T.HEALING_SMALL, 0, T.SANITY_SMALL),
        wormlight             = Food(T.HEALING_MEDSMALL + T.HEALING_SMALL, T.CALORIES_MED, -T.SANITY_SMALL),
        wormlight_lesser      = Food(T.HEALING_SMALL, T.CALORIES_SMALL, -T.SANITY_SMALL),
        royal_jelly           = Food(T.HEALING_LARGE, T.CALORIES_SMALL, T.SANITY_MED),
        butter                = Food(T.HEALING_LARGE, T.CALORIES_MED, 0),
        goatmilk              = Food(T.HEALING_SMALL, T.CALORIES_SMALL, T.SANITY_SMALL),
    }
end

-- Items that heal through the HEAL action instead of being eaten.
local function BuildHealers(T)
    return
    {
        healingsalve = T.HEALING_MED,
        bandage      = T.HEALING_MEDLARGE,
        spidergland  = T.HEALING_MEDSMALL,
    }
end

local healers = nil

local function Build()
    db = {}

    for _, recipes in pairs(cooking.recipes) do
        for name, recipe in pairs(recipes) do
            if db[name] == nil and (recipe.health ~= nil or recipe.hunger ~= nil or recipe.sanity ~= nil) then
                db[name] = Food(recipe.health, recipe.hunger, recipe.sanity)
            end
        end
    end

    if VEGGIES ~= nil then
        for name, veg in pairs(VEGGIES) do
            db[name] = Food(veg.health, veg.hunger, veg.sanity)
            db[name .. "_cooked"] = Food(veg.cooked_health, veg.cooked_hunger, veg.cooked_sanity)
        end
    end

    for name, food in pairs(BuildRawFoods(TUNING)) do
        db[name] = food
    end

    healers = BuildHealers(TUNING)
end

-- Base values for a food prefab, or nil if unknown.
function FoodDB.Get(prefab)
    if db == nil then
        Build()
    end
    return db[prefab]
end

-- Health restored by a healing item, or nil if it isn't one.
function FoodDB.GetHealAmount(prefab)
    if db == nil then
        Build()
    end
    return healers[prefab]
end

-- Values after freshness, matching the rules in components/edible.lua.
function FoodDB.ApplyFreshness(item, food)
    local health, hunger, sanity = food.health, food.hunger, food.sanity
    if item:HasTag("stale") then
        if health > 0 then health = health * TUNING.STALE_FOOD_HEALTH end
        if hunger > 0 then hunger = hunger * TUNING.STALE_FOOD_HUNGER end
        if sanity > 0 then sanity = 0 end
    elseif item:HasTag("spoiled") then
        if health > 0 then health = health * TUNING.SPOILED_FOOD_HEALTH end
        if hunger > 0 then hunger = hunger * TUNING.SPOILED_FOOD_HUNGER end
        if sanity >= 0 then sanity = -TUNING.SANITY_SMALL end
    end
    return { health = health, hunger = hunger, sanity = sanity }
end

return FoodDB
