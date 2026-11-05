-- One slot in the grouped HUD: a vanilla item tile with our own click handling,
-- hints and hotkey label.
--
-- opts:
--   item, bg, in_hand, hotkey
--   scale         slot scale (default 0.8; the HUD uses 1 inside its vanilla-scaled bar)
--   clicks        handlers: left, right, shift_left, shift_right, ctrl_left
--                 (a modified click with no handler of its own falls back to the plain one)
--   hints         tooltip lines, same keys as clicks: { left = "Pick up", ... }
--   empty_label, tooltip               for empty slots
--   art           { atlas, tex }: a drawing for an empty slot, in place of a
--                 label. The slot becomes vanilla's grey-green gear slot
--                 (slot_blank.tex in the same atlas) and the drawing, white in
--                 the atlas, is tinted like the gear slots' silhouettes
--   dim           the held item can't go here: darken the slot
--   available     an empty slot the held item can go in: show it at full brightness

local ItemSlot = require("widgets/itemslot")
local ItemTile = require("widgets/itemtile")
local Text = require("widgets/text")
local Image = require("widgets/image")

local HUD_ATLAS = "images/hud.xml"
local SLOT_SCALE = 0.8

-- The hand/body/head slots' silhouettes darken the slot evenly, to x0.887.
-- The drawings' strokes are solid, so black at 11.3% does exactly the same.
local ART_TINT = { 0, 0, 0, 0.113 }
local ART_BLANK = "slot_blank.tex"

-- Slot states, all solid (see SetSlotTint):
local EMPTY_TINT = { 0.78, 0.78, 0.78, 1 }  -- empty, nothing held: greyed out
local DIM_TINT = { 0.45, 0.45, 0.45, 1 }    -- can't take the held item: dark

local QUIET = { 0.75, 0.75, 0.7, 1 }
local ACCENT = { 1, 0.85, 0.45, 1 }

local function MouseName(control)
    return TheInput:GetLocalizedControl(TheInput:GetControllerID(), control)
end

local HINT_ORDER =
{
    { "left", "", CONTROL_PRIMARY },
    { "ctrl_left", "Ctrl + ", CONTROL_PRIMARY },
    { "right", "", CONTROL_SECONDARY },
    { "shift_left", "Shift + ", CONTROL_PRIMARY },
    { "shift_right", "Shift + ", CONTROL_SECONDARY },
}

local HudSlot = Class(ItemSlot, function(self, owner, opts)
    ItemSlot._ctor(self, HUD_ATLAS, opts.bg or "inv_slot.tex", owner)
    local scale = opts.scale or SLOT_SCALE
    self.base_scale = scale
    self.highlight_scale = scale * 1.2
    self:SetScale(scale)
    self.clicks = opts.clicks or {}

    local lines = {}
    local hints = opts.hints or {}
    for _, h in ipairs(HINT_ORDER) do
        if hints[h[1]] ~= nil then
            table.insert(lines, h[2] .. MouseName(h[3]) .. ": " .. hints[h[1]])
        end
    end
    local hint_text = table.concat(lines, "\n")

    if opts.item ~= nil then
        local tile = ItemTile(opts.item)
        -- Our own hints replace vanilla's slot hints, which describe different clicks.
        tile.GetDescriptionString = function(t)
            local name = (t.item ~= nil and t.item:IsValid()) and t.item:GetDisplayName() or ""
            return hint_text ~= "" and (name .. "\n" .. hint_text) or name
        end
        self:SetTile(tile)
    else
        if opts.art ~= nil then
            self.bgimage:SetTexture(opts.art[1], ART_BLANK)
            self.bgimage:SetSize(68, 68)
            self.art = self:AddChild(Image(opts.art[1], opts.art[2]))
            self.art:SetSize(68, 68)
            self.art:SetClickable(false)
        elseif opts.empty_label ~= nil then
            -- Long names ("Pickaxe") get a smaller font so they fit the slot.
            local size = #opts.empty_label > 4 and 20 or 30
            self.label = self:AddChild(Text(BODYTEXTFONT, size, opts.empty_label))
            self.label:SetColour(unpack(QUIET))
        end
        local tooltip = opts.tooltip
        if hint_text ~= "" then
            tooltip = tooltip ~= nil and (tooltip .. "\n" .. hint_text) or hint_text
        end
        if tooltip ~= nil then
            self:SetTooltip(tooltip)
        end
        -- Empty slots are greyed out by darkening, not transparency: see-through
        -- slots turn muddy over the plank and their drawings all but vanish.
        self:SetSlotTint(unpack(EMPTY_TINT))
    end

    if opts.in_hand then
        self:SetSlotTint(unpack(ACCENT))
    end
    if opts.available then
        self:SetSlotTint(1, 1, 1, 1)
    elseif opts.dim then
        self:SetSlotTint(unpack(DIM_TINT))
        if self.tile ~= nil and self.tile.image ~= nil then
            self.tile.image:SetTint(1, 1, 1, 0.35)
        end
        if self.label ~= nil then
            self.label:SetColour(0.5, 0.5, 0.5, 0.5)
        end
    end

    if opts.hotkey ~= nil then
        self.hotkey = self:AddChild(Text(NUMBERFONT, 30, opts.hotkey))
        self.hotkey:SetPosition(-22, 24)
        self.hotkey:SetColour(unpack(ACCENT))
    end
end)

-- Tints the slot for its state (neutral, can take the held item, can't).
-- The drawing on it, if any, follows the same tint so they never disagree.
function HudSlot:SetSlotTint(r, g, b, a)
    self.bgimage:SetTint(r, g, b, a)
    if self.art ~= nil then
        self.art:SetTint(ART_TINT[1] * r, ART_TINT[2] * g, ART_TINT[3] * b, ART_TINT[4] * a)
    end
end

function HudSlot:OnControl(control, down)
    if HudSlot._base.OnControl(self, control, down) then
        return true
    end
    if not down then
        return false
    end
    local clicks = self.clicks
    local shift = TheInput:IsControlPressed(CONTROL_FORCE_TRADE)
    local ctrl = TheInput:IsControlPressed(CONTROL_FORCE_STACK)
    local fn = nil
    if control == CONTROL_ACCEPT then
        fn = (shift and clicks.shift_left) or (ctrl and clicks.ctrl_left) or clicks.left
    elseif control == CONTROL_SECONDARY then
        fn = (shift and clicks.shift_right) or clicks.right
    end
    if fn ~= nil then
        fn()
        return true
    end
    return false
end

HudSlot.QUIET = QUIET
HudSlot.ACCENT = ACCENT

return HudSlot
