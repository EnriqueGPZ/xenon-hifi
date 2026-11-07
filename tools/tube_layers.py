# Makes the tube pictures of the tube preamp (Resources/Tubes/) from two
# AI pictures (kie.ai, nano-banana, 2026-11-07): crops the tube, turns the
# background to pure black, and splits the amber light into its own layer.
# Run with a Python that has Pillow and numpy, next to small_b.png and large_a.png.

import sys
from PIL import Image, ImageFilter
import numpy as np

def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

def process(src, name, out_height, bottom_at=None):
    img = Image.open(src).convert('RGB')
    a = np.asarray(img).astype(np.float32)
    h, w, _ = a.shape
    cx = w // 2
    band = a[:, cx - 160:cx + 160].max(2)
    # Find the tube: rows and columns with clearly lit glass near the centre.
    rows = np.where((band > 45).sum(1) > 3)[0]
    top, bottom = rows.min(), rows.max()
    if bottom_at: bottom = bottom_at
    mid = a[top:bottom].max(2)
    cols = np.where((mid > 45).sum(0) > 10)[0]
    cols = cols[np.abs(cols - cx) < 230]
    left, right = cols.min(), cols.max()
    pad = 24
    box = (max(0, left - pad), max(0, top - pad), min(w, right + pad), min(h, bottom + pad))
    crop = a[box[1]:box[3], box[0]:box[2]]
    # Background to pure black: the glass floats in the window (drawn with screen).
    border = np.concatenate([crop[:8].reshape(-1, 3), crop[:, :8].reshape(-1, 3), crop[:, -8:].reshape(-1, 3)])
    black = np.percentile(border.max(1), 97) + 3
    clean = np.clip((crop - black) / (255 - black) * 255, 0, 255)
    # Fade the edges so no rectangle shows.
    ch, cw, _ = clean.shape
    yy = np.minimum(np.arange(ch), ch - 1 - np.arange(ch))[:, None]
    xx = np.minimum(np.arange(cw), cw - 1 - np.arange(cw))[None, :]
    edge = smooth(0, pad, np.minimum(yy, xx))[..., None]
    clean *= edge
    r, g, b = clean[..., 0], clean[..., 1], clean[..., 2]
    # The glow: warm, saturated light (filament and its orange shine).
    warmth = np.clip(r - b, 0, 255)
    sat = warmth / np.maximum(r, 1)
    mask = smooth(0.25, 0.6, sat) * smooth(30, 120, r)
    # The white-hot core of the filament sits inside the orange: it goes too.
    near = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9))).astype(np.float32) / 255
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    core = smooth(150, 230, lum) * near
    mask = np.maximum(mask, core)
    glow = clean * mask[..., None]
    # Cold tube: the glow mostly gone, a faint ember left.
    cold = clean - glow * 0.88
    print(name, 'box', box, 'black', round(float(black), 1), 'size', (cw, ch))
    def save(arr, suffix):
        im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
        im = im.resize((round(cw * out_height / ch), out_height), Image.LANCZOS)
        im.save(f'out/{name}-{suffix}.png', optimize=True)
    save(cold, 'cold')
    save(glow, 'glow')
    save(clean, 'full')

import os
os.makedirs('out', exist_ok=True)
process('small_b.png', 'tube-small', 384)
process('large_a.png', 'tube-large', 560, bottom_at=1110)
