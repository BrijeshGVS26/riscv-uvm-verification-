#!/usr/bin/env python3
"""
run_regression.py

Tiny driver that runs N seeds of a UVM test and collects results.
I use it locally because I got tired of `for seed in $(seq 1 20)` in bash.

Usage:
    python3 run_regression.py --test riscv_random_test --seeds 20

Assumes the simulator is on PATH as `vsim` / `xrun` / whatever; the
actual command is in SIM_CMD below -- adjust for your tool.
"""
import argparse
import subprocess
import re
import sys
from pathlib import Path

SIM_CMD = ["vsim", "-c", "-do", "run -all; quit -f"]  # Questa/ModelSim style

RESULT_LINE = re.compile(r"(UVM_FATAL|UVM_ERROR)\s*:\s*(\d+)")


def run_one(test, seed):
    """Run one sim, return (errors, log_path)."""
    log = Path(f"logs/{test}_{seed}.log")
    log.parent.mkdir(exist_ok=True)
    cmd = SIM_CMD + [f"+UVM_TESTNAME={test}", f"+ntb_random_seed={seed}"]
    with open(log, "w") as fh:
        r = subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT)

    errors = 0
    with open(log) as fh:
        for line in fh:
            m = RESULT_LINE.search(line)
            if m:
                errors = max(errors, int(m.group(2)))
    return errors, log


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", required=True)
    ap.add_argument("--seeds", type=int, default=20)
    args = ap.parse_args()

    results = []
    for s in range(1, args.seeds + 1):
        errors, log = run_one(args.test, s)
        status = "PASS" if errors == 0 else f"FAIL ({errors} errs)"
        print(f"seed={s:3d}  {status}  log={log}")
        results.append((s, errors))

    passed = sum(1 for _, e in results if e == 0)
    print(f"\nTotal: {passed}/{args.seeds} passed")


if __name__ == "__main__":
    main()
