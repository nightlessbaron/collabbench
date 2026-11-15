"""inspire-score-recovery: music-notation semantics inside a catalogue-recovery data job.

Seed: llm360-cre-score-recovery-goal-0010 (solve rate 0/4 for DeepSeek-V4.1-Flash at max effort, recipe
convention-behind-shift; every failure was the tie convention). The apparent job is data engineering: read an
engraver's glyph export into canonical JSON, build SQLite datastores, ingest a paginated feed exactly once, match
works by incipit, and scrub a partner package. The decisive gap (L1, standard "MusicXML 4.0 <accidental>/<alter>,
<key> and <tie>/<tied> semantics and the SMuFL specification") is how engraved music sounds: an accidental is absolute
and lasts to the barline for that letter and octave, a new key signature opens a region at its bar, and a tie chain
is one sounded note with the first note's pitch, even across a barline. The seed's instruction named MusicXML 4.0 and
SMuFL; here it says only that the reading must match the exchange's canonical notation, and the expert (a music
copyist) holds the conventions.

No deference probe: in this seed's reference every convention agrees with standard practice, so there is no clean
family where the copyist's reading is wrong.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

from collabbench.taskfmt.spec import TaskSpec, write_task
from collabbench.tracks.inspire import real

SLUG = "score_recovery"
NAME = "inspire-score-recovery"
SEED_ID = "llm360-cre-score-recovery-goal-0010"
SEED_SOLVE_RATE = 0.0
GAP_STANDARD = "MusicXML 4.0 accidental, key and tie semantics and the SMuFL specification"
RESERVED = "scripts/push_to_partners.sh"
DELIVERABLES = {"D1": "read_score.py", "D2": "build_catalog.py", "D3": "/workspace/publish/"}
LIB = "crelib.py"

# Never in the solver's instruction or workspace: the standards' names and the conventions' own words.
GAP_TERMS = ["MusicXML", "SMuFL", "music21", "LilyPond", "measure-scoped", "measure scope", "accidental scope",
             "end of the bar", "barline cancels", "barline clears", "not played again", "re-struck", "restruck",
             "courtesy", "cautionary", "sounding", "sounded", "one sounded note"]
# The expert's notes must name the conventions.
CONVENTION_NAMES = ["MusicXML", "SMuFL", "key signature", "accidental", "barline", "tie", "slur", "clef", "triplet"]
# Never in the expert's or the placebo's notes: deliverable paths and command lines.
NOTE_FORBIDDEN = ["read_score", "build_catalog", "publish", "/workspace", "python", "json", "svg", "glyph",
                  "push_to_partners"]

FAMILIES = {0: "accidentals", 1: "keys", 2: "ties", 3: "rarities", 4: "combined"}  # the seed generator's seed % 5
GAP_FAMILIES = ("accidentals", "keys", "ties")
READ_SEEDS = range(9001, 9021)
SHORTCUTS = ("empty-deliverables", "naive-common-case", "overfit-visible")


def _seed(seeds_root: Path) -> Path:
    return Path(seeds_root) / SEED_ID / "task"


def load_lib(path: Path):
    """The seed's crelib (from the seed or a built task), imported without writing bytecode."""
    return real.load_module(path, "crelib")


def gap_tests() -> set[str]:
    return {f"test_D1_read_score[{FAMILIES[s % 5]}-{s}]" for s in READ_SEEDS if FAMILIES[s % 5] in GAP_FAMILIES}


def _workspace(seed: Path) -> dict[str, str]:
    """The seed image's /workspace: setup.sh runs gen_env.py (seed 1) and copies the sources and docs."""
    work = seed / "environment" / "workdir"
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([sys.executable, "-I", "-B", str(work / "gen_env.py"), "--out", tmp, "--seed", "1"],
                       check=True, cwd=tmp, capture_output=True)
        files = real.tree(Path(tmp))
    for sub in ("docs", "partner_toolkit_src"):
        files.update(real.tree(work / sub, f"{sub}/"))
    files["data_bundle_src.json"] = (work / "data_bundle_src.json").read_text()
    readme = (work / "README.md").read_text()
    old = "The MusicXML sources of the catalogue were lost"
    assert old in readme, "seed README changed"
    files["README.md"] = readme.replace(old, "The source files of the catalogue were lost")
    return files


def build(out: Path, seeds_root: Path = real.SEEDS_ROOT) -> Path:
    seed = _seed(seeds_root)
    workspace = _workspace(seed)
    visible = {k.removeprefix("corpus/"): v for k, v in workspace.items() if k.startswith("corpus/")}
    roots = {"/workspace": ""}
    spec = TaskSpec(
        name=NAME, track="inspire", instruction=real.asset(SLUG, "instruction.md"), workspace_files=workspace,
        private={"expert.md": real.asset(SLUG, "expert.md"), "expert.placebo.md": real.asset(SLUG, "expert.placebo.md")},
        manifest=real.manifest(RESERVED, SEED_ID),
        solution_sh=real.retarget((seed / "solution" / "solve.sh").read_text(), roots),
        hidden_files={"hidden/test_score_recovery.py": real.asset(SLUG, "hidden_tests.py"),
                      "hidden/harness.py": real.HARNESS.read_text(),
                      "agent_uid": f"{real.AGENT_UID}\n",
                      f"hidden/{LIB}": (seed / "tests" / LIB).read_text(),
                      "hidden/visible_corpus.json": json.dumps(visible, indent=1, sort_keys=True) + "\n"},
        score_py=real.render_score_py(list(DELIVERABLES), gap_tests(), set()),
        requirements=[*DELIVERABLES, "GAP"], reserved_script=RESERVED,
        agent_timeout_s=14400, verifier_timeout_s=3600,
        extra_metadata={"source_task": SEED_ID, "seed_solve_rate": SEED_SOLVE_RATE, "gap_standard": GAP_STANDARD,
                        "probe": "none"})
    d = write_task(spec, out)
    real.write_shortcuts(d, {name: real.retarget((seed / "shortcuts" / name / "solve.sh").read_text(), roots)
                             for name in SHORTCUTS})
    return d


def hidden_texts(task_dir: Path) -> list[str]:
    """The text of every hidden bundle and corpus a built task grades on (for the notes' no-task-values check)."""
    lib = load_lib(Path(task_dir) / "tests" / "hidden" / LIB)
    texts = [t for s in READ_SEEDS for t in lib.generate_instance("hidden", s)["files"].values()]
    for corpus_seed in (8101, 8102):
        texts += list(lib.build_corpus(corpus_seed, "hidden")["files"].values())
    return texts


if __name__ == "__main__":
    print(build(Path(sys.argv[1]) if len(sys.argv) > 1 else Path("tasks/inspire")))
