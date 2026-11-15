"""emmet to pydantic 2: materialsproject/emmet PRs #790, #836 and #838 (Sept 2023, parent 699ec1da, last dc71e0bd).

emmet is the Materials Project's document, builder and API library, made of three packages that share the `emmet`
namespace: emmet-core, emmet-builders and emmet-api. #790 ports it to pydantic 2 and pydantic-settings, and #836 and
#838 fix the port. Together they change 95 source files. The upstream suites (about 260 tests) read 72 MB of
`test_files/`, which the migration does not change. The images fetch it at build time from the pinned parent commit, so
it is not copied into this repository.

Like ormar, this is a pydantic v1 -> v2 migration, in a different project and domain (materials-science documents,
builders and a FastAPI service rather than ORM internals).
"""

import base64
import re
from pathlib import Path

from collabbench.tracks.swarm.real.common import Area, Migration, dist_stub, git

HERE = Path(__file__).resolve().parent
IMAGE = "public.ecr.aws/docker/library/python:3.11-slim"  # upstream CI ran 3.9-3.11
PARENT = "699ec1da63e4910c64af83206811732d3376b6da"
AFTER = "dc71e0bd54183e292d779706df0c1957257e05c9"
URL = "https://github.com/materialsproject/emmet.git"
PACKAGES = ["emmet-core", "emmet-builders", "emmet-api"]
# Left out of the images: emmet itself (its code must come from the workspace), mp-api (depends on emmet-core), the
# optional ML models (torch, ~2 GB; emmet's ml modules import them lazily), and docs/lint tools.
EXCLUDE = re.compile(r"^(emmet-|mp-api$|torch|triton$|nvidia-|dgl$|matgl$|chgnet$|matcalc$|lightning|pytorch-lightning$"
                     r"|mkdocs|pymdown|griffe$|livereload$|ghp-import$|mergedeep$|pyyaml-env-tag$|csscompressor$"
                     r"|htmlmin2$|jsmin$|pre-commit$|cfgv$|identify$|nodeenv$|virtualenv$|distlib$|mypy|types-"
                     r"|flake8$|pyflakes$|pycodestyle$|pydocstyle$|snowballstemmer$|mccabe$|coverage$|pytest-cov$"
                     r"|wincertstore$|phonopy$|cmake$|lit$)")  # phonopy (sdist, C), cmake, lit: only via matcalc and triton
DATA = "/opt/emmet-test-files"
FETCH_DATA = (f"RUN git init -q /tmp/emmet && cd /tmp/emmet && git remote add origin {URL} "
              f"&& git fetch -q --depth 1 --filter=blob:none origin {PARENT} "
              f"&& git checkout -q FETCH_HEAD -- test_files && mv test_files {DATA} && cd / && rm -rf /tmp/emmet")
STUBS = "RUN " + " && ".join(dist_stub(p, "0.68.0") for p in PACKAGES)  # packages read their version from metadata
# Agent image only: every Python process appends the three packages of the checkout that contains its current
# directory (the lead works in /workspace, teammates in /work/<name>); outside a checkout, /workspace's.
_FIND_CHECKOUT = """try:
    d = os.getcwd()
except OSError:
    d = "/"
while d != "/" and not os.path.isdir(os.path.join(d, "emmet-core", "emmet")):
    d = os.path.dirname(d)
for p in ("emmet-core", "emmet-builders", "emmet-api"):
    p = os.path.join(d if d != "/" else "/workspace", p)
    if p not in sys.path:
        sys.path.append(p)
"""
DEV_PTH = f'import os, sys; exec({_FIND_CHECKOUT!r}, {{"os": os, "sys": sys}})\n'
DEV_PATH = (f"RUN echo {base64.b64encode(DEV_PTH.encode()).decode()} | base64 -d > "
            '"$(python -c \'import sysconfig; print(sysconfig.get_paths()["purelib"])\')/emmet-workspace.pth"')


def pinned_packages(migration: Migration) -> list[str]:
    """`name==version` from the post-migration emmet-api lock for Python 3.11 (it covers emmet-core[all] and the test
    extras), minus EXCLUDE. Installed with --no-deps, so the lock alone decides every version."""
    lock = git(migration.repo(), "show", f"{AFTER}:emmet-api/requirements/ubuntu-latest_py3.11_extras.txt")
    out = []
    for line in lock.splitlines():
        m = re.match(r"^([A-Za-z0-9_.\-]+)(\[[^\]]*\])?==(\S+)", line)
        if m and not EXCLUDE.match(m.group(1).lower()):
            out.append(f"{m.group(1)}=={m.group(3)}")
    # Upstream CI installed openbabel from conda for the molecule documents and builders; this is its PyPI build.
    return out + ["setuptools==68.2.2", "openbabel-wheel==3.1.1.17"]


HIDDEN_CONFTEST = '''"""Written by the CollabBench builder into tests/hidden/ (emmet). Pytest runs isolated (python -I), so the workspace's
three emmet packages are on sys.path only through this file, appended: workspace files can never replace stdlib or
pytest modules. `emmet` is a namespace package spread over the three directories.

MAPISettings looks for test data in the workspace's test_files/, a link that the scored copy of the workspace does not
keep; MAPI_TEST_FILES points it at the image's copy next to this file."""

import os
import sys

os.environ.setdefault("MAPI_TEST_FILES", os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_files"))
_ws = os.environ.get("COLLAB_WORKSPACE")
if _ws:
    for _pkg in ("emmet-core", "emmet-builders", "emmet-api"):
        _path = os.path.join(_ws, _pkg)
        if _path not in sys.path:
            sys.path.append(_path)
'''

CORE_FACTS = '''"""Brief-only decisions F1 and F2 (CollabBench)."""
import warnings


def test_F1_pyobject_alias():
    from pydantic import ImportString

    from emmet.core.settings import PyObject

    assert PyObject is ImportString


def test_F2_dict_without_warning():
    from emmet.core.base import EmmetBaseModel

    class Doc(EmmetBaseModel):
        value: int = 3

    doc = Doc()
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        out = doc.dict()
    assert out == doc.model_dump() and out["value"] == 3
'''

API_FACTS = '''"""Brief-only decision F3 (CollabBench)."""


def test_F3_mapi_settings_ignore_unknown():
    from emmet.api.core.settings import MAPISettings

    settings = MAPISettings(not_a_setting=1)
    assert not hasattr(settings, "not_a_setting")
'''

FACT_EDITS = {
    "emmet-core/emmet/core/settings.py": [
        ('from pydantic_settings import BaseSettings, SettingsConfigDict\n',
         'from pydantic_settings import BaseSettings, SettingsConfigDict\n\n'
         '# pydantic 1 name, kept for code that subclasses EmmetSettings and still imports it from here.\n'
         'PyObject = ImportString\n'),
    ],
    "emmet-core/emmet/core/base.py": [
        ('    builder_meta: EmmetMeta = Field(\n        default_factory=EmmetMeta, description="Builder metadata."\n    )\n',
         '    builder_meta: EmmetMeta = Field(\n        default_factory=EmmetMeta, description="Builder metadata."\n    )\n\n'
         '    def dict(self, **kwargs):  # noqa: A003\n'
         '        """Same as model_dump(), without the deprecation warning: builders still call it in hot loops."""\n'
         '        return self.model_dump(**kwargs)\n'),
    ],
    "emmet-api/emmet/api/core/settings.py": [
        ('    model_config = SettingsConfigDict(env_prefix="MAPI_")\n',
         '    model_config = SettingsConfigDict(env_prefix="MAPI_", extra="ignore")\n'),
    ],
}

def _core(*modules: str) -> list[str]:
    return [f"emmet-core.tests.{m}::" for m in modules]


# emmet-core's top-level documents are split by module so that no area holds more than about a third of the pinned
# tests (pinned per area when split: 50, 53, 39, 9, then 9, 14, 26, 30, 10).
AREAS = [
    Area("R1", "core diffraction and spectra", _core("test_xrd", "test_absorption"),
         "emmet-core's XRD and X-ray absorption documents (`emmet/core/xrd.py`, `absorption.py`, `spectrum.py`) "
         "validate, build and dump under pydantic 2; covered by emmet-core/tests/test_xrd.py and test_absorption.py"),
    Area("R2", "core structure analysis",
         _core("test_chemenv", "test_oxidation_states", "test_robocrys", "test_structure_group", "test_magnetism",
               "test_polar", "test_structure_metadata", "test_molecule_metadata", "test_optimade"),
         "emmet-core's structure-derived documents: chemical environments, oxidation states, robocrystallographer, "
         "structure groups, magnetism, dielectric and piezoelectric, structure and molecule metadata, OPTIMADE; "
         "covered by the matching emmet-core/tests/test_*.py"),
    Area("R3", "core calculations and properties",
         _core("test_calculation", "test_task", "test_electronic_structure", "test_elasticity", "test_thermo",
               "test_electrodes", "test_ml") + ["emmet-core.tests.mobility."],
         "emmet-core's calculation and task documents (`emmet/core/tasks.py`, `vasp/calculation.py`) and the "
         "property documents built from them: electronic structure, elasticity, thermo, electrodes, ML, mobility; "
         "covered by the matching emmet-core/tests/test_*.py and mobility/"),
    Area("R4", "core identifiers, settings and utilities",
         _core("test_mpid", "test_utils", "test_settings", "test_provenance"),
         "emmet-core's shared foundations: the MPID and MPculeID types, settings, utilities and provenance "
         "(`emmet/core/mpid.py`, `settings.py`, `utils.py`, `provenance.py`); covered by the matching tests"),
    Area("R5", "core VASP", ["emmet-core.tests.vasp."],
         "emmet-core's VASP task, calculation and validation documents (`emmet/core/vasp`); covered by "
         "emmet-core/tests/vasp"),
    Area("R6", "core molecules and Q-Chem", ["emmet-core.tests.molecules.", "emmet-core.tests.qchem."],
         "emmet-core's molecule and Q-Chem documents (`emmet/core/molecules`, `emmet/core/qchem`); covered by "
         "emmet-core/tests/molecules and qchem"),
    Area("R7", "builders", ["emmet-builders.tests."],
         "emmet-builders' builders run on pydantic 2 documents with maggma stores; covered by emmet-builders/tests"),
    Area("R8", "API materials", ["emmet-api.tests.materials."],
         "emmet-api's materials resources and query operators; covered by emmet-api/tests/materials"),
    # One area for the API's molecules and core: after fail-to-pass pinning the core alone keeps a single test.
    Area("R9", "API molecules and core", ["emmet-api.tests.molecules.", "emmet-api.tests.legacy.",
                                          "emmet-api.tests.core.", "emmet-api.tests._consumer.",
                                          "emmet-api.tests._general_store.", "emmet-api.tests.test_"],
         "emmet-api's molecules (and legacy molecules) resources and query operators, and its core: the MAPI app, "
         "settings, consumer and general-store resources; covered by emmet-api/tests outside materials/"),
]

BRIEF = """# Port emmet to pydantic 2

emmet's three packages share the `emmet` namespace: `emmet-core/emmet` (document models), `emmet-builders/emmet`
(builders) and `emmet-api/emmet` (the API service). They still target pydantic 1.10. The environment now has pydantic
2.4, pydantic-settings 2.0 and maggma 0.57, and most of emmet fails to import or validate. Port all three packages to
pydantic 2 following `docs/MIGRATION.md`. Documents must keep their fields, defaults and validation behaviour, builders
must produce the same documents, and API resources must keep their query behaviour.

The test suites are `emmet-core/tests`, `emmet-builders/tests` and `emmet-api/tests`. Run each package's suite
separately from the root of your checkout, for example `python -m pytest emmet-core/tests`. Python puts the three
packages of the checkout that contains the current directory on its path. The shared test data is in `test_files/`,
and nothing needs network."""

MIGRATION = Migration(
    slug="emmet-pydantic2",
    url=URL,
    parent=PARENT,
    after=AFTER,
    prs=["https://github.com/materialsproject/emmet/pull/790", "https://github.com/materialsproject/emmet/pull/836",
         "https://github.com/materialsproject/emmet/pull/838"],
    source_globs=[f"{p}/emmet/*" for p in PACKAGES],
    hidden_tests={f"{p}/tests": f"{p}/tests" for p in PACKAGES},
    areas=AREAS,
    facts={
        "F1": "keep the pydantic 1 name importable: `from emmet.core.settings import PyObject` must work, and it must "
              "be the same object as `pydantic.ImportString`.",
        "F2": "`.dict()` on any `EmmetBaseModel` document must keep working without emitting any warning, and return "
              "the same as `.model_dump()` (builders call it in hot loops).",
        "F3": "`emmet.api.core.settings.MAPISettings` must ignore unknown settings instead of failing, so that "
              "`MAPISettings(not_a_setting=1)` succeeds and the instance has no `not_a_setting` attribute.",
    },
    fact_tests={"hidden/emmet-core/tests/test_collab_facts.py": CORE_FACTS,
                "hidden/emmet-api/tests/test_collab_facts.py": API_FACTS},
    fact_edits=FACT_EDITS,
    migration_md=(HERE / "emmet_migration.md").read_text(),
    brief_intro=BRIEF,
    post_versions=["0.69.0", "0.69.1", "v0.69"],
    drop=[".github/*", "test_files/*"],
    targets=[f"{p}/tests" for p in PACKAGES],
    pytest_args=["--continue-on-collection-errors", "-p", "no:warnings"],
    hidden_conftest=HIDDEN_CONFTEST,
    test_timeout_s=1200,
    spec_kwargs=dict(base_image=IMAGE, pip_args=["--no-deps"], apt_packages=["git"],
                     env_dockerfile=f"{FETCH_DATA}\n{STUBS}\n{DEV_PATH}",
                     tests_dockerfile=f"{FETCH_DATA}\n{STUBS}\nRUN mkdir -p /tests/hidden && ln -s {DATA} "
                                      f"/tests/hidden/test_files",
                     workspace_setup=f"ln -s {DATA} test_files", cpus=2, memory_mb=4096, verifier_timeout_s=7200,
                     max_snapshots_per_label=6, score_workers=2, score_timeout_s=2400),
    naive_probe_reward=0.06995884773662552,  # runs/gates/emmet-pydantic2-naive--gate-oracle--20261115-051901: 17/243
)


def build_spec_kwargs() -> None:
    """The pip list needs the upstream lock, read through git when the task is built."""
    MIGRATION.spec_kwargs["pip_packages"] = pinned_packages(MIGRATION)
