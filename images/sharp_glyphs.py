# Filled, thickened, crisp glyphs for small sizes.
import numpy as np
from PIL import Image, ImageFilter
from fill_glyphs import dil, ero, half_width

def shapes(alpha, filled, thicken, widen, min_gap_area=500):
    """Binary mask at full resolution. thicken/widen: pixels added to each side
    of solid parts / cut-out gaps."""
    a = np.asarray(alpha).astype(np.float32) / 255
    pad = 16
    a = np.pad(a, pad)
    mask = a > 0.5
    if not filled:
        out = dil(mask, 2 * thicken + 1)
        return out[pad:-pad, pad:-pad]
    hw = max(1, half_width(mask))
    sealed = ero(dil(mask, 2 * hw + 1), 2 * hw + 1)
    free = ~sealed
    ext = np.zeros_like(free); ext[0, :] = ext[-1, :] = ext[:, 0] = ext[:, -1] = True
    ext &= free
    while True:
        grown = dil(ext, 3) & free
        if grown.sum() == ext.sum(): break
        ext = grown
    filled_region = ~ext
    band = filled_region & ~ero(filled_region, 2 * (2 * hw) + 1)
    inner_lines = mask & ~band
    solid = dil(filled_region, 2 * thicken + 1)
    if widen is None:                                # no inner details: a plain solid shape
        return drop_small(solid, min_gap_area)[pad:-pad, pad:-pad]
    gaps = dil(inner_lines, 2 * widen + 1) if widen > 0 else inner_lines
    gaps = drop_small(gaps & solid, min_gap_area)    # specks too small to read at slot size
    out = solid & ~gaps
    out = drop_small(out, min_gap_area)              # and stray solid crumbs the gaps cut off
    return out[pad:-pad, pad:-pad]

def drop_small(mask, min_area):
    """Removes connected pieces smaller than min_area pixels."""
    from collections import deque
    h, w = mask.shape
    seen = np.zeros_like(mask)
    out = mask.copy()
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        comp = []; q = deque([(y0, x0)]); seen[y0, x0] = True
        while q:
            y, x = q.popleft(); comp.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True; q.append((ny, nx))
        if len(comp) < min_area:
            ys, xs = zip(*comp); out[list(ys), list(xs)] = False
    return out

def crisp_resize(mask, size, fill):
    """Shrink a hard-edged mask to fit `fill` of a size x size cell by exact
    pixel coverage, then tighten the edges to about one pixel."""
    ys, xs = np.nonzero(mask)
    m = mask[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h, w = m.shape
    s = fill * size / max(w, h)
    tw, th = max(1, round(w * s)), max(1, round(h * s))
    SS = 8
    big = Image.fromarray((m * 255).astype(np.uint8)).resize((tw * SS, th * SS), Image.NEAREST)
    small = np.asarray(big.reduce(SS)).astype(np.float32) / 255     # exact coverage per pixel
    small = np.clip((small - 0.2) / 0.6, 0, 1)                       # ~1px edges, no halo
    cell = np.zeros((size, size), np.float32)
    oy, ox = (size - th) // 2, (size - tw) // 2
    cell[oy:oy + th, ox:ox + tw] = small
    return cell
