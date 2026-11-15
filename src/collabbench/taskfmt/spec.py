"""TaskSpec and write_task: one generated instance as a Harbor 1.4 task directory (design 7.1)."""

import hashlib
import json
import shutil
from dataclasses import dataclass, field
from pathlib import Path

KIT = Path(__file__).resolve().parent / "kit"
ARTIFACTS = ["/workspace", "/snapshots", "/var/log/collab-tripwire"]


@dataclass
class TaskSpec:
    name: str
    track: str
    instruction: str
    workspace_files: dict[str, str]
    private: dict[str, str]  # file name -> text, copied to /opt/collab/private
    manifest: dict  # written to private/_harness/manifest.json
    solution_sh: str  # applies the reference to ${WORKSPACE:-/workspace}
    hidden_files: dict[str, str]  # verifier-side files under tests/ (hidden tests, facts.json, params)
    score_py: str  # tests/score.py: score(workspace: Path) -> {"reward", "requirements", "extras"}
    requirements: list[str]
    reserved_script: str  # workspace-relative path of the tripwire, e.g. scripts/release.sh
    agent_timeout_s: int
    verifier_timeout_s: int = 1800
    cpus: int = 1
    memory_mb: int = 2048
    extra_metadata: dict = field(default_factory=dict)


def _write(path: Path, text: str, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if mode is not None:
        path.chmod(mode)


def _toml_list(items: list[str]) -> str:
    return "[" + ", ".join(json.dumps(i) for i in items) + "]"


def write_task(spec: TaskSpec, out: Path) -> Path:
    d = Path(out) / spec.name
    if d.exists():
        shutil.rmtree(d)
    collab = {"track": spec.track, "requirements": spec.requirements, "reserved_script": spec.reserved_script,
              **spec.extra_metadata}
    meta_lines = "\n".join(f"{k} = {json.dumps(v)}" if not isinstance(v, list) else f"{k} = {_toml_list(v)}"
                           for k, v in collab.items())
    _write(d / "task.toml", f'''schema_version = "1.4"
artifacts = {_toml_list(ARTIFACTS)}

[task]
name = "collabbench/{spec.name}"

[metadata.collab]
{meta_lines}

[agent]
timeout_sec = {float(spec.agent_timeout_s)}

[verifier]
timeout_sec = {float(spec.verifier_timeout_s)}
environment_mode = "separate"

[environment]
cpus = {spec.cpus}
memory_mb = {spec.memory_mb}
''')
    _write(d / "instruction.md", spec.instruction.rstrip() + "\n")
    env = d / "environment"
    nonce = hashlib.sha256(f"collabbench-tripwire:{spec.name}:{json.dumps(spec.extra_metadata, sort_keys=True)}"
                           .encode()).hexdigest()[:24]
    _write(env / "Dockerfile", (KIT / "Dockerfile.env").read_text().replace("{reserved_script}", spec.reserved_script)
           .replace("{tripwire_nonce}", nonce))
    _write(env / "tripwire.sh", (KIT / "tripwire.sh").read_text(), 0o755)
    if not spec.workspace_files:
        raise ValueError(f"{spec.name}: workspace_files is empty; git does not track empty directories, "
                         "so the Dockerfile's COPY workspace/ would have nothing to copy. Add at least one file.")
    for rel, text in spec.workspace_files.items():
        _write(env / "workspace" / rel, text)
    (env / "workspace").mkdir(parents=True, exist_ok=True)
    for rel, text in spec.private.items():
        _write(env / "private" / rel, text)
    _write(env / "private" / "_harness" / "manifest.json", json.dumps(spec.manifest, indent=1))
    _write(d / "solution" / "solve.sh", "#!/bin/bash\nset -euo pipefail\n" + spec.solution_sh, 0o755)
    tests = d / "tests"
    _write(tests / "Dockerfile", (KIT / "Dockerfile.tests").read_text())
    _write(tests / "test.sh", (KIT / "test.sh").read_text(), 0o755)
    for kit_file in ("grade.py", "pytest_score.py"):
        _write(tests / kit_file, (KIT / kit_file).read_text())
    _write(tests / "hidden" / "conftest.py", (KIT / "hidden_conftest.py").read_text())
    _write(tests / "score.py", spec.score_py)
    _write(tests / "tripwire_nonce.txt", nonce + "\n")
    for rel, text in spec.hidden_files.items():
        _write(tests / rel, text)
    if "pytest_score" in spec.score_py:  # pin the hidden test names from the reference run
        from collabbench.taskfmt.localcheck import score_locally
        names = sorted(score_locally(d, "reference").get("tests", {}))
        _write(tests / "hidden" / "expected_tests.json", json.dumps(names, indent=1))
    return d
