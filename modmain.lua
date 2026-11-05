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

-- The key code for a key option, or nil when it's set to Off.
local function GetKey(option)
    local name = GetModConfigData(option)
    return name and G[name] or nil
end

-- Binds a key option's handlers; does nothing when the key is Off.
local function OnKey(option, down, up)
    local key = GetKey(option)
    if key == nil then
        return
    end
    if down ~= nil then
        G.TheInput:AddKeyDownHandler(key, down)
    end
    if up ~= nil then
        G.TheInput:AddKeyUpHandler(key, up)
    end
end

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
local travel_mode = GetModConfigData("travel_mode")
if travel_mode ~= "off" then
    Travel.Install(env, travel_mode)
end
if travel_mode == "hold" then
    OnKey("travel_key", Travel.HoldDown, Travel.HoldUp)
end

-- Quick-eat, one key per stat.
OnKey("eat_health_key", function() QuickEat.Eat("health") end)
OnKey("eat_sanity_key", function() QuickEat.Eat("sanity") end)
OnKey("eat_hunger_key", function() QuickEat.Eat("hunger") end)

-- Number keys replace vanilla's slot hotkeys.
-- With the grouped HUD, each number equips that tool slot (1 = first slot), so
-- they follow whatever types you've put in the slots. Without it, 1-3 equip
-- melee / ranged / magic and the other numbers keep their vanilla behaviour.
if GetModConfigData("weapon_keys") then
    local grouped = GetModConfigData("grouped_hud")
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
        if grouped then
            return G.require("combatinv/layout").EquipColumn(index)
        end
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
if GetModConfigData("grouped_hud") then
    local CombatHud = G.require("widgets/combatinv_hud")
    local HudMode = G.require("combatinv/hudmode")
    local ToolTypes = G.require("combatinv/tooltypes")
    G.require("combatinv/layout").Configure(GetModConfigData("tool_slots"))
    ToolTypes.SetNumberKeys(GetModConfigData("weapon_keys"))

    -- "B" for KEY_B, or nil when the key is Off.
    local function KeyLabel(option)
        local name = GetModConfigData(option)
        return name and (name:gsub("^KEY_", "")) or nil
    end

    AddClassPostConstruct("widgets/controls", function(self)
        local art_atlas = MODROOT .. "images/combatinv_slots.xml"
        if not G.kleifileexists(art_atlas) then
            print("[CombatInventory] slot art missing, using text labels: " .. art_atlas)
            art_atlas = nil
        end
        HudMode.Install(self, CombatHud, { inventory_key = KeyLabel("inventory_key"), art_atlas = art_atlas })
    end)
    OnKey("inventory_key", HudMode.Toggle)

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
