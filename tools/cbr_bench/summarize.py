#!/usr/bin/env python3
"""Summarize tools/cbr_bench results.jsonl as Markdown tables (medians of runs).

usage: summarize.py <results.jsonl>
"""

from __future__ import annotations

import json
import statistics
import sys
from collections import defaultdict

IMPL_ORDER = ["v137", "before", "current"]


def pct(values: list[float], q: float) -> float:
    s = sorted(values)
    return s[min(len(s) - 1, int(round(q * (len(s) - 1))))]


def med(values):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None


def fmt(v, digits=0):
    if v is None:
        return "—"
    return f"{v:.{digits}f}"


def main() -> None:
    rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
    by = defaultdict(list)
    for r in rows:
        by[(r["file"], r["scenario"], r["impl"])].append(r)
    files = list(dict.fromkeys(r["file"] for r in rows))
    impls = [i for i in IMPL_ORDER if any(r["impl"] == i for r in rows)]

    def runs(f, s, i):
        return by.get((f, s, i), [])

    print("### Read-through (seq): every page in page order, back to back\n")
    print("| file | build | all pages (s) | page med / p90 / max (ms) | stream opens | peak MB | failures |")
    print("|---|---|---|---|---|---|---|")
    for f in files:
        for i in impls:
            rs = runs(f, "seq", i)
            if not rs:
                continue
            total = med([r["total_ms"] / 1000 for r in rs])
            m = med([statistics.median(r["latencies_ms"]) for r in rs])
            p90 = med([pct(r["latencies_ms"], 0.9) for r in rs])
            mx = med([max(r["latencies_ms"]) for r in rs])
            opens = med([r["stream_opens"] for r in rs])
            rss = med([r["rss_bytes"] / 1e6 for r in rs])
            fails = max(r["failures"] for r in rs)
            print(f"| {f} | {i} | {fmt(total, 2)} | {fmt(m)} / {fmt(p90)} / {fmt(mx)} | "
                  f"{fmt(opens)} | {fmt(rss)} | {fails} |")

    print("\n### Page turns\n")
    print("paced: first 30 pages, one per 300 ms (median / max ms). "
          "jump: page 1 → middle → last → page 1 → ¼ (ms).\n")
    print("| file | build | paced med / max | → middle | → last | → page 1 | → ¼ |")
    print("|---|---|---|---|---|---|---|")
    for f in files:
        for i in impls:
            p, j = runs(f, "paced", i), runs(f, "jump", i)
            if not p and not j:
                continue
            pm = med([statistics.median(r["latencies_ms"]) for r in p])
            px = med([max(r["latencies_ms"]) for r in p])
            steps = [med([r["latencies_ms"][k] for r in j]) if j else None for k in range(1, 5)]
            print(f"| {f} | {i} | {fmt(pm)} / {fmt(px)} | " + " | ".join(fmt(s) for s in steps) + " |")

    print("\n### Open\n")
    print("| file | build | open (ms) | 1st data (ms) | 1st decode (ms) |")
    print("|---|---|---|---|---|")
    for f in files:
        for i in impls:
            rs = runs(f, "open", i)
            if not rs:
                continue
            print(f"| {f} | {i} | {fmt(med([r['open_ms'] for r in rs]), 1)} | "
                  f"{fmt(med([r['latencies_ms'][0] for r in rs]), 1)} | "
                  f"{fmt(med([r['decode_ms'] for r in rs]), 1)} |")


if __name__ == "__main__":
    main()
