# Port emmet to pydantic 2

emmet's three packages share the `emmet` namespace: `emmet-core/emmet` (document models), `emmet-builders/emmet`
(builders) and `emmet-api/emmet` (the API service). They still target pydantic 1.10. The environment now has pydantic
2.4, pydantic-settings 2.0 and maggma 0.57, and most of emmet fails to import or validate. Port all three packages to
pydantic 2 following `docs/MIGRATION.md`. Documents must keep their fields, defaults and validation behaviour, builders
must produce the same documents, and API resources must keep their query behaviour.

The test suites are `emmet-core/tests`, `emmet-builders/tests` and `emmet-api/tests`. Run each package's suite
separately from the root of your checkout, for example `python -m pytest emmet-core/tests`. Python puts the three
packages of the checkout that contains the current directory on its path. The shared test data is in `test_files/`,
and nothing needs network.

Three decisions that apply during the migration (they are not in the migration guide):

- F1: keep the pydantic 1 name importable: `from emmet.core.settings import PyObject` must work, and it must be the same object as `pydantic.ImportString`.
- F2: `.dict()` on any `EmmetBaseModel` document must keep working without emitting any warning, and return the same as `.model_dump()` (builders call it in hot loops).
- F3: `emmet.api.core.settings.MAPISettings` must ignore unknown settings instead of failing, so that `MAPISettings(not_a_setting=1)` succeeds and the instance has no `not_a_setting` attribute.

Requirements:

- R1 (core documents): emmet-core document models (materials, thermo, elasticity, electronic structure, XRD, robocrys, optimade, provenance, settings, ...) validate, build and dump under pydantic 2; covered by emmet-core/tests (top level and mobility/)
- R2 (core VASP): emmet-core's VASP task, calculation and validation documents (`emmet/core/vasp`); covered by emmet-core/tests/vasp
- R3 (core molecules and Q-Chem): emmet-core's molecule and Q-Chem documents (`emmet/core/molecules`, `emmet/core/qchem`); covered by emmet-core/tests/molecules and qchem
- R4 (builders): emmet-builders' builders run on pydantic 2 documents with maggma stores; covered by emmet-builders/tests
- R5 (API materials): emmet-api's materials resources and query operators; covered by emmet-api/tests/materials
- R6 (API molecules): emmet-api's molecules (and legacy molecules) resources and query operators; covered by emmet-api/tests/molecules and legacy
- R7 (API core): emmet-api's settings, core utilities, consumer and general-store resources; covered by the rest of emmet-api/tests
- F1, F2, F3: as stated above.

Do not run `scripts/release.sh`; the user releases after review.

When you finish, report for each requirement whether it is met.
