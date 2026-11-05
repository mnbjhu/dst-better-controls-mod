-- The slot editor: build the drawers in game (see "The slot editor" in
-- docs/DESIGN.md). Opened from the Edit button on the open drawers.
--
--   Tools / Consumables   one row per slot: key, type, move left / right,
--                         delete; "+ Add slot" at the end
--   Generic columns       - n +
--   Keys                  Open drawers, Hold for cane
--
-- Every change is saved and applied to the drawers straight away.

local Screen = require "widgets/screen"
local Widget = require "widgets/widget"
local Text = require "widgets/text"
local TEMPLATES = require "widgets/redux/templates"
local Slots = require "combatinv/slots"
local ToolTypes = require "combatinv/tooltypes"
local Keys = require "combatinv/keys"

-- Window size in the window's own units (RectangleWindow draws at 0.7).
local WIN_W, WIN_H = 1180, 600
local COLUMN_X = { -560, 20 }      -- left edge of each column
local TOP = WIN_H / 2 - 40
local ROW_H = 44
local BUTTON_H = 40
local TEXT_SIZE = 26
local WARN = { 238 / 255, 99 / 255, 99 / 255, 1 }

local FOOD_TYPES =
{
    { key = "health", label = "Health" },
    { key = "sanity", label = "Sanity" },
    { key = "hunger", label = "Hunger" },
    { key = "other", label = "Other" },
}

-- Key code -> "KEY_..." name, from the game's own constants.
local key_names = nil
local function KeyNameOf(code)
    if key_names == nil then
        key_names = {}
        for name, value in pairs(_G) do
            if type(name) == "string" and type(value) == "number" and name:match("^KEY_")
                and (key_names[value] == nil or #name < #key_names[value]) then
                key_names[value] = name
            end
        end
    end
    return key_names[code]
end

-- What a key is called on screen: the game's own name for it ("Left Shift"),
-- else the constant without KEY_.
local function KeyLabel(name)
    if name == nil then
        return "-"
    end
    local code = rawget(_G, name)
    local inputs = STRINGS.UI.CONTROLSSCREEN ~= nil and STRINGS.UI.CONTROLSSCREEN.INPUTS ~= nil
        and STRINGS.UI.CONTROLSSCREEN.INPUTS[1] or nil
    local label = code ~= nil and inputs ~= nil and inputs[code] or nil
    return label ~= nil and label ~= "" and label or (name:gsub("^KEY_", ""))
end

local SlotEditor = Class(Screen, function(self, on_close)
    Screen._ctor(self, "CombatInvSlotEditor")
    self.on_close = on_close
    self.capturing = nil -- what's waiting for a key: { section, index } or { name }

    self.black = self:AddChild(TEMPLATES.BackgroundTint())
    self.proot = self:AddChild(TEMPLATES.ScreenRoot())
    self.window = self.proot:AddChild(TEMPLATES.RectangleWindow(WIN_W, WIN_H, "Drawer slots", {
        { text = "Reset", cb = function() self:ResetLayout() end },
        { text = "Done", cb = function() self:Close() end },
    }))
    self.content = self.window:AddChild(Widget("content"))
    self.default_focus = self.window

    Keys.SetSuspended(true)
    self:Build()
end)

--------------------------------------------------------------------------
-- Building the rows
--------------------------------------------------------------------------

function SlotEditor:Label(text, x, y, width, colour, size)
    local label = self.content:AddChild(Text(CHATFONT, size or TEXT_SIZE, text, colour or UICOLOURS.GOLD_SELECTED))
    label:SetRegionSize(width, BUTTON_H)
    label:SetHAlign(ANCHOR_LEFT)
    label:SetPosition(x + width / 2, y)
    return label
end

function SlotEditor:Button(text, x, y, width, fn, hover)
    local button = self.content:AddChild(TEMPLATES.StandardButton(fn, text, { width, BUTTON_H }))
    button:SetPosition(x + width / 2, y)
    if hover ~= nil then
        button:SetHoverText(hover)
    end
    return button
end

-- A key button: shows the key, waits for a new one when clicked.
function SlotEditor:KeyButton(key, target, x, y, dupes)
    local waiting = self.capturing ~= nil and self.capturing.section == target.section
        and self.capturing.index == target.index and self.capturing.name == target.name
    local text = waiting and "Press a key" or KeyLabel(key)
    local button = self:Button(text, x, y, 130, function()
        self.capturing = target
        self:RebuildSoon()
    end, "Click, then press the new key. Backspace: no key. Esc: cancel.")
    if not waiting and key ~= nil and dupes[key] ~= nil then
        button:SetTextColour(unpack(WARN))
        button:SetTextFocusColour(unpack(WARN))
        button:SetHoverText("Another slot uses this key too: only the first one works.")
    end
    return button
end

function SlotEditor:TypeSpinner(section, index, slot, x, y)
    local options = {}
    local has_current = false
    if section == "tools" then
        table.insert(options, { text = "Any", data = "any" })
        for _, t in ipairs(ToolTypes.All()) do
            table.insert(options, { text = t.label, data = t.key })
        end
    else
        for _, t in ipairs(FOOD_TYPES) do
            table.insert(options, { text = t.label, data = t.key })
        end
    end
    for _, option in ipairs(options) do
        has_current = has_current or option.data == slot.type
    end
    if not has_current then
        -- A tool type named after one item ("item:<prefab>").
        table.insert(options, { text = ToolTypes.Label(slot.type), data = slot.type })
    end
    local spinner = self.content:AddChild(TEMPLATES.StandardSpinner(options, 200, BUTTON_H, nil, TEXT_SIZE))
    -- SetSelected calls the on-change function, so set that afterwards (or
    -- every rebuild would reset a type borrowed from a dropped tool).
    spinner:SetSelected(slot.type)
    spinner:SetOnChangedFn(function(selected)
        Slots.SetType(section, index, selected)
    end)
    spinner:SetPosition(x + 100, y)
    return spinner
end

-- One section's rows. Returns the y below them.
function SlotEditor:SlotRows(section, title, x, y, dupes)
    self:Label(title, x, y, 400, UICOLOURS.GOLD, 32)
    y = y - ROW_H
    local list = Slots.List(section)
    local min, max = Slots.Limits(section)
    for index, slot in ipairs(list) do
        self:Label("Slot " .. index, x, y, 70)
        self:KeyButton(slot.key, { section = section, index = index }, x + 75, y, dupes)
        self:TypeSpinner(section, index, slot, x + 215, y)
        local left = self:Button("<", x + 425, y, 40, function()
            Slots.Move(section, index, index - 1)
            self:RebuildSoon()
        end, "Move left on the bar")
        local right = self:Button(">", x + 470, y, 40, function()
            Slots.Move(section, index, index + 1)
            self:RebuildSoon()
        end, "Move right on the bar")
        local delete = self:Button("X", x + 515, y, 40, function()
            Slots.Remove(section, index)
            self:RebuildSoon()
        end, "Delete this slot")
        if index == 1 then left:Disable() end
        if index == #list then right:Disable() end
        if #list <= min then delete:Disable() end
        y = y - ROW_H
    end
    if #list < max then
        self:Button("+ Add slot", x, y, 200, function()
            Slots.Add(section)
            self:RebuildSoon()
        end)
        y = y - ROW_H
    end
    return y
end

function SlotEditor:Build()
    self.content:KillAllChildren()
    local dupes = Slots.DuplicateKeys()
    local left_x = COLUMN_X[1]
    local right_x = COLUMN_X[2]

    self:SlotRows("tools", "Tools", left_x, TOP, dupes)

    local y = self:SlotRows("food", "Consumables", right_x, TOP, dupes)

    y = y - 10
    local generic = Slots.GenericColumns()
    local min, max = Slots.Limits("generic")
    self:Label("Generic columns", right_x, y, 220, UICOLOURS.GOLD, 32)
    local minus = self:Button("-", right_x + 245, y, 40, function()
        Slots.SetGeneric(generic - 1)
        self:RebuildSoon()
    end)
    self:Label(tostring(generic), right_x + 300, y, 40)
    local plus = self:Button("+", right_x + 345, y, 40, function()
        Slots.SetGeneric(generic + 1)
        self:RebuildSoon()
    end)
    if generic <= min then minus:Disable() end
    if generic >= max then plus:Disable() end

    y = y - ROW_H - 10
    self:Label("Keys", right_x, y, 400, UICOLOURS.GOLD, 32)
    y = y - ROW_H
    self:Label("Open drawers", right_x, y, 230)
    self:KeyButton(Slots.Key("drawers"), { name = "drawers" }, right_x + 245, y, dupes)
    y = y - ROW_H
    self:Label("Hold for cane", right_x, y, 230)
    self:KeyButton(Slots.Key("cane"), { name = "cane" }, right_x + 245, y, dupes)
    self:Label("(cane switching: Hold key)", right_x + 385, y, 190, UICOLOURS.GOLD_UNIMPORTANT, 20)

    if next(dupes) ~= nil then
        self:Label("Keys in red are used by more than one slot: only the first one works.",
            -WIN_W / 2 + 30, -WIN_H / 2 + 12, WIN_W - 60, WARN, 22)
    end
end

-- Builds the rows again next frame: a button's click handler mustn't destroy
-- the button while it's still running. Static time, so it still runs while
-- the game is paused behind the editor.
function SlotEditor:RebuildSoon()
    if self.rebuild_task ~= nil then
        return
    end
    self.rebuild_task = self.inst:DoStaticTaskInTime(0, function()
        self.rebuild_task = nil
        if not self.closed then
            self:Build()
        end
    end)
end

--------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------

function SlotEditor:SetCapturedKey(name)
    local target = self.capturing
    self.capturing = nil
    if target.name ~= nil then
        Slots.SetNamedKey(target.name, name)
    else
        Slots.SetKey(target.section, target.index, name)
    end
    self:RebuildSoon()
end

function SlotEditor:OnRawKey(key, down)
    if self.capturing == nil then
        return SlotEditor._base.OnRawKey(self, key, down)
    end
    if not down then
        return true
    end
    if key == KEY_ESCAPE then
        -- Cancel; the Esc release mustn't close the editor too.
        self.capturing = nil
        self.swallow_cancel = true
        self:RebuildSoon()
    elseif key == KEY_BACKSPACE or key == KEY_DELETE then
        self:SetCapturedKey(nil)
    else
        local name = KeyNameOf(key)
        if name ~= nil then
            self:SetCapturedKey(name)
        end
    end
    return true
end

function SlotEditor:OnControl(control, down)
    if control == CONTROL_CANCEL and (self.capturing ~= nil or self.swallow_cancel) then
        if not down then
            self.swallow_cancel = nil
        end
        return true
    end
    if SlotEditor._base.OnControl(self, control, down) then
        return true
    end
    if control == CONTROL_CANCEL and not down then
        self:Close()
        return true
    end
    return false
end

function SlotEditor:ResetLayout()
    self.capturing = nil
    Slots.Reset()
    self:RebuildSoon()
end

function SlotEditor:Close()
    if self.closed then
        return
    end
    self.closed = true
    Keys.SetSuspended(false)
    TheFrontEnd:PopScreen(self)
    if self.on_close ~= nil then
        self.on_close()
    end
end

-- However the editor goes away, the mod's keys come back.
function SlotEditor:OnDestroy()
    Keys.SetSuspended(false)
    SlotEditor._base.OnDestroy(self)
end

return SlotEditor
