# PressProof v3.2: reading the proof

You own `pressproof.py`. These are Halcyon's prepress lead's notes on how PressProof reads a proof, up to the
normalised lightness rho that it measures; your teammate has the notes on what PressProof measures from rho (the ink
threshold, the contrast figure and the readiness index). Names: the image is W pixels wide and H high, and
round_half_up(x) = floor(x + 0.5).

- A proof with an alpha channel is laid on opaque white before anything else: each colour channel becomes c * a + 255 * (1 - a), with a = alpha / 255.
- Lightness is linear-light luminance: each 8-bit channel value v becomes c = v / 255, then c_lin = c / 12.92 if c <= 0.04045, else ((c + 0.055) / 1.055) ** 2.4; Y = 0.2126 R_lin + 0.7152 G_lin + 0.0722 B_lin.
- The proof's own recorded resolution governs the reading: when the PNG has a pHYs chunk in pixels per metre, dpi = round_half_up(pixels_per_metre * 0.0254), whatever the ticket says; only a proof without one falls back to the ticket's resolution_dpi. The content box goes to pixels with s = dpi / 25.4: x0 = round_half_up(X0 * s), and likewise y0, x1 and y1, each clipped to the image; the box is the half-open rectangle [x0, x1) x [y0, y1).
- The paper is judged from the border frame only: fw = max(4, round_half_up(0.04 * W)) and fh = max(4, round_half_up(0.04 * H)); the frame is every pixel with x < fw, x >= W - fw, y < fh or y >= H - fh.
- Over the frame, the paper white w is the 99.5 percentile of Y and the black reference b the 0.5 percentile, both with linear interpolation between order statistics.
- The normalised lightness is rho = clip((Y - b) / (w - b + 1e-12), 0, 1), with no other guard: a perfectly flat border, as on a clean digital render, makes w = b, so every pixel at or below the paper tone reads rho = 0.
- PressProof runs on the counter workstation and returns a reading sheet in about three seconds per proof.
- The shop keeps every submitted proof on file for seven years.
