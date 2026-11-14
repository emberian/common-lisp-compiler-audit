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
  2.6.10 darwin-arm64 assembler crash (`The value -262149 is not of type (SIGNED-BYTE 19)`)
  reduced to a 19-line pure ANSI CL reproducer (`repros/recursive-defun-inline-sbcl-arm64/plain-sbcl.lisp`)
  and traced to unrelaxed PC-relative `LDR Rt, label` / conditional branch offsets in
  `src/compiler/arm64/insts.lisp`.
- **[SBCL-2.6.10-FINDINGS.md](SBCL-2.6.10-FINDINGS.md)** — Four brand-new **LIVE** compiler
  soundness & register-lifetime bugs in SBCL 2.6.10 (`arm64` + `x86-64`), all reproducing at
  `(safety 3)` and two at default `(speed 1)(safety 1)`: `SB-2610-1` pure ANSI CL x86-64
  segfault in `%more-arg-values-skip` (`multiple-value-prog1` + `(values-list (cdr r))`);
  `SB-2610-2` arm64 `%make-simd-pack-single` + x86-64 AVX-512 `%make-simd-pack-512-single`
  off-by-one `:from (:argument ...)` clobber; `SB-2610-3` arm64 `bignum-mult-and-add-4-arg`
  double register clobber corrupting both 64-bit output limbs; `SB-2610-4` backwards
  `(move x y)` across all 8 `%simd-pack{,-256,-512}-int-to-{single,double}` VOPs overwriting
  caller's live input variable.
- **[CCL-CODEGEN-FINDINGS.md](CCL-CODEGEN-FINDINGS.md)** — Four new Clozure CL 1.14
  compiler & backend bug families (`CCL-CG-1` ARM64/ARM32 2D `aset2` / 3D `aref3` register
  clobber at `(safety 3)`; `CCL-CG-2` `nx1-expand-inline-call` copying `space` into `safety`
  and compiling all `inline` functions at `(safety 0)` whenever `(space 0)` is active;
  `CCL-CG-3` unsound `(/ (* c1 x) c2)` float rewrite erasing overflow and flipping `-0.0d0`;
  `CCL-CG-4a/4b` P2 compiler crashes & unsigned bit-offset shift).
- **[ACL2-XDSMITH-GUARDS.md](ACL2-XDSMITH-GUARDS.md)** — Five new ACL2 soundness bug classes
  (7 root causes, all proving `(defthm nil-proved nil)` on both SBCL 2.6.10 and CCL 1.14 with
  `:ttag nil` and `:skip-proofs-seen nil`) + 3 robustness/host-divergence bugs uncovered by
  XDsmith negative-guard fuzzing and guard-obligation source audit (`XDS-S1` plain `FOR`
  `loop$` `of-type` `(member ...)`/`real`/`complex`/`(or)` dropping all loop & body guard
  obligations; `XDS-S2` `flet`/`macrolet` dropping `known-dfs`; `XDS-S3` `mv-let` retry
  dropping `known-dfs`; `XDS-S4` `FOR` `loop$` `of-type double-float`; `XDS-S5a/b/c` `DO`
  `loop$` `known-dfs` + `*cl-cache*` poisoning; `XDS-R1..R3`).
- **[ACL2-STATE-CACHE-RISK.md](ACL2-STATE-CACHE-RISK.md)** — Three new certifiable-book ACL2
  soundness bugs (all proving `(defthm nil-proved nil)` + `(certify-book ... :ttags nil)` on
  both SBCL 2.6.10 and CCL 1.14) + 1 guard-verified `serialize-read` crash + 5 latent source
  defects (`SCR-S1` `(memoize fn :aokp t)` + `apply$` + `defattach` + `:clause-processor`;
  `SCR-S2` default `(memoize fn)` `:aokp nil` + `apply$-lambda` `*cl-cache*` `:GOOD` fast-path
  bypassing `*warrant-reqs*` and `*aokp*`; `SCR-S3` `defattach` failing to propagate or enforce
  `invariant-risk` on constrained stobj/array updaters; `SCR-R1` `(serialize-read file :hons-mode :never)`
  stream desynchronization; `SCR-L1..L5`).
- **[ACL2-PKG-SERIALIZE-CERT.md](ACL2-PKG-SERIALIZE-CERT.md)** — Package, reader, `.sao`/`#Y`
  serializer, and certification boundary audit (`PSC-S1` 13-byte `.sao` V1 `size/idx = 0`
  `(svref arr -1)` OOB read at `(safety 0)` yielding `#<BOGUS object @ #xBE>` outside the ACL2
  universe on single-host CCL and proving `(defthm nil-proved nil)` across SBCL->CCL `#Y` book
  certification with `:ttags nil` and zero `#+`/`#-`; `PSC-S2` `serialize-write` bypassing both
  `*wormholep*` purity during `defthm` and `writes-okp` `:ttags nil` book-certification sandbox;
  `PSC-R1a..d` normed-spine fast-alist `hl-alist-stolen-warning` raw break & FAL decoder bugs;
  `PSC-F1` `read-object-with-case` ignoring `:downcase`/`:invert`; `PSC-R2`/`PSC-R3` `#u`, `#f`,
  and `#!` `hidden-defpkg` reader bugs).
- **[Z3-COMPILER-EQUIVALENCE.md](Z3-COMPILER-EQUIVALENCE.md)** — Z3 SMT equivalence verification
  (67 checks: 15 `SAT` counterexamples, 52 `UNSAT` proofs) across SBCL 2.6.10 and Clozure CL 1.14:
  `Z3-1` SBCL 2.6.10 `inherit-equality-p` (`equality-constraints.lisp:153`) returning `from`
  instead of the equivalence-lattice meet + default-FPU QNaN inversions at `(speed 1)(safety 3)`;
  `Z3-1-ACL2` pure guard-verified ACL2 `:logic` function proving `(defthm nil-proved nil)` on
  SBCL 2.6.10 via `char-equal` (`:ttag nil`, zero books); `Z3-2` SBCL 2.6.10 `same-arg` float
  `derive-type` bogus compile-time `WARNING` + `0.0d0/0.0d0` NaN -> `1.0d0` & signed-zero misfolds;
  `Z3-3` CCL 1.14 ARM64 `FCMP` unordered-`NaN` signed-condition reuse (17 `(safety 3)` miscompilations
  + silent `NaN -> 0/1` `truncate`/`ceiling` corruption, with Z3-verified 0-overhead fix).

Host-level summaries at the repo root:
- `CCL.md` and `CCL-OPTIMIZERS.md` (Clozure CL 1.14 arm64 + x86-64: `CCL-1`, `CCL-2`,
  `CCL-3` 13-operator `require-type` multiple-values/comparison bug, and 4-operator unary
  division value-count bug).
- `SBCL.md` (SBCL 2.6.8–2.6.10 x86-64 + arm64: `SB1` root-fixed in 2.6.10 via `0fd47cc68`,
  and live arm64 branch-overflow `SB2`/`F18`).
