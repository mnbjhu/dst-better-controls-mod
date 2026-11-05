# Extracts the ink drawing from each generated tile (dropping its frame and
# parchment) and packs the drawings, white with alpha, into a DST atlas.
# The game tints them to match vanilla's silhouette slots.
# Also packs slot_blank.tex: vanilla's grey-green gear slot with no silhouette,
# rebuilt from the game's hand/body/head slots (images/slot_blank.png).
# Usage: python3 -I build_glyphs.py <sheet.png> <mod dir> [preview dir]
import sys, io, struct, os
import numpy as np
from PIL import Image, ImageFilter

sheet_path, mod_dir = sys.argv[1], sys.argv[2]
preview_dir = sys.argv[3] if len(sys.argv) > 3 else None
NAMES = ['weapon', 'ranged', 'staff', 'axe', 'tool', 'health', 'sanity', 'hunger']
# Drawings are made small-size friendly at full resolution (sharp_glyphs.py):
# filled solid like vanilla's silhouettes, solid parts thickened, cut-out gaps
# widened, specks dropped. Then they're shrunk by exact pixel coverage to the
# size they appear on screen (57px slots at 2560x1440, HUD size 5), so the game
# draws them 1:1 with crisp ~1px edges.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sharp_glyphs import shapes, crisp_resize
CELL = 57
# per drawing: filled? and how much to widen its cut-out gaps (None = no gaps)
STYLE = {'ranged': (False, 0), 'weapon': (True, None)}
DEFAULT_STYLE = (True, 2)
GUTTER = 4                        # empty pixels between cells, so smaller copies don't bleed
FILL = 0.80                       # drawing's longest side, as a share of the slot
ATLAS_W, ATLAS_H = 512, 256
BLANK = os.path.join(mod_dir, 'images', 'slot_blank.png')

sheet = np.asarray(Image.open(sheet_path).convert('RGB')).astype(np.float32)
H, W, _ = sheet.shape
lum_sheet = sheet @ np.array([0.299, 0.587, 0.114], dtype=np.float32)

def runs(v, th):
    out, start = [], None
    for i, c in enumerate(v):
        if c > th and start is None: start = i
        if c <= th and start is not None: out.append((start, i)); start = None
    if start is not None: out.append((start, len(v)))
    return out

bright = lum_sheet > 40
bands = [b for b in runs(bright.sum(axis=1), 10) if b[1] - b[0] > 50]
boxes = []
for (y0, y1) in bands:
    for (x0, x1) in runs(bright[y0:y1].sum(axis=0), 6):
        if x1 - x0 > 50:
            boxes.append((x0, y0, x1, y1))
assert len(boxes) == len(NAMES), f'found {len(boxes)} tiles'

def inner_rect(lum):
    # Walk out from the centre along each axis until the frame's dark line.
    h, w = lum.shape; cy, cx = h // 2, w // 2
    def walk(line, start, step):
        i = start
        while 0 <= i + step < len(line) and line[i] > 70:
            i += step
        return i
    row, col = lum[cy], lum[:, cx]
    # sample a few rows/cols and take the tightest, so the drawing can't fool it
    lefts, rights, tops, bottoms = [], [], [], []
    for k in (-0.3, 0, 0.3):
        r = lum[int(cy + k * h * 0.5)]; c = lum[:, int(cx + k * w * 0.5)]
        lefts.append(walk(r, 4 if r[4] > 70 else cx, -1)); rights.append(walk(r, cx, 1))
        tops.append(walk(c, cy, -1)); bottoms.append(walk(c, cy, 1))
    return max(lefts), max(tops), min(rights), min(bottoms)

def glyph(box):
    x0, y0, x1, y1 = box
    lum = lum_sheet[y0:y1, x0:x1]
    h, w = lum.shape
    # Frame: scan in from the edges until the parchment starts.
    m = 0
    def edge_dark(i):
        return min(lum[i, w // 4:3 * w // 4].mean(), lum[h - 1 - i, w // 4:3 * w // 4].mean(),
                   lum[h // 4:3 * h // 4, i].mean(), lum[h // 4:3 * h // 4, w - 1 - i].mean())
    while m < min(h, w) // 4 and edge_dark(m) < 150:
        m += 1
    m += 6                                   # clear of the inner frame line
    inner = lum[m:h - m, m:w - m]
    # Parchment brightness under the ink: close away the strokes, then blur.
    img = Image.fromarray(np.clip(inner, 0, 255).astype(np.uint8))
    paper = img.filter(ImageFilter.MaxFilter(21)).filter(ImageFilter.GaussianBlur(12))
    paper = np.asarray(paper).astype(np.float32)
    ink_level = np.percentile(inner, 3)
    ink = (paper - inner) / np.maximum(paper - ink_level, 1)
    ink = np.clip((ink - 0.2) / 0.7, 0, 1)      # drop paper grain, full ink at ~90%
    # fade out near the inner edge in case any frame shading crept in
    fy = np.minimum(np.arange(ink.shape[0]), np.arange(ink.shape[0])[::-1])
    fx = np.minimum(np.arange(ink.shape[1]), np.arange(ink.shape[1])[::-1])
    edge = np.clip(np.minimum.outer(fy, fx) / 6.0, 0, 1)
    ink *= edge
    # Keep only ink near real strokes: the parchment's own blotches and
    # vignette read as faint ink and would show as a haze around the drawing.
    strong = Image.fromarray(((ink > 0.4) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7))
    near = np.asarray(strong.filter(ImageFilter.GaussianBlur(1.5))).astype(np.float32) / 255
    ink *= near
    ink[ink < 0.05] = 0
    # Firm the strokes up into solid shapes, like vanilla's flat silhouettes:
    # the brush texture inside a stroke reads as blur once it's this faint.
    # Edges keep a short smooth ramp, so they stay anti-aliased after resizing.
    lo, hi = 0.28, 0.52
    t = np.clip((ink - lo) / (hi - lo), 0, 1)
    ink = t * t * (3 - 2 * t)
    a = Image.fromarray((ink * 255).astype(np.uint8))
    bb = a.getbbox()
    return a.crop(bb)

atlas = Image.new('L', (ATLAS_W, ATLAS_H), 0)
elements = []
def cell_origin(i):
    return (i % 4) * (CELL + GUTTER), (i // 4) * (CELL + GUTTER)

for i, (name, box) in enumerate(zip(NAMES, boxes)):
    a = glyph(box)
    if preview_dir:
        a.save(os.path.join(preview_dir, f'full_{name}.png'))
    filled, widen = STYLE.get(name, DEFAULT_STYLE)
    mask = shapes(a, filled=filled, thicken=3, widen=widen)
    a = Image.fromarray((crisp_resize(mask, CELL, FILL) * 255).astype(np.uint8))
    cx, cy = cell_origin(i)
    atlas.paste(a, (cx + (CELL - a.width) // 2, cy + (CELL - a.height) // 2))
    u1, u2 = cx / ATLAS_W, (cx + CELL) / ATLAS_W
    v1, v2 = 1 - (cy + CELL) / ATLAS_H, 1 - cy / ATLAS_H
    elements.append((name + '.tex', u1, u2, v1, v2))
    if preview_dir:
        a.save(os.path.join(preview_dir, f'glyph_{name}.png'))

# White drawing, alpha = ink; premultiplied like vanilla (so rgb = alpha).
alpha = atlas
rgba = Image.merge('RGBA', (alpha, alpha, alpha, alpha))

# The blank gear slot, at its native size (68px), below the drawings.
blank = Image.open(BLANK).convert('RGBA')
barr = np.asarray(blank).astype(np.float32)
barr[..., :3] *= barr[..., 3:4] / 255             # premultiply
blank = Image.fromarray(barr.astype(np.uint8))
bx, by = cell_origin(8)
rgba.paste(blank, (bx, by))
u1, u2 = bx / ATLAS_W, (bx + blank.width) / ATLAS_W
v1, v2 = 1 - (by + blank.height) / ATLAS_H, 1 - by / ATLAS_H
elements.append(('slot_blank.tex', u1, u2, v1, v2))

# Section dividers, generated at 4 px per menu unit as replacement patches for
# the plain panel (see images/notch_plain_*_reference.png, cut from the panel as
# the game draws it):
#   notch_background.png  480x256 (120x64 units): the panel behind the divider
#   notch_border.png      480x256 (120x64 units): the border with the ornament
#   spacer_tile.png        48x1024 (12x256 units): a line down between sections, tiled
# Each patch keeps only the pixels that differ from the plain reference (plus a
# feathered margin), so the game's own border and panel show everywhere else and
# no seam is possible. A patch identical to its reference is left out.
# Stored at on-screen size (0.8325 px per unit), so the game draws them 1:1.
PX = 0.8325
NOTCH_A = os.path.join(mod_dir, 'images', 'notch_border.png')
NOTCH_B = os.path.join(mod_dir, 'images', 'notch_background.png')
PLAIN_A = os.path.join(mod_dir, 'images', 'notch_plain_border_reference.png')
PLAIN_B = os.path.join(mod_dir, 'images', 'notch_plain_background_reference.png')
SPACER = os.path.join(mod_dir, 'images', 'spacer_tile.png')

def changed_only(img, ref, margin=10, feather=3.0):
    # premultiplied comparison, so fully transparent pixels compare equal
    pa = img[..., :3] * img[..., 3:4] / 255; pr = ref[..., :3] * ref[..., 3:4] / 255
    diff = np.abs(pa - pr).sum(-1) + np.abs(img[..., 3] - ref[..., 3])
    mask = Image.fromarray(((diff > 12) * 255).astype(np.uint8))
    if mask.getbbox() is None:
        return None
    mask = mask.filter(ImageFilter.MaxFilter(2 * margin + 1)).filter(ImageFilter.GaussianBlur(feather))
    out = img.copy(); out[..., 3] *= np.asarray(mask).astype(np.float32) / 255
    return out

def store(name, arr, w, h, x, y):
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    im = im.resize((w * 2, h * 2), Image.LANCZOS).resize((w, h), Image.LANCZOS)
    t = np.asarray(im).astype(np.float32); t[..., :3] *= t[..., 3:4] / 255     # premultiply
    rgba.paste(Image.fromarray(np.clip(t, 0, 255).astype(np.uint8)), (x, y))
    elements.append((name, x / ATLAS_W, (x + w) / ATLAS_W, 1 - (y + h) / ATLAS_H, 1 - y / ATLAS_H))

x = bx + blank.width + GUTTER
nw, nh = round(120 * PX), round(64 * PX)
for name, path, ref in (('notch_background.tex', NOTCH_B, PLAIN_B), ('notch_border.tex', NOTCH_A, PLAIN_A)):
    if not (os.path.exists(path) and os.path.exists(ref)):
        continue
    img = np.asarray(Image.open(path).convert('RGBA')).astype(np.float32)
    patch = changed_only(img, np.asarray(Image.open(ref).convert('RGBA')).astype(np.float32))
    if patch is None:
        print(name, 'identical to the plain panel: left out')
        continue
    store(name, patch, nw, nh, x, by)
    x += nw + GUTTER
    print(name, 'patch', nw, 'x', nh)
if os.path.exists(SPACER):
    sw, sh = max(1, round(12 * PX)), round(256 * PX)
    store('spacer_tile.tex', np.asarray(Image.open(SPACER).convert('RGBA')).astype(np.float32), sw, sh, ATLAS_W - sw - GUTTER, 0)
    print('spacer', sw, 'x', sh)
if preview_dir:
    rgba.save(os.path.join(preview_dir, 'glyph_atlas.png'))

def dxt5(img):
    buf = io.BytesIO(); img.save(buf, format='DDS', pixel_format='DXT5')
    d = buf.getvalue(); assert d[:4] == b'DDS ' and d[84:88] == b'DXT5'
    return d[128:]

mips, level = [], rgba
while True:
    w, h = level.size
    pw, ph = max(4, w), max(4, h)
    padded = level if (pw, ph) == (w, h) else level.resize((pw, ph), Image.LANCZOS)
    mips.append((w, h, max(1, (w + 3) // 4) * 16, dxt5(padded.transpose(Image.FLIP_TOP_BOTTOM))))
    if w == 1 and h == 1: break
    level = level.resize((max(1, w // 2), max(1, h // 2)), Image.LANCZOS)
header = (2 << 4) | (1 << 9) | (len(mips) << 13) | (3 << 18) | (0xFFF << 20)
out = bytearray(b'KTEX') + struct.pack('<I', header)
for w, h, p, d in mips: out += struct.pack('<HHHI', w, h, p, len(d))
for w, h, p, d in mips: out += d
os.makedirs(os.path.join(mod_dir, 'images'), exist_ok=True)
open(os.path.join(mod_dir, 'images', 'combatinv_slots.tex'), 'wb').write(out)
with open(os.path.join(mod_dir, 'images', 'combatinv_slots.xml'), 'w') as f:
    f.write('<Atlas><Texture filename="combatinv_slots.tex" /><Elements>')
    for n, u1, u2, v1, v2 in elements:
        f.write(f'<Element name="{n}" u1="{u1:.9f}" u2="{u2:.9f}" v1="{v1:.9f}" v2="{v2:.9f}" />')
    f.write('</Elements></Atlas>\n')
print('glyphs:', NAMES, 'mips:', len(mips), 'bytes:', len(out))
