# Coverage progress: 65% -> 90%

Quick log of how I closed the coverage gap. Headline: 65% -> 90.2%.
This is where those points came from.

## Starting point: 65%

After one night of `riscv_random_test` with default weights:

| covergroup | coverage |
|------------|----------|
| cg_opcode  | 88.9%    |
| cg_alu_ops | 81.2%    |
| cg_branch  | 50.0%    |
| cg_regs    | 100.0%   |
| cg_raw     | 18.4%    |
| weighted   | 65.3%    |

`cg_raw` was low because uniform random registers almost never create
back-to-back dependencies. `cg_branch` was stuck at 50% because the
`taken=1` bins don't hit unless branch addresses actually match.

## What moved the needle

- Constrain rd/rs1/rs2 to `[0:15]`: 65% -> 72%. `cg_raw` doubled.
- Add `riscv_raw_seq` with `w_r = 70`, no branches/loads: 72% -> 81%.
- Add `riscv_branch_seq` with `w_branch = 50`: 81% -> 85%. All branch
  opcodes hit, taken-cross still ~60%.
- Python feedback loop: 85% -> 90%. `cov_analyzer.py` flagged 6/12
  empty bins on `cross_br: cp_br_type x cp_taken`. `stim_tuner.py`
  emitted tighter immediate ranges so more branches would match.
  One iteration and `cg_branch` hit 95%, weighted crossed 90%.

## Final state: 90.2%

| covergroup | coverage |
|------------|----------|
| cg_opcode  | 100.0%   |
| cg_alu_ops | 100.0%   |
| cg_branch  | 95.8%    |
| cg_regs    | 100.0%   |
| cg_raw     | 86.0%    |
| weighted   | 90.2%    |

The remaining `cg_raw` gap is specific register-pair bins that never
hit even with the biased sequence. A directed sequence would force
them, but 90% was the project goal so I stopped.

## Lessons

- Dump coverage on day 1, not day 3. First two nights I was running blind.
- The Python analyzer took about an hour to write and saved more than that hunting gaps by hand.
- Watch `iff` guards on covergroups -- my first `cg_branch` sampled every commit and the denominator made the percentage meaningless.
