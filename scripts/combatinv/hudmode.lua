-- Switches between the grouped HUD and the vanilla inventory bar.
--
-- The vanilla bar stays alive but hidden: it still owns the cursor item and the
-- controller inventory. Vanilla shows and hides it as a whole (ghosts, cutscenes,
-- the map...), so those calls are routed through here and applied to whichever
-- view is active.
--
-- The inventory key opens the HUD's drawers; Shift + the inventory key swaps the
-- whole HUD back to vanilla (and the key then swaps it back again).

local Util = require("combatinv/util")
local ItemTile = require("widgets/itemtile")
local ContainerWidget = require("widgets/containerwidget")

local HudMode = {}

local vanilla = false
local controls = nil
local hud = nil
local ShowInv, HideInv = nil, nil

-- A worn backpack opens its own side panel unless "integrated backpack" is on.
-- Its contents are in the boxes, so hide it with the vanilla bar.
local function ApplyBackpack()
    local inventory = controls.owner.replica.inventory
    local backpack = inventory ~= nil and inventory:GetOverflowContainer() or nil
    local widget = backpack ~= nil and controls.containers[backpack.inst] or nil
    if widget == nil or widget.parent ~= controls.containerroot_side then
        return
    end
    if not vanilla and widget.shown then
        widget:Hide()
        widget.combatinv_hidden = true
    elseif vanilla and widget.combatinv_hidden then
        widget:Show()
        widget.combatinv_hidden = nil
    end
end

-- Vanilla's pickup animations: each tile flies its own icon in. With our HUD
-- showing, the hidden vanilla bar and backpack window must not, or every
-- pickup shows several icons. Tiles read ignore_stacksize_anim from the class
-- unless they set their own (ours do: one tile per item animates).
local function SilenceVanilla()
    ItemTile.ignore_stacksize_anim = not vanilla or nil
end

local function IsOwnBackpack(container)
    local inventory = controls.owner.replica.inventory
    local backpack = inventory ~= nil and inventory:GetOverflowContainer() or nil
    return backpack ~= nil and backpack.inst == container
end

local function Apply()
    SilenceVanilla()
    local inv = controls.inv
    if inv.combatinv_wanted then
        if vanilla then
            ShowInv(inv)
            hud:Hide()
        else
            HideInv(inv)
            hud:Show()
            hud:Refresh(true)
        end
    else
        HideInv(inv)
        hud:Hide()
    end
    if (vanilla or not inv.combatinv_wanted) and hud:IsOpen() then
        hud:Close()
    end
    ApplyBackpack()
end

local function ToggleVanilla()
    vanilla = not vanilla
    Apply()
end

function HudMode.Install(new_controls, CombatHud, options)
    controls = new_controls
    local inv = controls.inv
    hud = controls.bottom_root:AddChild(CombatHud(controls.owner, options))
    hud.on_refresh = ApplyBackpack

    -- New items: the hidden bar and backpack window fly an icon to their own
    -- slots. Drop the start position so they don't; our HUD flies one instead.
    local OnItemGet = inv.OnItemGet
    function inv:OnItemGet(item, slot, source_pos, ...)
        return OnItemGet(self, item, slot, not vanilla and nil or source_pos, ...)
    end
    if not ContainerWidget.combatinv_patched then
        ContainerWidget.combatinv_patched = true
        local WidgetOnItemGet = ContainerWidget.OnItemGet
        function ContainerWidget:OnItemGet(data)
            if not vanilla and data ~= nil and data.src_pos ~= nil and IsOwnBackpack(self.container) then
                local copy = {}
                for k, v in pairs(data) do
                    copy[k] = v
                end
                copy.src_pos = nil
                data = copy
            end
            return WidgetOnItemGet(self, data)
        end
    end

    ShowInv, HideInv = inv.Show, inv.Hide
    inv.combatinv_wanted = inv.shown
    function inv:Show()
        self.combatinv_wanted = true
        Apply()
    end
    function inv:Hide()
        self.combatinv_wanted = false
        Apply()
    end
    Apply()
end

-- The inventory key: open or close the drawers. With Shift: switch to the
-- vanilla bar and back.
function HudMode.Toggle()
    if controls == nil or not Util.CanUseHotkeys() then
        return
    end
    if vanilla or TheInput:IsKeyDown(KEY_LSHIFT) or TheInput:IsKeyDown(KEY_RSHIFT) then
        ToggleVanilla()
    elseif hud:IsOpen() then
        hud:Close()
    elseif controls.inv.combatinv_wanted then
        hud:Open()
    end
end

-- A chest (or Chester, a Crock Pot...) opened: open the drawers to store into it.
function HudMode.OnContainerOpen(container)
    if controls == nil or vanilla or not controls.inv.combatinv_wanted or IsOwnBackpack(container) then
        return
    end
    local replica = container.replica.container
    if replica == nil or replica:IsReadOnlyContainer() then
        return
    end
    hud:OpenFor(container)
end

function HudMode.OnContainerClose(container)
    if hud ~= nil then
        hud:OnContainerClosed(container)
    end
end

-- Esc: close the drawers. Returns true if it did.
function HudMode.HandleCancel()
    if controls == nil then
        return false
    end
    if hud ~= nil and hud:IsOpen() then
        hud:Close()
        return true
    end
    return false
end

return HudMode
