# CRE engraver SVG format (cre-engraver-svg/1)

The retired in-house engraver emitted one directory per score:

- `score.meta.json` — page and staff geometry plus bibliographic fields.
- `score.svg` — one `<g>` per glyph, carrying `data-glyph`, `data-staff`,
  `data-x` and `data-y`. There are no other attributes.

## Coordinates

- `data-x` is a horizontal grid coordinate. A quarter-note beat is
  `spaces_per_beat` grid units wide (`spaces_per_beat` is 12 for every bundle
  in this archive), so an onset in quarter-note beats is `data-x / spaces_per_beat`.
  Barline glyphs therefore fall on measure boundaries.
- `data-y` is vertical position in staff spaces, increasing downwards. The
  five staff lines are at `y = 0, 2, 4, 6, 8`; the four spaces between them are
  at `y = 1, 3, 5, 7`. Leger lines extend the same lattice above and below.
- `data-staff` identifies the staff (all bundles in this archive have one
  staff, numbered 0).

## Glyph vocabulary

| glyph | meaning |
| --- | --- |
| `noteheadWhole`, `noteheadHalf`, `noteheadBlack` | noteheads |
| `flag8thUp`, `flag8thDown`, `flag16thUp`, `flag16thDown`, `flag32ndUp`, `flag32ndDown` | flags on a black notehead |
| `augmentationDot` | augmentation dot |
| `tuplet3` | triplet bracket/numeral for the note it accompanies |
| `accidentalDoubleFlat`, `accidentalFlat`, `accidentalNatural`, `accidentalSharp`, `accidentalDoubleSharp` | written accidentals |
| `keySharp`, `keyFlat`, `keyNatural` | key-signature glyphs |
| `gClef`, `fClef`, `cClef` | clefs, drawn on the line they refer to |
| `tie`, `slur` | curved connectors |
| `restWhole`, `restHalf`, `restQuarter`, `rest8th`, `rest16th`, `rest32nd` | rests |
| `barlineSingle`, `barlineFinal` | barlines |
| `ledgerLine` | a leger line |
| `timeSigCommon`, `timeSigCutCommon`, `timeSig0` … `timeSig9` | time signature |

Every auxiliary glyph is drawn relative to the notehead it belongs to:

- flag: same `data-x`, `data-y` one and a half staff spaces away;
- augmentation dot: `data-x + 1`, same `data-y`;
- tuplet marker and tie: same `data-x`;
- accidental: `data-x - 1`, same `data-y`;
- slur: same `data-x`.

A notehead's notated value comes from its notehead glyph and, for black
noteheads, from its flag: a flagless black notehead is a quarter, then
`flag8th*` halves it, `flag16th*` quarters it and `flag32nd*` eighths it. An
augmentation dot multiplies the notated value by 3/2; a `tuplet3` marker
multiplies it by 2/3.

A key signature is the group of `keySharp` or `keyFlat` glyphs printed together
at a measure start; a lone `keyNatural` marks a signature with no sharps and no
flats.

`score.meta.json` carries `work_id`, `title`, `composer`, `mode`, 
`spaces_per_beat`, `format` and `staves` (with `staff`, `top_y`, `bottom_y`).