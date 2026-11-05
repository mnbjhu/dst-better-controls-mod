# Converts line-drawing glyphs to vanilla's convention: a solid filled shape,
# outer outline as its edge, inner lines cut out as gaps.
import sys
import numpy as np
from PIL import Image, ImageFilter

def dil(m, k): return np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(k))) > 127
def ero(m, k): return np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(k))) > 127

def half_width(mask):
    total = mask.sum(); m = mask.copy(); k = 0
    while m.sum() > 0.1 * total and k < 30:
        m = ero(m, 3); k += 1
    return k

def to_filled(alpha):
    a = np.asarray(alpha).astype(np.float32) / 255
    pad = 12
    a = np.pad(a, pad)
    mask = a > 0.5
    hw = max(1, half_width(mask))
    sealed = ero(dil(mask, 2 * hw + 1), 2 * hw + 1)        # close small breaks in the outline
    free = ~sealed
    ext = np.zeros_like(free); ext[0, :] = ext[-1, :] = ext[:, 0] = ext[:, -1] = True
    ext &= free
    while True:                                            # flood the outside
        grown = dil(ext, 3) & free
        if grown.sum() == ext.sum(): break
        ext = grown
    filled = ~ext
    band = filled & ~ero(filled, 2 * (2 * hw) + 1)        # the outline: a stroke-wide edge band
    inner_lines = mask & ~band
    out = filled & ~inner_lines
    # soft, even edges (the resize to 68px anti-aliases them further)
    img = Image.fromarray((out * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    img = img.crop((pad, pad, img.width - pad, img.height - pad))
    return img, hw

if __name__ == '__main__':
    src_dir, out_dir = sys.argv[1], sys.argv[2]
    for n in ['weapon', 'ranged', 'staff', 'axe', 'tool', 'health', 'sanity', 'hunger']:
        img, hw = to_filled(Image.open(f'{src_dir}/full_{n}.png'))
        img.save(f'{out_dir}/filled_{n}.png')
        print(n, 'stroke half-width', hw, 'px')
