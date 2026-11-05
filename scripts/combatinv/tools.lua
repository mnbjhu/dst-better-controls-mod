-- Contextual tools: clicks and the action button pick the right tool from your
-- inventory, and attacking with a tool or cane in hand switches to your weapon.
--
-- Clicks: when the hovered target needs a tool you aren't holding (an axe for a
-- tree), actions are worked out as if your best tool of that kind were in hand.
-- Vanilla's DoActionAutoEquip then equips it when you click.
--
-- Action button: if vanilla finds nothing to do, try again with each kind of tool.
-- The action button doesn't auto-equip in vanilla, so equip the tool before sending.
--
-- When a tool breaks, the next click or button press simply finds the next tool.

local Util = require("combatinv/util")
local HandSlot = require("combatinv/handslot")
local Travel = require("combatinv/travel")

local Tools = {}

-- Tool actions the mod picks a tool for. HAMMER is left out on purpose: hovering
-- your own base with a hammer in your bag must never mean "smash".
local AUTO_ACTIONS = { "CHOP", "MINE", "DIG", "NET" }

-- The action button only reaches for these: they never target things you built
-- or planted on purpose. (DIG would dig up berry bushes and saplings.)
local BUTTON_ACTIONS = { "CHOP", "MINE", "NET" }

-- Clicks only dig these up; everything else needs the shovel in hand already.
local DIG_TARGET_TAGS = { "stump", "grave" }

-- Rough material cost, cheapest first. Unknown tools sit in the middle.
local COST =
{
    lucy = 0,
    axe = 1, pickaxe = 1, shovel = 1, bugnet = 1,
    goldenaxe = 2, goldenpickaxe = 2, goldenshovel = 2,
    moonglassaxe = 3, thulecitebugnet = 3,
    multitool_axe_pickaxe = 4,
    pickaxe_lunarplant = 5, shovel_lunarplant = 5, voidcloth_scythe = 5,
}
local DEFAULT_COST = 2.5

local priority = "cheapest"
local attack_swap = true

--------------------------------------------------------------------------
-- Choosing a tool
--------------------------------------------------------------------------

local function IsUsable(player, item)
    local equippable = item.replica.equippable
    return equippable ~= nil
        and equippable:EquipSlot() == EQUIPSLOTS.HANDS
        and not equippable:IsRestricted(player)
end

local function Worn(item)
    return Util.GetUsesPercent(item) or 1
end

local function Better(a, b)
    if priority ~= "worn" then
        local ca, cb = COST[a.prefab] or DEFAULT_COST, COST[b.prefab] or DEFAULT_COST
        if ca ~= cb then
            if priority == "best" then
                return ca > cb
            end
            return ca < cb
        end
    end
    -- Ties, and "most worn first": finish half-used tools before starting new ones.
    local wa, wb = Worn(a), Worn(b)
    if wa ~= wb then
        return wa < wb
    end
    return a.prefab < b.prefab
end

-- Sort order for tools of one kind, best first (per the priority setting).
Tools.Better = Better

-- Best carried tool for an action id ("CHOP"), or nil.
function Tools.FindTool(player, action_id)
    local tag = action_id .. "_tool"
    local first, ordered = Util.FirstInOrder(function(item)
        return item:HasTag(tag) and IsUsable(player, item)
    end)
    if ordered then
        return first
    end
    local best = nil
    for _, item in ipairs(Util.GetCarriedItems(player)) do
        if item:HasTag(tag) and IsUsable(player, item) and (best == nil or Better(item, best)) then
            best = item
        end
    end
    return best
end

local function HasAnyTag(inst, tags)
    for _, tag in ipairs(tags) do
        if inst:HasTag(tag) then
            return true
        end
    end
    return false
end

-- The tool to pretend is in hand for this target, or nil to leave things alone.
local function ToolForTarget(player, target, hand)
    if target == nil or not target:IsValid() then
        return nil
    end
    for _, action_id in ipairs(AUTO_ACTIONS) do
        if target:HasTag(action_id .. "_workable") then
            if hand ~= nil and hand:HasTag(action_id .. "_tool") then
                return nil
            end
            if action_id == "DIG" and not HasAnyTag(target, DIG_TARGET_TAGS) then
                return nil
            end
            return Tools.FindTool(player, action_id)
        end
    end
    return nil
end

--------------------------------------------------------------------------
-- Attacking switches to a weapon
--------------------------------------------------------------------------

-- The item to attack with, or nil to leave the hand alone.
-- hand is the item attacks would use (a tool, the cane, a weapon, nothing...).
function Tools.ChooseAttackItem(player, hand)
    if hand ~= nil and HandSlot.GetCategory(hand) ~= nil then
        return hand -- already a weapon
    end
    if attack_swap then
        local weapon = HandSlot.GetBest(player, "melee")
        if weapon ~= nil then
            return weapon
        end
    end
    -- No melee weapon: anything with a weapon tag still beats bare hands or a cane.
    if hand ~= nil and hand:HasTag("weapon") and Util.GetWalkSpeedMult(hand) <= 1 then
        return hand
    end
    return nil
end

local function SwitchForAttack(player)
    if Travel.GetVirtualHand(player) ~= nil then
        return -- travel.lua is bringing an item back and asks ChooseAttackItem itself
    end
    local hand = Util.GetHandItem(player)
    local weapon = Tools.ChooseAttackItem(player, hand)
    if weapon ~= nil and weapon ~= hand and HandSlot.GetPendingTarget() ~= weapon then
        HandSlot.SetHand(player, weapon)
    end
end

--------------------------------------------------------------------------
-- Pretending a tool is in hand
--------------------------------------------------------------------------

local function WithHand(player, item, fn, ...)
    local inventory = player.replica.inventory
    local had_own = rawget(inventory, "GetEquippedItem")
    local GetEquippedItem = inventory.GetEquippedItem
    inventory.GetEquippedItem = function(self, slot)
        if slot == EQUIPSLOTS.HANDS then
            return item
        end
        return GetEquippedItem(self, slot)
    end
    local results = { n = 0 }
    local function run(...)
        results = { n = select("#", ...), ... }
    end
    local ok, err = pcall(function(...) run(fn(...)) end, ...)
    inventory.GetEquippedItem = had_own
    if not ok then
        error(err, 0)
    end
    return unpack(results, 1, results.n)
end

local function IsMe(player)
    return player ~= nil and player == ThePlayer
end

-- Is this action's item one we pretended was in hand, and not there yet?
local function NeedsEquip(player, buffaction)
    local item = buffaction ~= nil and buffaction.invobject or nil
    return item ~= nil
        and item:IsValid()
        and item:HasTag(buffaction.action.id .. "_tool")
        and Util.GetHandItem(player) ~= item
        and HandSlot.IsCarried(player, item)
end

--------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------

-- Must run before Travel.Install, so travel's virtual hand wraps these hooks
-- and "the hand" seen here is the item travel would bring back.
function Tools.Install(env, options)
    priority = options.priority or priority
    attack_swap = options.attack_swap ~= false
    Travel.choose_attack_item = Tools.ChooseAttackItem

    local PlayerActionPicker = require("components/playeractionpicker")
    local GetLeftClickActions = PlayerActionPicker.GetLeftClickActions
    function PlayerActionPicker:GetLeftClickActions(position, target, ...)
        if IsMe(self.inst) and target ~= nil then
            local hand = self.inst.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
            local tool = ToolForTarget(self.inst, target, hand)
            if tool ~= nil then
                return WithHand(self.inst, tool, GetLeftClickActions, self, position, target, ...)
            end
        end
        return GetLeftClickActions(self, position, target, ...)
    end

    local PlayerController = require("components/playercontroller")

    local GetActionButtonAction = PlayerController.GetActionButtonAction
    function PlayerController:GetActionButtonAction(force_target, ...)
        local action = GetActionButtonAction(self, force_target, ...)
        if action ~= nil or not IsMe(self.inst) or self.inst.replica.inventory == nil then
            return action
        end
        -- Nothing to do with what's in hand: try each kind of tool and take the nearest job.
        local hand = self.inst.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
        local best, best_dist = nil, nil
        for _, action_id in ipairs(BUTTON_ACTIONS) do
            if hand == nil or not hand:HasTag(action_id .. "_tool") then
                local tool = Tools.FindTool(self.inst, action_id)
                if tool ~= nil then
                    local found = WithHand(self.inst, tool, GetActionButtonAction, self, force_target, ...)
                    if found ~= nil and found.target ~= nil and found.target:IsValid() then
                        local dist = self.inst:GetDistanceSqToInst(found.target)
                        if best_dist == nil or dist < best_dist then
                            best, best_dist = found, dist
                        end
                    end
                end
            end
        end
        return best
    end

    local DoActionButton = PlayerController.DoActionButton
    function PlayerController:DoActionButton(...)
        if IsMe(self.inst) and self.placer == nil then
            local action = self:GetActionButtonAction()
            if action ~= nil and action.invobject ~= Travel.GetVirtualHand(self.inst) and NeedsEquip(self.inst, action) then
                Travel.Forget()
                -- The equip RPC reaches the server before the action button RPC.
                Util.Equip(self.inst, action.invobject)
            end
        end
        return DoActionButton(self, ...)
    end

    local DoAction = PlayerController.DoAction
    function PlayerController:DoAction(buffaction, ...)
        if IsMe(self.inst) and buffaction ~= nil then
            if buffaction.action == ACTIONS.ATTACK then
                SwitchForAttack(self.inst)
            elseif NeedsEquip(self.inst, buffaction) and buffaction.invobject ~= Travel.GetVirtualHand(self.inst) then
                -- Vanilla's DoActionAutoEquip equips it; just stop travel tracking.
                Travel.Forget()
            end
        end
        return DoAction(self, buffaction, ...)
    end

    local DoAttackButton = PlayerController.DoAttackButton
    function PlayerController:DoAttackButton(...)
        if IsMe(self.inst) then
            SwitchForAttack(self.inst)
        end
        return DoAttackButton(self, ...)
    end
end

-- Console helper: ci_tools() prints which tool each action would use.
function Tools.Debug()
    local player = ThePlayer
    if player == nil then
        return
    end
    for _, action_id in ipairs(AUTO_ACTIONS) do
        local tool = Tools.FindTool(player, action_id)
        print(string.format("[CombatInventory] %-5s -> %s", action_id, tool ~= nil and tool.prefab or "none"))
    end
    local weapon = Tools.ChooseAttackItem(player, Util.GetHandItem(player))
    print("[CombatInventory] attack -> " .. (weapon ~= nil and weapon.prefab or "keep hand item"))
end

return Tools
