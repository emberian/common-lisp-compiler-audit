# Bug Reports Index

`ACL2-BUG-REPORT.md` at the repository root is **frozen** as Batch 1 (already shared with
ACL2 maintainer Eric Smith; covers `S1`–`S7`, `R1`–`R7`, `H1`, and host notes `C1`–`C2`).
All subsequent findings are accumulated as separate report files in this `reports/`
directory so previously shared URLs remain stable:

- **[ACL2-BATCH-2.md](ACL2-BATCH-2.md)** — ACL2 findings discovered after Batch 1 (`F16`
  `proclaim-dfs` tail multiple-values raw abort on SBCL, `F17` `loop$` binder prematurely
  shadowing `:df` formal in outer target expression, `F13-stobj` stobj `:df` field `ftype`
  surviving `(u)` and faulting on CCL, plus cross-reference to `ME1` trust-tag-gated
  `make-event :expansion?`).
- **[SBCL-F18-ARM64-BRANCH-OVERFLOW.md](SBCL-F18-ARM64-BRANCH-OVERFLOW.md)** — Live SBCL
  2.6.10 darwin-arm64 assembler crash (`The value -262148 is not of type (SIGNED-BYTE 19)`)
  triggered by recursive `defun-inline` expansion.
- **[CCL-CODEGEN-FINDINGS.md](CCL-CODEGEN-FINDINGS.md)** — Four new Clozure CL 1.14
  compiler & backend bug families (`CCL-CG-1` ARM64/ARM32 2D `aset2` / 3D `aref3` register
  clobber at `(safety 3)`; `CCL-CG-2` `nx1-expand-inline-call` copying `space` into `safety`
  and compiling all `inline` functions at `(safety 0)` whenever `(space 0)` is active;
  `CCL-CG-3` unsound `(/ (* c1 x) c2)` float rewrite erasing overflow and flipping `-0.0d0`;
  `CCL-CG-4a/4b` P2 compiler crashes & unsigned bit-offset shift).

Host-level summaries at the repo root:
- `CCL.md` and `CCL-OPTIMIZERS.md` (Clozure CL 1.14 arm64 + x86-64: `CCL-1`, `CCL-2`,
  `CCL-3` 13-operator `require-type` multiple-values/comparison bug, and 4-operator unary
  division value-count bug).
- `SBCL.md` (SBCL 2.6.8–2.6.10 x86-64 + arm64: `SB1` root-fixed in 2.6.10 via `0fd47cc68`,
  and live arm64 branch-overflow `SB2`/`F18`).
