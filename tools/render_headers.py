"""Render check_headers.lua's optional TSV using the real compressed atlases.

luajit tools/check_headers.lua images/section_headers/layout.tsv
python tools/render_headers.py
This is an empty-slot layout preview, not a screenshot of a running game.
"""
from pathlib import Path
import io
import struct
import zipfile
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "images/section_headers"
game = zipfile.ZipFile(ROOT / "../../data/databundles/images.zip")


def decode(data):
    assert data[:4] == b"KTEX"
    header, = struct.unpack_from("<I", data, 4)
    count = (header >> 13) & 31
    fmt = (header >> 4) & 31
    w, h, _, size = struct.unpack_from("<HHHI", data, 8)
    payload = data[8 + count * 10:8 + count * 10 + size]
    assert fmt in (0, 2), f"unsupported texture format {fmt}"
    fourcc = b"DXT1" if fmt == 0 else b"DXT5"
    dds = b"DDS " + struct.pack("<7I", 124, 0x81007, h, w, size, 0, 0)
    dds += bytes(44) + struct.pack("<II4s5I", 32, 4, fourcc, 0, 0, 0, 0, 0)
    dds += struct.pack("<5I", 0x1000, 0, 0, 0, 0)
    image = Image.open(io.BytesIO(dds + payload)).convert("RGBA").transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    p = np.asarray(image).astype(np.float32)
    p[..., :3] *= 255 / np.maximum(p[..., 3:4], 1)
    return Image.fromarray(np.clip(p, 0, 255).astype(np.uint8))


atlases = {}
for key, xml_path in (("images/hud.xml", "images/hud.xml"), ("headers", "images/combatinv_headers.xml")):
    local = key == "headers"
    read = (lambda path: (ROOT / path).read_bytes()) if local else game.read
    xml = ET.fromstring(read(xml_path))
    texture = str(Path(xml_path).parent / xml.find("Texture").get("filename")).replace("\\", "/")
    image = decode(read(texture))
    sprites = {}
    for el in xml.find("Elements"):
        u1, u2, v1, v2 = (float(el.get(k)) for k in ("u1", "u2", "v1", "v2"))
        sprites[el.get("name")] = image.crop((round(u1*image.width), round((1-v2)*image.height),
                                                round(u2*image.width), round((1-v1)*image.height)))
    atlases[key] = sprites

commands = []
for line in (ART / "layout.tsv").read_text().splitlines():
    atlas, tex, *numbers = line.split("\t")
    commands.append((atlas, tex, *map(float, numbers)))
left = min(x - abs(w)/2 for _, _, x, y, w, h in commands) - 24
right = max(x + abs(w)/2 for _, _, x, y, w, h in commands) + 24
top = max(y + abs(h)/2 for _, _, x, y, w, h in commands) + 24
bottom = 16/0.6
scale = 1
canvas = Image.new("RGBA", (round((right-left)*scale), round((top-bottom)*scale)), (42, 44, 33, 255))
for atlas, tex, x, y, w, h in commands:
    sprite = atlases[atlas][tex].resize((max(1, round(abs(w)*scale)), max(1, round(abs(h)*scale))), Image.Resampling.LANCZOS)
    if tex == "inv_slot.tex":
        # HudSlot dims empty slots without making them transparent.
        pixels = np.array(sprite)
        pixels[..., :3] = (pixels[..., :3] * 0.78).astype(np.uint8)
        sprite = Image.fromarray(pixels)
    if w < 0: sprite = sprite.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    if h < 0: sprite = sprite.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    canvas.alpha_composite(sprite, (round((x-abs(w)/2-left)*scale), round((top-y-abs(h)/2)*scale)))
canvas.convert("RGB").save(ART / "layout_preview.png")
print("Rendered real atlas textures and HUD geometry to", ART / "layout_preview.png")
