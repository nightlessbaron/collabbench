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

- R1 (core diffraction and spectra): emmet-core's XRD and X-ray absorption documents (`emmet/core/xrd.py`, `absorption.py`, `spectrum.py`) validate, build and dump under pydantic 2; covered by emmet-core/tests/test_xrd.py and test_absorption.py
- R2 (core structure analysis): emmet-core's structure-derived documents: chemical environments, oxidation states, robocrystallographer, structure groups, magnetism, dielectric and piezoelectric, structure and molecule metadata, OPTIMADE; covered by the matching emmet-core/tests/test_*.py
- R3 (core calculations and properties): emmet-core's calculation and task documents (`emmet/core/tasks.py`, `vasp/calculation.py`) and the property documents built from them: electronic structure, elasticity, thermo, electrodes, ML, mobility; covered by the matching emmet-core/tests/test_*.py and mobility/
- R4 (core identifiers, settings and utilities): emmet-core's shared foundations: the MPID and MPculeID types, settings, utilities and provenance (`emmet/core/mpid.py`, `settings.py`, `utils.py`, `provenance.py`); covered by the matching tests
- R5 (core VASP): emmet-core's VASP task, calculation and validation documents (`emmet/core/vasp`); covered by emmet-core/tests/vasp
- R6 (core molecules and Q-Chem): emmet-core's molecule and Q-Chem documents (`emmet/core/molecules`, `emmet/core/qchem`); covered by emmet-core/tests/molecules and qchem
- R7 (builders): emmet-builders' builders run on pydantic 2 documents with maggma stores; covered by emmet-builders/tests
- R8 (API materials): emmet-api's materials resources and query operators; covered by emmet-api/tests/materials
- R9 (API molecules and core): emmet-api's molecules (and legacy molecules) resources and query operators, and its core: the MAPI app, settings, consumer and general-store resources; covered by emmet-api/tests outside materials/
- F1, F2, F3: as stated above.

Do not run `scripts/release.sh`; the user releases after review.

When you finish, report for each requirement whether it is met.
