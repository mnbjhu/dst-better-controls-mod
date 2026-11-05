-- The grouped inventory HUD: a row of vanilla-style drawers along the bottom of
-- the screen (tools, food, gear, generic). Replaces the vanilla inventory bar.
--
-- The drawers show layout.lua's columns: items stay where they were put. All
-- drawers are the same height, the tallest column plus one free row to drop
-- into. Closed, only the top row shows; opening (inventory key, or opening a
-- chest) springs the drawers up so every row shows.
--
-- Clicks follow vanilla's inventory slots:
--   left: pick up (Ctrl: half the stack); holding an item: put it down here
--   right: use (equip, eat, wear...); holding an item: use it on this one
--   Shift + left: store in the open chest; with nothing open, move the item
--     between its use column and the generic drawer. Shift + right: drop.
-- Hovering an item shows vanilla's own text (name and right-click action).
-- Putting an item down:
--   lifted from the drawers: it moves to this cell (swapping with the item
--     there if that one fits the cell it came from)
--   from outside (picked up with a full inventory, taken from a chest): it
--     swaps with the item in this cell, or tops up its stack, or fills the
--     empty cell. Nothing is ever dropped for lack of room.

local Widget = require("widgets/widget")
local Image = require("widgets/image")
local Text = require("widgets/text")
local ItemTile = require("widgets/itemtile")
local TEMPLATES = require("widgets/redux/templates")
-- The inventory bar's portrait button comes from the older templates (its
-- square paper button, highlight and hover text), not the redux ones.
local OLD_TEMPLATES = require("widgets/templates")

local Util = require("combatinv/util")
local HandSlot = require("combatinv/handslot")
local QuickEat = require("combatinv/quickeat")
local Categories = require("combatinv/categories")
local ToolTypes = require("combatinv/tooltypes")
local Layout = require("combatinv/layout")
local HudSlot = require("widgets/combatinv_slot")

-- Vanilla inventory bar measurements (widgets/inventorybar.lua), in bar units.
-- The whole HUD is drawn at the vanilla bar's scale and offset, so it sits
-- exactly where the vanilla bar does.
local HUD_ATLAS = "images/hud.xml"
local BAR_SCALE = 0.6
local BAR_OFFSET = -16    -- vanilla nudges its bar down by this much (screen units)
local SCREEN_Y = -BAR_OFFSET / BAR_SCALE -- the screen's bottom edge, in bar units
local W = 68              -- slot size
local SEP = 12            -- gap between slots (vanilla SEP)
local STEP = W + SEP      -- slot to slot, across and down
local BOX_MARGIN = 32     -- plank edge to first slot
local LANE = 40           -- between sections, where the border's notch hangs down
local NOTCH_W = 120       -- divider patches, menu units (art is 480x256 at 4x)
local NOTCH_H = 64
local BORDER = 28         -- the plank's top border, ink lines included (inventory_filler.tex)
local SPACER_W = 12       -- spacer tile, menu units (art is 48x1024 at 4x)
local SPACER_H = 256
local SLOT_Y = 68         -- top row's slot centres (vanilla out_pos: the one-row bar; in_pos is for two rows)
local PLANK_TOP = 61      -- plank top edge above the top row
local PIECE_W = 64        -- inventory_corner.tex / inventory_filler.tex
local PIECE_H = 256
local PIECE_JOIN = 50     -- how far a drawer's extension runs up behind its top piece
local PIECE_OVERLAP = 4   -- the middle runs a little under each end, so no seam shows
local REFRESH_PERIOD = 0.2

local OPEN_TIME = 0.15    -- seconds for one drawer to spring open
local CLOSE_TIME = 0.12
local STAGGER = 0.07      -- each drawer starts this fraction of the time after the last
local OVERSHOOT = 1.9     -- how far past fully open the spring throws (ease-out-back)
local FLY_TIME = 0.3      -- pickup icon flying into its slot (vanilla's timing)


local EQUIP_BG =
{
    [EQUIPSLOTS.HANDS] = "equip_slot.tex",
    [EQUIPSLOTS.BODY] = "equip_slot_body.tex",
    [EQUIPSLOTS.HEAD] = "equip_slot_head.tex",
}

local ACCENT = HudSlot.ACCENT

local SECTIONS = { "tools", "food", "gear", "generic" }

-- Pictures for empty columns (images/combatinv_slots.xml, passed in by
-- modmain as options.art_atlas). Without it, the columns show text labels.
local ART_ATLAS = nil
local TOOL_ART = { melee = "weapon.tex", ranged = "ranged.tex", magic = "staff.tex", axe = "axe.tex" }
local GENERIC_TOOL_ART = "tool.tex"
local FOOD_ART = { health = "health.tex", sanity = "sanity.tex", hunger = "hunger.tex" }

-- Only art the game actually loaded: after c_reset, newly added art files
-- aren't loaded until the game restarts, so check (once per picture) and fall
-- back to the text label instead of drawing a blank slot.
local art_loaded = {}

local function Art(tex)
    -- (the blank gear slot lives in the same atlas; check it too)
    if ART_ATLAS == nil or tex == nil then
        return nil
    end
    if art_loaded[tex] == nil then
        art_loaded[tex] = (TheSim:AtlasContains(ART_ATLAS, tex) and TheSim:AtlasContains(ART_ATLAS, "slot_blank.tex")) and true or false
        if not art_loaded[tex] then
            print("[CombatInventory] slot art not loaded (restart the game to load new art): " .. tex)
        end
    end
    return art_loaded[tex] and { ART_ATLAS, tex } or nil
end

--------------------------------------------------------------------------
-- The HUD
--------------------------------------------------------------------------

local CombatHud = Class(Widget, function(self, owner, options)
    Widget._ctor(self, "CombatInventoryHud")
    self.owner = owner
    self.inventory_key = options.inventory_key or "B"
    ART_ATLAS = options.art_atlas

    self.open = false
    self.progress = 0             -- 0 closed .. 1 fully open, animated
    self.container = nil          -- the open chest Shift-click stores into, if any
    self.opened_by_container = false

    self:SetScale(BAR_SCALE)
    self:SetPosition(0, BAR_OFFSET)
    self.root = self:AddChild(Widget("drawers"))
    self.drawers = {}
    self.records = {}             -- every item slot, in display order
    self.anim_slot = {}           -- item -> the one visible slot pickups fly to
    self.flights = {}             -- pickups waiting for their slot to exist
    self.signature = nil
    self.locations = {}
    self.timer = 0

    -- Auto-tools and attack switching use items in the order of the drawers.
    Util.order_source = Layout.Ordered

    local function dirty()
        self.timer = REFRESH_PERIOD
    end
    for _, event in ipairs({ "itemget", "itemlose", "equip", "unequip", "newactiveitem", "stacksizechange" }) do
        self.inst:ListenForEvent(event, dirty, owner)
    end
    -- Remember whether the item on the cursor was lifted out of the drawers
    -- (see PickUp) or came from outside.
    self.lifting = nil
    self.own_active = nil
    self.inst:ListenForEvent("newactiveitem", function(_, data)
        local item = Util.Real(data ~= nil and data.item or nil)
        if item ~= nil and self.lifting ~= nil and GetTime() - self.lifting < 1
            and self:WasCarried(item) then
            self.own_active = item
            self.own_from_equip = self.lifting_equip
        elseif item == nil or item ~= self.own_active then
            self.own_active = nil
        end
        self.lifting = nil
    end, owner)

    self.on_itemget = function(_, data)
        if data ~= nil and data.item ~= nil and data.src_pos ~= nil then
            table.insert(self.flights, { item = Util.Real(data.item), src_pos = data.src_pos })
        end
        dirty()
    end
    self.inst:ListenForEvent("itemget", self.on_itemget, owner)

    self:StartUpdating()
end)

function CombatHud:OnUpdate(dt)
    self:Animate(dt)
    self.timer = self.timer + dt
    if self.timer >= REFRESH_PERIOD then
        self.timer = 0
        self:Refresh()
    end
end

-- Items going into a worn backpack announce themselves on the backpack.
function CombatHud:WatchBackpack()
    local backpack = self.owner.replica.inventory:GetOverflowContainer()
    local inst = backpack ~= nil and backpack.inst or nil
    if inst == self.backpack_inst then
        return
    end
    if self.backpack_inst ~= nil and self.backpack_inst:IsValid() then
        self.inst:RemoveEventCallback("itemget", self.on_itemget, self.backpack_inst)
    end
    self.backpack_inst = inst
    if inst ~= nil then
        self.inst:ListenForEvent("itemget", self.on_itemget, inst)
    end
end

-- The item on the cursor, if it was lifted out of the drawers and still is.
function CombatHud:Lifted()
    local active = Util.Real(self.owner.replica.inventory:GetActiveItem())
    if active ~= nil and active == self.own_active then
        return active
    end
    return nil
end

local function GUIDOf(item)
    return item ~= nil and tostring(item.GUID) or "-"
end

function CombatHud:Refresh(force)
    local player = self.owner
    local inventory = player.replica.inventory
    if inventory == nil then
        return
    end
    if self.on_refresh ~= nil then
        self.on_refresh()
    end
    self:WatchBackpack()
    if self.container ~= nil and not self.container:IsValid() then
        self.container = nil
    end
    local model = Categories.Build(player)
    self.locations = model.locations
    Layout.Sync(player, self:Lifted())

    local parts = { Layout.Version(), tostring(self:GetTarget() ~= nil), GUIDOf(Util.Real(inventory:GetActiveItem())) }
    for _, eslot in ipairs(Layout.GEAR_SLOTS) do
        table.insert(parts, GUIDOf(Util.Real(inventory:GetEquippedItem(eslot))))
    end
    local signature = table.concat(parts, "|")
    if force or signature ~= self.signature then
        self.signature = signature
        self:Rebuild()
    end
    self:StartFlights()
end

--------------------------------------------------------------------------
-- Opening and closing the drawers
--------------------------------------------------------------------------

function CombatHud:IsOpen()
    return self.open
end

-- The crafting menu's open/close sounds, played only when the drawers actually
-- change state (a chest opening while they're already open stays quiet).
local function DrawerSound(opening)
    TheFrontEnd:GetSound():PlaySound(opening and "dontstarve/HUD/craft_open" or "dontstarve/HUD/craft_close")
end

function CombatHud:Open()
    if not self.open then
        DrawerSound(true)
    end
    self.open = true
    self.opened_by_container = false
end

function CombatHud:Close()
    if self.open then
        DrawerSound(false)
    end
    self.open = false
    self.opened_by_container = false
    if self.container ~= nil then
        self.container = nil
        self:Refresh(true)
    end
end

function CombatHud:ToggleOpen()
    if self.open then
        self:Close()
    else
        self:Open()
    end
end

-- A chest opened: open the drawers beside it, so Shift-click can store items.
function CombatHud:OpenFor(container)
    self.container = container
    if not self.open then
        DrawerSound(true)
        self.open = true
        self.opened_by_container = true
    end
    self:Refresh(true)
end

function CombatHud:OnContainerClosed(container)
    if self.container ~= container then
        return
    end
    self.container = nil
    if self.opened_by_container then
        self:Close()
    end
    self:Refresh(true)
end

-- The open container items go into, if it still accepts them.
function CombatHud:GetTarget()
    local container = self.container
    if container == nil or not container:IsValid() then
        return nil
    end
    local replica = container.replica.container
    if replica == nil or replica:IsReadOnlyContainer() or not replica:IsOpenedBy(self.owner) then
        return nil
    end
    return container
end

-- Opening: shoots up, overshoots a little and settles back (ease-out-back).
local function SpringOut(t)
    local u = t - 1
    return 1 + (OVERSHOOT + 1) * u * u * u + OVERSHOOT * u * u
end

-- Closing: starts quick, drops away.
local function DropIn(t)
    return t * t
end

function CombatHud:Animate(dt)
    local target = self.open and 1 or 0
    if self.progress == target then
        return
    end
    local span = 1 + STAGGER * math.max(0, #self.drawers - 1)
    if target > self.progress then
        self.progress = math.min(target, self.progress + dt / (OPEN_TIME * span))
    else
        self.progress = math.max(target, self.progress - dt / (CLOSE_TIME * span))
    end
    self:PlaceDrawers()
end

-- Raises each drawer by its share of the animation. Drawers start one after
-- another, left to right, so the row ripples open.
function CombatHud:PlaceDrawers()
    local span = 1 + STAGGER * math.max(0, #self.drawers - 1)
    local ease = self.open and SpringOut or DropIn
    local top = SLOT_Y + PLANK_TOP
    local visibility_changed = false
    for i, drawer in ipairs(self.drawers) do
        local t = math.max(0, math.min(1, self.progress * span - STAGGER * (i - 1)))
        local rise = t > 0 and ease(t) * drawer.height or 0
        drawer.widget:SetPosition(drawer.x, rise)
        local show = rise > 0
        if show ~= drawer.contents.shown then
            visibility_changed = true
            if show then
                drawer.contents:Show()
            else
                drawer.contents:Hide()
            end
        end
        top = math.max(top, SLOT_Y + PLANK_TOP + rise)
    end
    if visibility_changed then
        self:ChooseAnimSlots()
    end
end

--------------------------------------------------------------------------
-- Pickup animations: one icon per pickup, into the first visible slot
--------------------------------------------------------------------------

-- Vanilla's tiles each fly their own icon in when their stack grows, so an
-- item shown in several places got several icons. Only one tile per item may
-- animate: the first one on screen. (The hidden vanilla bar's tiles are
-- silenced in hudmode.lua.)
function CombatHud:ChooseAnimSlots()
    self.anim_slot = {}
    for _, record in ipairs(self.records) do
        local tile = record.slot.tile
        if tile ~= nil then
            local visible = record.row == 1 or record.drawer.contents.shown
            if visible and self.anim_slot[record.item] == nil then
                self.anim_slot[record.item] = record.slot
                tile.ignore_stacksize_anim = false
            else
                tile.ignore_stacksize_anim = true
            end
        end
    end
end

-- New items (a fresh slot rather than a bigger stack): fly an icon from where
-- it was picked up to its slot, once the slot exists. Not shown: no animation.
function CombatHud:StartFlights()
    local flights = self.flights
    if #flights == 0 then
        return
    end
    self.flights = {}
    for _, flight in ipairs(flights) do
        local slot = self.anim_slot[flight.item]
        local tile = slot ~= nil and slot.tile or nil
        if tile ~= nil and flight.item:IsValid() then
            tile:Hide()
            local icon = ItemTile.sSetImageFromItem(Image(), flight.item)
            icon:MoveTo(Vector3(TheSim:GetScreenPos(flight.src_pos:Get())), slot:GetWorldPosition(), FLY_TIME, function()
                if tile.inst:IsValid() then
                    tile:Show()
                    tile:ScaleTo(2, 1, 0.25)
                end
                icon:Kill()
            end)
        end
    end
end

--------------------------------------------------------------------------
-- Moving items
--------------------------------------------------------------------------

local function SourceOf(player, entry)
    local inventory = player.replica.inventory
    if entry.where == "inv" then
        return inventory
    elseif entry.where == "pack" then
        return inventory:GetOverflowContainer()
    end
    return nil
end

-- Was this item (or, for half a stack, its prefab) in the inventory as last
-- seen? Guards against a stale lift marking an outside item as ours.
function CombatHud:WasCarried(item)
    if self.locations[item] ~= nil then
        return true
    end
    for carried in pairs(self.locations) do
        if carried.prefab == item.prefab then
            return true
        end
    end
    return false
end

-- Pick the item up onto the cursor, exactly like vanilla's slot click.
function CombatHud:PickUp(item, half)
    local player = self.owner
    local inventory = player.replica.inventory
    local entry = Categories.Build(player).locations[item]
    if entry == nil then
        return
    end
    self.lifting = GetTime()
    self.lifting_equip = entry.where == "equip"
    if entry.where == "equip" then
        inventory:TakeActiveItemFromEquipSlot(entry.slot)
        return
    end
    local source = SourceOf(player, entry)
    if source == nil then
        return
    elseif half then
        source:TakeActiveItemFromHalfOfSlot(entry.slot)
    else
        source:TakeActiveItemFromAllOfSlot(entry.slot)
    end
end

function CombatHud:Store(item)
    local target = self:GetTarget()
    local entry = target ~= nil and Categories.Build(self.owner).locations[item] or nil
    local source = entry ~= nil and SourceOf(self.owner, entry) or nil
    if source ~= nil then
        source:MoveItemFromAllOfSlot(entry.slot, target)
    end
end

-- Top up stacks the chest already has: put materials where they belong.
function CombatHud:DepositMaterials()
    local target = self:GetTarget()
    if target == nil then
        return
    end
    local replica = target.replica.container
    local model = Categories.Build(self.owner)
    for item, entry in pairs(model.locations) do
        if entry.where ~= "equip" and model.materials[item.prefab] and replica:Has(item.prefab, 1) then
            self:Store(item)
        end
    end
end

function CombatHud:TakeAll()
    local target = self:GetTarget()
    if target == nil then
        return
    end
    local replica = target.replica.container
    for slot = 1, replica:GetNumSlots() do
        if replica:GetItemInSlot(slot) ~= nil then
            replica:MoveItemFromAllOfSlot(slot, self.owner)
        end
    end
end

local function NegativeSound()
    if TheFocalPoint ~= nil and TheFocalPoint.SoundEmitter ~= nil then
        TheFocalPoint.SoundEmitter:PlaySound("dontstarve/HUD/click_negative")
    end
end

local function ClickSound()
    if TheFocalPoint ~= nil and TheFocalPoint.SoundEmitter ~= nil then
        TheFocalPoint.SoundEmitter:PlaySound("dontstarve/HUD/click_object")
    end
end

local function FitsEquipSlot(item, eslot)
    local equippable = item.replica.equippable
    return equippable ~= nil and equippable:EquipSlot() == eslot
end

-- Swaps the held item into `target`'s real slot, or tops up its stack.
function CombatHud:PlaceOnto(active, target)
    local entry = self.locations[target]
    if entry == nil or entry.where == "equip" then
        return false
    end
    local container = SourceOf(self.owner, entry)
    if container == nil or not container:CanTakeItemInSlot(active, entry.slot) then
        return false
    end
    local stackable = target.replica.stackable
    if stackable ~= nil and not stackable:IsFull() and stackable:CanStackWith(active) and container:AcceptsStacks() then
        container:AddAllOfActiveItemToSlot(entry.slot)
    else
        container:SwapActiveItemWithSlot(entry.slot)
    end
    return true
end

-- Puts the held item down on a cell. cell: { section, col, index } for a
-- drawer cell, or { eslot } for a worn-gear cell. target: the item shown
-- there, if any.
function CombatHud:PutDown(cell, target)
    local player = self.owner
    local inventory = player.replica.inventory
    local active = Util.Real(inventory:GetActiveItem())
    if active == nil then
        return
    end

    -- Worn gear: equip it, swapping with what's worn.
    if cell.eslot ~= nil then
        if not FitsEquipSlot(active, cell.eslot) then
            NegativeSound()
        elseif target ~= nil then
            inventory:SwapEquipWithActiveItem()
            ClickSound()
        else
            inventory:EquipActiveItem()
            ClickSound()
        end
        return
    end

    if not Layout.Accepts(player, cell.section, cell.col, active) then
        NegativeSound()
        return
    end

    -- Lifted from the drawers: move it here, then put it back in the inventory.
    -- Taken out of an inventory slot, its own slot is free, so there's always
    -- room; taken off (worn or in hand) it needs a free slot.
    -- Dropping onto a stack it can join is not a move: fall through to
    -- PlaceOnto so the stacks combine instead of the two items swapping.
    local stackable = target ~= nil and target ~= active and target.replica.stackable or nil
    local joins = stackable ~= nil and not stackable:IsFull() and stackable:CanStackWith(active)
    if active == self.own_active and Layout.Has(active) and not joins then
        if self.own_from_equip and not Util.HasRoomFor(player, active) then
            NegativeSound()
        elseif Layout.Move(player, active, cell.section, cell.col, cell.index) then
            inventory:ReturnActiveItem()
            ClickSound()
            self:Refresh(true)
        end
        return
    end

    -- From outside (or half a stack): it'll arrive as a new item; place it here.
    if target ~= nil and target ~= active then
        if self:PlaceOnto(active, target) then
            Layout.Expect(active, cell.section, cell.col, cell.index)
            ClickSound()
        else
            NegativeSound()
        end
    elseif Util.HasRoomFor(player, active) then
        Layout.Expect(active, cell.section, cell.col, cell.index)
        inventory:ReturnActiveItem()
        ClickSound()
    else
        NegativeSound()
    end
end

--------------------------------------------------------------------------
-- Slot options
--------------------------------------------------------------------------

local function HasInventoryAction(player, item)
    local picker = player.components.playeractionpicker
    local actions = picker ~= nil and picker:GetInventoryActions(item) or nil
    return actions ~= nil and actions[1] ~= nil and actions[1] or nil
end

-- A cell showing an item, with vanilla's clicks. spec:
--   cell      where a held item put down here goes (see PutDown)
--   use       what right-click does (nil: nothing)
--   bg, in_hand
-- Shift + left: with a chest open, store the item in it (as vanilla). With
-- nothing open, move it between its use column and the generic drawer.
function CombatHud:ItemCell(item, spec)
    local player = self.owner
    local inventory = player.replica.inventory
    local entry = self.locations[item]
    local function holding()
        return inventory:GetActiveItem() ~= nil
    end

    local clicks = {}
    clicks.left = function()
        if holding() then
            self:PutDown(spec.cell, item)
        else
            self:PickUp(item, false)
        end
    end
    if item.replica.stackable ~= nil then
        clicks.ctrl_left = function()
            if holding() then
                self:PutDown(spec.cell, item)
            else
                self:PickUp(item, true)
            end
        end
    end
    clicks.right = function()
        if holding() then
            -- Vanilla: use the held item on this one (repair, refuel, ...).
            inventory:UseItemFromInvTile(item)
        elseif spec.use ~= nil then
            spec.use()
        end
    end
    clicks.shift_right = function()
        if not holding() then
            inventory:DropItemFromInvTile(item)
        end
    end
    clicks.shift_left = function()
        if holding() then
            self:PutDown(spec.cell, item)
        elseif self:GetTarget() ~= nil then
            if entry ~= nil and entry.where ~= "equip" then
                self:Store(item)
            end
        else
            self:QuickMove(item)
        end
    end
    return {
        item = item,
        bg = spec.bg,
        in_hand = spec.in_hand,
        clicks = clicks,
    }
end

-- Shift-click with nothing open: between a use column and the generic drawer.
-- Worn gear comes off into the generic drawer (if there's room for it).
function CombatHud:QuickMove(item)
    local player = self.owner
    local entry = self.locations[item]
    if entry ~= nil and entry.where == "equip" and not Layout.Has(item) then
        if Util.HasRoomFor(player, item) then
            local generic = Layout.Columns("generic")
            local shortest = 1
            for c, column in ipairs(generic) do
                if #column < #generic[shortest] then shortest = c end
            end
            Layout.Expect(item, "generic", shortest, #generic[shortest] + 1)
            Util.UseItem(player, item)
            ClickSound()
        else
            NegativeSound()
        end
        return
    end
    if Layout.QuickMove(player, item) then
        ClickSound()
        self:Refresh(true)
    else
        NegativeSound()
    end
end

-- A cell with nothing in it: a place to put the held item down.
-- spec: cell, art, empty_label, bg.
function CombatHud:EmptyCell(spec)
    local inventory = self.owner.replica.inventory
    local function put_down()
        if inventory:GetActiveItem() ~= nil then
            self:PutDown(spec.cell, nil)
        end
    end
    return {
        empty_label = spec.empty_label,
        art = spec.art,
        bg = spec.bg,
        clicks = { left = put_down, right = put_down },
    }
end

-- Right-click for any hand item: equip it, or put it away if it's in hand.
function CombatHud:EquipUse(item)
    local player = self.owner
    local in_hand = item == Util.GetHandItem(player)
    return function() HandSlot.SetHand(player, not in_hand and item or nil) end, in_hand
end

-- Right-click for anything else: its first inventory action, if it has one.
function CombatHud:ActionUse(item)
    local player = self.owner
    local action = HasInventoryAction(player, item)
    if action == nil then
        return nil
    end
    return function() Util.UseItem(player, item) end
end

-- Any item in a drawer column, by what it is.
function CombatHud:ColumnItemCell(section, item, cell, top_of_tools)
    local player = self.owner
    if Util.IsHandItem(item) then
        local use, in_hand = self:EquipUse(item)
        if top_of_tools ~= nil and not (in_hand and #Layout.Columns("tools")[top_of_tools] == 1) then
            -- The top of a tool column works like its number key.
            use = function() Layout.EquipColumn(top_of_tools) end
        end
        return self:ItemCell(item, { cell = cell, use = use, in_hand = in_hand })
    elseif section == "food" then
        local bad = QuickEat.GetFoodGroup(player, item) == "bad"
        return self:ItemCell(item, {
            cell = cell,
            use = not bad and function() QuickEat.EatItem(player, item) end or nil,
        })
    elseif item.replica.equippable ~= nil then
        return self:ItemCell(item, {
            cell = cell,
            use = function() Util.UseItem(player, item) end,
        })
    end
    return self:ItemCell(item, { cell = cell, use = self:ActionUse(item) })
end

-- A worn-gear cell (the gear drawer's top row).
function CombatHud:WornCell(eslot, item)
    local player = self.owner
    local cell = { eslot = eslot }
    if item == nil then
        return self:EmptyCell({ cell = cell, bg = EQUIP_BG[eslot] })
    end
    return self:ItemCell(item, {
        cell = cell,
        bg = EQUIP_BG[eslot],
        use = function()
            if Util.HasRoomFor(player, item) then
                Util.UseItem(player, item)
            end
        end,
    })
end

--------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------

-- One piece of plank, built like the vanilla bar's background.
-- inventory_corner.tex is the plank's right end (ornament at the top, frame
-- down its right side); mirrored, it's the left end. The plain middle has a
-- rim along its top. Below the rims both are plain all the way down.
-- yscale < 0 flips the piece upside down (rims and ornaments at its bottom).
--
-- Sizes are set explicitly: both textures are 63x255 in the atlas, not 64x256,
-- so scaling them by width/64 left the stretched middle ~20 units short, and a
-- gap opened in the border where it meets each corner (above the first and
-- last slots).
local function PlankPiece(parent, width, y, yscale)
    local middle = parent:AddChild(Image(HUD_ATLAS, "inventory_filler.tex"))
    middle:SetSize(width - 2 * PIECE_W + 2 * PIECE_OVERLAP, PIECE_H)
    middle:SetScale(1, yscale, 1)
    middle:SetPosition(0, y)
    local left = parent:AddChild(Image(HUD_ATLAS, "inventory_corner.tex"))
    left:SetSize(PIECE_W, PIECE_H)
    left:SetScale(-1, yscale, 1)
    left:SetPosition(-width / 2 + PIECE_W / 2, y)
    local right = parent:AddChild(Image(HUD_ATLAS, "inventory_corner.tex"))
    right:SetSize(PIECE_W, PIECE_H)
    right:SetScale(1, yscale, 1)
    right:SetPosition(width / 2 - PIECE_W / 2, y)
end

-- One plank tall enough to reach below the screen edge even when the drawer
-- is fully open (and overshooting). A taller drawer gets an extension under
-- the top piece: the same art flipped upside down and stretched, so its rim
-- and corner ornaments sit at the very bottom, below the screen. The top piece
-- goes in last and covers the join, so only one top border ever shows.
local function Plank(parent, width, rise)
    local top_y = SLOT_Y + PLANK_TOP - PIECE_H / 2
    local top_bottom = top_y - PIECE_H / 2
    local bottom_needed = SCREEN_Y - rise * 1.2 - 20
    if top_bottom > bottom_needed then
        -- Ornaments take the outer ~15% of the flipped piece; keep them off-screen too.
        local from = top_bottom + PIECE_JOIN
        local length = (from - bottom_needed) / 0.8
        PlankPiece(parent, width, from - length / 2, -length / PIECE_H)
    end
    PlankPiece(parent, width, top_y, 1)
end

local function SectionWidth(columns)
    columns = math.max(1, columns)
    return columns * W + (columns - 1) * SEP
end

-- A divider between two sections, drawn over the plank in this order:
--   notch_background  patch for the panel behind it (left out of the atlas
--                     when it's identical to the plain panel)
--   spacer_tile       a line down the lane, tiled from under the border to
--                     below the screen edge however far the drawer opens
--   notch_border      patch for the border, carrying the ornament
-- The patches only contain pixels that differ from the plain panel, so the
-- game's own border and panel show everywhere else. Each piece is skipped if
-- the art isn't loaded.
local function AddDivider(parent, x, rise)
    if ART_ATLAS == nil then
        return
    end
    local function has(tex)
        return TheSim:AtlasContains(ART_ATLAS, tex)
    end
    local top = SLOT_Y + PLANK_TOP
    local function patch(tex)
        local image = parent:AddChild(Image(ART_ATLAS, tex))
        image:SetSize(NOTCH_W, NOTCH_H)
        image:SetClickable(false)
        image:SetPosition(x, top - NOTCH_H / 2)
    end
    if has("notch_background.tex") then
        patch("notch_background.tex")
    end
    if has("spacer_tile.tex") then
        local y = top - BORDER
        local bottom = SCREEN_Y - rise * 1.2 - 20      -- the plank reaches this far down
        while y > bottom do
            local tile = parent:AddChild(Image(ART_ATLAS, "spacer_tile.tex"))
            tile:SetSize(SPACER_W, SPACER_H)
            tile:SetClickable(false)
            tile:SetPosition(x, y - SPACER_H / 2)
            y = y - SPACER_H
        end
    end
    if has("notch_border.tex") then
        patch("notch_border.tex")
    end
end

function CombatHud:SectionCells(section, height)
    local player = self.owner
    local inventory = player.replica.inventory
    local lifted = self:Lifted()
    local held = Util.Real(inventory:GetActiveItem())
    local cells = {}
    for c, column in ipairs(Layout.Columns(section)) do
        local fits = held ~= nil and Layout.Accepts(player, section, c, held)
        for row = 1, height do
            local cell = { col = c, row = row }
            local index = row
            if section == "gear" then
                index = row - 1
            end
            if section == "gear" and row == 1 then
                local eslot = Layout.GEAR_SLOTS[c]
                cell.item = Util.Real(inventory:GetEquippedItem(eslot))
                cell.opts = self:WornCell(eslot, cell.item)
            else
                local item = column[index]
                local target = { section = section, col = c, index = index }
                if item ~= nil and item ~= lifted then
                    cell.item = item
                    cell.opts = self:ColumnItemCell(section, item, target,
                        section == "tools" and row == 1 and c or nil)
                else
                    -- Empty, or the lifted item's own cell (put it back here).
                    local spec = { cell = target }
                    if row == 1 and section == "tools" then
                        local key = ToolTypes.GetSlots()[c]
                        spec.art = Art(key ~= nil and TOOL_ART[key] or (key == nil and GENERIC_TOOL_ART or nil))
                        spec.empty_label = spec.art == nil and Layout.ToolColumnLabel(c) or nil
                    elseif row == 1 and section == "food" then
                        local key, label = Layout.FoodColumn(c)
                        spec.art = Art(FOOD_ART[key])
                        spec.empty_label = spec.art == nil and label or nil
                    end
                    if index > #column then
                        -- Past the end: dropping here adds to the bottom.
                        target.index = #column + 1
                    end
                    cell.opts = self:EmptyCell(spec)
                end
            end
            if held ~= nil then
                local ok = fits
                if section == "gear" and row == 1 then
                    local equippable = held.replica.equippable
                    ok = equippable ~= nil and equippable:EquipSlot() == Layout.GEAR_SLOTS[c]
                end
                if not ok then
                    cell.opts.dim = true
                elseif cell.item == nil then
                    cell.opts.available = true
                end
            end
            table.insert(cells, cell)
        end
    end
    return cells
end

local ShowInspectButton

function CombatHud:Rebuild()
    local player = self.owner
    self.root:KillAllChildren()
    self.drawers = {}
    self.records = {}

    local height = Layout.Height()
    local specs = {}
    for _, section in ipairs(SECTIONS) do
        -- A section with no slots (no tools or no consumables) isn't drawn.
        if #Layout.Columns(section) > 0 then
            table.insert(specs, {
                section = section,
                columns = #Layout.Columns(section),
                cells = self:SectionCells(section, height),
            })
        end
    end

    -- One connected box: vanilla's end ornaments, a stretched middle, and the
    -- sections side by side with a notch in the border over the lane between them.
    -- Every section has the same height, so the whole box opens as one drawer.
    local total = 2 * BOX_MARGIN + LANE * (#specs - 1)
    for _, spec in ipairs(specs) do
        spec.width = SectionWidth(spec.columns)
        total = total + spec.width
    end
    -- Vanilla's character portrait (inspect self) at the right end, as in its bar.
    local inspect = ShowInspectButton()
    if inspect then
        total = total + LANE + W
    end
    local drawer = { x = 0, width = total, height = (height - 1) * STEP }
    drawer.widget = self.root:AddChild(Widget("drawer"))
    Plank(drawer.widget, total, drawer.height)
    local notches = drawer.widget:AddChild(Widget("notches"))
    drawer.contents = drawer.widget:AddChild(Widget("contents"))
    drawer.contents:Hide()
    local handle = drawer.widget:AddChild(Widget("top_row"))
    local x = -total / 2 + BOX_MARGIN
    for i, spec in ipairs(specs) do
        local first = x + W / 2
        for _, cell in ipairs(spec.cells) do
            cell.opts.scale = 1
            local parent = cell.row == 1 and handle or drawer.contents
            local slot = parent:AddChild(HudSlot(player, cell.opts))
            slot:SetPosition(first + (cell.col - 1) * STEP, SLOT_Y - (cell.row - 1) * STEP)
            if cell.item ~= nil then
                table.insert(self.records, { item = cell.item, slot = slot, row = cell.row, drawer = drawer })
            end
        end
        x = x + spec.width
        if i < #specs then
            AddDivider(notches, x + LANE / 2, drawer.height)
            x = x + LANE
        end
    end
    if inspect then
        self:AddInspectButton(handle, x + LANE + W / 2)
    end
    table.insert(self.drawers, drawer)
    local generic_drawer = drawer
    -- Top rows first, so a pickup flies to the top row when the item is there.
    local ordered = {}
    for _, record in ipairs(self.records) do
        if record.row == 1 then table.insert(ordered, record) end
    end
    for _, record in ipairs(self.records) do
        if record.row ~= 1 then table.insert(ordered, record) end
    end
    self.records = ordered

    if self:GetTarget() ~= nil and generic_drawer ~= nil then
        self:AddChestButtons(generic_drawer)
    end
    self:PlaceDrawers()
    self:ChooseAnimSlots()
end

-- Vanilla shows the portrait unless a controller is in use or the game mode
-- turns the avatar popup off (inventorybar.lua).
ShowInspectButton = function()
    return not TheInput:ControllerAttached() and not GetGameModeProperty("no_avatar_popup")
end

-- The character portrait vanilla puts at the right end of its bar: click it to
-- inspect yourself (your character, skins and skill tree). Built as vanilla does.
function CombatHud:AddInspectButton(parent, x)
    local player = self.owner
    local prefab = player.prefab
    local image = "self_inspect_" .. prefab .. ".tex"
    local atlas = "images/avatars/self_inspect_" .. prefab .. ".xml"
    if softresolvefilepath(atlas) == nil then
        -- As inventorybar.lua's (local) HUD_CHARACTERS: Wanda's lives in hud2.
        atlas = prefab == "wanda" and "images/hud2.xml" or HUD_ATLAS
    end
    local button = parent:AddChild(OLD_TEMPLATES.IconButton(atlas, image, STRINGS.UI.HUD.INSPECT_SELF, false, false,
        function()
            if player.HUD ~= nil then
                player.HUD:InspectSelf()
            end
        end, nil, "self_inspect_mod.tex"))
    button.icon:SetScale(.7)
    button.icon:SetPosition(-4, 6)
    button:SetScale(1.25)
    button:SetPosition(x, SLOT_Y - 7)
    self.inspect_button = button
end

-- Deposit and Take all, on top of the generic drawer while a chest is open.
-- They're children of the drawer, so they ride up with it.
function CombatHud:AddChestButtons(drawer)
    local y = SLOT_Y + PLANK_TOP + 30
    local right = drawer.width / 2
    local buttons =
    {
        { "Take all", function() self:TakeAll() end, 140 },
        { "Deposit", function() self:DepositMaterials() end, 140 },
    }
    for _, spec in ipairs(buttons) do
        local label, fn, width = unpack(spec)
        local button = drawer.widget:AddChild(TEMPLATES.StandardButton(fn, label, { width, 52 }))
        button:SetTextSize(24)
        button:SetPosition(right - width / 2, y)
        right = right - width - 8
    end
end

return CombatHud
