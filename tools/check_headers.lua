-- Headless geometry smoke test for the real HUD Rebuild/PlaceDrawers methods.
-- Run: luajit tools/check_headers.lua
package.path = "scripts/?.lua;" .. package.path

function Class(base, ctor)
    local class = { _ctor = ctor, _base = base }
    class.__index = class
    return setmetatable(class, { __index = base, __call = function(c, ...)
        local self = setmetatable({}, c)
        ctor(self, ...)
        return self
    end })
end

local Widget = Class(nil, function(self, name)
    self.name, self.children, self.shown = name, {}, true
    self.x, self.y = 0, 0
    self.inst = { ListenForEvent = function() end }
end)
function Widget:AddChild(child) table.insert(self.children, child); return child end
function Widget:KillAllChildren() self.children = {} end
function Widget:SetPosition(x, y) self.x, self.y = x, y end
function Widget:SetSize(w, h) self.w, self.h = w, h end
function Widget:SetScale(x, y) self.sx, self.sy = x, y or x end
function Widget:SetClickable(value) self.clickable = value end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
for _, name in ipairs({ "SetRotation", "SetTint", "StartUpdating", "SetTextSize", "SetHoverText" }) do
    Widget[name] = function() end
end
local function Image(atlas, tex)
    local image = Widget("image")
    image.atlas, image.tex = atlas, tex
    return image
end
local function Button(_, label, size)
    local button = Widget(label)
    button:SetSize(unpack(size))
    return button
end
local function IconButton()
    local button = Widget("inspect")
    button.icon = button:AddChild(Widget("icon"))
    return button
end
local function stub(name, value) package.loaded[name] = value end
stub("widgets/widget", Widget)
stub("widgets/image", Image)
stub("widgets/text", function() return Widget("text") end)
stub("widgets/itemtile", {})
stub("widgets/redux/templates", { StandardButton = Button })
stub("widgets/templates", { IconButton = IconButton })
stub("widgets/combatinv_slot", setmetatable({}, { __call = function()
    local slot = Image("images/hud.xml", "inv_slot.tex")
    slot:SetSize(68, 68)
    return slot
end }))
for _, name in ipairs({ "util", "handslot", "quickeat", "categories", "tooltypes" }) do
    stub("combatinv/" .. name, {})
end
local counts, rows, art, controller
local Layout = { Height = function() return rows end, Columns = function(section)
    local columns = {}
    for i = 1, counts[section] do columns[i] = {} end
    return columns
end }
stub("combatinv/layout", Layout)
EQUIPSLOTS = { HANDS = "hands", BODY = "body", HEAD = "head" }
UIFONT = "test"
STRINGS = { UI = { HUD = { INSPECT_SELF = "Inspect" } } }
TheSim = { AtlasContains = function(_, atlas) return atlas ~= "headers" or art end }
TheInput = { ControllerAttached = function() return controller end }
function GetGameModeProperty() return false end
function softresolvefilepath() return true end
local Hud = require("widgets/combatinv_hud")
function Hud:SectionCells(section, height)
    local cells = {}
    for col = 1, counts[section] do
        for row = 1, height do
            table.insert(cells, { col = col, row = row, opts = {} })
        end
    end
    return cells
end
function Hud:GetTarget() return self.test_chest and {} or nil end

local function find(parent, name)
    for _, child in ipairs(parent.children) do
        if child.name == name then return child end
    end
end
local cases = 0
for _, shape in ipairs({ {6,3,4}, {0,0,1}, {1,1,1}, {10,6,8} }) do
    counts = { tools = shape[1], food = shape[2], gear = 3, generic = shape[3] }
    for _, loaded in ipairs({ true, false }) do
        art = loaded
        for _, gamepad in ipairs({ true, false }) do
            controller = gamepad
            for _, chest in ipairs({ true, false }) do
                rows = 4
                local hud = Hud({ prefab = "wilson" }, { art_atlas = "slots", header_atlas = "headers" })
                hud.test_chest = chest
                hud:Rebuild()
                local drawer = hud.drawers[1]
                local handle = find(drawer.widget, "top_row")
                local headers, previous_right = 0, -math.huge
                for _, child in ipairs(handle.children) do
                    if child.name:match("^section_crest_") then
                        headers = headers + 1
                        if art then
                            local sprite = child.children[1]
                            assert(sprite.clickable == false, "header intercepts item clicks")
                            assert(child.x - sprite.w/2 > previous_right, "headers overlap")
                            previous_right = child.x + sprite.w/2
                            assert(child.y - sprite.h/2 >= 102, "header covers first slot row")
                            assert(child.y + sprite.h/2 <= 131, "inset projects above rail")
                            assert(child.y + sprite.h/2 < 135, "inset overlaps action row")
                            assert(#child.children == 1, "inset has extra label/decorations")
                            assert(sprite.tex:match("^inset_"), "old floating header still used")
                        end
                    end
                end
                local expected = 2 + (shape[1] > 0 and 1 or 0) + (shape[2] > 0 and 1 or 0)
                assert(headers == expected, "missing or extra section label")
                if chest then
                    local edit = find(drawer.contents, "Edit")
                    local deposit = find(drawer.widget, "Deposit")
                    assert(edit.x + edit.w/2 < deposit.x - deposit.w/2, "actions overlap in compact layout")
                end
                for _, progress in ipairs({ 0, 0.5, 1 }) do
                    hud.progress, hud.open = progress, true
                    hud:PlaceDrawers()
                    assert(drawer.contents.shown == (progress > 0), "drawer visibility mismatch")
                end
                -- Optional geometry export for rendering the actual widget tree
                -- against the installed game's atlas (empty inventory preview).
                if arg[1] and shape[1] == 6 and art and not controller and not chest then
                    local file = assert(io.open(arg[1], "w"))
                    local function dump(widget, px, py, sx, sy)
                        if not widget.shown then return end
                        local x, y = px + widget.x * sx, py + widget.y * sy
                        sx, sy = sx * (widget.sx or 1), sy * (widget.sy or 1)
                        if widget.tex then
                            file:write(string.format("%s\t%s\t%f\t%f\t%f\t%f\n",
                                widget.atlas, widget.tex, x, y, widget.w * sx, widget.h * sy))
                        end
                        for _, child in ipairs(widget.children) do dump(child, x, y, sx, sy) end
                    end
                    dump(drawer.widget, 0, 0, 1, 1)
                    file:close()
                end
                cases = cases + 1
            end
        end
    end
end
print(string.format("%d header layout cases passed (compact/max, art/fallback, controller, chest, animation)", cases))
