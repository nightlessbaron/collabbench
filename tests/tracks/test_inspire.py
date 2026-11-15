import filecmp
import json
import random
import re
import statistics
from pathlib import Path

import numpy as np
import pytest

from collabbench.taskfmt.localcheck import score_locally
from collabbench.tracks.common import words
from collabbench.tracks.inspire import fields
from collabbench.tracks.inspire.generator import generate, generate_all, task_name
from collabbench.tracks.inspire.sims import CONCEPTS, SIMULATORS

SEEDS = (1, 2)
ALL = list(SIMULATORS)  # the six concepts and the trap
# Generic English words of length >= 5 that a field's notes cannot avoid; they carry no task information.
STOPLIST = {"which", "their", "there", "about", "other", "every", "where", "these", "those", "should", "would",
            "could", "while", "after", "before", "first", "being", "under", "between", "because", "often", "given",
            "since", "until", "whose", "again", "still", "later", "whole", "another", "without", "within", "through",
            "above", "gives", "number", "system", "possible", "average", "itself", "needs", "total", "different",
            "series", "least"}


@pytest.fixture(scope="module")
def tasks(tmp_path_factory):
    out = tmp_path_factory.mktemp("inspire")
    return {(c, s): generate(c, s, out) for c in ALL for s in SEEDS}


def random_plan(sim, params, rng):
    items = params["items"]
    if sim.key == "depth":
        while True:
            plan = {sim.key: {k: rng.randint(2, 9) for k in items}}
            if sim.validate(plan, params) is None:
                return plan
    if sim.key == "stake_share":
        return {sim.key: {k: rng.uniform(0, 0.99) for k in items}}
    return {sim.key: {k: math_exp(rng) for k in items}}


def math_exp(rng):
    return float(np.exp(rng.uniform(-3, 3)))


@pytest.mark.parametrize("seed", SEEDS)
@pytest.mark.parametrize("concept", ALL)
def test_optimum_beats_random_plans(concept, seed):
    sim = SIMULATORS[concept]
    p = sim.params(seed)
    best, gap = sim.objective(sim.optimum(p), p), sim._gap(p)
    rng = random.Random(seed)
    for _ in range(1000):
        plan = random_plan(sim, p, rng)
        assert sim.validate(plan, p) is None
        assert sim.objective(plan, p) <= best + 0.01 * gap


@pytest.mark.parametrize("concept", [c for c in ALL if c != "prefix_code"])
def test_optimum_beats_its_neighbours(concept):
    sim = SIMULATORS[concept]
    p = sim.params(1)
    opt = sim.optimum(p)[sim.key]
    best, gap, rng = sim.objective({sim.key: opt}, p), sim._gap(p), np.random.default_rng(0)
    for _ in range(300):
        near = {k: max(0.0, v * (1 + rng.normal(0, 0.1)) + rng.normal(0, 0.02)) for k, v in opt.items()}
        if sim.validate({sim.key: near}, p) is None:
            assert sim.objective({sim.key: near}, p) <= best + 1e-6 * gap


@pytest.mark.parametrize("seed", SEEDS)
@pytest.mark.parametrize("concept", ALL)
def test_baseline_normalizes_to_zero_and_optimum_to_one(concept, seed):
    sim = SIMULATORS[concept]
    p = sim.params(seed)
    assert sim.validate(sim.baseline(p), p) is None and sim.validate(sim.optimum(p), p) is None
    assert sim.normalized(sim.baseline(p), p) == pytest.approx(0, abs=1e-9)
    assert sim.normalized(sim.optimum(p), p) == pytest.approx(1, abs=1e-9)
    assert sim.optimum(p) != sim.baseline(p)


@pytest.mark.parametrize("seed", SEEDS)
@pytest.mark.parametrize("concept", ALL)
def test_noise_is_bounded(concept, seed):
    sim = SIMULATORS[concept]
    p = sim.params(seed)
    draws = [sim.objective(sim.baseline(p), p, noise_seed=n) for n in range(300)]
    assert 0 < statistics.pstdev(draws) <= 0.05 * sim._gap(p)
    assert sim.objective(sim.baseline(p), p) == sim.objective(sim.baseline(p), p)  # no noise without a seed


@pytest.mark.parametrize("seed", SEEDS)
@pytest.mark.parametrize("concept", ALL)
def test_hint_capture_high_for_optimum_low_for_baseline(concept, seed):
    sim = SIMULATORS[concept]
    p = sim.params(seed)
    concept_plan = sim.concept_plan(p) if concept.endswith("_trap") else sim.optimum(p)
    assert sim.hint_capture(concept_plan, p) > 0.99
    assert sim.hint_capture(sim.baseline(p), p) < 0.8


def test_kelly_has_zero_stakes_and_wide_range():
    sim = SIMULATORS["kelly"]
    for seed in range(1, 6):
        stakes = list(sim.optimum(sim.params(seed))["stake_share"].values())
        assert sum(s == 0 for s in stakes) == 2
        assert 0.15 <= min(s for s in stakes if s > 0) and max(stakes) <= 0.6


def heuristic_plans(concept, p):
    """Natural plans a practitioner would try without the concept, as {name: plan}."""
    n = len(p["items"])
    if concept in ("water_filling", "water_filling_trap"):
        return {"allocation proportional to 1/floor": {"allocation": {k: 1 / f for k, f in zip(p["items"], p["floors"])}}}
    if concept == "marginal_value":
        return {"dwell for one half-life": {"dwell_minutes": {k: t * np.log(2) for k, t in zip(p["items"], p["tau"])}}}
    if concept == "kelly":
        edge = [q * (1 + b) - 1 for q, b in zip(p["p"], p["b"])]
        return {"stake 0.1 wherever the edge is positive": {"stake_share": {k: 0.1 if e > 0 else 0 for k, e in zip(p["items"], edge)}}}
    if concept == "sqrt_staffing":
        return {"equal agents per queue": {"agents": {k: 1.0 for k in p["items"]}}}
    if concept == "inverse_elasticity":
        return {"markup proportional to volume": {"markup": {k: v for k, v in zip(p["items"], p["volume"])}}}
    order = sorted(range(n), key=lambda i: -p["share"][i])
    unary = {p["items"][i]: min(r + 1, n - 1) for r, i in enumerate(order)}
    return {"one more step per rank (unary)": {"depth": unary}}


@pytest.mark.parametrize("seed", SEEDS)
@pytest.mark.parametrize("concept", ALL)
def test_naive_heuristic_leaves_room(concept, seed):
    sim = SIMULATORS[concept]
    p = sim.params(seed)
    scores = {}
    for name, plan in heuristic_plans(concept, p).items():
        assert sim.validate(plan, p) is None, name
        scores[name] = sim.normalized(plan, p)
    assert min(scores.values()) <= 0.85, scores


def test_trap_optimum_differs_from_concept():
    sim = SIMULATORS["water_filling_trap"]
    for seed in SEEDS:
        p = sim.params(seed)
        assert sim.normalized(sim.concept_plan(p), p) < 0.5  # following the notes costs a lot
        a, b = sim._vector(sim.optimum(p), p), sim._vector(sim.concept_plan(p), p)
        assert np.abs(a - b).sum() > 0.2 * p["budget"]
        assert {n for pair in p["pairs"] for n in pair} <= set(p["items"])


def test_validate_rejects_malformed_plans():
    wf, kelly, code = SIMULATORS["water_filling"], SIMULATORS["kelly"], SIMULATORS["prefix_code"]
    p, kp, cp = wf.params(1), kelly.params(1), code.params(1)
    assert "allocation" in wf.validate({"alloc": {}}, p)
    assert "unknown" in wf.validate({"allocation": {"nope": 1}}, p)
    assert "non-negative" in wf.validate({"allocation": {p["items"][0]: -1}}, p)
    assert "non-negative" in wf.validate({"allocation": {p["items"][0]: True}}, p)
    assert "below 1" in kelly.validate({"stake_share": {kp["items"][0]: 1.5}}, kp)
    assert "missing" in code.validate({"depth": {cp["items"][0]: 3}}, cp)
    assert "tree" in code.validate({"depth": {k: 1 for k in cp["items"]}}, cp)
    assert "whole" in code.validate({"depth": {k: 2.5 for k in cp["items"]}}, cp)


def text(path):
    return path.read_text()


@pytest.mark.parametrize("concept", ALL)
def test_notes_share_no_task_words(tasks, concept):
    d = tasks[(concept, 1)]
    brief = words(text(d / "instruction.md"))
    long_words = {w for w in brief if len(w) >= 5 and not w.isdigit()} - STOPLIST
    private = d / "environment" / "private"
    for name in ("expert.md", "expert.placebo.md"):
        shared = long_words & words(text(private / name))
        assert not shared, f"{name} reuses brief words {sorted(shared)}"


@pytest.mark.parametrize("concept", CONCEPTS)
def test_placebo_length_within_10_percent(concept):
    notes, placebo = fields.NOTES[concept], fields.PLACEBOS[concept]
    assert 130 <= len(notes.split()) <= 280
    assert abs(len(placebo.split()) - len(notes.split())) <= 0.1 * len(notes.split())


def test_every_concept_has_notes_and_a_distinct_placebo_field():
    assert set(fields.NOTES) == set(fields.PLACEBOS) == set(CONCEPTS)
    assert len({fields.PLACEBOS[c] for c in CONCEPTS}) == len(CONCEPTS)


@pytest.mark.parametrize("concept", ALL)
def test_layout_manifest_and_private(tasks, concept):
    d = tasks[(concept, 1)]
    assert d.name == task_name(concept, 1) == f"inspire-{concept.replace('_', '-')}-0001"
    m = json.loads(text(d / "environment" / "private" / "_harness" / "manifest.json"))
    sim = SIMULATORS[concept]
    assert m["roles"] == ["solver", "expert"] and m["workspace"] == "shared"
    assert m["evaluate"] == {"concept": concept, "params": sim.params(1), "train_noise_seed": m["evaluate"]["train_noise_seed"],
                             "cap": 12}
    assert isinstance(m["evaluate"]["train_noise_seed"], int)
    private = sorted(p.name for p in (d / "environment" / "private").iterdir())
    assert private == ["_harness", "expert.md", "expert.placebo.md"]
    base = concept.removesuffix("_trap")
    assert text(d / "environment" / "private" / "expert.md") == fields.NOTES[base]
    assert text(d / "environment" / "private" / "expert.placebo.md") == fields.PLACEBOS[base]
    assert list((d / "environment" / "workspace").iterdir()) == []
    assert (d / "tests" / "sims.py").read_bytes() == (Path(fields.__file__).parent / "sims.py").read_bytes()
    assert json.loads(text(d / "tests" / "sim_params.json")) == {"concept": concept, "params": sim.params(1)}


@pytest.mark.parametrize("concept", ALL)
def test_brief_rules(tasks, concept):
    d = tasks[(concept, 1)]
    brief = text(d / "instruction.md")
    sim, p = SIMULATORS[concept], SIMULATORS[concept].params(1)
    assert not re.search(r"collaborat|teammate|parallel|together|helper|subagent", brief, re.I)
    assert "evaluate" in brief and "12" in brief and "scripts/submit_to_production.sh" in brief
    assert all(f"R{i}" in brief for i in (1, 2, 3)) and "plan.json" in brief and f'"{sim.key}"' in brief
    assert "half of the way" in brief and "90%" in brief and "baseline plan" in brief
    for row in sim.observables(p):
        assert all(str(v) in brief for v in row.values()), row
    assert text(d / "tests" / "score.py").count("sims") >= 1
    assert "secretary" not in brief.lower()
    if concept.endswith("_trap"):
        assert all(a in brief and b in brief for a, b in p["pairs"])
    # the objective's form is never stated
    assert not re.search(r"log1p|exp\(|sqrt\(|\bformula\b|\bobjective\b", brief)


@pytest.mark.parametrize("concept", ALL)
def test_reference_scores_one_and_start_zero(tasks, concept):
    d = tasks[(concept, 1)]
    ref = score_locally(d, "reference")
    assert ref["reward"] >= 0.98 and ref["requirements"] == {"R1": True, "R2": True, "R3": True}
    assert ref["extras"]["hint_capture"] > 0.99 if not concept.endswith("_trap") else ref["extras"]["hint_capture"] < 0.9
    start = score_locally(d, "start")
    assert start["reward"] == 0 and start["requirements"] == {"R1": False, "R2": False, "R3": False}


def test_score_py_levels_and_invalid(tasks, tmp_path):
    d = tasks[("water_filling", 1)]
    sim, p = SIMULATORS["water_filling"], SIMULATORS["water_filling"].params(1)

    def run(plan_text):
        ws = tmp_path / "ws"
        ws.mkdir(exist_ok=True)
        (ws / "plan.json").write_text(plan_text)
        return score_locally(d, "start", workspace=ws)

    base = run(json.dumps(sim.baseline(p)))
    assert base["reward"] == pytest.approx(0, abs=1e-6) and base["requirements"] == {"R1": True, "R2": False, "R3": False}
    good = {"allocation": {k: v * 0.5 + b * 0.5 for (k, v), b in zip(sim.optimum(p)["allocation"].items(),
                                                                   sim.baseline(p)["allocation"].values())}}
    r = run(json.dumps(good))
    assert 0.5 <= r["reward"] < 0.9 and r["requirements"] == {"R1": True, "R2": True, "R3": False}
    assert r["extras"]["normalized"] == pytest.approx(r["reward"])
    worse = run(json.dumps({"allocation": {k: (1.0 if i == 0 else 0.0) for i, k in enumerate(p["items"])}}))
    assert worse["reward"] == 0 and worse["extras"]["normalized"] < 0 and worse["requirements"]["R1"] is True
    for bad in ("not json", json.dumps({"allocation": {"zzz": 1}}), json.dumps([1, 2])):
        r = run(bad)
        assert r["reward"] == 0 and r["requirements"]["R1"] is False


def test_generate_all_and_deterministic(tmp_path):
    paths = generate_all(tmp_path / "a")
    assert [d.name for d in paths] == [task_name(c, 1) for c in CONCEPTS] + [task_name("water_filling_trap", 1)]
    again = generate("kelly", 1, tmp_path / "b")
    cmp = filecmp.dircmp(paths[CONCEPTS.index("kelly")], again)

    def same(c):
        return not (c.left_only or c.right_only or c.diff_files) and all(same(s) for s in c.subdirs.values())

    assert same(cmp)
