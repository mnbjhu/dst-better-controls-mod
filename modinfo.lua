name = "Combat Inventory"
description = [[Button-driven hand slot and quick-eat.

- Walking switches to your cane. Clicks and Space still do what the
  item you were holding would (dig, chop, attack...), swapping it back
  as needed.
- Clicking a tree, boulder, stump or grave uses the right tool from
  your inventory; attacking with a tool in hand switches to your weapon.
- Number keys equip your tool slots (1 = first slot). Press again to cycle.
- Quick-eat keys pick the best food for health, sanity or hunger.
- The inventory bar becomes a row of drawers: tools, food, gear and
  generic. Items stay where you put them; new ones fit themselves in.
- Tool columns 1-4 have a type (weapon, ranged, staff, axe); the rest
  take the type of the first tool put in them.
- B springs the drawers up to show everything you carry. They also open
  with chests: Shift-click to store, or use Deposit and Take all.
  With nothing open, Shift-click moves an item between its column and
  the generic drawer.
  Shift + B switches to the vanilla bar and back.
- Clicks work like vanilla: left picks up, right uses. Something picked
  up with a full inventory can be clicked onto an item to swap it out.

Client-only: works on any server.]]
author = "James"
version = "0.8.8"
api_version = 10

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false

client_only_mod = true
all_clients_require_mod = false

-- modinfo.lua runs in an empty sandbox: no string, table or ipairs.
-- Only plain syntax and operators work here.

-- Keys offered in every key option.
local key_names =
{
    "LSHIFT", "RSHIFT", "LALT", "TAB", "CAPSLOCK",
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
}

local function key_options()
    local options = {}
    for i = 1, #key_names do
        options[i] = { description = key_names[i], data = "KEY_" .. key_names[i] }
    end
    return options
end

local function key_option(name, label, default, hover)
    return { name = name, label = label, hover = hover, options = key_options(), default = default }
end

configuration_options =
{
    {
        name = "travel_mode",
        label = "Cane switching",
        hover = "Auto: walking switches to the cane. Hold key: hold the travel key instead.",
        options =
        {
            { description = "Auto", data = "auto" },
            { description = "Hold key", data = "hold" },
            { description = "Off", data = "off" },
        },
        default = "auto",
    },
    key_option("travel_key", "Travel key (hold mode)", "KEY_LSHIFT", "Only used when cane switching is set to Hold key."),
    {
        name = "weapon_keys",
        label = "Number keys",
        hover = "Each number equips that tool slot (1 = first slot). Without the grouped HUD: 1 melee, 2 ranged, 3 magic.",
        options =
        {
            { description = "On", data = true },
            { description = "Off", data = false },
        },
        default = true,
    },
    {
        name = "auto_tools",
        label = "Automatic tools",
        hover = "Clicking a tree, boulder, stump or grave uses the right tool from your inventory. Space does the same for trees and boulders.",
        options =
        {
            { description = "On", data = true },
            { description = "Off", data = false },
        },
        default = true,
    },
    {
        name = "tool_priority",
        label = "Tool priority",
        hover = "Which tool to use first when you carry several of a kind.",
        options =
        {
            { description = "Cheapest", data = "cheapest", hover = "Flint before gold. Most worn first among equals." },
            { description = "Most worn", data = "worn", hover = "Finish nearly broken tools first." },
            { description = "Best", data = "best", hover = "Gold and better tools first." },
        },
        default = "cheapest",
    },
    {
        name = "attack_swap",
        label = "Attack switches to weapon",
        hover = "Attacking while holding a tool or cane switches to your melee weapon.",
        options =
        {
            { description = "On", data = true },
            { description = "Off", data = false },
        },
        default = true,
    },
    {
        name = "grouped_hud",
        label = "Grouped inventory HUD",
        hover = "Replace the inventory bar with boxes for weapons and tools, food, usables and gear.",
        options =
        {
            { description = "On", data = true },
            { description = "Off", data = false },
        },
        default = true,
    },
    {
        name = "tool_slots",
        label = "Tool slots",
        hover = "How many tool columns. The first 4 have a type; the rest take the type of the first tool put in them.",
        options =
        {
            { description = "4", data = 4 },
            { description = "5", data = 5 },
            { description = "6", data = 6 },
            { description = "7", data = 7 },
            { description = "8", data = 8 },
        },
        default = 6,
    },
    key_option("inventory_key", "Inventory key", "KEY_B", "Opens the drawers to show everything you carry. Shift + this key: vanilla bar."),
    key_option("eat_health_key", "Quick-eat: health", "KEY_H"),
    key_option("eat_sanity_key", "Quick-eat: sanity", "KEY_J"),
    key_option("eat_hunger_key", "Quick-eat: hunger", "KEY_K"),
}
