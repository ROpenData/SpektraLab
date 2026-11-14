#!/usr/bin/env python3
"""Generate the Spektra XD application icon.

A camera aperture (iris) drawn as six thick pinwheel chords over the
application's dark warm charcoal, with a warm amber centre dot. Pure
geometry, no text, legible from 16 px up.

Outputs icons/spektra_xd.ico plus PNG masters at 16..512 px.
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

SS = 4  # supersample factor for free antialiasing
OUT = Path(__file__).resolve().parent.parent / "icons"
OUT.mkdir(exist_ok=True)

BG_TOP = (46, 44, 41)      # warm charcoal, Theme.card family
BG_BOTTOM = (23, 22, 21)   # Theme.wellDark family
BLADE = (234, 228, 216)    # warm off-white
ACCENT = (217, 154, 78)    # warm amber, the app accent family


def build(size: int) -> Image.Image:
    big = size * SS
    # 1. Rounded-square gradient background.
    icon = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    grad = Image.new("RGB", (big, big))
    for y in range(big):
        t = y / max(1, big - 1)
        grad.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    row = grad.crop((0, 0, 1, big)).resize((big, big))
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=round(big * 0.2215), fill=255)
    icon.paste(row, (0, 0), mask)

    d = ImageDraw.Draw(icon)
    cx = cy = big * 0.5
    R = big * 0.315          # blade anchor radius
    width = round(big * 0.088)
    sweep = 148              # degrees: classic pinwheel iris opening

    # 2. Six blades: chord from angle a to a+sweep on the anchor circle.
    for i in range(6):
        a1 = math.radians(90 + i * 60)
        a2 = math.radians(90 + i * 60 + sweep)
        p1 = (cx + R * math.cos(a1), cy - R * math.sin(a1))
        p2 = (cx + R * math.cos(a2), cy - R * math.sin(a2))
        d.line([p1, p2], fill=BLADE + (255,), width=width)

    # 3. Warm centre dot inside the iris opening.
    r = big * 0.062
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ACCENT + (255,))

    return icon.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    master = build(512)
    master.save(OUT / "spektra_xd_512.png")
    for s in (256, 128, 64, 48, 32, 16):
        master.resize((s, s), Image.LANCZOS).save(OUT / f"spektra_xd_{s}.png")
    master.resize((256, 256), Image.LANCZOS).save(
        OUT / "spektra_xd.ico",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print("written:", sorted(p.name for p in OUT.iterdir()))
