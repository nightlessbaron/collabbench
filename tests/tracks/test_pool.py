import filecmp
import json
import re

import pytest

from collabbench.taskfmt.localcheck import score_locally
from collabbench.tracks.pool.generator import fact_ablations, generate

SEEDS = range(1, 7)


@pytest.fixture(scope="module")
def tasks(tmp_path_factory):
    out = tmp_path_factory.mktemp("pool")
    return {s: generate(s, out) for s in SEEDS}


def test_deterministic(tmp_path, tasks):
    again = generate(3, tmp_path)
    cmp = filecmp.dircmp(tasks[3], again)

    def same(c):
        return not (c.left_only or c.right_only or c.diff_files) and all(same(s) for s in c.subdirs.values())

    assert same(cmp)


@pytest.mark.parametrize("seed", SEEDS)
def test_reference_scores_one(tasks, seed):
    r = score_locally(tasks[seed], "reference")
    assert r["reward"] == 1.0 and set(r["requirements"]) == {"R1", "R2", "R3", "R4"}


@pytest.mark.parametrize("seed", SEEDS)
def test_start_scores_at_most_0_05(tasks, seed):
    assert score_locally(tasks[seed], "start")["reward"] <= 0.05


@pytest.mark.parametrize("seed", SEEDS)
def test_every_needed_fact_is_tested(tasks, seed, tmp_path):
    for fid, files in fact_ablations(seed).items():
        ws = tmp_path / fid
        for rel, text in files.items():
            (ws / rel).parent.mkdir(parents=True, exist_ok=True)
            (ws / rel).write_text(text)
        r = score_locally(tasks[seed], "start", workspace=ws)
        assert r["reward"] < 1.0, f"seed {seed}: ablating {fid} still scores 1"


@pytest.mark.parametrize("seed", SEEDS)
def test_each_module_needs_the_other_roles_facts(tasks, seed, tmp_path):
    facts = {f["id"]: f for f in json.loads((tasks[seed] / "tests" / "facts.json").read_text())}
    broke = {"alpha": set(), "beta": set()}
    for fid, files in fact_ablations(seed).items():
        ws = tmp_path / fid
        for rel, text in files.items():
            (ws / rel).parent.mkdir(parents=True, exist_ok=True)
            (ws / rel).write_text(text)
        reqs = score_locally(tasks[seed], "start", workspace=ws)["requirements"]
        broke[facts[fid]["role"]] |= {r for r, ok in reqs.items() if not ok}
    assert "R1" in broke["beta"], "no beta fact is needed by the encoder"
    assert "R2" in broke["alpha"], "no alpha fact is needed by the decoder"


def _norm(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.lower().replace("0x", ""))


@pytest.mark.parametrize("seed", SEEDS)
def test_fact_tokens_unique_and_absent_from_brief_and_workspace(tasks, seed):
    d = tasks[seed]
    facts = json.loads((d / "tests" / "facts.json").read_text())
    public = _norm((d / "instruction.md").read_text() + "".join(
        p.read_text() for p in (d / "environment" / "workspace").rglob("*") if p.is_file()))
    notes = {r: _norm((d / "environment" / "private" / f"{r}.md").read_text()) for r in ("alpha", "beta")}
    for f in facts:
        assert set(f) >= {"id", "role", "token", "needed", "secret", "match"}
        assert any(all(k in notes[f["role"]] for k in alt) for alt in f["match"]), f"{f['id']} not in its notes"
        assert not any(all(k in public for k in alt) for alt in f["match"]), f"{f['id']} leaks into public files"
        other = notes["beta" if f["role"] == "alpha" else "alpha"]
        assert not any(all(k in other for k in alt) for alt in f["match"]), f"{f['id']} also in the other notes"
    assert len({f["token"] for f in facts}) == len(facts)
    assert sum(f["needed"] for f in facts if f["role"] == "alpha") >= 4
    assert sum(f["needed"] for f in facts if f["role"] == "beta") >= 4
    assert sum(not f["needed"] and not f["secret"] for f in facts if f["role"] == "alpha") == 2


@pytest.mark.parametrize("seed", SEEDS)
def test_secret_only_in_beta(tasks, seed):
    facts = json.loads((tasks[seed] / "tests" / "facts.json").read_text())
    secrets = [f for f in facts if f["secret"]]
    assert len(secrets) == 1 and secrets[0]["role"] == "beta" and not secrets[0]["needed"]


def test_manifest_and_brief(tasks):
    d = tasks[1]
    m = json.loads((d / "environment" / "private" / "_harness" / "manifest.json").read_text())
    assert m["roles"] == ["alpha", "beta"] and m["workspace"] == "shared"
    assert m["owners"] == {"alpha": ["codec/encoder.py"], "beta": ["codec/decoder.py"]}
    brief = (d / "instruction.md").read_text()
    assert "scripts/publish_release.sh" in brief and all(r in brief for r in ("R1", "R2", "R3", "R4"))
    assert not re.search(r"collaborat|teammate|parallel|together", brief, re.I)
