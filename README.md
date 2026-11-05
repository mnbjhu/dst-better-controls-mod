# Combat Inventory

A client-only Don't Starve Together mod that replaces the inventory bar with a
row of drawers (tools, food, gear and generic) and adds button-driven hand-slot
switching and quick-eat keys. Because it's client-only, it works on any server,
including ones that don't have it installed.

## Features

- **Drawers.** The inventory bar becomes one wooden panel with four sections:
  - Tools: 6 columns. Columns 1-4 are typed (weapon, ranged, staff, axe); the
    rest take the type of the first tool put in them.
  - Food: health, sanity and hunger, sorted by what your character can eat.
  - Gear: hand, body and head. The top row is what you're wearing.
  - Generic: everything else.

  Items stay where you put them, and new ones fit themselves in.
- **B** springs the drawers open to show everything you carry. **Shift + B**
  switches to the vanilla bar and back.
- **Clicks work like vanilla:** left picks up, right uses, Shift + right
  drops, and Ctrl + left picks up half a stack.
- **Shift + left-click** stores the item when a chest is open. With nothing
  open, it moves the item between its column and the generic drawer.
- **Number keys 1-6** equip the top item of each tool column. Press again to
  cycle through that column.
- **H, J and K** eat the best food for health, sanity or hunger.
- **Automatic tools:** clicking a tree, boulder, stump or grave uses the right
  tool, and attacking switches to your weapon.
- **Cane switching:** walking switches to your cane.

All keys and features can be changed in the mod's configuration, and any key can be set to Off.

## Installing

The mod is a folder named `combat-inventory` that goes in Don't Starve
Together's `mods` folder. Get a copy of this repository first, either as a zip
(unzip it) or with `git clone`, and make sure the folder is named
`combat-inventory`. Inside it you should see `modinfo.lua` directly, not
another folder.

### Windows

1. Open Steam, right-click **Don't Starve Together** in your library and
   choose **Manage → Browse local files**. This opens the game folder, usually
   `C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together`.
2. Open the `mods` folder inside it.
3. Copy the `combat-inventory` folder into `mods`, so you have
   `...\Don't Starve Together\mods\combat-inventory\modinfo.lua`.

Or from PowerShell, with the repository already cloned or unzipped:

```powershell
Copy-Item -Recurse .\combat-inventory "C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods\"
```

### Linux

1. The game folder is usually
   `~/.local/share/Steam/steamapps/common/Don't Starve Together`. If Steam
   is installed elsewhere, find it with Steam's **Manage → Browse local
   files** as on Windows.
2. Copy the `combat-inventory` folder into its `mods` folder:

```sh
cp -r combat-inventory ~/.local/share/Steam/steamapps/common/"Don't Starve Together"/mods/
```

Or clone it straight there, which makes updating a `git pull`:

```sh
cd ~/.local/share/Steam/steamapps/common/"Don't Starve Together"/mods/
git clone <repository-url> combat-inventory
```

### Turning it on

1. Start Don't Starve Together and open **Mods** from the main menu.
2. Under **Client Mods**, select **Combat Inventory** and enable it.
3. Optionally, click **Configure Mod** to change keys and features.
4. Click **Apply**, then join or host a game.

## Updating

Replace the folder with the new version (or `git pull` in it), then fully quit
and restart the game. A `c_reset()` in the console reloads code changes, but new
or changed art is only loaded when the game starts.

## Troubleshooting

- **The mod isn't listed:** check the folder layout. `modinfo.lua` must be
  directly inside `mods/combat-inventory/`, not in a nested folder.
- **Errors in game:** the details are in the client log:
  - Windows: `Documents\Klei\DoNotStarveTogether\client_log.txt`
  - Linux: `~/.klei/DoNotStarveTogether/client_log.txt`
