#!/usr/bin/env python3
"""
cov_analyzer.py

Reads a UCDB-ish text coverage report (the kind you get from
`vcover report -details`) and prints the coverpoints that are
below a threshold.  Used as the first half of the coverage
feedback loop -- the output of this feeds into stim_tuner.py.

I wrote this because my simulator's GUI cov browser is slow and
I wanted something I could pipe into a script.  Not fancy.

Usage:
    python3 cov_analyzer.py coverage.rpt [--threshold 80]

Output (JSON to stdout):
    [
      {"group": "cg_raw", "bin": "cross_raw_rs1::x3,x7", "hits": 0},
      {"group": "cg_branch", "bin": "cp_br_type::bgeu", "hits": 2},
      ...
    ]
"""
import argparse
import json
import re
import sys


COV_LINE = re.compile(r"^\s*(?P<group>\w+)::(?P<bin>[^\s]+)\s+(?P<hits>\d+)")


def parse_report(path):
    """Very small parser for 'group::bin   hits' style lines."""
    rows = []
    with open(path) as fh:
        for line in fh:
            m = COV_LINE.match(line)
            if not m:
                continue
            rows.append({
                "group": m["group"],
                "bin": m["bin"],
                "hits": int(m["hits"]),
            })
    return rows


def find_holes(rows, threshold):
    """Return bins whose hit count is below the threshold."""
    return [r for r in rows if r["hits"] < threshold]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("report", help="coverage report file")
    ap.add_argument(
        "--threshold", type=int, default=1,
        help="bins with fewer hits than this count as holes"
    )
    args = ap.parse_args()

    rows = parse_report(args.report)
    holes = find_holes(rows, args.threshold)

    # Print a short human summary to stderr and the JSON gap list to stdout
    # (so you can pipe: python cov_analyzer.py rpt | python stim_tuner.py)
    total = len(rows)
    hit = sum(1 for r in rows if r["hits"] > 0)
    pct = (hit / total * 100.0) if total else 0.0
    print(f"[cov_analyzer] {hit}/{total} bins hit ({pct:.1f}%), {len(holes)} below threshold",
          file=sys.stderr)

    json.dump(holes, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
