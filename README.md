# Coverage-driven UVM verification of a RISC-V core (with Python feedback)

A full UVM-1.2 verification environment targeting a 3-stage RV32I core.
Sequence / driver / monitor / scoreboard are all conventional UVM
components; the scoreboard runs a tiny in-class ISS and compares
register writes against the DUT. A pair of Python scripts close the
coverage-feedback loop: one parses the coverage report for holes, the
other emits biased sequence weights for the next regression run.

## About

I built this as the verification companion to my RV32I core project
(`riscv-cpu-sv` on my profile). I wanted to work through the full UVM
pipeline end-to-end -- factory, phases, analysis ports, config_db,
covergroups, the works. Used my own core as the DUT so I had something
real to verify. The ISS in the scoreboard is intentionally
hand-written so I understood every instruction it executes.

The coverage-feedback-loop idea came out of frustration: I had a
covergroup sitting at 65% and no obvious way to climb. Writing a quick
Python script that parses the report, finds the biggest hole, and
suggests new weights for the next run was the project I enjoyed most.
It's not a sophisticated ML thing -- just an if/else tree based on which
group has the most unhit bins -- but it was enough to go from 65% to
90% in about 3 iterations.

## What's verified

- Full UVM-1.2 env: sequence, sequencer, driver, monitor, scoreboard,
  coverage collector, agent, env (8 class files + package)
- 3 test classes: random, RAW-hazard-focused, branch-focused
- In-scoreboard ISS modeling R/I/L/S/B/JAL/JALR/LUI/AUIPC opcodes
- 5 covergroups with ~35 coverpoints total -- opcodes, ALU ops,
  branches, register usage, RAW hazard cross
- **65% → 90% coverage** after Python-guided stimulus retuning
  (`docs/coverage_progress.md`)
- **7 functional mismatches found and fixed** during bring-up -- full
  write-up in `docs/bugs_found.md`
- 20-seed regression script in Python

## Layout

```
rtl/
  riscv_core_stub.sv       -- simplified 3-stage RV32I DUT

uvm/
  riscv_pkg.sv             -- package that includes everything below
  riscv_if.sv              -- virtual interface
  riscv_transaction.sv     -- riscv_instr_item + riscv_commit_item
  riscv_sequence.sv        -- base + RAW + branch sequences
  riscv_driver.sv          -- writes instrs into imem, releases reset
  riscv_monitor.sv         -- snoops commit port
  riscv_scoreboard.sv      -- ISS + compare
  riscv_coverage.sv        -- 5 covergroups
  riscv_agent.sv
  riscv_env.sv

tests/
  riscv_base_test.sv
  riscv_random_test.sv
  riscv_raw_hazard_test.sv
  riscv_branch_test.sv

tb/
  tb_top.sv                -- clock, reset, DUT, memory model, UVM kickoff

python/
  cov_analyzer.py          -- parses cov report, finds holes, JSON out
  stim_tuner.py            -- turns holes into UVM config_db overrides
  run_regression.py        -- sweeps N seeds of a given test

docs/
  bugs_found.md            -- 7 functional mismatches, how I caught them
  coverage_progress.md     -- 65% -> 90% journey in detail
```

## Run

Needs a UVM-1.2-capable simulator (Questa / VCS / Xcelium). iverilog
doesn't compile UVM so the TB won't run there -- I develop on my
university's Questa install. Example command:

```
vsim -c \
    +UVM_TESTNAME=riscv_random_test \
    +UVM_VERBOSITY=UVM_LOW \
    -do "run -all; quit -f" \
    rtl/*.sv uvm/riscv_pkg.sv tb/tb_top.sv
```

Or run the 20-seed regression:

```
python3 python/run_regression.py --test riscv_random_test --seeds 20
```

Python feedback loop (after a cov report is produced):

```
python3 python/cov_analyzer.py coverage.rpt --threshold 1 \
    | python3 python/stim_tuner.py > overrides.f
# then re-run with: vsim -f overrides.f ...
```

## DUT scope

The DUT is a **3-stage simplified subset** of RV32I, not my full
5-stage core. IF -> EX (decode+execute+mem) -> WB. This keeps the
verification focused on the UVM env rather than pipeline edge cases.

Known limitations I accepted:
- No load-use stall in the stub (bug #4 in bugs_found.md)
- LW/SW only -- no LB/LH/LBU/LHU/SB/SH
- No CSRs, no ECALL/EBREAK
- No mult/div

For the full 5-stage pipelined core, see my `riscv-cpu-sv` repo.

## Student notes

Things that took longer than they should have (so maybe my notes here
save someone else some time):

- `uvm_config_db` is extremely unforgiving about hierarchical paths.
  My first set/get pair silently failed for a whole day because I had
  `"*"` on one end and `"env.agt.*"` on the other.
- You need `\`uvm_object_utils` (macro) registered for factory
  overrides to find your class. Missed this on the sequence class and
  spent an afternoon confused about why `type_id::create` returned
  null.
- Coverage reports look impressive at "92%" but that's 92% of the
  bins you asked about. Adding a new covergroup can _drop_ your
  coverage percentage even though you're covering more. Worth
  versioning your covergroup list alongside your numbers.
- The simulator spews pages of UVM report summary at the end of each
  run. The thing you actually care about is the `UVM_FATAL` /
  `UVM_ERROR` counts at the very end. Everything else is noise.

## What I'd add next

- Replace the ad-hoc coverage report format with a proper UCDB loader
  (via `libucdb` or `xmcoverage -summary`).
- Plug in riscv-dv or riscv-arch-test for a proper compliance-style
  regression alongside my custom tests.
- Auto-diff the DUT commit stream against a `spike` log so the
  scoreboard's ISS can be retired.
- Reset-in-the-middle testing -- right now I only reset at sim start.
