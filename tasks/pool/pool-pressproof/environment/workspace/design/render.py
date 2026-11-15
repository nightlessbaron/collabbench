#!/usr/bin/env python3
"""render.py -- draw a Halcyon Press plate parameter set.

Usage:
    python render.py --params recovered.json --dpi 300 --out proof.png
    python render.py --params recovered.json --bbox
    python render.py --params recovered.json --bbox --trim

The parameter file is the JSON schema described in design/spec.md.  Coordinates
are trim-relative millimetres with the origin at the trim top-left.  The media
is the trim grown by ``panel.bleed`` millimetres on every side.
"""

import argparse
import json
import math

import numpy as np
from PIL import Image, ImageDraw

PALETTE = {
    "bone": (244, 239, 230),
    "ink": (20, 16, 12),
    "forest": (31, 77, 58),
    "rust": (180, 83, 42),
    "slate": (91, 102, 112),
    "sun": (232, 179, 58),
}

_FONT = {
    "A": ".###.|#...#|#...#|#####|#...#|#...#|#...#",
    "B": "####.|#...#|#...#|####.|#...#|#...#|####.",
    "C": ".###.|#...#|#....|#....|#....|#...#|.###.",
    "D": "####.|#...#|#...#|#...#|#...#|#...#|####.",
    "E": "#####|#....|#....|####.|#....|#....|#####",
    "F": "#####|#....|#....|####.|#....|#....|#....",
    "G": ".###.|#...#|#....|#.###|#...#|#...#|.###.",
    "H": "#...#|#...#|#...#|#####|#...#|#...#|#...#",
    "I": ".###.|..#..|..#..|..#..|..#..|..#..|.###.",
    "J": "..###|...#.|...#.|...#.|...#.|#..#.|.##..",
    "K": "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#",
    "L": "#....|#....|#....|#....|#....|#....|#####",
    "M": "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#",
    "N": "#...#|##..#|#.#.#|#.#.#|#..##|#...#|#...#",
    "O": ".###.|#...#|#...#|#...#|#...#|#...#|.###.",
    "P": "####.|#...#|#...#|####.|#....|#....|#....",
    "Q": ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#",
    "R": "####.|#...#|#...#|####.|#.#..|#..#.|#...#",
    "S": ".####|#....|#....|.###.|....#|....#|####.",
    "T": "#####|..#..|..#..|..#..|..#..|..#..|..#..",
    "U": "#...#|#...#|#...#|#...#|#...#|#...#|.###.",
    "V": "#...#|#...#|#...#|#...#|#...#|.#.#.|..#..",
    "W": "#...#|#...#|#...#|#.#.#|#.#.#|##.##|#...#",
    "X": "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
    "Y": "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..",
    "Z": "#####|....#|...#.|..#..|.#...|#....|#####",
    " ": ".....|.....|.....|.....|.....|.....|.....",
    "0": ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.",
    "1": "..#..|.##..|..#..|..#..|..#..|..#..|.###.",
    "2": ".###.|#...#|....#|...#.|..#..|.#...|#####",
    "3": "#####|...#.|..#..|...#.|....#|#...#|.###.",
    "4": "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.",
    "5": "#####|#....|####.|....#|....#|#...#|.###.",
    "6": "..##.|.#...|#....|####.|#...#|#...#|.###.",
    "7": "#####|....#|...#.|..#..|.#...|.#...|.#...",
    "8": ".###.|#...#|#...#|.###.|#...#|#...#|.###.",
    "9": ".###.|#...#|#...#|.####|....#|...#.|.##..",
}
FONT = {k: v.split("|") for k, v in _FONT.items()}


def _round_half_up(x):
    return int(math.floor(float(x) + 0.5))


def media_px(art, dpi):
    trim = art["panel"]["trim"]
    bleed = float(art["panel"]["bleed"])
    tw = float(trim[2]) - float(trim[0])
    th = float(trim[3]) - float(trim[1])
    return (
        _round_half_up((tw + 2.0 * bleed) * float(dpi) / 25.4),
        _round_half_up((th + 2.0 * bleed) * float(dpi) / 25.4),
    )


def render_art(art, dpi):
    dpi = float(dpi)
    bleed = float(art["panel"]["bleed"])
    trim = art["panel"]["trim"]
    tx0, ty0 = float(trim[0]), float(trim[1])
    W, H = media_px(art, dpi)
    im = Image.new("RGB", (W, H), PALETTE[art["panel"]["fill"]])
    dr = ImageDraw.Draw(im)
    scale = dpi / 25.4

    def mmx(x):
        return (float(x) - tx0 + bleed) * scale

    def mmy(y):
        return (float(y) - ty0 + bleed) * scale

    def P(v):
        return _round_half_up(v)

    def ebox(cx, cy, r):
        return [P(mmx(cx - r)), P(mmy(cy - r)), P(mmx(cx + r)), P(mmy(cy + r))]

    disc = art["disc"]
    cx, cy = float(disc["center"][0]), float(disc["center"][1])
    dr.ellipse(ebox(cx, cy, float(disc["radius"])), fill=PALETTE[disc["fill"]])

    ring = art["ring"]
    rcx, rcy = float(ring["center"][0]), float(ring["center"][1])
    width = max(1, _round_half_up(float(ring["stroke_width"]) * scale))
    dr.ellipse(
        ebox(rcx, rcy, float(ring["radius"])),
        outline=PALETTE[ring["fill"]],
        width=width,
    )

    arrow = art["arrow"]
    pts = [(P(mmx(v[0])), P(mmy(v[1]))) for v in arrow["vertices"]]
    if len(pts) >= 3:
        dr.polygon(pts, fill=PALETTE[arrow["fill"]])

    for run in art["texts"]:
        size_mm = float(run["size_pt"]) * 25.4 / 72.0
        cell = size_mm / 7.0
        track = float(run["tracking"]) * size_mm
        color = PALETTE[run["fill"]]
        adv = 0.0
        for ch in str(run["text"]).upper():
            bm = FONT.get(ch, FONT[" "])
            for ry, rowbits in enumerate(bm):
                for col, bit in enumerate(rowbits):
                    if bit != "#":
                        continue
                    xa = float(run["x"]) + adv + col * cell
                    ya = float(run["y"]) - (7 - ry) * cell
                    x0 = P(mmx(xa))
                    x1 = P(mmx(xa + cell))
                    y0 = P(mmy(ya))
                    y1 = P(mmy(ya + cell))
                    if x1 - 1 < x0 or y1 - 1 < y0:
                        continue
                    dr.rectangle([x0, y0, x1 - 1, y1 - 1], fill=color)
            adv += 5.0 * cell + track

    return np.asarray(im, dtype=np.uint8)


def vector_bbox(art):
    xs, ys = [], []
    disc = art["disc"]
    cx, cy = float(disc["center"][0]), float(disc["center"][1])
    r = float(disc["radius"])
    xs += [cx - r, cx + r]
    ys += [cy - r, cy + r]
    ring = art["ring"]
    rcx, rcy = float(ring["center"][0]), float(ring["center"][1])
    rr = float(ring["radius"])
    xs += [rcx - rr, rcx + rr]
    ys += [rcy - rr, rcy + rr]
    for v in art["arrow"]["vertices"]:
        xs.append(float(v[0]))
        ys.append(float(v[1]))
    for run in art["texts"]:
        size_mm = float(run["size_pt"]) * 25.4 / 72.0
        cell = size_mm / 7.0
        track = float(run["tracking"]) * size_mm
        adv = 0.0
        for ch in str(run["text"]).upper():
            bm = FONT.get(ch, FONT[" "])
            for ry, rowbits in enumerate(bm):
                for col, bit in enumerate(rowbits):
                    if bit != "#":
                        continue
                    xa = float(run["x"]) + adv + col * cell
                    ya = float(run["y"]) - (7 - ry) * cell
                    xs += [xa, xa + cell]
                    ys += [ya, ya + cell]
            adv += 5.0 * cell + track
    return [min(xs), min(ys), max(xs), max(ys)]


def content_box_mm(art):
    trim = art["panel"]["trim"]
    bleed = float(art["panel"]["bleed"])
    bx = vector_bbox(art)
    return [
        bx[0] - float(trim[0]) + bleed,
        bx[1] - float(trim[1]) + bleed,
        bx[2] - float(trim[0]) + bleed,
        bx[3] - float(trim[1]) + bleed,
    ]


def main():
    ap = argparse.ArgumentParser(description="Render a Halcyon plate parameter set.")
    ap.add_argument("--params", required=True)
    ap.add_argument("--dpi", type=int, default=300)
    ap.add_argument("--out", default=None)
    ap.add_argument("--bbox", action="store_true")
    ap.add_argument("--trim", action="store_true", help="with --bbox, report trim coordinates")
    args = ap.parse_args()

    with open(args.params, "r", encoding="utf-8") as fh:
        art = json.load(fh)

    if args.bbox:
        box = content_box_mm(art)
        if args.trim:
            bleed = float(art["panel"]["bleed"])
            box = [box[0] - bleed, box[1] - bleed, box[2] - bleed, box[3] - bleed]
        print(json.dumps({"content_box_mm": [round(v, 6) for v in box]}))
        if args.out is None:
            return

    arr = render_art(art, args.dpi)
    if args.out:
        Image.fromarray(arr).save(args.out, format="PNG", dpi=(args.dpi, args.dpi))
    print(json.dumps({"width": int(arr.shape[1]), "height": int(arr.shape[0]), "dpi": args.dpi}))


if __name__ == "__main__":
    main()