# Combat Inventory: core design

This is the short list of ideas the mod is built on. When a change is unclear,
check it against these. If a change needs to break one of them, change this
document first, on purpose.

Status: **draft**. The principles below were written down from how the mod
already behaves; the open questions at the end aren't settled yet.

## Who it's for

A Don't Starve Together player on keyboard and mouse who is tired of digging
through the inventory bar mid-fight or mid-chore. They want the right item in
hand, or the right food eaten, with one key or one click, and an inventory
where they always know where things are.

## Principles

1. **Works on any server.** The mod is client-only. Everything it does goes
   through actions a vanilla client could send, so it never needs the server to
   have it installed.
2. **Vanilla first.** Clicks, hover text, sounds and art behave the way the
   base game does. The mod adds shortcuts; it doesn't make players relearn
   anything they already know.
3. **One input, the right result.** Picking a tool, switching to a weapon, the
   cane for walking, or the best food is the mod's job, not the player's. A
   single key or click should be enough.
4. **Things stay where you put them.** Items keep their place in the drawers.
   New items find a sensible place on their own; the mod never reshuffles what
   the player arranged.
5. **Every feature can be turned off.** Each feature has an option, and with it
   off the game behaves like vanilla. Shift + B gets the vanilla bar back at any
   time.
6. **Options are for behaviour, not numbers.** A choice becomes an option when
   reasonable players want the mod to *behave* differently: on or off, or a
   different way of working. A number that only needs one good value gets a
   good default instead. This keeps the config screen short enough to read.
7. **Predictable over clever.** When the mod picks something for the player
   (a tool, a food, a slot), the rule should be one they could explain. The
   `ci_food()` and `ci_tools()` console helpers exist so the choice can be
   checked.
8. **Set things where you use them.** The drawer layout and its keys are edited
   in game, in the slot editor. Configure Mod only turns features on and off.

## The slot editor

The drawers are a list of slots the player builds, and each slot carries its
own key. It's edited in game from an Edit button on the drawers, because DST's
Configure Mod screen can only show dropdowns.

```
Tools
  Slot 1   key: 1   type: Weapon    ▲ ▼  ✕
  Slot 2   key: 2   type: Axe       ▲ ▼  ✕
  + Add slot
Consumables
  Slot 1   key: H   type: Health    ▲ ▼  ✕
  Slot 2   key: –   type: Other     ▲ ▼  ✕
  + Add slot
Generic          columns: 4   − +
Gear             (fixed: hand, body, head)
Keys
  Open drawers     B
  Hold for cane    –
```

- **Keys belong to slots.** A tool slot's key equips that column, and pressing
  it again cycles through it. A Health, Sanity or Hunger slot's key eats the
  best food for that stat. An Other slot's key eats the top item in that slot,
  the same as right-clicking it. A key left empty means no key: nothing is
  bound.
- **Tool types:** any of the tool types (weapon, ranged, staff, axe, pickaxe,
  ...) or **Any**, which takes the type of the first tool put in it. A type the
  player picks stays, even when the column is empty.
- **Consumable types:** Health, Sanity, Hunger or **Other**. Other is for food
  that doesn't belong under a stat, such as food with a downside.
- **Where new food goes**, first match wins:
  1. a consumable slot already holding the same food;
  2. food with a downside (it lowers health or sanity, like monster meat): an
     Other slot;
  3. the slot whose type matches the food's best stat;
  4. an Other slot;
  5. the generic drawer.
- **Placing food by hand:** any food the character can eat can go in any
  consumable slot, whatever its type. The type only guides where new food lands.
- **Gear** shows what's worn, so it's always there and can't be edited.
- The layout is saved to the player's profile, so it's the same in every world.
- Two slots with the same key both show a warning; the change isn't blocked.

## The pieces

| Piece | What it does | Code |
| --- | --- | --- |
| Drawers | Replace the inventory bar with tools, food, gear and generic sections that spring open on B or with a chest | `widgets/combatinv_hud.lua`, `widgets/combatinv_slot.lua`, `combatinv/layout.lua`, `combatinv/hudmode.lua` |
| Tool columns | Typed columns (weapon, ranged, staff, axe, ...) that number keys equip and cycle | `combatinv/tooltypes.lua`, `combatinv/handslot.lua` |
| Automatic tools | Clicking a tree, boulder, stump or grave uses the right tool; attacking switches to the weapon | `combatinv/tools.lua` |
| Cane switching | Walking brings out the cane; clicks still act as the item it replaced | `combatinv/travel.lua` |
| Quick-eat | One key per stat eats the food that best fills what's missing, respecting each character's diet | `combatinv/quickeat.lua`, `combatinv/fooddb.lua` |

## Open questions

These are tracked as issues with the `design` label under the **Core design**
milestone. When one is settled, the answer moves into the sections above.

- **Controllers.** The drawers are built for mouse and keyboard. Should
  controllers get the drawers, or always fall back to the vanilla bar?
- **Default keys.** H, J, K and B may clash with keys other popular mods use.
