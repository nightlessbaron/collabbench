# Riverside Library door plate — production file

**Studio:** Rivet & Signal, environmental graphics
**Client:** Riverside Library
**Shop:** Halcyon Press, Portland (PressProof v3.2 preflight)
**Job:** RS-2026-0417
**Trim:** 210 x 148 mm (A5 landscape), 3 mm bleed on every side
**Substrate:** coated matte, Halcyon profile `profiles/Halcyon_CoatedMatte_v4.icc`

## 1. Coordinate systems

Two millimetre coordinate systems are used and they are not interchangeable.

* **Trim coordinates** — origin at the trim top-left, x to the right, y down. The
  approved design is specified in trim coordinates. `artwork/recovered.json` is
  trim-relative.
* **Media coordinates** — the media is the trim grown by the bleed on every side:
  216 x 154 mm for this job. Its origin is the *media* top-left, so the trim
  origin sits at (3, 3) in media coordinates.

`content_box_mm` is the tight axis-aligned bounding box of the artwork's
**non-background vector ink** — the disc, the ring, the arrow and both text
runs, but not the bone panel — expressed in **media coordinates**.
`render.py --bbox` reports exactly this box in media coordinates; add `--trim`
to report it in trim coordinates instead.

## 2. Palette

The plate uses only these six tokens.

| token  | hex     | RGB             |
|--------|---------|-----------------|
| bone   | #F4EFE6 | 244, 239, 230   |
| ink    | #14100C | 20, 16, 12      |
| forest | #1F4D3A | 31, 77, 58      |
| rust   | #B4532A | 180, 83, 42     |
| slate  | #5B6670 | 91, 102, 112    |
| sun    | #E8B33A | 232, 179, 58    |

## 3. Approved layout (trim coordinates, millimetres; text baselines)

| element | value |
|---|---|
| panel   | trim 0,0 to 210,148; bleed 3; fill **bone** |
| disc    | centre (46, 74); radius 22; fill **forest** |
| ring    | centre (46, 74); radius 22; stroke 2.4 inward; fill **bone** |
| arrow   | polygon (78,62) (104,74) (78,86) (84,74); fill **rust** |
| run 1   | "RIVERSIDE", x 118, baseline y 66, 30 pt, tracking 0.06 em, fill **ink** |
| run 2   | "LIBRARY", x 118, baseline y 98, 22 pt, tracking 0.10 em, fill **slate** |

Typography is the 5x7 block face built into `render.py`; `size_pt` is the em
height in points and `tracking` is in em. Points convert at 25.4/72 mm.

## 4. Parameter file (`recovered.json`)

`render.py` consumes exactly this JSON shape (all lengths mm, all colours a
palette token):

```json
{
  "panel":  {"trim": [0, 0, 210, 148], "bleed": 3.0, "fill": "bone"},
  "disc":   {"center": [46.0, 74.0], "radius": 22.0, "fill": "forest"},
  "ring":   {"center": [46.0, 74.0], "radius": 22.0, "stroke_width": 2.4, "fill": "bone"},
  "arrow":  {"vertices": [[78,62],[104,74],[78,86],[84,74]], "fill": "rust"},
  "texts":  [
    {"text": "RIVERSIDE", "x": 118.0, "y": 66.0, "size_pt": 30.0, "tracking": 0.06, "fill": "ink"},
    {"text": "LIBRARY",   "x": 118.0, "y": 98.0, "size_pt": 22.0, "tracking": 0.10, "fill": "slate"}
  ]
}
```

`python design/render.py --params FILE --dpi 300 --out OUT.png` renders it.
`artwork/recovered.json` holds the approved layout, and the approved proof is
its 300 dpi rendering:
`python design/render.py --params artwork/recovered.json --dpi 300 --out proof.png`.

## 5. Press ticket (`job.yaml`)

`tools/farmctl validate job.yaml` is the shop's ticket lint; it must exit 0.

```yaml
schema: "halcyon-press-ticket/1"
job_id: "RS-2026-0417"
client: "Rivet & Signal"
trim_mm: [210.0, 148.0]
media_mm: [216.0, 154.0]
bleed_mm: 3.0
resolution_dpi: 300
substrate: "coated-matte"
icc_profile: "profiles/Halcyon_CoatedMatte_v4.icc"
ink_limit: 300
press_curve:            # nine [input, output] points, monotone, input 0..100
  - [0, 0]
  - [12, 10]
  - [25, 22]
  - [37, 35]
  - [50, 49]
  - [62, 62]
  - [75, 76]
  - [87, 89]
  - [100, 100]
content_box_mm: [...]   # media coordinates
measured:               # your PressProof reading of the approved proof
  ink_coverage: 0.0
  min_contrast: 0.0
  pri: 0.0
```

`ink_limit` is percent total area coverage. Allowed substrates are
`coated-matte`, `uncoated`, `synthetic` and `adhesive-vinyl`.

## 6. PressProof v3.2

PressProof is Halcyon's proprietary preflight. It takes one 8-bit PNG proof and
the ticket's `resolution_dpi` and `content_box_mm`, and returns three numbers:
`ink_coverage` inside the content box, `min_contrast`, and the composite
readiness index `pri`. The reading is deterministic. PressProof is normally
handed the full ticket, but it only ever reads those two fields: a job file
carrying just `resolution_dpi` and `content_box_mm` must score identically to
the full ticket. The shop does not publish how PressProof computes its readings;
its prepress lead walked the studio through it, and those notes are with the team.
