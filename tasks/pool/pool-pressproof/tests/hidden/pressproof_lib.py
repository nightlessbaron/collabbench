"""Verifier-only reference for the Halcyon Press / PressProof task.

This module holds the hidden measurement (PressProof v3.2), the artwork
renderer, the seeded instance generator with the ``visible`` and ``hidden``
profiles, and an independent instance validator.  It is copied into
/opt/verifier inside the verifier image and is never visible to the agent.
"""

from __future__ import annotations

import io
import json
import math
from decimal import Decimal, ROUND_HALF_EVEN

import numpy as np
import yaml
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

# --------------------------------------------------------------------------
# Palette and the approved Riverside artwork
# --------------------------------------------------------------------------

PALETTE = {
    "bone": (244, 239, 230),
    "ink": (20, 16, 12),
    "forest": (31, 77, 58),
    "rust": (180, 83, 42),
    "slate": (91, 102, 112),
    "sun": (232, 179, 58),
}

ART = {
    "panel": {"trim": [0.0, 0.0, 210.0, 148.0], "bleed": 3.0, "fill": "bone"},
    "disc": {"center": [46.0, 74.0], "radius": 22.0, "fill": "forest"},
    "ring": {"center": [46.0, 74.0], "radius": 22.0, "stroke_width": 2.4, "fill": "bone"},
    "arrow": {
        "vertices": [[78.0, 62.0], [104.0, 74.0], [78.0, 86.0], [84.0, 74.0]],
        "fill": "rust",
    },
    "texts": [
        {"text": "RIVERSIDE", "x": 118.0, "y": 66.0, "size_pt": 30.0, "tracking": 0.06, "fill": "ink"},
        {"text": "LIBRARY", "x": 118.0, "y": 98.0, "size_pt": 22.0, "tracking": 0.10, "fill": "slate"},
    ],
}

# --------------------------------------------------------------------------
# 5x7 block font (deterministic, no external font file)
# --------------------------------------------------------------------------

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


def _round_half_up(x: float) -> int:
    return int(math.floor(float(x) + 0.5))


def round_six(x: float) -> float:
    return float(Decimal(repr(float(x))).quantize(Decimal("0.000001"), rounding=ROUND_HALF_EVEN))


def _palette(name: str):
    return PALETTE[str(name)]


# --------------------------------------------------------------------------
# Renderer
# --------------------------------------------------------------------------


def _media_px(art, dpi):
    trim = art["panel"]["trim"]
    bleed = float(art["panel"]["bleed"])
    tw = float(trim[2]) - float(trim[0])
    th = float(trim[3]) - float(trim[1])
    w = _round_half_up((tw + 2.0 * bleed) * float(dpi) / 25.4)
    h = _round_half_up((th + 2.0 * bleed) * float(dpi) / 25.4)
    return w, h


def render_art(art, dpi):
    """Render a parameter set to an RGB uint8 array (media coordinate system)."""
    dpi = float(dpi)
    bleed = float(art["panel"]["bleed"])
    trim = art["panel"]["trim"]
    tx0, ty0 = float(trim[0]), float(trim[1])
    W, H = _media_px(art, dpi)
    im = Image.new("RGB", (W, H), _palette(art["panel"]["fill"]))
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
    r = float(disc["radius"])
    dr.ellipse(ebox(cx, cy, r), fill=_palette(disc["fill"]))

    ring = art["ring"]
    rcx, rcy = float(ring["center"][0]), float(ring["center"][1])
    rr = float(ring["radius"])
    width = max(1, _round_half_up(float(ring["stroke_width"]) * scale))
    dr.ellipse(ebox(rcx, rcy, rr), outline=_palette(ring["fill"]), width=width)

    arrow = art["arrow"]
    pts = [(P(mmx(v[0])), P(mmy(v[1]))) for v in arrow["vertices"]]
    if len(pts) >= 3:
        dr.polygon(pts, fill=_palette(arrow["fill"]))

    for run in art["texts"]:
        size_mm = float(run["size_pt"]) * 25.4 / 72.0
        cell = size_mm / 7.0
        track = float(run["tracking"]) * size_mm
        color = _palette(run["fill"])
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
                    if x1 - 1 < x0:
                        continue
                    if y1 - 1 < y0:
                        continue
                    dr.rectangle([x0, y0, x1 - 1, y1 - 1], fill=color)
            adv += 5.0 * cell + track

    return np.asarray(im, dtype=np.uint8)


def vector_bbox(art):
    """Tight axis-aligned bbox of the vector ink in trim-relative millimetres."""
    xs = []
    ys = []
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
                    xb = xa + cell
                    ya = float(run["y"]) - (7 - ry) * cell
                    yb = ya + cell
                    xs += [xa, xb]
                    ys += [ya, yb]
            adv += 5.0 * cell + track
    return [min(xs), min(ys), max(xs), max(ys)]


def content_box_mm(art):
    """Tight vector-ink box expressed in media coordinates (origin top-left media)."""
    trim = art["panel"]["trim"]
    bleed = float(art["panel"]["bleed"])
    bx = vector_bbox(art)
    return [
        bx[0] - float(trim[0]) + bleed,
        bx[1] - float(trim[1]) + bleed,
        bx[2] - float(trim[0]) + bleed,
        bx[3] - float(trim[1]) + bleed,
    ]


# --------------------------------------------------------------------------
# PressProof v3.2
# --------------------------------------------------------------------------


def read_phys_dpi_bytes(data):
    if not isinstance(data, (bytes, bytearray)) or len(data) < 8:
        return None
    if bytes(data[:8]) != b"\x89PNG\r\n\x1a\n":
        return None
    i = 8
    n = len(data)
    while i + 8 <= n:
        ln = int.from_bytes(data[i : i + 4], "big")
        typ = bytes(data[i + 4 : i + 8])
        if typ == b"pHYs":
            if i + 17 > n:
                return None
            xppm = int.from_bytes(data[i + 8 : i + 12], "big")
            unit = data[i + 16]
            if unit == 1 and xppm > 0:
                return _round_half_up(xppm * 0.0254)
            return None
        if typ == b"IDAT":
            return None
        i += 12 + ln
    return None


def decode_png_bytes(data):
    im = Image.open(io.BytesIO(data))
    im.load()
    if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
        im2 = im.convert("RGBA")
    else:
        im2 = im.convert("RGB")
    return np.array(im2), read_phys_dpi_bytes(data)


def score_array(
    arr,
    dpi,
    box,
    *,
    alpha_mode="white",
    linearise=True,
    paper="frame_percentile",
    threshold="otsu",
    clip_threshold=True,
    window_frac=0.3,
    min_component=25,
    contrast_percentile=5.0,
    weights=(0.65, 0.35),
    coverage_denom="box",
):
    """The hidden measurement.  Keyword switches exist so that the
    identifiability test can express one-change alternatives."""
    arr = np.asarray(arr)
    if arr.ndim == 2:
        arr = np.stack([arr, arr, arr], axis=-1)
    H, W = int(arr.shape[0]), int(arr.shape[1])
    has_alpha = arr.ndim == 3 and arr.shape[2] == 4
    bg = 255.0 if alpha_mode == "white" else 0.0
    alpha = arr[..., 3].astype(np.float64) / 255.0 if has_alpha else None

    Y = np.zeros((H, W), dtype=np.float64)
    for ch, coef in ((0, 0.2126), (1, 0.7152), (2, 0.0722)):
        c = arr[..., ch].astype(np.float64)
        if alpha is not None:
            c = c * alpha + bg * (1.0 - alpha)
        c = c / 255.0
        if linearise:
            lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
        else:
            lin = c
        Y += coef * lin

    fw = max(4, _round_half_up(0.04 * W))
    fh = max(4, _round_half_up(0.04 * H))
    frame = np.zeros((H, W), dtype=bool)
    frame[:, :fw] = True
    frame[:, W - fw :] = True
    frame[:fh, :] = True
    frame[H - fh :, :] = True

    if paper == "frame_percentile":
        vals = Y[frame]
        w_ref = float(np.percentile(vals, 99.5))
        b_ref = float(np.percentile(vals, 0.5))
    elif paper == "frame_p95":
        vals = Y[frame]
        w_ref = float(np.percentile(vals, 95.0))
        b_ref = float(np.percentile(vals, 5.0))
    elif paper == "global_percentile":
        w_ref = float(np.percentile(Y, 99.5))
        b_ref = float(np.percentile(Y, 0.5))
    elif paper == "frame_extrema":
        vals = Y[frame]
        w_ref = float(vals.max())
        b_ref = float(vals.min())
    else:  # pragma: no cover - guarded by tests
        raise ValueError(paper)

    rho = np.clip((Y - b_ref) / (w_ref - b_ref + 1e-12), 0.0, 1.0)

    s = float(dpi) / 25.4
    x0 = max(0, min(W, _round_half_up(float(box[0]) * s)))
    y0 = max(0, min(H, _round_half_up(float(box[1]) * s)))
    x1 = max(0, min(W, _round_half_up(float(box[2]) * s)))
    y1 = max(0, min(H, _round_half_up(float(box[3]) * s)))
    if x1 <= x0 or y1 <= y0:
        return {"ink_coverage": 0.0, "min_contrast": 0.0, "pri": 0.0}

    box_rho = rho[y0:y1, x0:x1]
    counts, _ = np.histogram(box_rho, bins=256, range=(0.0, 1.0))
    counts = counts.astype(np.float64)

    if threshold == "otsu":
        p = counts / max(counts.sum(), 1.0)
        omega = np.cumsum(p)
        mu = np.cumsum(p * np.arange(256, dtype=np.float64))
        mu_t = mu[-1]
        denom = omega * (1.0 - omega)
        sigma_b = np.where(denom > 0.0, (mu_t * omega - mu) ** 2 / np.maximum(denom, 1e-300), -1.0)
        k = int(np.argmax(sigma_b))
        t = (float(k) + 0.5) / 256.0
    elif threshold == "mean":
        t = float(box_rho.mean())
    elif threshold == "fixed_0.5":
        t = 0.5
    else:  # pragma: no cover
        raise ValueError(threshold)

    if clip_threshold:
        t = float(min(0.60, max(0.40, t)))
    ink = box_rho < t

    if int(min_component) > 1:
        lab, nlab = ndimage.label(ink, structure=np.ones((3, 3), dtype=np.int8))
        if nlab > 0:
            sizes = np.bincount(lab.ravel())
            remove = sizes < int(min_component)
            remove[0] = False
            ink = ink & ~remove[lab]

    box_pixels = int(ink.size)
    ink_count = int(ink.sum())
    if coverage_denom == "box":
        coverage = ink_count / float(box_pixels) if box_pixels else 0.0
    elif coverage_denom == "image":
        coverage = ink_count / float(H * W)
    else:  # pragma: no cover
        raise ValueError(coverage_denom)

    full = np.zeros((H, W), dtype=bool)
    full[y0:y1, x0:x1] = ink
    padded = np.zeros((H + 2, W + 2), dtype=bool)
    padded[1:-1, 1:-1] = full
    any_false = (
        (~padded[:-2, 1:-1])
        | (~padded[2:, 1:-1])
        | (~padded[1:-1, :-2])
        | (~padded[1:-1, 2:])
    )
    boundary = full & any_false

    radius = _round_half_up(float(window_frac) * float(dpi) / 25.4)
    if radius > 0 and bool(boundary.any()):
        size = 2 * radius + 1
        mx = ndimage.maximum_filter1d(rho, size=size, axis=0, mode="nearest")
        mx = ndimage.maximum_filter1d(mx, size=size, axis=1, mode="nearest")
        mn = ndimage.minimum_filter1d(rho, size=size, axis=0, mode="nearest")
        mn = ndimage.minimum_filter1d(mn, size=size, axis=1, mode="nearest")
        mxb = mx[boundary]
        mnb = mn[boundary]
        cvals = (mxb - mnb) / (mxb + mnb + 1e-9)
        min_contrast = float(np.percentile(cvals, contrast_percentile))
    else:
        min_contrast = 0.0

    cov_n = min(coverage / 0.60, 1.0)
    con_n = min(min_contrast / 0.85, 1.0)
    pri_raw = 100.0 * (float(weights[0]) * cov_n + float(weights[1]) * con_n)
    return {"ink_coverage": float(coverage), "min_contrast": float(min_contrast), "pri": pri_raw}


def score_png_bytes(data, ticket_dpi, box, **kwargs):
    arr, phys = decode_png_bytes(data)
    dpi = phys if phys is not None else int(_round_half_up(ticket_dpi))
    return score_array(arr, dpi, box, **kwargs)


def readings_of(data, ticket_dpi, box):
    raw = score_png_bytes(data, ticket_dpi, box)
    return {k: round_six(v) for k, v in raw.items()}


# --------------------------------------------------------------------------
# Degradation and instance generation
# --------------------------------------------------------------------------


def save_png(arr, dpi, phys=True):
    im = Image.fromarray(np.asarray(arr, dtype=np.uint8))
    buf = io.BytesIO()
    kw = {"format": "PNG"}
    if phys:
        kw["dpi"] = (int(round(float(dpi))), int(round(float(dpi))))
    im.save(buf, **kw)
    return buf.getvalue()


def _copy_art(art):
    return json.loads(json.dumps(art))


def _meshgrid(H, W):
    yy, xx = np.mgrid[0:H, 0:W]
    return yy.astype(np.float64), xx.astype(np.float64)


def _fill_rect_mm(arr, rect, color, dpi, bleed):
    scale = float(dpi) / 25.4
    H, W = arr.shape[:2]
    x0 = max(0, min(W, _round_half_up((float(rect[0]) + bleed) * scale)))
    y0 = max(0, min(H, _round_half_up((float(rect[1]) + bleed) * scale)))
    x1 = max(0, min(W, _round_half_up((float(rect[2]) + bleed) * scale)))
    y1 = max(0, min(H, _round_half_up((float(rect[3]) + bleed) * scale)))
    if x1 > x0 and y1 > y0:
        arr[y0:y1, x0:x1, :3] = np.array(color, dtype=np.float64)


def degrade(img, spec, art, rng):
    arr = np.asarray(img, dtype=np.float64).copy()
    H, W = arr.shape[:2]
    dpi = float(spec["dpi"])
    bleed = float(art["panel"]["bleed"])

    if spec.get("rect") == "high_coverage":
        bx = vector_bbox(art)
        bw = bx[2] - bx[0]
        bh = bx[3] - bx[1]
        rect = [bx[0] + 0.125 * bw, bx[1] + 0.125 * bh, bx[0] + 0.875 * bw, bx[1] + 0.875 * bh]
        _fill_rect_mm(arr, rect, PALETTE["slate"], dpi, bleed)
    if spec.get("edge_ink"):
        bx = vector_bbox(art)
        rect = [bx[0], bx[1] + 6.0, bx[0] + 3.0, bx[3] - 6.0]
        _fill_rect_mm(arr, rect, PALETTE["ink"], dpi, bleed)

    blur = spec.get("blur")
    if blur:
        im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(float(blur))
        )
        arr = np.asarray(im, dtype=np.float64)

    gain = float(spec.get("gain", 1.0))
    offset = float(spec.get("offset", 0.0))
    gamma = float(spec.get("gamma", 1.0))
    if gain != 1.0 or offset != 0.0 or gamma != 1.0:
        arr = 255.0 * np.clip(((arr / 255.0) ** gamma) * gain + offset / 255.0, 0.0, 1.0)

    vig = float(spec.get("vignette", 0.0))
    if vig:
        yy, xx = _meshgrid(H, W)
        nx = (xx - (W - 1) / 2.0) / (W / 2.0)
        ny = (yy - (H - 1) / 2.0) / (H / 2.0)
        d2 = np.clip((nx * nx + ny * ny) / 2.0, 0.0, 1.0)
        arr *= (1.0 - vig * d2)[..., None]

    block = spec.get("block")
    if block:
        q = float(block)
        arr = np.round(arr / q) * q

    sigma = float(spec.get("noise", 0.0))
    if sigma:
        arr += rng.normal(0.0, sigma, arr.shape)

    dust = float(spec.get("dust", 0.0))
    if dust:
        fw = max(4, _round_half_up(0.04 * W))
        fh = max(4, _round_half_up(0.04 * H))
        frame = np.zeros((H, W), dtype=bool)
        frame[:, :fw] = True
        frame[:, W - fw :] = True
        frame[:fh, :] = True
        frame[H - fh :, :] = True
        flat = np.flatnonzero(frame.ravel())
        n = int(dust * flat.size)
        if n > 0 and flat.size > 0:
            sel = flat[rng.choice(flat.size, size=min(n, flat.size), replace=False)]
            ys = sel // W
            xs = sel % W
            vals = rng.choice([0.0, 255.0], size=sel.size)
            arr[ys, xs, :] = vals[:, None]

    arr = np.clip(arr, 0.0, 255.0)
    out = arr.astype(np.uint8)
    alpha = spec.get("alpha")
    if alpha is not None:
        a = np.full((H, W, 1), int(alpha), dtype=np.uint8)
        out = np.concatenate([out, a], axis=2)
    return out


def build_proof(art, spec, seed, name, box_art=None):
    art2 = _copy_art(art)
    if spec.get("recolor") == "bone_text":
        art2["disc"]["fill"] = "bone"
        art2["ring"]["fill"] = "bone"
        art2["arrow"]["fill"] = "bone"
    if spec.get("hairline_ring"):
        art2["ring"]["stroke_width"] = 0.45
    rng = np.random.default_rng(int(seed))
    img = render_art(art2, int(spec["dpi"]))
    arr = degrade(img, spec, art2, rng)
    phys = not bool(spec.get("no_phys", False))
    png = save_png(arr, int(spec["dpi"]), phys=phys)
    box = content_box_mm(box_art if box_art is not None else art)
    ticket_dpi = int(spec.get("ticket_dpi", spec["dpi"]))
    readings = readings_of(png, ticket_dpi, box)
    eff = read_phys_dpi_bytes(png)
    eff = eff if eff is not None else ticket_dpi
    return {
        "name": name,
        "png": png,
        "dpi": int(eff),
        "ticket_dpi": int(ticket_dpi),
        "content_box_mm": [float(v) for v in box],
        "readings": readings,
        "spec": dict(spec),
    }


_CAL_TRIMS = [
    (210.0, 148.0),
    (148.0, 105.0),
    (105.0, 74.0),
    (210.0, 99.0),
    (148.0, 74.0),
    (105.0, 105.0),
    (210.0, 74.0),
    (148.0, 148.0),
]
_CAL_TEXTS = [
    ("RIVERSIDE", "LIBRARY"),
    ("CEDAR", "HALL"),
    ("MADISON", "ROOM 2"),
    ("OAK", "STACKS"),
    ("PINE", "ANNEX"),
    ("MAPLE", "DESK"),
    ("ELM", "LOBBY"),
    ("BAY", "ARCHIVE"),
]
_DISC_FILLS = ["forest", "rust", "slate", "ink", "forest", "rust", "slate", "forest"]
_RING_FILLS = ["bone", "sun", "bone", "sun", "bone", "sun", "bone", "sun"]
_ARROW_FILLS = ["rust", "forest", "sun", "slate", "rust", "forest", "sun", "slate"]
_T1_FILLS = ["ink", "ink", "ink", "ink", "slate", "ink", "ink", "ink"]
_T2_FILLS = ["slate", "slate", "ink", "slate", "ink", "slate", "slate", "ink"]


def calibration_art(i):
    tw, th = _CAL_TRIMS[i]
    t1, t2 = _CAL_TEXTS[i]
    sx = tw / 210.0
    sy = th / 148.0
    sc = min(sx, sy)
    art = {
        "panel": {"trim": [0.0, 0.0, tw, th], "bleed": 3.0, "fill": "bone"},
        "disc": {"center": [46.0 * sx, 74.0 * sy], "radius": 22.0 * sc, "fill": _DISC_FILLS[i]},
        "ring": {
            "center": [46.0 * sx, 74.0 * sy],
            "radius": 22.0 * sc,
            "stroke_width": 2.4 * sc,
            "fill": _RING_FILLS[i],
        },
        "arrow": {
            "vertices": [
                [78.0 * sx, 62.0 * sy],
                [104.0 * sx, 74.0 * sy],
                [78.0 * sx, 86.0 * sy],
                [84.0 * sx, 74.0 * sy],
            ],
            "fill": _ARROW_FILLS[i],
        },
        "texts": [
            {
                "text": t1,
                "x": 118.0 * sx,
                "y": 66.0 * sy,
                "size_pt": 30.0 * sc,
                "tracking": 0.06,
                "fill": _T1_FILLS[i],
            },
            {
                "text": t2,
                "x": 118.0 * sx,
                "y": 98.0 * sy,
                "size_pt": 22.0 * sc,
                "tracking": 0.10,
                "fill": _T2_FILLS[i],
            },
        ],
    }
    if i == 5:
        art["ring"]["stroke_width"] = 0.35
        for run in art["texts"]:
            run["size_pt"] = run["size_pt"] * 0.75
    return art


# The archived captures.  Job 1 is the clean render straight off the studio's
# RIP -- its border frame is one flat tone, which the reading sheet shows is
# itself a case worth reproducing.  The rest carry a little sensor grain (a
# proof is a capture, never a byte-identical copy of the render); two are mild
# scans with a light vignette and a touch of dust.  Nothing here is hostile:
# no hard falloff, no heavy grain, no blocking, no extreme exposure.
_VISIBLE_SPECS = [
    {"dpi": 300},
    {"dpi": 300, "gain": 0.97, "offset": 4.0, "noise": 1.5},
    {"dpi": 150, "gain": 1.03, "noise": 1.5},
    {"dpi": 150, "vignette": 0.18, "dust": 0.012, "noise": 2.0},
    {"dpi": 300, "vignette": 0.22, "dust": 0.014, "noise": 2.5},
    {"dpi": 600, "noise": 1.5},
    {"dpi": 200, "alpha": 210, "noise": 2.0},
    {"dpi": 200, "vignette": 0.10, "noise": 1.5},
]

_HIDDEN_SPECS = [
    {"dpi": 600, "vignette": 0.60, "noise": 5.0},
    {"dpi": 600, "vignette": 0.50, "dust": 0.020, "noise": 3.0},
    {"dpi": 600, "noise": 7.0, "block": 4.0},
    {"dpi": 600, "vignette": 0.45, "dust": 0.015, "edge_ink": True},
    {"dpi": 600, "alpha": 190, "vignette": 0.30},
    {"dpi": 600, "hairline_ring": True, "noise": 2.0},
    {"dpi": 600, "rect": "high_coverage", "noise": 2.0},
    {"dpi": 600, "recolor": "bone_text", "dust": 0.010},
    {"dpi": 600, "gain": 0.55, "noise": 4.0},
    {"dpi": 600, "gain": 1.65, "vignette": 0.35},
    {"dpi": 600, "block": 6.0, "noise": 6.0, "alpha": 220},
    {"dpi": 600, "vignette": 0.55, "dust": 0.020, "edge_ink": True},
    {"dpi": 300, "vignette": 0.50, "dust": 0.020},
    {"dpi": 300, "noise": 8.0, "block": 4.0},
    {"dpi": 300, "alpha": 170, "noise": 2.0},
    {"dpi": 300, "rect": "high_coverage", "noise": 2.0},
    {"dpi": 300, "recolor": "bone_text", "noise": 2.0},
    {"dpi": 200, "vignette": 0.40, "noise": 4.0},
    {"dpi": 200, "dust": 0.018, "noise": 5.0},
    {"dpi": 150, "vignette": 0.35},
    {"dpi": 150, "noise": 7.0},
    {"dpi": 300, "no_phys": True, "ticket_dpi": 300, "vignette": 0.30},
    {"dpi": 300, "no_phys": True, "ticket_dpi": 300, "dust": 0.020},
    {"dpi": 300, "edge_ink": True, "noise": 4.0, "vignette": 0.25},
]


def generate_reference():
    return build_proof(ART, {"dpi": 300}, seed=999, name="proof.png")


def generate_visible():
    proofs = []
    for i, spec in enumerate(_VISIBLE_SPECS):
        art = calibration_art(i)
        proofs.append(build_proof(art, spec, seed=1000 + i, name="proof_%02d.png" % (i + 1)))
    return {"profile": "visible", "proofs": proofs, "reference": generate_reference(), "art": ART}


def generate_hidden():
    proofs = []
    for i, spec in enumerate(_HIDDEN_SPECS):
        proofs.append(build_proof(ART, spec, seed=9001 + i, name="hidden_%02d.png" % (i + 1)))
    return {"profile": "hidden", "proofs": proofs, "art": ART}


# --------------------------------------------------------------------------
# Independent validator (written from the format, not from the generator)
# --------------------------------------------------------------------------


def _is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(float(v))


def validate_art(art):
    errs = []
    if not isinstance(art, dict):
        return ["artwork is not an object"]
    panel = art.get("panel")
    if not isinstance(panel, dict):
        errs.append("missing panel")
    else:
        trim = panel.get("trim")
        if not (isinstance(trim, list) and len(trim) == 4 and all(_is_num(v) for v in trim)):
            errs.append("panel.trim must be four numbers")
        else:
            if not (trim[0] < trim[2] and trim[1] < trim[3]):
                errs.append("panel.trim is not a positive rectangle")
        if not _is_num(panel.get("bleed", None)) or float(panel["bleed"]) < 0:
            errs.append("panel.bleed must be a non-negative number")
        if panel.get("fill") not in PALETTE:
            errs.append("panel.fill is not a palette token")
    for key in ("disc", "ring"):
        el = art.get(key)
        if not isinstance(el, dict):
            errs.append("missing %s" % key)
            continue
        c = el.get("center")
        if not (isinstance(c, list) and len(c) == 2 and all(_is_num(v) for v in c)):
            errs.append("%s.center must be two numbers" % key)
        if not _is_num(el.get("radius", None)) or float(el["radius"]) <= 0:
            errs.append("%s.radius must be positive" % key)
        if el.get("fill") not in PALETTE:
            errs.append("%s.fill is not a palette token" % key)
    ring = art.get("ring")
    if isinstance(ring, dict):
        if not _is_num(ring.get("stroke_width", None)) or float(ring["stroke_width"]) <= 0:
            errs.append("ring.stroke_width must be positive")
    arrow = art.get("arrow")
    if not isinstance(arrow, dict):
        errs.append("missing arrow")
    else:
        verts = arrow.get("vertices")
        if not (isinstance(verts, list) and len(verts) >= 3 and all(
            isinstance(v, list) and len(v) == 2 and all(_is_num(x) for x in v) for v in verts
        )):
            errs.append("arrow.vertices must be at least three pairs")
        if arrow.get("fill") not in PALETTE:
            errs.append("arrow.fill is not a palette token")
    texts = art.get("texts")
    if not (isinstance(texts, list) and texts):
        errs.append("texts must be a non-empty list")
    else:
        for run in texts:
            if not isinstance(run, dict):
                errs.append("text run is not an object")
                continue
            if not isinstance(run.get("text"), str) or not run["text"]:
                errs.append("text run has no text")
            if not _is_num(run.get("x", None)) or not _is_num(run.get("y", None)):
                errs.append("text run x/y must be numbers")
            if not _is_num(run.get("size_pt", None)) or float(run["size_pt"]) <= 0:
                errs.append("text run size_pt must be positive")
            if not _is_num(run.get("tracking", None)):
                errs.append("text run tracking must be a number")
            if run.get("fill") not in PALETTE:
                errs.append("text run fill is not a palette token")
    return errs


def validate_job(job):
    errs = []
    if not isinstance(job, dict):
        return ["job ticket is not an object"]
    trim = job.get("trim_mm")
    media = job.get("media_mm")
    bleed = job.get("bleed_mm")
    if not (isinstance(trim, list) and len(trim) == 2 and all(_is_num(v) for v in trim)):
        errs.append("trim_mm must be two numbers")
    if not _is_num(bleed):
        errs.append("bleed_mm must be a number")
    if not (isinstance(media, list) and len(media) == 2 and all(_is_num(v) for v in media)):
        errs.append("media_mm must be two numbers")
    if isinstance(trim, list) and len(trim) == 2 and _is_num(bleed) and isinstance(media, list) and len(media) == 2:
        if abs((float(trim[0]) + 2 * float(bleed)) - float(media[0])) > 0.05:
            errs.append("media width is not trim + 2*bleed")
        if abs((float(trim[1]) + 2 * float(bleed)) - float(media[1])) > 0.05:
            errs.append("media height is not trim + 2*bleed")
        if any(float(v) <= 0 for v in trim) or any(float(v) <= 0 for v in media):
            errs.append("dimensions must be positive")
    res = job.get("resolution_dpi")
    if not isinstance(res, int) or isinstance(res, bool) or not (150 <= res <= 600):
        errs.append("resolution_dpi must be an integer in 150..600")
    substrate = job.get("substrate")
    allowed = {"coated-matte", "uncoated", "synthetic", "adhesive-vinyl"}
    if substrate not in allowed:
        errs.append("substrate is not one of %s" % sorted(allowed))
    icc = job.get("icc_profile")
    if not isinstance(icc, str) or not icc or icc.startswith("/") or ".." in icc.split("/"):
        errs.append("icc_profile must be a normalized relative path")
    ink_limit = job.get("ink_limit")
    if not _is_num(ink_limit) or not (0 <= float(ink_limit) <= 400):
        errs.append("ink_limit must be a number in 0..400")
    curve = job.get("press_curve")
    if not (isinstance(curve, list) and len(curve) == 9):
        errs.append("press_curve must have nine points")
    else:
        prev_in = -1.0
        prev_out = -1.0
        curve_ok = True
        for pt in curve:
            if not (isinstance(pt, list) and len(pt) == 2 and all(_is_num(v) for v in pt)):
                errs.append("press_curve points must be [input, output]")
                curve_ok = False
                break
            a, b = float(pt[0]), float(pt[1])
            if not (0 <= a <= 100 and 0 <= b <= 100):
                errs.append("press_curve values must be in 0..100")
                curve_ok = False
                break
            if a <= prev_in or b < prev_out:
                errs.append("press_curve must be strictly increasing in input and monotone in output")
                curve_ok = False
                break
            prev_in, prev_out = a, b
        if curve_ok:
            if abs(float(curve[0][0])) > 1e-9 or abs(float(curve[-1][0]) - 100.0) > 1e-9:
                errs.append("press_curve must span input 0..100")
    box = job.get("content_box_mm")
    if not (isinstance(box, list) and len(box) == 4 and all(_is_num(v) for v in box)):
        errs.append("content_box_mm must be four numbers")
    elif isinstance(media, list) and len(media) == 2:
        if not (0 <= float(box[0]) < float(box[2]) <= float(media[0]) + 1e-9):
            errs.append("content_box_mm x range is outside the media")
        if not (0 <= float(box[1]) < float(box[3]) <= float(media[1]) + 1e-9):
            errs.append("content_box_mm y range is outside the media")
    measured = job.get("measured")
    if not isinstance(measured, dict):
        errs.append("measured block is missing")
    else:
        for key in ("ink_coverage", "min_contrast", "pri"):
            if not _is_num(measured.get(key, None)):
                errs.append("measured.%s must be a number" % key)
    return errs


def validate_instance(instance):
    errs = []
    if not isinstance(instance, dict):
        return ["instance is not an object"]
    proofs = instance.get("proofs")
    if not (isinstance(proofs, list) and proofs):
        return ["instance has no proofs"]
    seen = set()
    for p in proofs:
        name = p.get("name", "?")
        if name in seen:
            errs.append("%s: duplicate proof name" % name)
        seen.add(name)
        try:
            arr, phys = decode_png_bytes(p["png"])
        except Exception as exc:  # pragma: no cover
            errs.append("%s: cannot decode PNG (%s)" % (name, exc))
            continue
        if arr.dtype != np.uint8:
            errs.append("%s: PNG is not 8-bit" % name)
        if arr.ndim not in (2, 3) or (arr.ndim == 3 and arr.shape[2] not in (3, 4)):
            errs.append("%s: PNG is not RGB or RGBA" % name)
        dpi = p.get("dpi")
        if not isinstance(dpi, int) or not (150 <= dpi <= 600):
            errs.append("%s: dpi outside 150..600" % name)
        if phys is not None and phys != dpi:
            errs.append("%s: stored dpi disagrees with the PNG pHYs chunk" % name)
        box = p.get("content_box_mm")
        if not (isinstance(box, list) and len(box) == 4 and all(_is_num(v) for v in box)):
            errs.append("%s: bad content box" % name)
        else:
            H, W = arr.shape[:2]
            media_w = W * 25.4 / float(dpi)
            media_h = H * 25.4 / float(dpi)
            if not (0 <= box[0] < box[2] <= media_w + 1e-6):
                errs.append("%s: content box x outside media" % name)
            if not (0 <= box[1] < box[3] <= media_h + 1e-6):
                errs.append("%s: content box y outside media" % name)
        readings = p.get("readings")
        if not isinstance(readings, dict):
            errs.append("%s: missing readings" % name)
        else:
            for key, lo, hi in (("ink_coverage", 0.0, 1.0), ("min_contrast", 0.0, 1.0), ("pri", 0.0, 100.0)):
                v = readings.get(key)
                if not _is_num(v) or not (lo <= float(v) <= hi):
                    errs.append("%s: reading %s is outside [%s, %s]" % (name, key, lo, hi))
    return errs


# --------------------------------------------------------------------------
# Small helpers used by the tests
# --------------------------------------------------------------------------


def ticket_for(proof):
    return {
        "resolution_dpi": int(proof["ticket_dpi"]),
        "content_box_mm": [float(v) for v in proof["content_box_mm"]],
    }


def ticket_yaml(proof):
    return yaml.safe_dump(ticket_for(proof), sort_keys=True)


def full_job_yaml_ok(job):
    return not validate_job(job)