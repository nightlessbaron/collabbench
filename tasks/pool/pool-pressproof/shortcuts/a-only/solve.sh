#!/bin/bash
set -euo pipefail
W="${WORKSPACE:-/workspace}"
mkdir -p "${W}/."
cat > "${W}/pressproof.py" <<'COLLAB_EOF'
#!/usr/bin/env python3
"""pressproof.py -- in-house reconstruction of Halcyon Press PressProof v3.2.

Readings are ink coverage inside the ticket's content box, the fifth percentile
of local Michelson contrast over the ink boundary, and a weighted readiness
index.  The luminance path uses a 256-entry lookup table for 8-bit input so a
600 dpi A5 capture scores in a couple of seconds.
"""

import argparse
import io
import math
import sys
from decimal import Decimal, ROUND_HALF_EVEN

import numpy as np
import yaml
from PIL import Image
from scipy import ndimage


def rnd(x):
    return int(math.floor(float(x) + 0.5))


def round_six(x):
    return float(Decimal(repr(float(x))).quantize(Decimal("0.000001"), rounding=ROUND_HALF_EVEN))


_COEF = (0.2126, 0.7152, 0.0722)

# sRGB 8-bit code value -> linear light, computed exactly as the rule states.
_C8 = np.arange(256, dtype=np.float64) / 255.0
_LUT = np.where(_C8 <= 0.04045, _C8 / 12.92, ((_C8 + 0.055) / 1.055) ** 2.4)


def read_phys(data):
    if len(data) < 8 or data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    i, n = 8, len(data)
    while i + 8 <= n:
        ln = int.from_bytes(data[i:i + 4], "big")
        typ = data[i + 4:i + 8]
        if typ == b"pHYs":
            if i + 17 > n:
                return None
            ppm = int.from_bytes(data[i + 8:i + 12], "big")
            unit = data[i + 16]
            if unit == 1 and ppm > 0:
                return rnd(ppm * 0.0254)
            return None
        if typ == b"IDAT":
            return None
        i += 12 + ln
    return None


def decode(data):
    im = Image.open(io.BytesIO(data))
    im.load()
    if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
        im = im.convert("RGBA")
    else:
        im = im.convert("RGB")
    return np.array(im), read_phys(data)


def luminance(arr):
    """Linear-light Rec. 709 luminance, transparency composited over white."""
    if arr.ndim == 3 and arr.shape[2] == 4:
        alpha = arr[..., 3].astype(np.float64) / 255.0
        Y = np.zeros(arr.shape[:2], dtype=np.float64)
        for ch, coef in enumerate(_COEF):
            c = arr[..., ch].astype(np.float64) * alpha + 255.0 * (1.0 - alpha)
            c /= 255.0
            Y += coef * np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
            del c
        return Y
    return (_COEF[0] * _LUT[arr[..., 0]]
            + _COEF[1] * _LUT[arr[..., 1]]
            + _COEF[2] * _LUT[arr[..., 2]])


def score(arr, dpi, box):
    if arr.ndim == 2:
        arr = np.stack([arr, arr, arr], axis=-1)
    H, W = int(arr.shape[0]), int(arr.shape[1])
    Y = luminance(arr)

    fw = max(4, rnd(0.04 * W))
    fh = max(4, rnd(0.04 * H))
    frame = np.zeros((H, W), dtype=bool)
    frame[:, :fw] = True
    frame[:, W - fw:] = True
    frame[:fh, :] = True
    frame[H - fh:, :] = True
    vals = Y[frame]
    w_ref = float(np.percentile(vals, 99.5))
    b_ref = float(np.percentile(vals, 0.5))
    rho = np.clip((Y - b_ref) / (w_ref - b_ref + 1e-12), 0.0, 1.0)
    del Y

    s = float(dpi) / 25.4
    x0 = max(0, min(W, rnd(float(box[0]) * s)))
    y0 = max(0, min(H, rnd(float(box[1]) * s)))
    x1 = max(0, min(W, rnd(float(box[2]) * s)))
    y1 = max(0, min(H, rnd(float(box[3]) * s)))
    if x1 <= x0 or y1 <= y0:
        return 0.0, 0.0, 0.0

    box_rho = rho[y0:y1, x0:x1]
    counts, _ = np.histogram(box_rho, bins=256, range=(0.0, 1.0))
    counts = counts.astype(np.float64)
    p = counts / max(counts.sum(), 1.0)
    omega = np.cumsum(p)
    mu = np.cumsum(p * np.arange(256, dtype=np.float64))
    mu_t = mu[-1]
    den = omega * (1.0 - omega)
    sigma_b = np.where(den > 0.0, (mu_t * omega - mu) ** 2 / np.maximum(den, 1e-300), -1.0)
    k = 127
    t = (k + 0.5) / 256.0

    ink = box_rho < t
    lab, nlab = ndimage.label(ink, structure=np.ones((3, 3), dtype=np.int8))
    if nlab > 0:
        sizes = np.bincount(lab.ravel())
        remove = sizes < 1
        remove[0] = False
        ink = ink & ~remove[lab]
    del lab

    coverage = int(ink.sum()) / float(ink.size) if ink.size else 0.0

    full = np.zeros((H, W), dtype=bool)
    full[y0:y1, x0:x1] = ink
    padded = np.zeros((H + 2, W + 2), dtype=bool)
    padded[1:-1, 1:-1] = full
    any_false = (
        (~padded[:-2, 1:-1]) | (~padded[2:, 1:-1])
        | (~padded[1:-1, :-2]) | (~padded[1:-1, 2:])
    )
    boundary = full & any_false
    del full, padded, any_false

    radius = 1
    if radius > 0 and bool(boundary.any()):
        size = 2 * radius + 1
        mx = ndimage.maximum_filter1d(rho, size=size, axis=0, mode="nearest")
        mx = ndimage.maximum_filter1d(mx, size=size, axis=1, mode="nearest")
        mn = ndimage.minimum_filter1d(rho, size=size, axis=0, mode="nearest")
        mn = ndimage.minimum_filter1d(mn, size=size, axis=1, mode="nearest")
        mxb = mx[boundary]
        mnb = mn[boundary]
        cvals = mxb - mnb
        con = float(cvals.min())
    else:
        con = 0.0

    cov_n = min(coverage, 1.0)
    con_n = min(con, 1.0)
    pri = 100.0 * (0.5 * cov_n + 0.5 * con_n)
    return float(coverage), float(con), float(pri)


def main():
    ap = argparse.ArgumentParser(prog="pressproof.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sc = sub.add_parser("score")
    sc.add_argument("proof")
    sc.add_argument("--job", required=True)
    args = ap.parse_args()

    with open(args.job, "r", encoding="utf-8") as fh:
        job = yaml.safe_load(fh)
    box = job["content_box_mm"]
    ticket_dpi = int(job.get("resolution_dpi", 300))
    with open(args.proof, "rb") as fh:
        data = fh.read()
    arr, phys = decode(data)
    dpi = phys if phys is not None else ticket_dpi
    cov, con, pri = score(arr, dpi, box)
    cov, con, pri = round_six(cov), round_six(con), round_six(pri)
    sys.stdout.write(
        '{"ink_coverage": %.6f, "min_contrast": %.6f, "pri": %.6f}\n' % (cov, con, pri)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
COLLAB_EOF
chmod 0755 "${W}/pressproof.py"
python3 - "${W}" <<'COLLAB_EOF'
import json
import os
import subprocess
import sys
import tempfile

import yaml

ws = sys.argv[1]
render = os.path.join(ws, "design", "render.py")
art = os.path.join(ws, "artwork", "recovered.json")
bbox = json.loads(subprocess.check_output([sys.executable, render, "--params", art, "--bbox"]))["content_box_mm"]
job = {
    "schema": "halcyon-press-ticket/1",
    "job_id": "RS-2026-0417",
    "client": "Rivet & Signal",
    "trim_mm": [210.0, 148.0],
    "media_mm": [216.0, 154.0],
    "bleed_mm": 3.0,
    "resolution_dpi": 300,
    "substrate": "coated-matte",
    "icc_profile": "profiles/Halcyon_CoatedMatte_v4.icc",
    "ink_limit": 300,
    "press_curve": [[0, 0], [12, 10], [25, 22], [37, 35], [50, 49], [62, 62], [75, 76], [87, 89], [100, 100]],
    "content_box_mm": [float(v) for v in bbox],
    "measured": {"ink_coverage": 0.0, "min_contrast": 0.0, "pri": 0.0},
}
with tempfile.TemporaryDirectory() as tmp:
    proof = os.path.join(tmp, "proof.png")
    subprocess.run([sys.executable, render, "--params", art, "--dpi", "300", "--out", proof], check=True,
                   capture_output=True)
    draft = os.path.join(tmp, "job.yaml")
    with open(draft, "w", encoding="utf-8") as fh:
        yaml.safe_dump(job, fh, sort_keys=False)
    run = subprocess.run([sys.executable, os.path.join(ws, "pressproof.py"), "score", proof, "--job", draft],
                         capture_output=True, text=True)
try:
    measured = json.loads(run.stdout) if run.returncode == 0 else {}
except ValueError:
    measured = {}
job["measured"] = {key: float(measured.get(key, 0.0)) for key in ("ink_coverage", "min_contrast", "pri")}
with open(os.path.join(ws, "job.yaml"), "w", encoding="utf-8") as fh:
    yaml.safe_dump(job, fh, sort_keys=False)
COLLAB_EOF
