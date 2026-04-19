# Functional mismatches caught during UVM verification

Seven real mismatches the scoreboard (or SVA) caught while bringing up the
UVM env. Most of them would have been painful to find from a raw waveform
dump.

## 1 -- x0 not pinned to zero in my ISS

**Found by:** scoreboard, first random test.
**Symptom:** every instruction with rd = x0 (e.g. BEQ/BNE use rd = x0 via
funct7, and NOPs are `ADDI x0,x0,0`) printed a false mismatch. 200+ errors
per test.
**Cause:** my scoreboard's golden ISS stored the write into
`iss_regs[0]` and then compared against the DUT, which always reads x0 = 0.
**Fix:** added `iss_regs[0] = 32'h0;` at the end of `run_iss_one`. Felt
stupid, but it's the kind of thing everyone misses once.

## 2 -- JALR target not masking the LSB

**Found by:** scoreboard on the `riscv_random_test`.
**Symptom:** every JALR to an odd-immediate target showed PC off by 1 vs the
DUT. ~30 failures before I spotted the pattern.
**Cause:** my ISS computed `rs1 + imm` but didn't mask bit 0 (RV32I says
JALR targets must be `(rs1+imm) & ~1`).
**Fix:** added `& ~32'h1`. DUT was correct all along; this was an ISS bug.

## 3 -- Monitor sampled commit_valid on the wrong edge

**Found by:** coverage report showed impossible numbers (more commits than
instructions in memory).
**Symptom:** cg_opcode hit 100% on a 5-instruction program.
**Cause:** my first monitor was sampling on `negedge clk`, which caught the
commit port mid-settling. Every cycle looked like a new retire.
**Fix:** used the `mon_cb` clocking block (posedge-aligned) and added a
"PC actually advanced" check before publishing a transaction.

## 4 -- Load-use hazard caused back-to-back LW/ADD to fail

**Found by:** `riscv_raw_hazard_test`.
**Symptom:** when the random sequence produced `LW x3, 0(x1)` followed by
`ADD x4, x3, x5`, the ADD used the stale x3 value. 3-5 mismatches per
raw-heavy run.
**Cause:** my 3-stage stub core doesn't have a load-use stall (it would in
the full 5-stage core). The UVM env was correctly reporting real DUT
behaviour -- the stub just doesn't do load-use stalls.
**Fix:** documented this in the README as a known limitation of the stub
DUT, and added an SVA (`a_no_load_use`) that fires when this sequence
shows up so I don't mistake it for a different bug. Real fix would be a
load-use stall in the stub; out of scope for this project.

## 5 -- Constrained-random generated illegal funct7 combos

**Found by:** scoreboard reported random "MISMATCH instr=xxxxx" lines that
didn't match any legal opcode.
**Symptom:** ~1% of generated instructions decoded to illegal (funct7=...)
patterns that the DUT chose to treat as NOP but my ISS treated as ADD.
**Cause:** my first `riscv_instr_item` randomized all funct7 bits. Only
funct7 = 0000000 and 0100000 are legal for the RV32I R-type I care about.
**Fix:** added `c_funct` constraint restricting funct7 to legal values per
opcode class. Scoreboard false-mismatch rate dropped to zero.

## 6 -- BLT/BGE comparison was unsigned in the DUT stub

**Found by:** `riscv_branch_test` -- specifically the `cp_br_type::blt`
bin combined with negative rs1.
**Symptom:** BLT of a negative number against a positive number evaluated
to "not taken" in the DUT even though it should be taken.
**Cause:** my first cut of the branch compare used `<` (unsigned) instead
of `$signed(a) < $signed(b)`. The Python tuner hit the exact bin that
triggered it by biasing branches and then covering taken/not-taken
distinctly.
**Fix:** swapped to `$signed()` comparison in the DUT. Took 12 lines to
find, 1 line to fix.

## 7 -- Coverage cross stopped updating after ~100 instructions

**Found by:** coverage report plateauing.
**Symptom:** cg_raw coverage jumped to 45% in the first 100 retires and then
flatlined.
**Cause:** I was sampling covergroups inside the subscriber's `write`, but
using a stale `prev_rd` because I was updating it BEFORE `sample()`. So
every cross sample saw "prev_rd = current_rd", which collapsed the cross.
**Fix:** moved `prev_rd = t.rd` to AFTER the sample call. Coverage started
climbing again. Classic order-of-operations bug.

---

## What I'd do next

- Make the stub core have a proper load-use stall so bug #4 goes away
- Add an async-reset SVA bank (reset in the middle of a random test
  caused some weird monitor state I haven't fully chased down)
- Dump the coverage report in JSON natively so `cov_analyzer.py` doesn't
  have to regex-parse it
