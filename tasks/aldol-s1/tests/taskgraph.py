"""Graph-task kit, the pure part: graph.json loading, levels and stages, instruction rendering, output parsing and the
check comparator. Standard library only: write_task ships this file as tests/taskgraph.py (the grader and the
reference's CLI import it), so it must not import anything from collabbench.

graph.json (see the contract): sources and nodes. A node reads sources and upstream nodes; its level is its longest-path
distance from the sources (sources are level 0), computed here from the inputs and never trusted from the file.

Outputs. A node writes one file at output.path, format "json" or "csv". The parsed form of an output is what the
reference functions receive for their upstream nodes and what the comparator walks:
- json: whatever json.loads returns (NaN and Infinity are refused);
- csv: a list of row dicts, one per line under the header, each value coerced ("" -> None, integers, floats, else str).
  A csv node declares output.columns (the header) and output.key (the columns that identify a row).
A reference function returns the JSON-able form (a csv node: a list of row dicts); `roundtrip` serialises and parses it,
so expected and agent outputs always meet in the same parsed form.

Checks. Each node declares check families: {"id", "what", "count", "tolerance", "select", "fields"?}.
- `select` is a "/"-separated path into the parsed output ("*" matches every key of a dict or every item of a list).
  A csv node is keyed first: {"<key1>|<key2>": row}, so "*/anti_slope" is the anti_slope cell of every row.
- Every match in the REFERENCE output is one check. A selected scalar is compared under the family's tolerance. A selected
  dict is compared on `fields` (default: every key); the check passes when all of them do. With tolerance "set" a
  selected list is compared as a set of items (one check).
- A family may restrict its items to rows of the REFERENCE output: "where" (rows matching) and "where_not" (rows not
  matching), each {column: [values]} or a list of such dicts (any one may match), so that one family is one lab fact.
- tolerance: "exact" | "abs X" | "rel P%" | "set" | "rel P% or abs X" (within either). Numbers compare as numbers (1 == 1.0), booleans only with booleans,
  None only with None. A path absent from the agent's output fails its check. Extra keys, rows or items are ignored.
"""

import csv
import io
import json
import math
import re
from collections import deque
from pathlib import Path

KINDS = ("src", "work", "rework", "deliv")
NODE_REQUIRED = ("id", "title", "inputs", "output", "checks")
_INT = re.compile(r"-?[0-9]+")


class GraphError(ValueError):
    """graph.json is not a valid graph."""


# ---- loading, levels, stages -----------------------------------------------------------------------------------------

class Graph:
    def __init__(self, data: dict):
        self.data = data
        self.title = data.get("title", data.get("graph", ""))
        self.name = data["graph"]
        self.sources = {s["id"]: s for s in data.get("sources", [])}
        nodes = data.get("nodes", [])
        self.nodes = {n["id"]: n for n in nodes}
        if len(self.sources) != len(data.get("sources", [])) or len(self.nodes) != len(nodes):
            raise GraphError("duplicate id")
        if set(self.sources) & set(self.nodes):
            raise GraphError(f"ids used by a source and a node: {sorted(set(self.sources) & set(self.nodes))}")
        self.facts = {f["id"]: f for f in data.get("facts", [])}
        self.decisions = {d["id"]: d for d in data.get("decisions", [])}
        self.level = self._levels()
        self.stages = self._stages()
        for nid, n in self.nodes.items():
            if "level" in n and n["level"] != self.level[nid]:
                raise GraphError(f"node {nid}: level {n['level']} in the file, {self.level[nid]} from its inputs")
            n["level"] = self.level[nid]
            for fid in n.get("facts", []):
                if fid not in self.facts:
                    raise GraphError(f"node {nid}: unknown fact {fid}")
            for qid in n.get("decisions", []):
                if qid not in self.decisions:
                    raise GraphError(f"node {nid}: unknown decision {qid}")

    def _levels(self) -> dict[str, int]:
        for nid, n in self.nodes.items():
            for k in NODE_REQUIRED:
                if k not in n:
                    raise GraphError(f"node {nid}: missing {k}")
            for i in n["inputs"]:
                if i not in self.sources and i not in self.nodes:
                    raise GraphError(f"node {nid}: unknown input {i}")
        level = {s: 0 for s in self.sources}
        indeg = {nid: sum(i in self.nodes for i in n["inputs"]) for nid, n in self.nodes.items()}
        ready = deque(nid for nid, d in indeg.items() if d == 0)
        done = 0
        while ready:
            nid = ready.popleft()
            done += 1
            level[nid] = 1 + max((level[i] for i in self.nodes[nid]["inputs"]), default=0)
            for m, n in self.nodes.items():
                if nid in n["inputs"]:
                    indeg[m] -= 1
                    if indeg[m] == 0:
                        ready.append(m)
        if done != len(self.nodes):
            raise GraphError(f"cycle among {sorted(set(self.nodes) - set(level))}")
        return level

    def _stages(self) -> list[list[int]]:
        top = max(self.level.values(), default=0)
        stages = self.data.get("stages") or [[i, i] for i in range(1, top + 1)]
        prev = 0
        for first, last in stages:
            if first != prev + 1 or last < first:
                raise GraphError(f"stages must be contiguous groups of levels starting at 1: {stages}")
            prev = last
        if prev != top:
            raise GraphError(f"stages end at level {prev}, the graph at {top}")
        return [list(s) for s in stages]

    @property
    def n_stages(self) -> int:
        return len(self.stages)

    def last_level(self, stage: int) -> int:
        return self.stages[stage - 1][1]

    def stage_nodes(self, stage: int) -> list[str]:
        """The nodes that stage `stage` exposes: every node of level <= the stage's last level (stages are cumulative;
        graph.json's optional "stages" is a list of [first_level, last_level] pairs, default one level per stage)."""
        last = self.last_level(stage)
        return [nid for nid, n in self.nodes.items() if n["level"] <= last]

    def stage_sources(self, stage: int) -> list[str]:
        return list(self.sources)  # sources are complete from stage 1 on: every file is in the workspace

    def upstream_nodes(self, nid: str) -> list[str]:
        return [i for i in self.nodes[nid]["inputs"] if i in self.nodes]

    def order(self, stage: int) -> list[str]:
        """The stage's nodes with upstream before downstream."""
        out, seen = [], set()

        def visit(nid):
            if nid in seen:
                return
            seen.add(nid)
            for u in self.upstream_nodes(nid):
                visit(u)
            out.append(nid)
        for nid in self.stage_nodes(stage):
            visit(nid)
        return out

    @property
    def max_level(self) -> int:
        return max((n["level"] for n in self.nodes.values()), default=0)


def load_graph(source) -> Graph:
    if isinstance(source, dict):
        return Graph(json.loads(json.dumps(source)))
    return Graph(json.loads(Path(source).read_text()))


# ---- instruction ----------------------------------------------------------------------------------------------------

def render_instruction(g: Graph, stage: int, intro: str = "", reserved: str = "", notes: str = "") -> str:
    """The agent's instruction for a stage: each node's output path, schema and what, and what it reads. Never the facts,
    the decisions or the nodes' `hard` notes."""
    names = g.order(stage)
    lines = [f"# {g.title}", ""]
    if intro.strip():
        lines += [intro.strip(), ""]
    used = [s for s in g.sources if any(s in g.nodes[n]["inputs"] for n in names)]
    lines += ["## Sources", ""]
    for sid in used:
        s = g.sources[sid]
        lines.append(f"- **{sid}**, " + ", ".join(f"`{f}`" for f in s["files"]) + (f": {s['what']}" if s.get("what") else ""))
    unused = [s for s in g.sources if s not in used]
    if unused:
        lines.append("- Also in the workspace, for later steps: " +
                     ", ".join(f"{s} ({', '.join(f'`{f}`' for f in g.sources[s]['files'])})" for s in unused) + ".")
    if notes:
        lines += ["", f"The team's records are in `{notes}`; read them before you start."]
    lines += ["", "## What to produce", "",
              f"Stage {stage} has {len(names)} deliverable{'s' if len(names) != 1 else ''}, each one file under "
              "`/workspace/results/` at the exact path given. A deliverable that reads another one is built from that "
              "file's correct content, so mistakes carry downstream. Each file is scored against a reference "
              "computed from the sources, cell by cell; each deliverable counts equally. Compute with Python if you "
              "like, but the deliverables are the files, not a program.", ""]
    for nid in names:
        n = g.nodes[nid]
        out = n["output"]
        reads = [f"{i} (`{g.sources[i]['files'][0]}`{'...' if len(g.sources[i]['files']) > 1 else ''})"
                 if i in g.sources else f"{i} (`{g.nodes[i]['output']['path']}`)" for i in n["inputs"]]
        units = f" ({n['units']} units, graded separately inside the file)" if n.get("units") else ""
        lines += [f"### {nid}: {n['title']}{units}", "",
                  n.get("what", ""), "",
                  f"- Reads: {', '.join(reads)}",
                  f"- Writes: `/workspace/{out['path']}` ({out['format']})",
                  f"- Format: {out['schema']}", ""]
    if reserved:
        lines += [reserved.strip(), ""]
    return "\n".join(lines).rstrip() + "\n"


# ---- outputs: serialise and parse -------------------------------------------------------------------------------------

def _refuse_constant(name):
    raise ValueError(f"{name} is not valid JSON")


def coerce(text: str):
    t = text.strip()
    if t == "":
        return None
    if _INT.fullmatch(t):
        return int(t)
    try:
        x = float(t)
    except ValueError:
        return text
    return x if math.isfinite(x) else text


def _cell(v) -> str:
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        if not math.isfinite(v):
            raise ValueError("non-finite number")
        return repr(v)
    return str(v)


def serialize(node: dict, obj) -> str:
    out = node["output"]
    if out["format"] == "json":
        return json.dumps(obj, indent=1, allow_nan=False) + "\n"
    cols = out["columns"]
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(cols)
    for row in obj:
        if set(row) - set(cols):
            raise ValueError(f"row has columns outside the header: {sorted(set(row) - set(cols))}")
        w.writerow([_cell(row.get(c)) for c in cols])
    return buf.getvalue()


def parse_output(node: dict, data: bytes | str):
    """The parsed form of an output file; raises ValueError when it is malformed."""
    text = data.decode("utf-8") if isinstance(data, bytes) else data
    out = node["output"]
    if out["format"] == "json":
        return json.loads(text, parse_constant=_refuse_constant)
    rows = list(csv.reader(io.StringIO(text)))
    if not rows or not rows[0]:
        raise ValueError("empty csv")
    header = [h.strip() for h in rows[0]]
    if len(set(header)) != len(header):
        raise ValueError("duplicate column")
    parsed = []
    for r in rows[1:]:
        if not r or all(not c.strip() for c in r):
            continue
        if len(r) != len(header):
            raise ValueError("a row's width differs from the header")
        parsed.append({h: coerce(c) for h, c in zip(header, r)})
    return parsed


def roundtrip(node: dict, obj):
    return parse_output(node, serialize(node, obj))


def keyed(node: dict, parsed):
    """The comparison view of a parsed output: a csv node's rows keyed by their key columns; a duplicate key is malformed."""
    if node["output"]["format"] != "csv":
        return parsed
    key = node["output"]["key"]
    out = {}
    for row in parsed:
        if any(k not in row or row[k] is None for k in key):
            raise ValueError("a row lacks its key")
        k = "|".join(str(row[c]) for c in key)
        if k in out:
            raise ValueError(f"duplicate key {k}")
        out[k] = row
    return out


# ---- the comparator ------------------------------------------------------------------------------------------------------

def parse_tolerance(text: str) -> tuple[str, float]:
    t = text.strip().lower()
    if " or " in t:  # "rel 1% or abs 0.001": a value passes when it is within either
        return "any", [parse_tolerance(part) for part in t.split(" or ")]
    if t in ("exact", "set"):
        return t, 0.0
    m = re.fullmatch(r"abs\s+([0-9.eE+-]+)", t)
    if m:
        return "abs", float(m.group(1))
    m = re.fullmatch(r"rel\s+([0-9.eE+-]+)\s*%", t)
    if m:
        return "rel", float(m.group(1)) / 100
    raise GraphError(f"unknown tolerance {text!r}")


def _is_num(x) -> bool:
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def values_match(want, got, tol: tuple) -> bool:
    kind, t = tol
    if kind == "any":
        return any(values_match(want, got, one) for one in t)
    if isinstance(want, dict):
        return isinstance(got, dict) and all(k in got and values_match(v, got[k], tol) for k, v in want.items())
    if isinstance(want, list):
        if kind == "set":
            if not isinstance(got, list):
                return False
            dump = lambda xs: {json.dumps(x, sort_keys=True) for x in xs}  # noqa: E731
            return dump(want) == dump(got)
        return (isinstance(got, list) and len(got) == len(want)
                and all(values_match(a, b, tol) for a, b in zip(want, got)))
    if want is None or isinstance(want, (bool, str)):
        return type(got) is type(want) and got == want
    if not _is_num(got):
        return False
    if isinstance(got, float) and not math.isfinite(got):
        return False
    if kind == "exact" or kind == "set":
        return got == want
    if kind == "abs":
        return abs(got - want) <= t + 1e-12
    return abs(got - want) <= t * abs(want) + 1e-12


def select(obj, path: str):
    """Yield (concrete path tuple, value) for every match of `path` ("a/*/b") in `obj`."""
    def walk(o, parts, here):
        if not parts:
            yield here, o
            return
        head, rest = parts[0], parts[1:]
        if head == "*":
            items = o.items() if isinstance(o, dict) else enumerate(o) if isinstance(o, list) else ()
            for k, v in items:
                yield from walk(v, rest, here + (str(k),))
        elif isinstance(o, dict) and head in o:
            yield from walk(o[head], rest, here + (head,))
        elif isinstance(o, list) and head.isdigit() and int(head) < len(o):
            yield from walk(o[int(head)], rest, here + (head,))
    yield from walk(obj, [p for p in path.split("/") if p != ""], ())


def lookup(obj, path: tuple[str, ...]):
    """The value at a concrete path, or raise KeyError."""
    for p in path:
        if isinstance(obj, dict) and p in obj:
            obj = obj[p]
        elif isinstance(obj, list) and p.isdigit() and int(p) < len(obj):
            obj = obj[int(p)]
        else:
            raise KeyError(p)
    return obj


def _row_in(row, conds) -> bool:
    """`conds` is a dict {column: [values]} (all must hold) or a list of such dicts (any may hold)."""
    if isinstance(conds, dict):
        conds = [conds]
    return any(isinstance(row, dict) and all(row.get(c) in vals for c, vals in cond.items()) for cond in conds)


def expand_checks(node: dict, expected) -> list[dict]:
    """Every check of a node, from its reference output (parsed form, csv already keyed): one dict per check with the
    family id, the concrete path, the wanted value, the tolerance and the fields compared."""
    out = []
    for fam in node["checks"]["families"]:
        tol = parse_tolerance(fam["tolerance"])
        for path, value in select(expected, fam["select"]):
            if "where" in fam and not _row_in(value, fam["where"]):
                continue
            if "where_not" in fam and _row_in(value, fam["where_not"]):
                continue
            want = value
            if fam.get("fields") and isinstance(value, dict):
                want = {f: value[f] for f in fam["fields"]}
            out.append({"family": fam["id"], "path": path, "want": want, "tol": tol})
    return out


def evaluate(checks: list[dict], got, against=None) -> dict:
    """Run the checks on the agent's keyed output. `against` (a keyed output, the reference re-run on the agent's own
    upstream data) supplies the wanted values instead of each check's own, for the conditional score; a path it lacks fails."""
    per, passed = {}, 0
    for c in checks:
        ok = False
        try:
            want = c["want"] if against is None else lookup(against, c["path"])
            if against is not None and isinstance(c["want"], dict) and isinstance(want, dict):
                want = {f: want[f] for f in c["want"]}
            ok = values_match(want, lookup(got, c["path"]), c["tol"])
        except (KeyError, TypeError):
            ok = False
        fam = per.setdefault(c["family"], [0, 0])
        fam[1] += 1
        fam[0] += ok
        passed += ok
    return {"passed": passed, "total": len(checks), "families": per}


def node_score(node: dict, res: dict) -> float:
    """A node's score from `evaluate`: the mean of its families' scores weighted by each family's declared `count`; a
    family's score is the fraction of its items (rows, keys or cells) that match, so a family over many items gives
    partial credit and a family declared once (count 1) contributes its item fraction."""
    num = den = 0.0
    for fam in node["checks"]["families"]:
        p, t = res["families"].get(fam["id"], [0, 0])
        w = float(fam.get("count", t))
        num += w * (p / t if t else 0.0)
        den += w
    return num / den if den else 0.0


# ---- reference runs --------------------------------------------------------------------------------------------------

def run_reference(g: Graph, ref, src, stage: int) -> dict:
    """Every node output of stage <= `stage` from `ref.node_<id>(up, src)`, in the roundtripped parsed form."""
    outputs: dict = {}
    for nid in g.order(stage):
        fn = getattr(ref, f"node_{nid}", None)
        if fn is None:
            raise NotImplementedError(f"reference has no node_{nid}")
        up = {u: outputs[u] for u in g.upstream_nodes(nid)}
        outputs[nid] = roundtrip(g.nodes[nid], fn(up, Path(src)))
    return outputs


def write_outputs(g: Graph, outputs: dict, out_dir) -> list[Path]:
    paths = []
    for nid, obj in outputs.items():
        p = Path(out_dir) / g.nodes[nid]["output"]["path"]
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(serialize(g.nodes[nid], obj))
        paths.append(p)
    return paths


def reference_cli(ref_module, graph_json, argv=None) -> None:
    """python reference.py <src_dir> <out_dir> --stage S: write every node output of stage <= S under <out_dir>."""
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("src")
    p.add_argument("out")
    p.add_argument("--stage", type=int, required=True)
    a = p.parse_args(argv)
    g = load_graph(graph_json)
    write_outputs(g, run_reference(g, ref_module, a.src, a.stage), a.out)
