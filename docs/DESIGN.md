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
