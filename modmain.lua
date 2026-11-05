-- Combat Inventory: hand-slot hotkeys, auto-cane and quick-eat.
-- Game logic lives in scripts/combatinv/, which runs in the global environment.

local G = GLOBAL

-- Empty-slot art for the drawers (built from the icon sheet; see images/).
Assets =
{
    Asset("ATLAS", "images/combatinv_slots.xml"),
    Asset("IMAGE", "images/combatinv_slots.tex"),
}

local HandSlot = G.require("combatinv/handslot")
local Travel = G.require("combatinv/travel")
local Tools = G.require("combatinv/tools")
local QuickEat = G.require("combatinv/quickeat")
local Slots = G.require("combatinv/slots")
local Keys = G.require("combatinv/keys")

local grouped = GetModConfigData("grouped_hud")
local travel_mode = GetModConfigData("travel_mode")

-- The drawer layout and every key the mod uses (slots.lua) are built from
-- these options until the in-game slot editor replaces them. The layout is
-- loaded the first time it's needed, so nothing is read from disk here.
Slots.SetConfig({
    tool_slots = GetModConfigData("tool_slots"),
    number_keys = GetModConfigData("weapon_keys"),
    eat_keys =
    {
        health = GetModConfigData("eat_health_key"),
        sanity = GetModConfigData("eat_sanity_key"),
        hunger = GetModConfigData("eat_hunger_key"),
    },
    inventory_key = GetModConfigData("inventory_key"),
    cane_key = travel_mode == "hold" and GetModConfigData("travel_key") or nil,
})

-- Tools: the right tool for the target, and weapons for attacks.
-- Installed before travel so travel's hooks wrap these ones.
if GetModConfigData("auto_tools") then
    Tools.Install(env, {
        priority = GetModConfigData("tool_priority"),
        attack_swap = GetModConfigData("attack_swap"),
    })
end

-- Travel: the cane comes out for walking ("auto") or while a key is held ("hold").
-- Either way, clicks and the action button still offer the previous item's actions.
if travel_mode ~= "off" then
    Travel.Install(env, travel_mode)
end

-- Keys, all from the slot list (keys.lua):
--   drawers key      opens the drawers (grouped HUD)
--   cane key         held for the cane (travel "hold" mode)
--   tool slot keys   equip that tool column, again to cycle (grouped HUD)
--   consumable keys  eat the best food for the slot's stat; an Other slot's
--                    key eats the top item in that slot (grouped HUD)
local function Layout()
    return G.require("combatinv/layout")
end

local function EatFromColumn(c)
    local column = Layout().Columns("food")[c]
    QuickEat.EatChosen(column ~= nil and column[1] or nil)
end

Keys.Install({
    drawers = grouped and function() G.require("combatinv/hudmode").Toggle() end or nil,
    cane_down = travel_mode == "hold" and Travel.HoldDown or nil,
    cane_up = travel_mode == "hold" and Travel.HoldUp or nil,
    tool = grouped and function(c) Layout().EquipColumn(c) end or nil,
    food = function(c, food_type)
        if food_type == "other" then
            if grouped then
                EatFromColumn(c)
            end
        else
            QuickEat.Eat(food_type)
        end
    end,
    crafting_modifier = function()
        return G.TheInput:IsControlPressed(G.CONTROL_CRAFTING_MODIFIER)
    end,
})
G.TheInput:AddKeyHandler(Keys.OnKey)

-- Without the grouped HUD there are no tool columns: number keys 1-3 equip
-- melee / ranged / magic and the other numbers keep their vanilla behaviour.
if GetModConfigData("weapon_keys") and not grouped then
    local NUMBER_CONTROLS =
    {
        G.CONTROL_INV_1, G.CONTROL_INV_2, G.CONTROL_INV_3, G.CONTROL_INV_4, G.CONTROL_INV_5,
        G.CONTROL_INV_6, G.CONTROL_INV_7, G.CONTROL_INV_8, G.CONTROL_INV_9, G.CONTROL_INV_10,
    }
    local WEAPONS = { "melee", "ranged", "magic" }
    local slot_of = {}
    for i, control in ipairs(NUMBER_CONTROLS) do
        slot_of[control] = i
    end

    local function Press(index)
        return WEAPONS[index] ~= nil and HandSlot.EquipCategory(WEAPONS[index])
    end

    AddClassPostConstruct("screens/playerhud", function(self)
        local OnControl = self.OnControl
        function self:OnControl(control, down)
            local index = slot_of[control]
            -- Ctrl + number still selects crafting pins, as in vanilla.
            if down and index ~= nil and self.shown
                and not G.TheInput:IsControlPressed(G.CONTROL_CRAFTING_MODIFIER)
                and Press(index) then
                return true
            end
            return OnControl(self, control, down)
        end
    end)
end

-- Grouped HUD: replaces the vanilla inventory bar with drawers. The inventory
-- key opens them, and they also open when you open a chest.
if grouped then
    local CombatHud = G.require("widgets/combatinv_hud")
    local HudMode = G.require("combatinv/hudmode")
    local ToolTypes = G.require("combatinv/tooltypes")
    ToolTypes.SetNumberKeys(GetModConfigData("weapon_keys"))

    AddClassPostConstruct("widgets/controls", function(self)
        local art_atlas = MODROOT .. "images/combatinv_slots.xml"
        if not G.kleifileexists(art_atlas) then
            print("[CombatInventory] slot art missing, using text labels: " .. art_atlas)
            art_atlas = nil
        end
        local drawers_key = Slots.Key("drawers")
        HudMode.Install(self, CombatHud, {
            inventory_key = drawers_key ~= nil and (drawers_key:gsub("^KEY_", "")) or nil,
            art_atlas = art_atlas,
        })
    end)

    -- Vanilla's inventory hotkeys (CONTROL_INV_1...) use whatever sits in that
    -- slot of the vanilla bar. Skip them while one of the mod's keys is held,
    -- so a slot's key only does what the slot says. Ctrl + number still
    -- selects crafting pins.
    local INV_CONTROLS = {}
    for i = 1, 10 do
        INV_CONTROLS[G["CONTROL_INV_" .. i]] = true
    end
    local function IsKeyDown(code)
        return G.TheInput:IsKeyDown(code)
    end

    AddClassPostConstruct("screens/playerhud", function(self)
        local OnControlInv = self.OnControl
        function self:OnControl(control, down)
            if INV_CONTROLS[control] and not G.TheInput:IsControlPressed(G.CONTROL_CRAFTING_MODIFIER)
                and Keys.OwnsHeldKey(IsKeyDown) then
                return true
            end
            return OnControlInv(self, control, down)
        end
    end)

    AddClassPostConstruct("screens/playerhud", function(self)
        local OpenContainer = self.OpenContainer
        function self:OpenContainer(container, side, ...)
            local result = OpenContainer(self, container, side, ...)
            HudMode.OnContainerOpen(container)
            return result
        end

        local CloseContainer = self.CloseContainer
        function self:CloseContainer(container, side, ...)
            HudMode.OnContainerClose(container)
            return CloseContainer(self, container, side, ...)
        end

        -- Esc (keyboard pause, handled on release): close the drawers before
        -- it opens the pause menu.
        local OnControl = self.OnControl
        function self:OnControl(control, down)
            if not down and control == G.CONTROL_PAUSE and not G.TheInput:ControllerAttached()
                and HudMode.HandleCancel() then
                return true
            end
            return OnControl(self, control, down)
        end
    end)
end

-- Console helper: type ci_food() to see how quick-eat rates the food you carry.
G.ci_food = QuickEat.Debug
-- ci_tools() shows which tool each job would use and what attacks would switch to.
G.ci_tools = Tools.Debug
-- ci_slots() prints the drawer layout: each slot's type and key.
G.ci_slots = G.require("combatinv/slots").Debug
