# Rivet & Signal: Riverside Library door plate

- `design/spec.md`: the production file (coordinate systems, palette, approved layout, ticket schema).
- `design/render.py`: Halcyon's plate renderer (`--params FILE --dpi N --out OUT.png`, or `--bbox`).
- `artwork/recovered.json`: the approved Riverside layout, in render.py's parameter format.
- `tools/farmctl`: Halcyon's ticket lint (`farmctl validate JOB.yaml`).
- `templates/job.example.yaml`: an old ticket from another job, kept as a formatting reference.
- `profiles/`: the shop's substrate profile, referenced by tickets.
- `scripts/`: operations scripts. Submitting a ticket to the shop is the user's call.
