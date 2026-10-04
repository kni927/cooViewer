#!/usr/bin/env python3
"""Summarize tools/cbr_bench results.jsonl as Markdown tables (medians of runs).

usage: summarize.py <results.jsonl>

Peak MB is "ru_maxrss / peak physical footprint" of the bench process for
that scenario, medians of runs. ru_maxrss can read far below the memory the
process held (compressed or swapped pages); the footprint counts those.
Results written before the back/idlejump scenarios and counters existed
still summarize; the missing parts are left out.
"""

from __future__ import annotations

import json
import statistics
import sys
from collections import defaultdict

IMPL_ORDER = ["v137", "before", "current"]
BACK_STEPS = ["-3", "-10", "-100", "-200", "-300"]


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
    scenarios = list(dict.fromkeys(r["scenario"] for r in rows))

    def runs(f, s, i):
        return by.get((f, s, i), [])

    def peak(rs):
        """'rss / footprint' MB: ru_maxrss, then the peak physical footprint."""
        rss = med([r["rss_bytes"] / 1e6 for r in rs])
        fp = med([r["footprint_peak_bytes"] / 1e6 if "footprint_peak_bytes" in r else None
                  for r in rs])
        return f"{fmt(rss)} / {fmt(fp)}"

    def jump_steps(rs):
        return [med([r["latencies_ms"][k] for r in rs]) if rs else None for k in range(1, 5)]

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
            fails = max(r["failures"] for r in rs)
            print(f"| {f} | {i} | {fmt(total, 2)} | {fmt(m)} / {fmt(p90)} / {fmt(mx)} | "
                  f"{fmt(opens)} | {peak(rs)} | {fails} |")

    print("\n### Page turns\n")
    print("paced: first 30 pages, one per 300 ms (median / max ms). "
          "jump: page 1 → middle → last → page 1 → ¼ (ms). Peak MB of each.\n")
    print("| file | build | paced med / max | → middle | → last | → page 1 | → ¼ | peak MB paced · jump |")
    print("|---|---|---|---|---|---|---|---|")
    for f in files:
        for i in impls:
            p, j = runs(f, "paced", i), runs(f, "jump", i)
            if not p and not j:
                continue
            pm = med([statistics.median(r["latencies_ms"]) for r in p])
            px = med([max(r["latencies_ms"]) for r in p])
            print(f"| {f} | {i} | {fmt(pm)} / {fmt(px)} | "
                  + " | ".join(fmt(s) for s in jump_steps(j))
                  + f" | {peak(p)} · {peak(j)} |")

    if "back" in scenarios:
        print("\n### Paging back after a read-through (back)\n")
        print("Every page read in page order (untimed for the steps), then −N = N pages "
              "before the last, in turn (ms). — where the book is too short.\n")
        print("| file | build | read-through (s) | " + " | ".join("−" + s[1:] for s in BACK_STEPS)
              + " | stream opens | peak MB | failures |")
        print("|---|---|---|" + "---|" * len(BACK_STEPS) + "---|---|---|")
        for f in files:
            for i in impls:
                rs = runs(f, "back", i)
                if not rs:
                    continue
                cells = []
                for step in BACK_STEPS:
                    vals = [r["latencies_ms"][r["steps"].index(step)]
                            for r in rs if step in r.get("steps", [])]
                    cells.append(fmt(med(vals)))
                warm = med([r.get("warmup_ms", 0) / 1000 for r in rs])
                opens = med([r["stream_opens"] for r in rs])
                fails = max(r["failures"] for r in rs)
                print(f"| {f} | {i} | {fmt(warm, 2)} | " + " | ".join(cells)
                      + f" | {fmt(opens)} | {peak(rs)} | {fails} |")

    if "idlejump" in scenarios:
        print("\n### Jumps after an idle wait (idlejump)\n")
        print("Open, wait without reading, then page 1 → middle → last → page 1 → ¼ (ms).\n")
        print("| file | build | idle (s) | 1st page | → middle | → last | → page 1 | → ¼ | peak MB |")
        print("|---|---|---|---|---|---|---|---|---|")
        for f in files:
            for i in impls:
                rs = runs(f, "idlejump", i)
                if not rs:
                    continue
                first = med([r["latencies_ms"][0] for r in rs])
                idle = med([r.get("idle_ms", 0) / 1000 for r in rs])
                print(f"| {f} | {i} | {fmt(idle, 1)} | {fmt(first)} | "
                      + " | ".join(fmt(s) for s in jump_steps(rs)) + f" | {peak(rs)} |")

    print("\n### Open\n")
    print("| file | build | open (ms) | 1st data (ms) | 1st decode (ms) | peak MB |")
    print("|---|---|---|---|---|---|")
    for f in files:
        for i in impls:
            rs = runs(f, "open", i)
            if not rs:
                continue
            print(f"| {f} | {i} | {fmt(med([r['open_ms'] for r in rs]), 1)} | "
                  f"{fmt(med([r['latencies_ms'][0] for r in rs]), 1)} | "
                  f"{fmt(med([r['decode_ms'] for r in rs]), 1)} | {peak(rs)} |")

    counters = list(dict.fromkeys(k for r in rows if r["scenario"] != "open"
                                for k in r.get("counters", {})))
    if counters:
        print("\n### Archive counters (median of runs; — where the build lacks the counter)\n")
        print("Read right after the scenario's last timed read. Stream opens are the "
              "libarchive streams opened after the open.\n")
        print("| file | scenario | build | stream opens | " + " | ".join(counters) + " |")
        print("|---|---|---|---|" + "---|" * len(counters))
        for f in files:
            for s in scenarios:
                if s == "open":
                    continue
                for i in impls:
                    rs = runs(f, s, i)
                    if not rs:
                        continue
                    cells = [fmt(med([r.get("counters", {}).get(c) for r in rs])) for c in counters]
                    print(f"| {f} | {s} | {i} | {fmt(med([r['stream_opens'] for r in rs]))} | "
                          + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
