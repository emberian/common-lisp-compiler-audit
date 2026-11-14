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
- **[ACL2-WORLD-ROLLBACK.md](ACL2-WORLD-ROLLBACK.md)** — World-rollback & raw-side-table leak
  audit across `encapsulate` `local`, `:u`, failed `include-book`, and `make-event` (`WRB-S1`
  shallow `*user-stobj-alist*` snapshot aliasing `parent.k1` and `parent.k2` via `swap-stobjs`,
  certifying `NIL` with `:ttags nil`; `WRB-S2` child stobj retraction mutating `stobj-table`
  `tbl-keys`/`tbl-count` without `memoize-flush`, certifying `NIL` with `:ttags nil`; `WRB-S3`
  `hcomp-restore-defs` omitting `*the-live-<stobj>*` `redundant-raw-lisp-discriminator` on failed
  `include-book`, proving `NIL` with zero `memoize`/`apply$`/`defattach`; `WRB-S4` raw `defstobj`
  `(defg <st-lst> nil)` wiping stobj memo-flush list across `local` `include-book`, certifying
  `NIL` with `:ttags nil`; plus `WRB-R1..R3` raw Lisp crashes & `redef!` gensym desync).
- **[ACL2-PROVER-KERNEL.md](ACL2-PROVER-KERNEL.md)** — Pure-kernel prover, waterfall, proof-builder,
  meta-extract, and warrant-theory audit (**6 pure-kernel `NIL` proofs** `PK-S1..S6` on both SBCL
  & CCL with `:ttag nil`, zero books, zero stobjs, zero raw Lisp, plus 1 evaluation-theory /
  attachment-consistency refutation `PK-E1` and 5 minor kernel defects `PK-M1..M5`: `PK-S1`
  `type-set-relieve-hyps` free-var backtracking wiping forced `ttree` `'assumption` tags; `PK-S2`
  `relieve-hyps1-unify-subst-lst` `bind-free` candidate advance wiping forced `ttree` `'assumption`
  tags; `PK-S3` `meta-extract-contextual-fact` inheriting forced `type-alist`/`pot-lst` entries via
  `mfc` and dropping `ttree`; `PK-S4` proof-builder `:apply-linear` leaking unreachable `IF`-branch
  `governors` into top-level `:hyps`; `PK-S5` `encapsulate` Pass-2 `local` warrant world-drift in
  `(:guard-theorem fn)`; `PK-S6` unrestricted post-bootstrap `badge-table` reset abandoning warrants).
- **[ACL2-KERNEL-DEEP.md](ACL2-KERNEL-DEEP.md)** — Wave-3 audit & mechanical fuzzing blueprint for
  provisional certification (`pcert`), `hcomp` `defconst` elision, patterned congruence/`geneqv`,
  `:outside-inside`/`rewrite-quoted-constant`, `defchoose`/`defun-sk` + `:functional-instance`, and
  hint/parallel boundaries (`KD-1` `hcomp-elided-defconst-alist2` vs `subst-by-position-eliding-defconst2`
  wrapper desync on `with-output`/`with-prover-step-limit`/`with-guard-checking-event` crashing
  compiled `include-book`; `KD-2` `translate-functional-substitution` omitting `(logicp fn2 wrld)`
  and crashing `expand-abbreviations`; `KD-3` `certify-book :pcert :complete` mtime-only promotion
  ignoring sub-book certificate annotation changes).
- **[ACL2-FV-ENGINES.md](ACL2-FV-ENGINES.md)** — Community-book clause processors & `defttag`
  FV solver bridges (`FV-1` `centaur/misc/fast-alist-pop-raw.lsp` omitting `'invariant-risk` on
  `fast-alist-pop*`, proving `NIL`; `FV-2` `clause-processors/SULFA` `eriks-ht-*` raw/logic
  hash-table mismatch proving `NIL`; `FV-3` `projects/smtlink` `ACL2_to_Z3.py` conflating booleans
  with `0`/`1` across 8 ground ops; `FV-4` `SMTLink` case/package folding + stale `a.symbol-index`
  collapsing distinct quoted symbols to `"gensym_0"`; `FV-5` `SMTLink` uninterpreted-symbol Python
  injection spoofing `"proved"`; `FV-6` `centaur/satlink` `"s UNSATISFIABLE"` prefix match &
  exit-code `1`/`139` acceptance; plus 4-target mechanical fuzzing blueprint; `:ttags nil` verified
  cores of `GL`, `FGL`, and `clause-processors/*` audited clean).
- **[HOST-COMPILERS-WAVE3.md](HOST-COMPILERS-WAVE3.md)** — Nine zero-UB host-compiler bugs across
  SBCL 2.6.10 (`HC-W3-1..5`, all at `(safety 3)`) and Clozure CL 1.14 (`HC-W3-6..9`), including
  **two more pure guard-verified ACL2 `(defthm nil-proved nil)` proofs on SBCL 2.6.10**: `HC-W3-1`
  ARM64 `srctran.lisp:4084` `ash-inverted` `(:not (integer * 0))` subtype-negation bug + `arm64/arith.lisp`
  `LSL` `|x|>=64` (`(logand #xffffffffffffffff (ash 1 (- (the integer x))))` returning `0` at `x=-1`
  and proving `NIL` in ACL2); `HC-W3-2` ARM64/x86-64 `constraint-back.lisp:505` `char-code` `eq`
  non-singleton range negation (proving `NIL` in ACL2); `HC-W3-3` Unicode titlecase `char-equal`
  asymmetry; `HC-W3-4` `(set-exclusive-or x x) => x`; `HC-W3-5` `(reduce #'logior #() ...)` wrong
  `derive-type`; plus CCL 1.14 `x862-vset1` misplaced paren silently dropping `(safety 3)` 64-bit
  stores at `#x10000000` (`HC-W3-8`), `(complex single-float)` register clobber (`HC-W3-6`),
  for-effect `bad regspec: NIL` compiler crashes (`HC-W3-7`), and x86-64 `COMISD` `NaN` (`HC-W3-9`).
- **[ACL2-ON-SBCL-2.6.10-SOUNDNESS.md](ACL2-ON-SBCL-2.6.10-SOUNDNESS.md)** — Focused ACL2-maintainer
  digest consolidating the **three pure `:logic`-mode proofs of `NIL` in ACL2 caused by SBCL 2.6.10
  `(safety 3)` compiler bugs** (`HC-W3-1` modular `ash-inverted`, `HC-W3-2` `char-code` `constraint-back`,
  and `Z3-1-ACL2` `char-equal` `inherit-equality-p`), complete with minimal 16–22 line ACL2 scripts
  and ready-to-drop `acl2-check.lisp` boot-time sanity assertions.
- **[ACL2S-AUDIT.md](ACL2S-AUDIT.md)** — ACL2s (`books/acl2s/`) security, contract, and termination
  audit + dual-runtime mechanical fuzzer (`hunts/acl2s/fuzz_acl2s.py`) and 4-pipeline fuzzing blueprint:
  `ACL2S-1` `defdata-attach` & `register-type` silently opening `(defttag :defdata-attach)` +
  `defattach ... :skip-checks t` without guard checks, faulting raw memory inside `:verify-guards t`
  `:logic` callers; `ACL2S-2` `definec-core` `remove-duplicates` silently dropping/inverting duplicate
  positional formals (`(sub-dup 10 1) => -9`) and conjoining contradictory types so unsound `:exec`
  bodies (`(car x)`) pass guard verification (`:common-lisp-compliant`); `ACL2S-3` `ccg` `redefun defuns-fn`
  crashing valid `:loop$-recursion t` definitions with `HARD ACL2 ERROR in CHOKE-ON-LOOP$-RECURSION`;
  and `ACL2S-4` `defunc` `test?-phase` `skip-proofs` + `with-timeout-aux-raw` uncaught `storage-condition`
  aborting raw Lisp on non-terminating `definec` (+ 5 minor static defects).
- **[W4-KERNEL-FUZZ-FINDINGS.md](W4-KERNEL-FUZZ-FINDINGS.md)** — Wave-4 mechanical kernel fuzzing
  campaign (`hunts/w4-kernel-fuzz/`: 5,438 falsified congruence/rewrite goals, 352 book-DAG `:pcert`
  certifications, 3,960 `:functional-instance`/`defun-sk`/hint checks across SBCL 2.6.10 & CCL 1.14)
  uncovering 4 novel ACL2 kernel bugs: `W4-KF-1` `(:termination-theorem fn substn)` unchecked free-var
  capture triggering `HARD ACL2 ERROR in ASSERT$`; `W4-KF-2` out-of-clique `(:termination-theorem ...)`
  missing `(msg ...)` wrapper crashing `FMT0`; `W4-KF-3` `defun-sk-fn` macroexpander crashes + odd-length
  `(:stobjs st1 st2)` / `:dfs` splice under `:constrain t`; and `W4-KF-4` internal `:OMITTED` sentinel
  leaking into user `:backtrack` hints and top-of-waterfall `hints`.

Host-level summaries at the repo root:
- `CCL.md` and `CCL-OPTIMIZERS.md` (Clozure CL 1.14 arm64 + x86-64: `CCL-1`, `CCL-2`,
  `CCL-3` 13-operator `require-type` multiple-values/comparison bug, and 4-operator unary
  division value-count bug).
- `SBCL.md` (SBCL 2.6.8–2.6.10 x86-64 + arm64: `SB1` root-fixed in 2.6.10 via `0fd47cc68`,
  and live arm64 branch-overflow `SB2`/`F18`).
