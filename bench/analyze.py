#!/usr/bin/env python3
"""Auswertung der Bench-Roh-CSV.

Liest measurements*.csv, gruppiert nach (runtime, memory, payload_size, mode),
berechnet n, p50, p95, p99 fuer Init-Duration und Duration. Schreibt
summary.csv und einen Markdown-Report mit Pivot-Tabellen.

Aufruf:
    python3 analyze.py [input.csv] [output_dir]

Defaults:
    input  = ../results/raw/measurements-*.csv (neueste)
    output = ../results/

Standardbibliothek only, keine pip-Dependencies.
"""

from __future__ import annotations

import csv
import glob
import statistics
import sys
from collections import defaultdict
from pathlib import Path
from typing import Sequence

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DEFAULT_INPUT_GLOB = str(PROJECT_ROOT / "results" / "raw" / "measurements-*.csv")
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "results"


def percentile(values: Sequence[float], p: float) -> float | None:
    if not values:
        return None
    s = sorted(values)
    if len(s) == 1:
        return s[0]
    k = (len(s) - 1) * p / 100.0
    lo = int(k)
    hi = min(lo + 1, len(s) - 1)
    if lo == hi:
        return s[lo]
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def load_rows(path: Path) -> list[dict]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def to_float(s: str) -> float | None:
    if s is None or s == "":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def aggregate(rows: list[dict]) -> dict[tuple, dict]:
    groups: dict[tuple, dict] = defaultdict(
        lambda: {"init": [], "dur": [], "billed": [], "mem": []}
    )
    for r in rows:
        key = (r["runtime"], int(r["memory"]), r["payload_size"], r["mode"])
        if (v := to_float(r.get("init_duration_ms", ""))) is not None:
            groups[key]["init"].append(v)
        if (v := to_float(r.get("duration_ms", ""))) is not None:
            groups[key]["dur"].append(v)
        if (v := to_float(r.get("billed_duration_ms", ""))) is not None:
            groups[key]["billed"].append(v)
        if (v := to_float(r.get("max_memory_mb", ""))) is not None:
            groups[key]["mem"].append(v)
    return groups


def fmt(x: float | None, digits: int = 2) -> str:
    if x is None:
        return ""
    return f"{x:.{digits}f}"


def write_summary_csv(groups: dict, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "runtime", "memory_mb", "payload_size", "mode", "n",
            "init_p50_ms", "init_p95_ms", "init_p99_ms",
            "dur_p50_ms", "dur_p95_ms", "dur_p99_ms",
            "billed_p50_ms", "max_mem_p95_mb",
        ])
        for key in sorted(groups.keys()):
            runtime, memory, payload, mode = key
            g = groups[key]
            n = len(g["dur"])
            w.writerow([
                runtime, memory, payload, mode, n,
                fmt(percentile(g["init"], 50)),
                fmt(percentile(g["init"], 95)),
                fmt(percentile(g["init"], 99)),
                fmt(percentile(g["dur"], 50)),
                fmt(percentile(g["dur"], 95)),
                fmt(percentile(g["dur"], 99)),
                fmt(percentile(g["billed"], 50)),
                fmt(percentile(g["mem"], 95), 1),
            ])


def write_markdown_report(groups: dict, out: Path) -> None:
    runtimes = sorted({k[0] for k in groups})
    memories = sorted({k[1] for k in groups})
    payloads = sorted({k[2] for k in groups}, key=_payload_order)

    lines: list[str] = []
    lines.append("# Lambda Cold Start Benchmark Report\n")
    lines.append("Quelle: gruppierte Messungen aus `results/raw/`. ")
    lines.append("Init Duration ist nur in Cold Starts vorhanden, in Warm-Invocations leer.\n")

    # Cold Start INIT_DURATION p50 (ms) Tabelle
    for stat_label, mode, metric, p in [
        ("Cold Start Init Duration p50 (ms)", "cold", "init", 50),
        ("Cold Start Init Duration p95 (ms)", "cold", "init", 95),
        ("Cold Start Total Duration p95 (ms)", "cold", "dur", 95),
        ("Warm Duration p50 (ms)", "warm", "dur", 50),
        ("Warm Duration p99 (ms)", "warm", "dur", 99),
    ]:
        lines.append(f"\n## {stat_label}\n")
        for payload in payloads:
            lines.append(f"\n### Payload {payload}\n")
            header = "| Runtime \\ Memory | " + " | ".join(f"{m} MB" for m in memories) + " |"
            sep = "|---|" + "|".join(["---"] * len(memories)) + "|"
            lines.append(header)
            lines.append(sep)
            for runtime in runtimes:
                row = [runtime]
                for memory in memories:
                    g = groups.get((runtime, memory, payload, mode))
                    if g is None:
                        row.append("-")
                        continue
                    val = percentile(g[metric], p)
                    row.append(fmt(val) if val is not None else "-")
                lines.append("| " + " | ".join(row) + " |")

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")


def _payload_order(s: str) -> int:
    suffix_value = {"k": 1024, "m": 1024 * 1024}
    s = s.lower()
    for suf, mul in suffix_value.items():
        if s.endswith(suf):
            try:
                return int(float(s[:-1]) * mul)
            except ValueError:
                return 0
    try:
        return int(s)
    except ValueError:
        return 0


def find_default_input() -> Path | None:
    matches = sorted(glob.glob(DEFAULT_INPUT_GLOB))
    if not matches:
        return None
    return Path(matches[-1])


def main() -> int:
    if len(sys.argv) >= 2:
        in_path = Path(sys.argv[1])
    else:
        found = find_default_input()
        if not found:
            print(f"Keine Input-CSV gefunden unter {DEFAULT_INPUT_GLOB}", file=sys.stderr)
            return 2
        in_path = found

    out_dir = Path(sys.argv[2]) if len(sys.argv) >= 3 else DEFAULT_OUTPUT_DIR

    print(f"Input:  {in_path}", file=sys.stderr)
    print(f"Output: {out_dir}", file=sys.stderr)

    rows = load_rows(in_path)
    if not rows:
        print("CSV ist leer", file=sys.stderr)
        return 1

    groups = aggregate(rows)
    write_summary_csv(groups, out_dir / "summary.csv")
    write_markdown_report(groups, out_dir / "report.md")
    print(f"summary.csv und report.md geschrieben in {out_dir}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
