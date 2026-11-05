"""Pack generated header sprites into a premultiplied DST atlas.

Run: python images/build_headers.py
Requires Pillow with DDS/DXT5 support and numpy. Sources are kept alongside
the atlas for reproducible builds; this script only crops, sizes and packs art.
"""
from pathlib import Path
import io
import struct
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "section_headers"
SIZE = 1024
atlas = Image.new("RGBA", (SIZE, SIZE))
elements = []


def trim(image):
    box = image.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    assert box is not None, "empty sprite"
    return image.crop(box)


def store(name, image, x, y):
    atlas.paste(image, (x, y))
    elements.append((name + ".tex", x, y, image.width, image.height))


sheet = Image.open(SOURCE / "source_insets.png").convert("RGBA")
cw, ch = sheet.width // 2, sheet.height // 2
for i, name in enumerate(("tools", "food", "gear", "generic")):
    x, y = i % 2 * cw, i // 2 * ch
    sprite = trim(sheet.crop((x, y, x + cw, y + ch)))
    sprite = sprite.resize((256, 80), Image.Resampling.LANCZOS)
    # Fade ONLY the outer shoulders into the live vanilla rail beneath them.
    # The ends are completely transparent, so their vertical profile and colour
    # are exactly the game's own border at every HUD scale, not an approximation.
    pixels = np.array(sprite)
    edge = np.minimum(np.arange(256), np.arange(255, -1, -1))
    fade = np.clip((edge - 12) / 38, 0, 1)
    fade = fade * fade * (3 - 2 * fade)
    pixels[..., 3] = (pixels[..., 3] * fade[None, :]).astype(np.uint8)
    canvas = Image.fromarray(pixels)
    assert np.asarray(canvas)[..., 3][:, :12].max() == 0
    assert np.asarray(canvas)[..., 3][:, -12:].max() == 0
    store("inset_" + name, canvas, 8 + (i % 2) * 272, 8 + (i // 2) * 96)

divider = trim(Image.open(SOURCE / "source_divider.png").convert("RGBA"))
# Keep the fork's proportions. Below it, a straight part of the stem can be
# stretched vertically without stretching the fork or its ink outline.
fork_height = round(divider.width * 0.85)
fork = divider.crop((0, 0, divider.width, fork_height))
fork = fork.resize((128, 108), Image.Resampling.LANCZOS)
store("divider_fork", fork, 560, 8)
stem = trim(divider.crop((0, fork_height, divider.width, divider.height - 24)))
stem = stem.resize((32, 512), Image.Resampling.LANCZOS)
store("divider_stem", stem, 704, 8)

atlas.save(SOURCE / "atlas_preview.png")
# DST blends premultiplied RGB. Premultiply before mip generation to avoid
# bright fringes around the transparent ink outlines.
pixels = np.asarray(atlas).astype(np.float32)
pixels[..., :3] *= pixels[..., 3:4] / 255
level = Image.fromarray(pixels.astype(np.uint8))
mips = []
while True:
    w, h = level.size
    padded = level.resize((max(4, w), max(4, h)), Image.Resampling.BOX)
    buffer = io.BytesIO()
    padded.transpose(Image.Transpose.FLIP_TOP_BOTTOM).save(buffer, format="DDS", pixel_format="DXT5")
    dds = buffer.getvalue()
    assert dds[:4] == b"DDS " and dds[84:88] == b"DXT5"
    mips.append((w, h, max(1, (w + 3) // 4) * 16, dds[128:]))
    if (w, h) == (1, 1):
        break
    level = level.reduce(2)
header = (2 << 4) | (1 << 9) | (len(mips) << 13) | (3 << 18) | (0xFFF << 20)
out = bytearray(b"KTEX") + struct.pack("<I", header)
for w, h, pitch, data in mips:
    out += struct.pack("<HHHI", w, h, pitch, len(data))
for _, _, _, data in mips:
    out += data
(ROOT / "combatinv_headers.tex").write_bytes(out)

root = ET.Element("Atlas")
ET.SubElement(root, "Texture", filename="combatinv_headers.tex")
entries = ET.SubElement(root, "Elements")
for name, x, y, w, h in elements:
    ET.SubElement(entries, "Element", name=name, u1=f"{x/SIZE:.9f}",
                  u2=f"{(x+w)/SIZE:.9f}", v1=f"{1-(y+h)/SIZE:.9f}", v2=f"{1-y/SIZE:.9f}")
ET.indent(root)
ET.ElementTree(root).write(ROOT / "combatinv_headers.xml", encoding="unicode")
print(f"Packed {len(elements)} sprites; {len(mips)} mip levels; {len(out)} bytes")
