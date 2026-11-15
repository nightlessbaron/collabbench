"""TaskSpec and write_task: one generated instance as a Harbor 1.4 task directory (design 7.1)."""

import hashlib
import json
import shlex
import shutil
from dataclasses import dataclass, field
from pathlib import Path

KIT = Path(__file__).resolve().parent / "kit"
ARTIFACTS = ["/workspace", "/snapshots", "/var/log/collab-tripwire"]
DEFAULT_IMAGE = "public.ecr.aws/docker/library/python:3.12-slim"
DEFAULT_PIP = ["pytest==8.4.1", "numpy==2.2.6"]


@dataclass
class TaskSpec:
    name: str
    track: str
    instruction: str
    workspace_files: dict[str, str | bytes]
    private: dict[str, str]  # file name -> text, copied to /opt/collab/private
    manifest: dict  # written to private/_harness/manifest.json
    solution_sh: str  # applies the reference to ${WORKSPACE:-/workspace}
    hidden_files: dict[str, str | bytes]  # verifier-side files under tests/ (hidden tests, facts.json, params)
    score_py: str  # tests/score.py: score(workspace: Path) -> {"reward", "requirements", "extras"}
    requirements: list[str]
    reserved_script: str  # workspace-relative path of the tripwire, e.g. scripts/release.sh
    agent_timeout_s: int
    verifier_timeout_s: int = 1800
    cpus: int = 1
    memory_mb: int = 2048
    extra_metadata: dict = field(default_factory=dict)
    # Harbor NetworkMode for the agent sandbox and the separate verifier ("no-network", "public" or "allowlist").
    # Harbor defaults to public; the kit does not: images install every dependency at build time.
    network: str = "no-network"
    # Images. Both the agent image and the verifier image start from base_image and pip-install pip_packages (with
    # pip_args) and apt_packages; the agent image also gets git. env_dockerfile / tests_dockerfile are extra Dockerfile
    # instructions for one image only, run before the task files are copied in. workspace_setup is a shell command run
    # in /workspace just before the start commit.
    base_image: str = DEFAULT_IMAGE
    pip_packages: list[str] = field(default_factory=lambda: list(DEFAULT_PIP))
    pip_args: list[str] = field(default_factory=list)
    apt_packages: list[str] = field(default_factory=list)
    env_dockerfile: str = ""
    tests_dockerfile: str = ""
    workspace_setup: str = ""
    # Pinned hidden tests: None runs the reference locally and pins what it reports (synthetic tracks); a list pins
    # exactly that; "collect" writes the harvest marker (the gate's reference run reports every collected test, and
    # `collabbench pin-tests` pins from it), for suites that must not run on this host.
    expected_tests: list[str] | str | None = None
    # Verifier: score at most this many snapshots per label (the last of each label first), in `score_workers`
    # parallel processes, each within `score_timeout_s`. None scores every snapshot (synthetic tracks).
    max_snapshots_per_label: int | None = None
    score_workers: int = 1
    score_timeout_s: int = 900


def _write(path: Path, text: str | bytes, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(text, bytes):
        path.write_bytes(text)
    else:
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
network_mode = {json.dumps(spec.network)}
''')
    _write(d / "instruction.md", spec.instruction.rstrip() + "\n")
    env = d / "environment"
    nonce = hashlib.sha256(f"collabbench-tripwire:{spec.name}:{json.dumps(spec.extra_metadata, sort_keys=True)}"
                           .encode()).hexdigest()[:24]
    pip = " ".join([*spec.pip_args, *(shlex.quote(p) for p in spec.pip_packages)])
    apt = "".join(f" {shlex.quote(p)}" for p in spec.apt_packages)
    block = lambda text: f"\n{text.strip()}\n" if text.strip() else ""  # noqa: E731
    _write(env / "Dockerfile", (KIT / "Dockerfile.env").read_text().replace("{reserved_script}", spec.reserved_script)
           .replace("{tripwire_nonce}", nonce).replace("{base_image}", spec.base_image)
           .replace("{apt_packages}", "".join(f" {shlex.quote(p)}" for p in spec.apt_packages if p != "git"))
           .replace("{pip_packages}", pip).replace("{env_dockerfile}", block(spec.env_dockerfile))
           .replace("{workspace_setup}", f" && {spec.workspace_setup}" if spec.workspace_setup else ""))
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
    apt_install = (f"apt-get update && apt-get install -y --no-install-recommends{apt} "
                   f"&& rm -rf /var/lib/apt/lists/* && ") if apt else ""
    _write(tests / "Dockerfile", (KIT / "Dockerfile.tests").read_text().replace("{base_image}", spec.base_image)
           .replace("{apt_install}", apt_install).replace("{pip_packages}", pip)
           .replace("{tests_dockerfile}", block(spec.tests_dockerfile)))
    _write(tests / "test.sh", (KIT / "test.sh").read_text(), 0o755)
    for kit_file in ("grade.py", "pytest_score.py"):
        _write(tests / kit_file, (KIT / kit_file).read_text())
    _write(tests / "hidden" / "conftest.py", (KIT / "hidden_conftest.py").read_text())
    _write(tests / "score.py", spec.score_py)
    _write(tests / "tripwire_nonce.txt", nonce + "\n")
    if spec.max_snapshots_per_label is not None or spec.score_workers != 1 or spec.score_timeout_s != 900:
        _write(tests / "grade_config.json", json.dumps({"max_snapshots_per_label": spec.max_snapshots_per_label,
                                                        "workers": spec.score_workers,
                                                        "score_timeout_s": spec.score_timeout_s}))
    for rel, text in spec.hidden_files.items():
        _write(tests / rel, text)
    if spec.expected_tests is not None:
        _write(tests / "hidden" / "expected_tests.json", json.dumps(spec.expected_tests, indent=1))
    elif "pytest_score" in spec.score_py:  # pin the hidden test names from the reference run
        from collabbench.taskfmt.localcheck import score_locally
        names = sorted(score_locally(d, "reference").get("tests", {}))
        _write(tests / "hidden" / "expected_tests.json", json.dumps(names, indent=1))
    return d
