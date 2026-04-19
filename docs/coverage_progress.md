# Coverage progress log: 65% → 90%

Quick log of what I did to close the coverage gap. The headline number
for the project is "65% → 90%", which is what I tell people when they
ask. This file is the honest breakdown of where those points came from.

## Starting point: 65%

After the first night of `riscv_random_test` with balanced weights (the
defaults in `riscv_base_seq`):

| covergroup   | coverage |
|--------------|----------|
| cg_opcode    | 88.9%    |
| cg_alu_ops   | 81.2%    |
| cg_branch    | 50.0%    |
| cg_regs      | 100.0%   |
| cg_raw       | 18.4%    |
| **weighted** | **65.3%** |

cg_raw was way below everything else because random uniform registers
rarely produce back-to-back dependencies. And cg_branch was stuck at 50%
because half the bins are `taken=1` combinations that a random walk
doesn't hit (branches were mostly not-taken because the addresses didn't
match).

## What closed each hole

### Step 1: restrict register range → 72%

Easiest win. Constrained rd/rs1/rs2 to `[0:15]` instead of `[0:31]`.
cg_raw doubled to 41% immediately.

### Step 2: add riscv_raw_seq with biased weights → 81%

Bumped w_r = 70 and removed branches/loads. cg_raw climbed to 88% in a
single 150-instruction run.

### Step 3: add riscv_branch_seq → 85%

Made w_branch = 50. cg_branch got all BEQ/BNE/BLT/BGE/BLTU/BGEU bins.
Still held at ~60% on the taken cross because branches mostly didn't
match.

### Step 4: Python feedback loop → 90%

This is where `cov_analyzer.py` + `stim_tuner.py` actually helped. The
analyzer flagged that `cross_br: cp_br_type x cp_taken` had 6 of 12 bins
at zero. The tuner emitted new weights specifically for the next run --
biased toward R-type with tight immediate ranges so branches were
more likely to be taken.

After one feedback iteration: cg_branch hit 95%, and the weighted total
crossed 90%.

## Final state: 90.2%

| covergroup   | coverage |
|--------------|----------|
| cg_opcode    | 100.0%   |
| cg_alu_ops   | 100.0%   |
| cg_branch    | 95.8%    |
| cg_regs      | 100.0%   |
| cg_raw       | 86.0%    |
| **weighted** | **90.2%** |

cg_raw's last 14% is specific cross bins (e.g. `prev_rd=x15,
cur_rs2=x13` type pairs) that never hit even with the biased sequence.
I could probably force these with a directed sequence but stopped at
90% since that was the project goal.

## What I'd do differently

- Add the covergroups earlier. First two nights I was running blind --
  had no idea what coverage even was because I hadn't dumped a report
  yet.
- Write the Python analyzer on day 1 instead of at the end. It took me
  about an hour to write and saved more than that in manual gap-hunting
  time.
- Use `iff` guards on covergroups more carefully. My first pass had
  cg_branch always sampling on every commit, which made the denominator
  huge and the percentage meaningless.
