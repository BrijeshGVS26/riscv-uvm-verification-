#!/usr/bin/env python3
"""
stim_tuner.py

Second half of the coverage feedback loop.  Takes a list of cov holes
from cov_analyzer.py and emits UVM config_db overrides that bias the
next regression toward the uncovered bins.

The mapping is opcode-specific -- I hard-coded it based on which
covergroup feeds which opclass.  Not elegant, but in practice every
time I add a covergroup I know exactly which sequence weight to bump.

Usage:
    python3 cov_analyzer.py cov.rpt | python3 stim_tuner.py > overrides.f

The output is a list of +uvm_set_config_int= plusargs you pass to the
next run:

    +uvm_set_config_int=*,w_branch,60
    +uvm_set_config_int=*,w_r,50
"""
import json
import sys


# Which coverage holes should bias which sequence weights.
# Keys are coverpoint-group substrings, values are {weight: new_val}.
GROUP_TO_WEIGHT = {
    "cg_branch":  {"w_branch": 60, "w_r": 20, "w_i": 20},
    "cg_alu_ops": {"w_r": 50, "w_i": 40, "w_branch": 0},
    "cg_raw":     {"w_r": 70, "w_i": 20, "w_branch": 5},
    "cg_regs":    {"w_r": 40, "w_i": 40, "w_lui": 10},
}


def pick_strategy(holes):
    """Given the gap list, pick the group with the most holes and
    return its bias weights."""
    by_group = {}
    for h in holes:
        by_group[h["group"]] = by_group.get(h["group"], 0) + 1
    if not by_group:
        return None, {}
    worst = max(by_group, key=by_group.get)
    return worst, GROUP_TO_WEIGHT.get(worst, {})


def main():
    holes = json.load(sys.stdin)
    group, weights = pick_strategy(holes)

    if not weights:
        print("# no actionable holes -- run default regression", file=sys.stderr)
        return

    print(f"# biasing toward {group} ({len(holes)} holes total)", file=sys.stderr)
    for name, val in weights.items():
        print(f"+uvm_set_config_int=*,{name},{val}")


if __name__ == "__main__":
    main()
