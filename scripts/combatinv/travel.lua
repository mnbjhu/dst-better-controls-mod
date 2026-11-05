-- Travel: switch to the cane for walking, but keep the previous hand item's actions.
--
-- While travelling, the item you were holding is remembered as the "work item".
-- Mouse clicks and the action button are worked out as if the work item were in
-- your hand, so hovering a grave still says "Dig" with a shovel tucked away.
-- When you use one of those actions, the work item is equipped first, in the same
-- way vanilla auto-equips a tool you use from the inventory.

local Util = require("combatinv/util")
local HandSlot = require("combatinv/handslot")

local Travel = {}

-- Seconds after the work item comes back before the cane can come out again.
local LOCK_AFTER_RESTORE = 0.5
-- How long to keep treating the work item as held while the server catches up.
local RESTORE_GRACE = 1

-- Never put these away automatically: losing them hurts (darkness, rain, a bite).
local KEEP_TAGS = { "light", "lighter", "torch", "umbrella", "fishingrod" }

-- Actions that move the item around rather than use it. Same idea as the
-- exclusions in PlayerController:DoActionAutoEquip.
local NOT_USE_ACTIONS =
{
    DROP = true, STORE = true, EQUIP = true, GIVE = true, GIVETOPLAYER = true,
    GIVEALLTOPLAYER = true, ADDFUEL = true, ADDWETFUEL = true, DEPLOY = true,
    DEPLOY_FLOATING = true, CONSTRUCT = true, BUNDLESTORE = true, COMBINESTACK = true,
}

local mode = "auto"
local state = nil      -- { cane = item, work = item or nil, hold = bool } while travelling
local restoring = nil  -- { item = item, expires = time } after asking for the work item back
local lock_until = 0

local function IsMe(player)
    return player ~= nil and player == ThePlayer
end

local function Forget()
    state = nil
end

-- Stop travelling without switching anything: another module took over the hand.
function Travel.Forget()
    state = nil
    restoring = nil
end

--------------------------------------------------------------------------
-- The work item as seen by the action picker
--------------------------------------------------------------------------

-- The item actions should be worked out with, or nil to use the real hand item.
local function GetVirtualHand(player)
    if not IsMe(player) then
        return nil
    end
    local item = nil
    if restoring ~= nil and GetTime() < restoring.expires then
        item = restoring.item
    elseif state ~= nil then
        item = state.work
    end
    if item == nil or not item:IsValid() or Util.GetHandItem(player) == item then
        return nil
    end
    if not HandSlot.IsCarried(player, item) then
        return nil
    end
    return item
end

Travel.GetVirtualHand = GetVirtualHand

local function pack(...)
    return { n = select("#", ...), ... }
end

-- Run fn with the hands slot reporting the work item instead of the cane.
function Travel.WithVirtualHand(player, fn, ...)
    local virtual = GetVirtualHand(player)
    if virtual == nil then
        return fn(...)
    end
    local inventory = player.replica.inventory
    local had_own = rawget(inventory, "GetEquippedItem")
    local GetEquippedItem = inventory.GetEquippedItem
    inventory.GetEquippedItem = function(self, slot)
        if slot == EQUIPSLOTS.HANDS then
            return virtual
        end
        return GetEquippedItem(self, slot)
    end
    local results = pack(pcall(fn, ...))
    inventory.GetEquippedItem = had_own
    if not results[1] then
        error(results[2], 0)
    end
    return unpack(results, 2, results.n)
end

--------------------------------------------------------------------------
-- Getting the work item back
--------------------------------------------------------------------------

local function Restore(player, item)
    HandSlot.CancelPending()
    state = nil
    restoring = { item = item, expires = GetTime() + RESTORE_GRACE }
    lock_until = GetTime() + LOCK_AFTER_RESTORE
    -- The server handles RPCs in order, so this lands before the action that needs it.
    Util.Equip(player, item)
end

local function IsWeaponLike(item)
    return item:HasTag("weapon") or HandSlot.GetCategory(item) ~= nil
end

-- Set by tools.lua: picks the weapon to attack with given the work item.
Travel.choose_attack_item = nil

local function ChooseAttackItem(player, virtual)
    if Travel.choose_attack_item ~= nil then
        return Travel.choose_attack_item(player, virtual)
    end
    return IsWeaponLike(virtual) and virtual or nil
end

-- Called before an action is sent: bring the work item back if the action needs it.
local function BeforeAction(player, buffaction)
    if buffaction == nil then
        return
    end
    local virtual = GetVirtualHand(player)
    if virtual == nil then
        return
    end
    local action = buffaction.action
    if buffaction.invobject == virtual and not NOT_USE_ACTIONS[action.id] then
        Restore(player, virtual)
    elseif action == ACTIONS.ATTACK then
        -- Attacks never name the weapon; the server just uses whatever is in hand.
        local weapon = ChooseAttackItem(player, virtual)
        if weapon ~= nil then
            Restore(player, weapon)
        end
    end
end

--------------------------------------------------------------------------
-- Switching to the cane
--------------------------------------------------------------------------

local function HasKeepTag(item)
    for _, tag in ipairs(KEEP_TAGS) do
        if item:HasTag(tag) then
            return true
        end
    end
    return false
end

local function InCombat(player)
    local combat = player.replica.combat
    local target = combat ~= nil and combat:GetTarget() or nil
    return target ~= nil and target:IsValid()
        and not (target.replica.health ~= nil and target.replica.health:IsDead())
end

local function CanStartTravel(player)
    if not Util.CanUseHotkeys() then
        return false
    end
    local inventory = player.replica.inventory
    if inventory:GetActiveItem() ~= nil or inventory:IsHeavyLifting() or inventory:IsFloaterHeld() then
        return false
    end
    local rider = player.replica.rider
    return not (rider ~= nil and rider:IsRiding())
end

-- Returns true if travel started.
local function StartTravel(player, hold)
    local cane = HandSlot.FindTravelItem(player)
    if cane == nil then
        return false
    end
    local current = Util.GetHandItem(player)
    if current == cane then
        return false
    end
    restoring = nil
    state = { cane = cane, work = current, hold = hold }
    HandSlot.SetHand(player, cane)
    return true
end

local function TryAutoTravel(player)
    if mode ~= "auto" or state ~= nil or GetTime() < lock_until then
        return
    end
    if not CanStartTravel(player) or InCombat(player) then
        return
    end
    -- Holding a work button while walking means "keep working", not "travel".
    if TheInput:IsControlPressed(CONTROL_ACTION) or TheInput:IsControlPressed(CONTROL_ATTACK) then
        return
    end
    local current = Util.GetHandItem(player)
    if current ~= nil and HasKeepTag(current) then
        return
    end
    StartTravel(player, false)
end

local function Tick(player)
    if not IsMe(player) then
        return
    end
    local now = GetTime()
    local hand = Util.GetHandItem(player)

    if restoring ~= nil and (now >= restoring.expires or hand == restoring.item) then
        restoring = nil
    end

    if state ~= nil then
        if not HandSlot.IsPending() and hand ~= state.cane then
            -- Something else went into the hand (or the cane never made it): stop tracking.
            state = nil
        elseif state.work ~= nil and not HandSlot.IsCarried(player, state.work) then
            -- Dropped, stored or broken: nothing to come back to.
            state.work = nil
        end
    end

end

-- Runs every frame from PlayerController:OnUpdate, so the cane comes out on the
-- same frame you start walking.
local function CheckWalking(controller)
    if (controller.directwalking or controller.draggingonground) and IsMe(controller.inst) then
        TryAutoTravel(controller.inst)
    end
end

--------------------------------------------------------------------------
-- Hold-key mode
--------------------------------------------------------------------------

function Travel.HoldDown()
    if state ~= nil or not CanStartTravel(ThePlayer) then
        return
    end
    Util.ReturnActiveItem(ThePlayer)
    StartTravel(ThePlayer, true)
end

function Travel.HoldUp()
    if state == nil or not state.hold then
        return
    end
    local player = ThePlayer
    local work = state.work
    state = nil
    if player == nil then
        return
    end
    if work ~= nil and HandSlot.IsCarried(player, work) then
        HandSlot.SetHand(player, work)
    elseif work == nil then
        HandSlot.SetHand(player, nil)
    else
        HandSlot.CancelPending()
    end
end

--------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------

function Travel.Install(env, travel_mode)
    mode = travel_mode
    HandSlot.on_weapon_key = Forget

    local PlayerActionPicker = require("components/playeractionpicker")
    for _, name in ipairs({ "GetLeftClickActions", "GetRightClickActions" }) do
        local original = PlayerActionPicker[name]
        PlayerActionPicker[name] = function(self, ...)
            return Travel.WithVirtualHand(self.inst, original, self, ...)
        end
    end

    local PlayerController = require("components/playercontroller")

    local GetActionButtonAction = PlayerController.GetActionButtonAction
    function PlayerController:GetActionButtonAction(...)
        return Travel.WithVirtualHand(self.inst, GetActionButtonAction, self, ...)
    end

    -- Mouse clicks (and map clicks) all go through DoAction.
    local DoAction = PlayerController.DoAction
    function PlayerController:DoAction(buffaction, ...)
        if IsMe(self.inst) and buffaction ~= nil then
            if buffaction.action == ACTIONS.WALKTO then
                TryAutoTravel(self.inst)
            else
                BeforeAction(self.inst, buffaction)
            end
        end
        return DoAction(self, buffaction, ...)
    end

    -- The action button doesn't auto-equip in vanilla, so check its action first.
    local DoActionButton = PlayerController.DoActionButton
    function PlayerController:DoActionButton(...)
        if IsMe(self.inst) and self.placer == nil and GetVirtualHand(self.inst) ~= nil then
            BeforeAction(self.inst, self:GetActionButtonAction())
        end
        return DoActionButton(self, ...)
    end

    local OnUpdate = PlayerController.OnUpdate
    function PlayerController:OnUpdate(...)
        local result = OnUpdate(self, ...)
        CheckWalking(self)
        return result
    end

    -- The attack key: pressing it means you want your weapon back.
    local DoAttackButton = PlayerController.DoAttackButton
    function PlayerController:DoAttackButton(...)
        if IsMe(self.inst) then
            local virtual = GetVirtualHand(self.inst)
            local weapon = virtual ~= nil and ChooseAttackItem(self.inst, virtual) or nil
            if weapon ~= nil then
                Restore(self.inst, weapon)
            end
        end
        return DoAttackButton(self, ...)
    end

    env.AddPlayerPostInit(function(inst)
        local task = nil
        inst:ListenForEvent("playeractivated", function()
            if task == nil then
                task = inst:DoPeriodicTask(0.1, Tick)
            end
        end)
        inst:ListenForEvent("playerdeactivated", function()
            if task ~= nil then
                task:Cancel()
                task = nil
            end
            state, restoring = nil, nil
        end)
    end)
end

return Travel
