# Engraved border insets

Generated with the built-in image-generation tool. The revised design uses tiny
text-free engraved symbols within the rail. The game still draws its own
`inventory_corner.tex` and `inventory_filler.tex`; the inset shoulders fade to
fully transparent at both ends, exposing the exact native border profile and
colour instead of attempting to paint a matching join. Insets render at up to
96 x 28 HUD units, with their symbols approximately 20 units high.

- `source_insets.png`: current transparent 2 x 2 engraving sheet.
- `source_badges.png`: previous parchment design, retained as source history;
  no longer packed or loaded in the game.
- `source_divider.png`: transparent fork and long wooden stem.
- `../combatinv_headers.xml` and `../combatinv_headers.tex`: game-ready atlas.
- `atlas_preview.png`: straight-alpha preview of the packed sprites.
- `layout_preview.png`: empty-slot geometry preview using the real compressed
  game textures, not a running-game screenshot. Omits item icons, portrait and
  action button artwork.

Rebuild with `python images/build_headers.py` (Pillow and numpy). The builder
crops and packs the sources, premultiplies alpha, creates box-filtered mips,
and writes a DXT5 KTEX texture. It does not require an image-generation service.

Check layout with `luajit tools/check_headers.lua`. To refresh the visual preview:

```
luajit tools/check_headers.lua images/section_headers/layout.tsv
python tools/render_headers.py
```

The preview renderer reads the installed game's `data/databundles/images.zip`.
New textures may require one full game restart; `c_reset()` then suffices for
Lua-only changes. Until the atlas is loaded, the HUD uses tiny native icons
within the rail, without text. Versioned `inset_*.tex` entries prevent an old
cached parchment texture from appearing in the new compact layout.

## Generation prompts

All calls used the built-in image-generation tool with transparency enabled.
The current inset call used `../notch_plain_border_reference.png` as its palette
reference. Earlier badge/divider calls used the approved concept image.

### Current insets

Generate production transparent game UI sprite sheet for four extremely
understated engraved wood insets in the top inventory border of Don't Starve
Together. Reference shows exact dark brown vanilla wooden rail palette. Output
four isolated little horizontal lozenge-shaped wooden inset plaques in a precise
2x2 grid, centered in quadrants, genuinely transparent background. Each inset
has a squat central roughly oval/hexagonal dark wooden area and very short
tapered horizontal shoulders that disappear into transparency on left/right.
Width to height 2:1. All four IDENTICAL shape and size. No floating illustrations
above the inset, absolutely NO TEXT, no parchment, no labels, no gems with shine,
no jewelry, no ornate scrollwork. Each contains one extremely simple small pale
brown engraved silhouette: top left crossed axe and pick; top right carrot;
bottom left simple helmet; bottom right tied bundle of three logs. Symbols
contained entirely inside inset, taking 50% of central area, bold simple
silhouettes readable at 18 pixels, no fine detail. Very low-key hand drawn black
ink outlines and desaturated dark brown wood, one muted tan carved symbol, low
contrast but readable. The silhouette is a shallow slightly widened piece of
wooden rail with flat aligned left and right ends, not a round button. Very thin
irregular black edges and minimal tiny wood grain. No bright colours, no dramatic
shadows, no decorative object extending upward. These will be rendered only
40px wide x20px high as structural portions of an existing border. Lots of
transparent margin between the four assets. Match the classic Don't Starve
handmade scratchy restrained UI style.

### Badges

Create production-ready transparent PNG sprite sheet derived faithfully from
this approved Don't Starve inventory UI concept. Reference is style and exact
design source. Output ONLY FOUR separate header badges in a strict 2 by 2 grid
on genuinely transparent background, no board, no slots, no frame or shadows
outside badges. Top left crossed axe/pickaxe above torn parchment reading
TOOLS; top right carrot and meat above torn parchment reading FOOD; bottom
left battered football helmet above parchment reading GEAR; bottom right tied
logs and twigs above parchment reading SUPPLIES. Match reference icons and
lettering very closely. Each badge is unified emblem above a wide low parchment
scroll, identical overall scale, clearly readable jagged black lettering, black
ink outlines, warm aged cream paper, restrained brown/olive colours. Each badge
fully isolated with generous transparent padding and no touching between cells,
each centered in its own quadrant. Badge art takes about 80% cell width and 80%
cell height. Make this a square sheet. Do not include any other text or
decoration. Preserve hand inked classic Don't Starve style, simplify tiny
hatching for legibility at 140px width. Labels must read exactly TOOLS FOOD GEAR
SUPPLIES.

### Divider

Production game UI sprite, transparent background. Based on the reference Don't
Starve inventory concept, extract/recreate ONLY ONE of the thin forked wooden
vertical dividers between sections. Single straight-on flat 2D narrow brown
wood divider, symmetrical Y-shaped top, two short diagonal shoulders descending
inward into a narrow vertical stem. Broad black ink outline and muted warm brown
wood with one understated thin tan highlight. Fork at very top, long straight
slim stem below; no horizontal rail, no panel, no bottom rail, no icons, no words,
no surroundings, no cast shadow. Total silhouette width at fork around 100
pixels and stem width 18 pixels, total height around 700 pixels. Stem is
consistently narrow and essentially straight all the way to its square bottom
edge so it can continue into a repeating divider line; do not taper the whole
long stem into a point. Classic Don't Starve ink-drawn wooden UI, simple at
small scale, same dark brown/black palette as reference outer border. Generous
empty transparent space all around. Only the divider, alpha transparency.
