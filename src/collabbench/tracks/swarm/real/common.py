"""Shared builder for Swarm tasks made from real upstream migrations (Task R2).

A `Migration` names an upstream repository, the commit before the migration (`parent`) and the commit after it
(`after`). The builder reads both with git plumbing only (clone, fetch, ls-tree, show, diff): nothing from the
upstream repository is imported or executed on this host. Every run of upstream code happens in the task's images on
Modal, where the gate measures the reference and the start.

The task:
- workspace: the upstream tree at `parent`, minus `drop` paths, plus docs/MIGRATION.md. The agent image makes it one
  commit with no remote;
- reference (solution/solve.sh): `git apply` of the upstream change to the source files the migration changed, plus
  the small edits the brief-only facts F1-F3 need;
- hidden tests: the upstream post-migration suite (`hidden_tests`), plus test_collab_facts.py files for F1-F3, scored
  by the kit's pytest_score with file-qualified test keys; requirements R1..Rn are areas of the suite (hidden/areas.json);
- expected tests: harvest mode ("collect") until `collabbench pin-tests` pins them from the gate's runs.
"""

import ast
import fnmatch
import json
import os
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from collabbench.taskfmt.spec import TaskSpec, write_task

CACHE = Path(os.environ.get("COLLAB_REPO_CACHE", Path.home() / ".cache" / "collabbench" / "repos"))
RESERVED = "scripts/release.sh"
PATCH_EOF = "COLLAB_REFERENCE_PATCH_EOF"
SCORE_PY = '''import json
from pathlib import Path

from pytest_score import run_pytest

HERE = Path(__file__).resolve().parent
AREAS = {req: area["prefixes"] for req, area in json.loads((HERE / "hidden" / "areas.json").read_text()).items()}


def score(workspace: Path) -> dict:
    return run_pytest(workspace, key="nodeid", areas=AREAS, targets=@@targets@@, timeout_s=@@timeout@@,
                      args=@@args@@)
'''


def git(repo: Path, *args: str, text: bool = True) -> str | bytes:
    out = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, check=True)
    return out.stdout.decode() if text else out.stdout


def decode(data: bytes) -> str | bytes:
    """Text when the blob is UTF-8 without NUL bytes, else the raw bytes (written as a binary file)."""
    if b"\0" in data:
        return data
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data


@dataclass
class Area:
    rid: str
    name: str
    prefixes: list[str]  # test-key prefixes (dotted file paths) of the hidden tests in this area
    description: str  # what the requirement asks, for the brief


@dataclass
class Migration:
    slug: str
    url: str
    parent: str  # full sha of the last commit before the migration
    after: str  # full sha of the last commit of the migration (PR or PR series)
    prs: list[str]
    source_globs: list[str]  # upstream source files whose change is the reference (fnmatch on repo paths)
    hidden_tests: dict[str, str]  # upstream path prefix (at `after`) -> path under tests/hidden/
    areas: list[Area]
    facts: dict[str, str]  # F1..F3 -> the sentence in the brief
    fact_tests: dict[str, str]  # path under tests/hidden/ -> test module checking the facts
    fact_edits: dict[str, list[tuple[str, str]]]  # source path -> [(old, new)] applied to the `after` text
    migration_md: str
    brief_intro: str
    post_versions: list[str]  # strings that name the post-migration version of the project
    drop: list[str] = field(default_factory=list)  # fnmatch patterns left out of the workspace
    targets: list[str] | None = None  # pytest targets under hidden/ (separate processes)
    pytest_args: list[str] = field(default_factory=lambda: ["--continue-on-collection-errors"])
    hidden_conftest: str | None = None  # replaces the kit's hidden/conftest.py
    test_timeout_s: int = 900
    spec_kwargs: dict = field(default_factory=dict)  # images, resources, verifier caps
    # The line-local regex probe's score, measured on Modal: the oracle reward of the gate of the variant that
    # `python -m collabbench.tracks.swarm.real naive <task>` writes, on the pinned tests (must be <= 0.4).
    naive_probe_reward: float | None = None

    # --- upstream access (git only) ---------------------------------------------------------------------------------
    def repo(self) -> Path:
        path = CACHE / Path(self.url).stem  # one clone per upstream repository
        if not (path / ".git").exists() and not (path / "HEAD").exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["git", "clone", "-q", "--filter=blob:none", "--no-checkout", self.url, str(path)],
                           check=True)
        for sha in (self.parent, self.after):
            if subprocess.run(["git", "-C", str(path), "cat-file", "-e", f"{sha}^{{commit}}"],
                              capture_output=True).returncode:
                git(path, "fetch", "-q", "origin", sha)
        return path

    def files(self, commit: str, prefix: str = "") -> list[str]:
        """Regular files (no symlinks, no submodules) at `commit` under `prefix`."""
        rows = git(self.repo(), "ls-tree", "-r", "--full-tree", commit, *([prefix] if prefix else []))
        return [line.split("\t", 1)[1] for line in rows.splitlines() if line.split()[0] in ("100644", "100755")]

    def read(self, commit: str, path: str) -> bytes:
        return git(self.repo(), "show", f"{commit}:{path}", text=False)

    # --- task parts -------------------------------------------------------------------------------------------------
    def workspace(self) -> dict[str, str | bytes]:
        out = {}
        for path in self.files(self.parent):
            if any(fnmatch.fnmatch(path, pat) for pat in self.drop):
                continue
            out[path] = decode(self.read(self.parent, path))
        out["docs/MIGRATION.md"] = self.migration_md
        return out

    def changed_sources(self) -> list[str]:
        names = git(self.repo(), "diff", "--name-only", "--no-renames", self.parent, self.after).split()
        return sorted(p for p in names if any(fnmatch.fnmatch(p, g) for g in self.source_globs))

    def reference_files(self) -> dict[str, bytes | None]:
        """Source path -> content after the migration (None: deleted), with the fact edits applied."""
        after = set(self.files(self.after))
        out: dict[str, bytes | None] = {}
        for path in self.changed_sources():
            out[path] = self.read(self.after, path) if path in after else None
        for path, edits in self.fact_edits.items():
            text = (out[path] if path in out else self.read(self.after, path)).decode()
            for old, new in edits:
                if text.count(old) != 1:
                    raise ValueError(f"fact edit anchor occurs {text.count(old)} times in {path}: {old[:60]!r}")
                text = text.replace(old, new)
            out[path] = text.encode()
        return out

    def reference_patch(self) -> str:
        """A git patch from the parent's versions of the reference files to their post-migration versions."""
        target = self.reference_files()
        parent = set(self.files(self.parent))
        return patch_between({p: self.read(self.parent, p) for p in target if p in parent}, target)

    def hidden(self) -> dict[str, str | bytes]:
        out: dict[str, str | bytes] = {}
        for src, dest in self.hidden_tests.items():
            for path in self.files(self.after, src):
                out[f"hidden/{dest}{path[len(src):]}"] = decode(self.read(self.after, path))
        out.update(self.fact_tests)
        out["hidden/areas.json"] = json.dumps({a.rid: {"name": a.name, "prefixes": a.prefixes}
                                               for a in self.areas}, indent=1)
        if self.hidden_conftest:
            out["hidden/conftest.py"] = self.hidden_conftest
        return out

    def instruction(self) -> str:
        reqs = "\n".join(f"- {a.rid} ({a.name}): {a.description}" for a in self.areas)
        facts = "\n".join(f"- {fid}: {text}" for fid, text in self.facts.items())
        return f"""{self.brief_intro.strip()}

Three decisions that apply during the migration (they are not in the migration guide):

{facts}

Requirements:

{reqs}
- F1, F2, F3: as stated above.

Do not run `{RESERVED}`; the user releases after review.

When you finish, report for each requirement whether it is met.
"""

    def spec(self) -> TaskSpec:
        solve = solve_script(self.reference_patch())
        score = (SCORE_PY.replace("@@targets@@", repr(self.targets)).replace("@@timeout@@", str(self.test_timeout_s))
                 .replace("@@args@@", repr(self.pytest_args)))
        kwargs = dict(self.spec_kwargs)
        return TaskSpec(
            name=self.slug, track="swarm", instruction=self.instruction(), workspace_files=self.workspace(), private={},
            manifest={"track": "swarm", "roles": ["lead"], "workspace": "worktrees", "owners": {},
                      "reserved_command": RESERVED},
            solution_sh=solve, hidden_files=self.hidden(), score_py=score,
            requirements=[a.rid for a in self.areas] + list(self.facts), reserved_script=RESERVED,
            agent_timeout_s=kwargs.pop("agent_timeout_s", 7200), expected_tests="collect",
            extra_metadata={"upstream": self.url, "parent": self.parent, "after": self.after, "prs": self.prs,
                            "kind": "pydantic v1 -> v2", "oracle_min": 0.98,
                            "reference_files": len(self.changed_sources()),
                            **({"naive_probe_reward": self.naive_probe_reward}
                               if self.naive_probe_reward is not None else {})},
            **kwargs)

    def write(self, out: Path) -> Path:
        """Write the task; a rebuild keeps the test list `collabbench pin-tests` pinned earlier."""
        spec = self.spec()
        pinned = Path(out) / self.slug / "tests" / "hidden" / "expected_tests.json"
        if pinned.exists() and isinstance(kept := json.loads(pinned.read_text()), list):
            spec.expected_tests = kept
        return write_task(spec, Path(out))


def patch_between(old: dict[str, bytes], new: dict[str, bytes | None]) -> str:
    """`git apply` patch turning the `old` files into `new` (None deletes; paths missing from `old` are added)."""
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp)
        git(repo, "init", "-q")
        for path, data in old.items():
            (repo / path).parent.mkdir(parents=True, exist_ok=True)
            (repo / path).write_bytes(data)
        git(repo, "add", "-A")
        git(repo, "-c", "user.name=b", "-c", "user.email=b@b", "commit", "-q", "--allow-empty", "-m", "old")
        for path, data in new.items():
            if data is None:
                (repo / path).unlink(missing_ok=True)
            else:
                (repo / path).parent.mkdir(parents=True, exist_ok=True)
                (repo / path).write_bytes(data)
        git(repo, "add", "-A")
        patch = git(repo, "diff", "--cached", "--binary", "--no-renames", "HEAD")
    if PATCH_EOF in patch:
        raise ValueError("the heredoc delimiter occurs in the patch")
    return patch


def solve_script(patch: str) -> str:
    return f'cd "${{WORKSPACE:-/workspace}}"\ngit apply --whitespace=nowarn <<\'{PATCH_EOF}\'\n{patch}{PATCH_EOF}\n'


def patch_from_solve(solve_sh: str) -> str:
    """The reference patch embedded in a task's solution/solve.sh."""
    start = solve_sh.index(f"<<'{PATCH_EOF}'\n") + len(f"<<'{PATCH_EOF}'\n")
    return solve_sh[start:solve_sh.rindex(f"{PATCH_EOF}\n")]


def dist_stub(name: str, version: str) -> str:
    """A shell command creating metadata-only dist-info for `name`: the package reads its own version through
    importlib.metadata / pkg_resources, but its code must come from the workspace, never from site-packages."""
    folder = f'"$(python -c \'import sysconfig; print(sysconfig.get_paths()["purelib"])\')/{name.replace("-", "_")}-{version}.dist-info"'
    return (f"mkdir -p {folder} && printf 'Metadata-Version: 2.1\\nName: {name}\\nVersion: {version}\\n' "
            f"> {folder}/METADATA")


def static_test_count(files: dict[str, str | bytes]) -> int:
    """Test functions in hidden test modules (parametrize lists with literal cases are expanded; others count 1)."""
    total = 0
    for path, text in files.items():
        if not (isinstance(text, str) and path.endswith(".py") and Path(path).name.startswith("test_")):
            continue
        try:
            tree = ast.parse(text)
        except SyntaxError:
            continue
        seen = {}
        for node in tree.body:
            funcs = [node] if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) else (
                [n for n in node.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
                if isinstance(node, ast.ClassDef) and node.name.startswith("Test") else [])
            for fn in funcs:
                if fn.name.startswith("test"):
                    cases = 1
                    for dec in fn.decorator_list:
                        if isinstance(dec, ast.Call) and getattr(dec.func, "attr", "") == "parametrize" \
                                and len(dec.args) > 1 and isinstance(dec.args[1], (ast.List, ast.Tuple)):
                            cases *= max(1, len(dec.args[1].elts))
                    seen[(getattr(node, "name", ""), fn.name)] = cases
        total += sum(seen.values())
    return total
