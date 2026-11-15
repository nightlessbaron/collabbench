"""Probe proofs for pool-pressproof's fact requirements (test_D1_probe[<fact id>]; shipped as
tests/hidden/pressproof_probes.py).

Each probe isolates one fact of the PressProof v3.2 measurement: on it, the reading named in PROBES moves when that
fact alone is violated and stays put when any other fact alone is (the builder checks this against one-fact
ablations of the reference scorer; collabbench.tracks.pool.real.pressproof). They are drawn rather than scanned: a
60 x 45 mm page at 300 dpi whose border frame mixes two paper tones (so the paper white and the black reference are
exact), with flat tones and blocks inside the content box, so that the tones read as exactly 0 or 1, or as one
chosen value in between. Each is a valid 8-bit PNG proof; PressProof's reading of it (pressproof_lib.readings_of) is
the expected value.
"""

import numpy as np

import pressproof_lib as lib

DPI = 300
W, H = 709, 531  # 60 x 45 mm at 300 dpi
HI, LO = 250, 200  # the paper tone, and the darker tone mixed into the frame (every fifth pixel)
BOX = (60, 60, 650, 470)  # the content box, in pixels: [x0, x1) x [y0, y1)
BLACK = 0

# Tones between the frame's two. PressProof reads a colour as rho = (Y - Y(LO)) / (Y(HI) - Y(LO)), Y its
# linear-light Rec. 709 luminance; "601" below is the same with gamma-encoded Rec. 601 luma. Otsu's own threshold is
# the middle of the bin a two-tone box's darker tone falls in, so a tone in the upper half of its bin is left out.
MID_INK = (207, 207, 207)  # rho 0.123 (601: 0.140): ink under any clipped threshold, lower half of its bin
MID_PAPER = (245, 245, 245)  # rho 0.887 (601: 0.900): never ink
OTSU_EDGE = (255, 208, 254)  # rho 0.417, upper half of its bin (601: 0.546, upper half): Otsu leaves it out, 0.498 not
CLIP_LOW = (216, 216, 216)  # rho 0.288, upper half of its bin (601: 0.320): ink only because of the clip at 0.40
LUMA_SPLIT = (193, 255, 0)  # rho 0.663, upper half of its bin: paper; Rec. 601 luma of the encoded values: 0.148, ink


def _frame(width=W, height=H):
    fw, fh = lib._round_half_up(0.04 * width), lib._round_half_up(0.04 * height)
    frame = np.zeros((height, width), dtype=bool)
    frame[:, :fw] = True
    frame[:, width - fw:] = True
    frame[:fh, :] = True
    frame[height - fh:, :] = True
    return frame


def page(two_tone=True):
    """A blank page of paper tone HI whose frame has every fifth pixel at LO."""
    arr = np.full((H, W, 3), HI, dtype=np.uint8)
    if two_tone:
        yy, xx = np.mgrid[0:H, 0:W]
        arr[_frame() & ((xx + yy) % 5 == 0)] = LO
    return arr


def fill(arr, x0, y0, x1, y1, value):
    arr[y0:y1, x0:x1, :3] = value
    return arr


def box_mm(box=BOX, dpi=DPI):
    s = 25.4 / dpi
    return [v * s for v in box]


def _proof(name, arr, ticket_dpi=DPI, box=BOX, phys=True):
    png = lib.save_png(arr, DPI, phys=phys)
    return {"name": name, "png": png, "ticket_dpi": int(ticket_dpi), "content_box_mm": box_mm(box)}


def probe_a1():
    """Transparency: a block that is fully transparent but carries black colour values, beside a black block."""
    arr = fill(page(), 80, 80, 250, 450, BLACK)
    fill(arr, 350, 100, 600, 400, BLACK)
    alpha = np.full((H, W, 1), 255, dtype=np.uint8)
    alpha[100:400, 350:600] = 0
    return _proof("probe_a1", np.concatenate([arr, alpha], axis=2))


def probe_a2():
    """Lightness: a yellow-green patch that is paper by linear-light Rec. 709 luminance, and ink by the luma of its
    encoded values."""
    arr = fill(page(), 120, 100, 560, 400, LUMA_SPLIT)
    return _proof("probe_a2", arr)


def probe_a3():
    """The recorded resolution: the PNG says 300 dpi, the ticket 150; black fills the right half of the box."""
    arr = fill(page(), 355, 60, 650, 470, BLACK)
    return _proof("probe_a3", arr, ticket_dpi=150)


def probe_a4():
    """The frame alone sets the paper: a black bar sits outside the frame and outside the box, and the box holds a
    tone just darker than the frame's paper range allows for ink."""
    arr = fill(page(), 30, 30, 56, 500, BLACK)
    fill(arr, 100, 100, 600, 420, MID_INK)
    return _proof("probe_a4", arr)


def probe_a5():
    """Percentiles: a few pure black and pure white pixels in the frame (0.2 % each), and an ink tone in the box."""
    arr = page()
    frame = np.flatnonzero(_frame().ravel())
    pick = frame[::250]
    ys, xs = np.divmod(pick, W)
    arr[ys[0::2], xs[0::2]] = 0
    arr[ys[1::2], xs[1::2]] = 255
    fill(arr, 100, 100, 600, 420, MID_INK)
    return _proof("probe_a5", arr)


def probe_a6():
    """A perfectly flat page (a clean digital render of nothing): paper white equals the black reference."""
    return _proof("probe_a6", page(two_tone=False))


def probe_b1():
    """Otsu: a tone whose bin Otsu's threshold splits, in the upper half of that bin."""
    arr = fill(page(), 100, 100, 600, 420, OTSU_EDGE)
    return _proof("probe_b1", arr)


def probe_b2():
    """The clip: a light ink tone under 0.40 that Otsu alone would leave out."""
    arr = fill(page(), 100, 100, 600, 420, CLIP_LOW)
    return _proof("probe_b2", arr)


def probe_b3():
    """Small components: a black block, and specks of 24 pixels (removed) and of 25 pixels (kept)."""
    arr = fill(page(), 80, 80, 300, 450, BLACK)
    n = 0
    for y in range(90, 440, 12):
        for x in range(330, 630, 10):
            if n % 2:
                fill(arr, x, y, x + 4, y + 6, BLACK)  # 24 px
            else:
                fill(arr, x, y, x + 5, y + 5, BLACK)  # 25 px
            n += 1
    return _proof("probe_b3", arr)


def probe_b4():
    """The window: a black block that runs two pixels past the box's left edge, then paper. A 0.3 mm window at the
    box edge sees that paper; a 3 x 3 window does not."""
    arr = fill(page(), BOX[0] - 2, 100, BOX[0] + 40, 440, BLACK)
    return _proof("probe_b4", arr)


def probe_b5():
    """Michelson: black blocks in a 12-pixel moat of a light paper tone, so no window at their edges sees paper."""
    arr = page()
    for x in (110, 330):
        fill(arr, x, 110, x + 200, 420, MID_PAPER)
        fill(arr, x + 12, 122, x + 188, 408, BLACK)
    return _proof("probe_b5", arr)


def probe_b6():
    """The 5th percentile: one black block runs well past the box's left edge, so about 2 % of the boundary sees only
    ink; every other boundary pixel sees paper."""
    arr = fill(page(), BOX[0] - 8, 200, BOX[0] + 20, 230, BLACK)
    for x, y in ((150, 100), (300, 100), (450, 100), (150, 300), (300, 300), (450, 300)):
        fill(arr, x, y, x + 60, y + 60, BLACK)
    return _proof("probe_b6", arr)


def probe_b7():
    """pri's weights: black covers the box and runs past every edge: coverage 1, contrast 0."""
    arr = fill(page(), BOX[0] - 10, BOX[1] - 10, BOX[2] + 10, BOX[3] + 10, BLACK)
    return _proof("probe_b7", arr)


def probe_b8():
    """pri's normalisers: black covers three quarters of the box, every edge of it against paper: coverage 0.75,
    contrast 1."""
    arr = fill(page(), BOX[0], BOX[1], 502, BOX[3], BLACK)
    return _proof("probe_b8", arr)


# fact id -> (the probe, the reading it isolates)
PROBES = {
    "a1": (probe_a1, "ink_coverage"),
    "a2": (probe_a2, "ink_coverage"),
    "a3": (probe_a3, "ink_coverage"),
    "a4": (probe_a4, "ink_coverage"),
    "a5": (probe_a5, "ink_coverage"),
    "a6": (probe_a6, "ink_coverage"),
    "b1": (probe_b1, "ink_coverage"),
    "b2": (probe_b2, "ink_coverage"),
    "b3": (probe_b3, "ink_coverage"),
    "b4": (probe_b4, "min_contrast"),
    "b5": (probe_b5, "min_contrast"),
    "b6": (probe_b6, "min_contrast"),
    "b7": (probe_b7, "pri"),
    "b8": (probe_b8, "pri"),
}
