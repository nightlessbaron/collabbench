"""Stage-4 (full graph) reward chart: every model and setup per task -> results/s4_rewards.svg.

python3 -I s4_chart.py <runs_dir> <deepseek_results.json> <out.svg>
DeepSeek bars are 3-run means (from deepseek_results.json); frontier bars are single runs read from
runs/opus55*/ and runs/gpt61sol*/ (result.json). Bars with no finished run are drawn as a dotted outline.
"""
import json
import sys
from pathlib import Path

TASKS = [("aldol-s4", "aldol"), ("cohort-s4", "cohort"), ("fiscal-s4", "fiscal")]
# (key, label, colour, team?)  - one colour family per model, darker = team of three
BARS = [("ds:solo", "DeepSeek V4.1 Flash, 1 agent (3M)", "#9db4d6", False),
        ("ds:solo_2B", "DeepSeek, 1 agent (6M)", "#6a8cc2", False),
        ("ds:team_k3", "DeepSeek, team of 3 (3M each)", "#2f5597", True),
        ("opus55:solo", "Claude Opus 5.5, 1 agent", "#f0a868", False),
        ("opus55:team_k3", "Claude Opus 5.5, team of 3", "#c45f0f", True),
        ("gpt61sol:solo", "GPT-6.1 sol, 1 agent", "#8fd1a8", False),
        ("gpt61sol:team_k3", "GPT-6.1 sol, team of 3", "#1f8a4c", True)]


def frontier(runs: Path) -> dict:
    out = {}
    for prefix in ("opus55", "gpt61sol"):
        for res in runs.glob(f"{prefix}*/*--*--*/*__*/result.json"):
            task, cond = res.parent.parent.name.split("--")[:2]
            r = ((json.loads(res.read_text()).get("verifier_result") or {}).get("rewards") or {}).get("reward")
            if r is not None:
                out.setdefault(f"{prefix}:{cond}", {}).setdefault(task, []).append(r)
    return out


def main():
    runs, ds, svg = Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text()), Path(sys.argv[3])
    vals = {}
    for key, *_ in BARS:
        src, cond = key.split(":")
        for task, _ in TASKS:
            if src == "ds":
                cell = ds.get(task.rsplit("-s", 1)[0], {}).get(cond, {}).get("4") or {}
                rs = cell.get("runs") or []
            else:
                rs = frontier(runs).get(key, {}).get(task, [])
            vals[(key, task)] = (sum(rs) / len(rs), len(rs)) if rs else None
    W, H, ml, mt, ph = 980, 470, 56, 56, 260
    gw = (W - ml - 20) / len(TASKS); bw = (gw - 40) / len(BARS)
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" font-family="sans-serif" font-size="12" '
         f'role="img" aria-label="Reward on the full stage-4 graphs by model and setup">',
         f'<rect width="{W}" height="{H}" fill="white"/>',
         f'<text x="{W/2}" y="24" text-anchor="middle" font-size="16" font-weight="bold">'
         f'Reward on the full graphs (stage 4), by model and setup</text>',
         f'<text x="{W/2}" y="42" text-anchor="middle" fill="#555">DeepSeek: mean of up to 3 runs. Frontier: single runs. '
         f'Dotted = still running.</text>']
    for t in (0, 0.25, 0.5, 0.75, 1.0):
        y = mt + ph * (1 - t)
        o.append(f'<line x1="{ml}" x2="{W-20}" y1="{y}" y2="{y}" stroke="#e3e3e3"/>'
                 f'<text x="{ml-6}" y="{y+4}" text-anchor="end">{t:.2f}</text>')
    for i, (task, name) in enumerate(TASKS):
        gx = ml + i * gw + 20
        o.append(f'<text x="{gx + len(BARS)*bw/2}" y="{mt+ph+20}" text-anchor="middle" font-weight="bold" '
                 f'font-size="14">{name}</text>')
        for j, (key, label, col, team) in enumerate(BARS):
            x, v = gx + j * bw, vals[(key, task)]
            if v is None:
                o.append(f'<rect x="{x+2:.1f}" y="{mt+ph-18}" width="{bw-4:.1f}" height="18" fill="none" '
                         f'stroke="{col}" stroke-dasharray="2 2"/>')
                continue
            m, n = v; h = ph * m
            o.append(f'<rect x="{x+2:.1f}" y="{mt+ph-h:.1f}" width="{bw-4:.1f}" height="{h:.1f}" fill="{col}"/>'
                     f'<text x="{x+bw/2:.1f}" y="{mt+ph-h-4:.1f}" text-anchor="middle" font-size="10">{m:.2f}</text>')
    ly = mt + ph + 44
    for j, (key, label, col, team) in enumerate(BARS):
        cx, cy = ml + (j % 3) * 300, ly + (j // 3) * 20
        o.append(f'<rect x="{cx}" y="{cy-10}" width="14" height="12" fill="{col}"/><text x="{cx+20}" y="{cy}">{label}</text>')
    o.append("</svg>")
    svg.write_text("\n".join(o))
    for (key, task), v in sorted(vals.items()):
        print(key, task, v)


if __name__ == "__main__":
    main()
