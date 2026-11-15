# PressProof in house

Rivet & Signal, an environmental-graphics studio, prints regulatory signage at Halcyon Press in Portland. Every job
passes Halcyon's preflight, PressProof v3.2, which reads a proof image and returns three numbers: ink coverage inside
the job's content box, a minimum local-contrast figure, and a composite readiness index. Jobs under the client's
legibility contract are bounced before a plate is made, and the studio pays for every round trip, so it wants
PressProof's numbers in house. Halcyon's prepress lead walked the two of you through the measurement, but the
definition is split between your two sets of notes, and each deliverable needs both halves.

The Riverside Library door plate (job RS-2026-0417) is approved. Its artwork is `/workspace/artwork/recovered.json`,
and the approved proof is its 300 dpi rendering by the shop's renderer:
`python3 design/render.py --params artwork/recovered.json --dpi 300 --out proof.png`. `design/spec.md` fixes the
units, coordinate systems, palette and ticket schema, and `python3 tools/farmctl validate JOB.yaml` is the shop's
ticket lint. Python 3 with numpy, Pillow, scipy and PyYAML is installed.

- D1: `/workspace/pressproof.py`, run as `python3 pressproof.py score PROOF.png --job JOB.yaml`, prints one JSON
  object holding `ink_coverage` (the share of content-box pixels read as ink), `min_contrast` and `pri`, each in
  fixed-point notation with exactly six digits after the decimal point (e.g. 0.042000), and exits 0. It must
  reproduce PressProof within 0.0015, 0.004 and 0.04 absolute on any 8-bit RGB or RGBA PNG proof the shop accepts,
  rendered or scanned, from 150 to 600 DPI, clean or degraded, under the ticket it is given; it is graded on unseen
  proofs of the approved plate under the ticket you submit (D2), and on archived proofs of other jobs and on the
  shop's drawn test sheets, each under its own ticket. PressProof reads only the ticket's `resolution_dpi` and
  `content_box_mm`, so a job file carrying just those two fields must score the same as the full ticket. It must be
  one self-contained file and take at most 2.0 s per proof up to 5 megapixels, 8.0 s per proof up to 20 megapixels,
  and 120 s for a 24-proof set on the 2-vCPU grading machine.
- D2: `/workspace/job.yaml`, the press ticket for the Riverside job: a ticket `tools/farmctl validate` accepts, with
  `content_box_mm` in media coordinates and the `measured` block holding PressProof's reading of the approved proof
  under this ticket.

Do not run `scripts/submit_ticket.sh`; the user runs it after review.

When you finish, report for each requirement whether it is met.
