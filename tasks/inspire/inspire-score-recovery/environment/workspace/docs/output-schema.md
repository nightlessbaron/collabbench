# Output contract

## `read_score.py`

`python3 read_score.py <bundle_dir>` reads `<bundle_dir>/score.meta.json` and
`<bundle_dir>/score.svg` and prints one JSON object to standard output:

```
{"notes": [ {"staff": 0, "voice": 0, "onset": "0", "duration": "1",
             "midi": 60, "tie_group": null}, ... ],
 "key_regions": [ {"start_measure": 1, "fifths": 0, "mode": "major"}, ... ]}
```

- `onset` and `duration` are exact rationals in quarter-note beats, written as
  reduced strings (`"0"`, `"1"`, `"3/2"`); never floats.
- `midi` is the integer MIDI number (middle C = 60).
- `tie_group` is `null` for a note that is not tied, otherwise an integer
  identifying the tie chain; ids are 1, 2, 3, … in order of the chain's first
  onset.
- `notes` is sorted by `(staff, onset, midi)`.
- `key_regions` is ordered by `start_measure`; the first region starts at
  measure 1; `mode` is `"major"` or `"minor"`.

## `build_catalog.py`

`python3 build_catalog.py <corpus_root>` builds everything from a clean state
and writes it under `<corpus_root>/out/`:

- `notation/<work_id>.json` — the canonical notation of every reference and
  submission bundle, in the schema above.
- the datastore files named by the two manifests (`reference.db`,
  `submission.db`), created with exactly the tables, columns and column types
  the manifest declares and no others, and seeded as described below.
- `pairs.jsonl` — one JSON object per line,
  `{"reference": "<ref id>", "submission": "<sub id>"}`, sorted by
  `(reference, submission)`, each pair once.
- `counts.json` — the feed counts described below.

`python3 build_catalog.py --reset <corpus_root>` recreates the two datastores
under `<corpus_root>/out/` in their seeded initial state (all score rows
present, no feed rows).

### Datastores

`manifests/reference_manifest.json` and `manifests/submission_manifest.json`
each give a `datastore` file name and a list of `tables`, each with `columns`
(`name`, `type`, optional `primary_key`). Create exactly those tables and
columns with those SQLite type names.

- `references`: one row per bundle in `reference/`.
- `submissions`: one row per bundle in `submissions/`.
- `feed_items`: one row per distinct item ingested from the feed.

For `references` and `submissions` the row values are: `work_id`, `title` and
`composer` from the bundle's meta; `fifths` and `mode` from the first key
region; `incipit` the fingerprint below; `note_count` the number of canonical
notes. The columns not present in a given manifest are ignored.

### Feed ingestion

`feed/feed_index.json` gives `cutoff` (an ISO date) and the feed files are
`feed/page-NNNN.json`, each `{"records": [...]}` with `item_id`, `work_id`,
`title` and `submitted_at`. Ingest every record whose `submitted_at` is on or
before `cutoff`, exactly once per `item_id`, even when a page repeats a record.
`counts.json` is:

```
{"records_seen": <all page entries>, "ingested": <distinct ids under cutoff>,
 "skipped_after_cutoff": <distinct ids after cutoff>,
 "duplicates_skipped": <entries whose id was already seen>}
```

`ingested` must equal `feed_index.json`'s `total_under_cutoff`.

### Matching

- `normalise_title(t)`: lower-case `t`, replace every non-alphanumeric
  character with a space, split on whitespace and rejoin with single spaces.
- `block_key(t)`: `normalise_title(t)` with spaces removed, first four
  characters.
- `incipit_fingerprint`: take the first six canonical notes (fewer if the score
  has fewer). Let `tonic = (fifths * 7) % 12` for a major opening region and
  `(fifths * 7 + 9) % 12` for a minor one, using the first key region. Build the
  string `onset:duration:pc` for each note with `pc = (midi - tonic) % 12`, join
  with `|`, and take the SHA-256 hex digest.
- A candidate pair shares a `block_key`. It is delivered when the two
  `incipit` fingerprints are equal.