# CCL x86-64 differential audit — reproducers

Companion to `../../X86-CCL.md`. CCL build: `Clozure CL 1.14 (v1.14) linuxx8664`.
Oracle: SBCL 2.6.8. Run every Lisp under `timeout`.

## Headline finding — CCL-3 (soundness, multiple values; arm64 + x86-64)
- `repro-mv.lisp` — self-checking witness. `lx86cl64 --batch --no-init --load repro-mv.lisp`
  exits 1 (bug: `(logior 0 (round 37 10))` returns 2 values under (speed 3)(safety 0));
  SBCL exits 0. `(identity (values 5 6))` and `(logand -1 (values 5 6))` also leak.
- `minimal.lisp`, `minimal2.lisp` — wrapper- and policy-sensitivity characterization.

## Re-tests of the arm64 findings (both arm64-only; do NOT reproduce on x86-64)
- `ccl2-retest.txt` — transcript: `ash` near 2^60 signals correctly on x86-64.
- `ccl1-build.lisp` / `ccl1-test.lisp` — save-application image, purified specialized
  vectors (7 element types) swept after restart; no hang, zero mismatches.
  Build: `lx86cl64 --batch --no-init --load ccl1-build.lisp` then
  `TYPE=u8 ./img1 --batch --no-init --load ccl1-test.lisp` (TYPE in u8 bit u32 u64 s8 sf df).

## Differential fuzzers (deterministic; identical form stream across CCL and SBCL)
- `fuzz.lisp`  — Pass A, arithmetic (2,000,000 seeds).
- `fuzz3.lisp` — Pass B, multiple-values / type-dispatch / sequence+string / struct+array
  / control-flow (500,000 seeds).
- `drive.sh` / `launch.sh` — resumable parallel runner (one PID file per worker).
- `cmp.py` / `cmp3.py` — row-by-row comparators (equality rule in X86-CCL.md).
Run one worker: `START=0 END=2000 lx86cl64 --batch --no-init --load fuzz.lisp`.
