# ACL2 & Host Common Lisp Compiler Soundness Audit

Systematic soundness, code-generation, and trust-boundary audit of **ACL2** and its two primary Common Lisp hosts (**SBCL** and **Clozure CL**). Every reported defect is backed by a minimal, self-contained executable reproducer under [`repros/`](repros/).

## Targets & Environments

| Target | Version / Commit | Architectures Tested |
|---|---|---|
| **ACL2** | `8.7+` development snapshot (`1d2b39a424eabeab269f189b37c29148d49fc516`) | Hosted on SBCL 2.6.10 (`darwin-arm64`) and Clozure CL 1.14 (`darwin-arm64`) |
| **SBCL** | `2.6.10` (plus `2.2.9`, `2.6.8`, `2.6.9` for regression bisection) | `darwin-arm64`, `x86-64-linux` |
| **Clozure CL (CCL)** | `1.14` (`23c9edcf`) | `darwin-arm64`, `x86-64-linux` |

---

## Summary of Verified Findings

Counts below reflect **distinct root-cause bug classes** committed with standalone reproducers (excluding duplicate triggers of the same root cause).

| Target | Soundness / Wrong-Code | Security / Sandbox / Injection | Crash / Robustness / Divergence | Total Distinct Classes |
|---|---:|---:|---:|---:|
| **ACL2 Core (`8.7+`, `:ttags nil`)** | **27** *(29 ACL2 root causes + 3 pure SBCL-induced `NIL` proofs counted under SBCL)* | **1** *(`certify-book :ttags nil` & wormhole disk write)* | **27** *(+ 10 source-audited latent/minor kernel defects)* | **55** *(57 root causes)* |
| **ACL2 Community Books (`books/` — FV engines & `ACL2s`)** | **6** *(`fast-alist-pop*` & `SULFA` `NIL` proofs, `SMTLink` bool/num & symbol collisions, `SATlink` parser, `ACL2s` `definec` formal-swap / unsound `:exec`)* | **1** *(`SMTLink` Python code injection spoofing `"proved"`)* | **3** *(`ACL2s` `defdata-attach :skip-checks t` raw memory fault, `ccg` `loop$` hard error, `defunc` raw stack overflow)* | **10** |
| **SBCL (`2.6.8–2.6.10`)** | **11** *(10 live in `2.6.10` at `(safety 3)`, **3 proving `NIL` in pure ACL2**; 1 fixed in `2.6.10`)* | 0 | **2** *(both live in `2.6.10`, pure ANSI CL; 1 segfault at `(safety 3)`, 1 arm64 asm crash)* | **13** *(12 live in `2.6.10`)* |
| **Clozure CL (`1.14`)** | **9** *(5 at `(safety 3)`/default, incl. x86-64 `vset1` dropped store, `FCMP` `NaN` & `(space 0)` -> `(safety 0)`)* | 0 | **4** *(saved-image W^X livelock, `2^60` `ash` corruption, arm64/x86-64 P2 crashes)* | **13** |
| **Total** | **53** | **2** | **36** | **91** |

### Soundness Threat Model (ACL2)

An ACL2 finding is classified under **Soundness** only if it derives `(defthm ... nil)` (or exhibits a reproducible disagreement between logical semantics and guard-verified evaluation that immediately discharges `NIL`) under standard untrusted assumptions:

- **Zero trust tags**: `(ttag (w state)) = NIL` and `(global-val 'ttags-seen (w state)) = NIL`
- **Zero unproved axioms**: `(global-val 'skip-proofs-seen (w state)) = NIL`
- **Zero redefinition**: `(global-val 'redef-seen (w state)) = NIL` (note: `R7` uses `redef!` and is therefore classified under *Robustness*, not *Soundness*)

Breakdown of the **27 ACL2 soundness classes (29 root causes)** by trust boundary:

1. **Pure-kernel prover, waterfall, proof-builder, meta-extract & warrant-theory bugs — zero raw Lisp, zero stobjs, zero books (`7` classes, both SBCL & CCL)**:
   - Core inference engine dropping forced `'assumption` tag-trees across `type-set` free-variable backtracking (`PK-S1`), `bind-free` candidate advance (`PK-S2`), and `meta-extract-contextual-fact` `mfc` calls (`PK-S3`); proof-builder `:apply-linear` promoting unreachable `IF`-branch `governors` into top-level `:hyps` (`PK-S4`); `encapsulate` Pass-2 `local` warrant world-drift in `(:guard-theorem fn)` (`PK-S5`); post-bootstrap `badge-table` reset abandoning warrants (`PK-S6`) — all 6 proving `(defthm nil-proved nil)` `Q.E.D.` — plus constrained-function `bad-ancestor1` diagonal warrant refuting `Proposition (Attachment Consistency)` (`PK-E1`) in [`reports/ACL2-PROVER-KERNEL.md`](reports/ACL2-PROVER-KERNEL.md).
2. **Single-session, single-host translator / guard-obligation / evaluator bugs — zero books (`8` classes / `10` root causes, both SBCL & CCL)**:
   - Guard-obligation & unboxed `double-float` (`:df`) translator/evaluator invariants (`XDS-S1`, `XDS-S2`, `XDS-S3`, `XDS-S4`, `XDS-S5a`, `XDS-S5b`, `XDS-S5c` in [`reports/ACL2-XDSMITH-GUARDS.md`](reports/ACL2-XDSMITH-GUARDS.md)).
   - Standard library logical/raw mismatch on `count`/`search` (`S5`), empty `(and ...)` stobj array element-type collapse (`S4`), and stale `$inline` function survive-undo (`S7`) in [`ACL2-BUG-REPORT.md`](ACL2-BUG-REPORT.md).
3. **Certifiable books (`(certify-book ... 0 t :ttags nil)`) on single host (`6` classes, both SBCL & CCL)**:
   - `memoize :aokp t` + `apply$` + `defattach` failing to flush attachment-dependent memo tables (`SCR-S1`), default `memoize :aokp nil` + `apply$-lambda` `*cl-cache*` fast-path bypassing `*warrant-reqs*` and `*aokp*` (`SCR-S2`), and `defattach` failing to propagate `invariant-risk` onto constrained stobj updaters (`SCR-S3`) in [`reports/ACL2-STATE-CACHE-RISK.md`](reports/ACL2-STATE-CACHE-RISK.md).
   - Shallow `*user-stobj-alist*` undo snapshot aliasing nested stobj slots across `local` `swap-stobjs` (`WRB-S1`), child stobj retraction mutating `stobj-table` keys/counts without `memoize-flush` (`WRB-S2`), and raw `defstobj` `(defg <st-lst> nil)` wiping the stobj memo-flush list on `local` `include-book` rollback (`WRB-S4`) in [`reports/ACL2-WORLD-ROLLBACK.md`](reports/ACL2-WORLD-ROLLBACK.md).
4. **Host-exposed single-host ACL2 bugs (`2` classes, CCL)**:
   - CL `(satisfies p)` `upgraded-array-element-type` cache surviving ACL2 `:u` (`S3`) and unretracted `proclaim-dfs` `ftype` surviving `:u` (`S6`, plus stobj trigger `B2-S6b`).
5. **Book / `.cert` / `.sao` / `#Y` deserialization, failed-`include-book` rollback & cross-host boundaries (`4` classes)**:
   - Stale compiled `.fasl`/`.da64fsl`/`.lx64fsl` loaded without hash tie when timestamp `>=` `.cert` (`S1`), cross-host `#+`/`#-` reader conditionals in certified books (`S2`), `hcomp-restore-defs` failing to roll back `*the-live-<stobj>*` `redundant-raw-lisp-discriminator` after a failed `include-book` (`WRB-S3`, both SBCL & CCL, zero `memoize`/`apply$`/`defattach`), and 13-byte `.sao` V1 `size/idx = 0` `(svref arr -1)` OOB read at `(safety 0)` yielding non-ACL2 `#<BOGUS object @ #xBE>` on single-host CCL and proving `NIL` across SBCL->CCL `#Y` certification with `:ttags nil` and zero `#+`/`#-` (`PSC-S1` in [`reports/ACL2-PKG-SERIALIZE-CERT.md`](reports/ACL2-PKG-SERIALIZE-CERT.md)).
6. **Pure host-compiler miscompilations proving `NIL` in guard-verified ACL2 (`3` classes, counted under SBCL — consolidated in [`reports/ACL2-ON-SBCL-2.6.10-SOUNDNESS.md`](reports/ACL2-ON-SBCL-2.6.10-SOUNDNESS.md))**:
   - **SBCL 2.6.10 `equality-constraints.lisp:153` (`Z3-1-ACL2`)**: `inherit-equality-p` returns `from` instead of the equivalence-lattice meet when chaining `eq`/`eql`/`char=` with `=`/`char-equal` at `(speed 1)(safety 3)` -> proves `(defthm nil-proved nil)` via `char-equal` (`:ttag nil`, zero books; [`reports/Z3-COMPILER-EQUIVALENCE.md`](reports/Z3-COMPILER-EQUIVALENCE.md)).
   - **SBCL 2.6.10 ARM64 `srctran.lisp:4084` + `arm64/arith.lisp:1158` (`HC-W3-1`)**: `ash-inverted` tests `(:not (integer * 0))` ("not guaranteed `<= 0`" instead of "`>= 0`") -> pure arithmetic `(logand #xffffffffffffffff (ash 1 (- (the integer x))))` evaluates to `0` instead of `2` at `x = -1` and proves `(defthm nil-proved nil)` (`:ttag nil`, zero books; [`reports/HOST-COMPILERS-WAVE3.md`](reports/HOST-COMPILERS-WAVE3.md)).
   - **SBCL 2.6.10 ARM64 & x86-64 `constraint-back.lisp:505` (`HC-W3-2`)**: `(char-code c)` `eq` back-propagation unsoundly negates non-singleton integer intervals `[low, high]` on the `not-eq` branch -> proves `(defthm nil-proved nil)` (`:ttag nil`, zero books; [`reports/HOST-COMPILERS-WAVE3.md`](reports/HOST-COMPILERS-WAVE3.md)).

*(Note for ACL2 maintainers: `ACL2-BUG-REPORT.md` at the repository root is **frozen** as Batch 1 so URLs and section numbers already shared remain stable; all subsequent batches live in standalone files under [`reports/`](reports/README.md). Six earlier one-off findings shared prior to Batch 1 — `defthm.lisp` meta `hyp-fn` guard, `boot-strap-flg` `make-event :expansion?`, `encapsulate` `bogus-exported-compliants` `split-types-term`, `maybe-flush-and-compress1` raw cache hit, interactive `proof-builder` `(verify t) :prove`, and `put-defabsstobj-invariant-risk` — are excluded from the counts above.)*

---

## Report Breakdown

| Report | Target | Soundness | Security | Crash / Robustness | Key Subsystems |
|---|---|---:|---:|---:|---|
| [`ACL2-BUG-REPORT.md`](ACL2-BUG-REPORT.md) *(Batch 1, frozen)* | ACL2 `8.7+` | 7 (`S1`–`S7`) | 0 | 8 (`R1`–`R7`, `H1`) | `include-book` `.fasl` validation, `#+`/`#-`, `defstobj` `(satisfies)` / empty `(and)`, `count`/`search`, `proclaim-dfs` & `defun-inline` `:u` rollback |
| [`reports/ACL2-BATCH-2.md`](reports/ACL2-BATCH-2.md) | ACL2 `8.7+` | *(+1 trigger `B2-S6b`)* | 0 | 2 (`B2-R1`, `B2-R2`) | `proclaim-dfs` tail `mv` proclamation on SBCL, `loop$` binder shadowing outer `:df` formal, stobj `:df` `ftype` across `:u` |
| [`reports/ACL2-XDSMITH-GUARDS.md`](reports/ACL2-XDSMITH-GUARDS.md) | ACL2 `8.7+` | 5 (`XDS-S1..S5c`, 7 root causes) | 0 | 3 (`XDS-R1..R3`) | `loop$` `of-type` dropped guard obligations, `flet`/`macrolet`/`mv-let`/`loop$` `known-dfs` drops, `*cl-cache*` unboxed `:df` poisoning |
| [`reports/ACL2-STATE-CACHE-RISK.md`](reports/ACL2-STATE-CACHE-RISK.md) | ACL2 `8.7+` | 3 (`SCR-S1..S3`, all `:ttags nil` books) | 0 | 1 (`SCR-R1`, +5 latent `SCR-L1..L5`) | `memoize` (`:aokp t` & `:aokp nil`) × `apply$`/`*cl-cache*`/`defattach`, `invariant-risk` bypass on constrained stobj updaters, `serialize-read :hons-mode :never` |
| [`reports/ACL2-PKG-SERIALIZE-CERT.md`](reports/ACL2-PKG-SERIALIZE-CERT.md) | ACL2 `8.7+` | 1 (`PSC-S1`, + raw OOB read) | 1 (`PSC-S2`) | 3 (`PSC-R1..R3`, `PSC-F1`) | `.sao`/`#Y` V1 `size=0` `(svref arr -1)` OOB + `include-book` missing `chk-bad-lisp-object`, `serialize-write` `*wormholep*`/`writes-okp` bypass, fast-alist & `#u`/`#f`/`#!` reader bugs |
| [`reports/ACL2-WORLD-ROLLBACK.md`](reports/ACL2-WORLD-ROLLBACK.md) | ACL2 `8.7+` | 4 (`WRB-S1..S4`; 3 `:ttags nil` books) | 0 | 3 (`WRB-R1..R3`) | Shallow `*user-stobj-alist*` snapshot aliasing `swap-stobjs`, child stobj `stobj-table` retraction missing `memoize-flush`, failed-`include-book` `*the-live-<stobj>*` & `(defg <st-lst> nil)` leaks |
| [`reports/ACL2-PROVER-KERNEL.md`](reports/ACL2-PROVER-KERNEL.md) | ACL2 `8.7+` | 7 (`PK-S1..S6` pure-kernel `NIL` proofs + `PK-E1`) | 0 | *(+5 minor kernel defects `PK-M1..M5`)* | `type-set` free-var & `bind-free` forced `ttree` drops, `meta-extract-contextual-fact` `mfc` forced-fact leak, `:apply-linear` `governors` leak, `(:guard-theorem fn)` warrant drift & `badge-table` reset |
| [`reports/ACL2-KERNEL-DEEP.md`](reports/ACL2-KERNEL-DEEP.md) | ACL2 `8.7+` | 0 | 0 | 3 (`KD-1..3`) | `hcomp` `elided-defconst` wrapper desync crashing `include-book`, `:functional-instance` `:program`-mode crash, `:pcert :complete` stale sub-book annotation promotion, + 4-part mechanical fuzzing blueprint |
| [`reports/W4-KERNEL-FUZZ-FINDINGS.md`](reports/W4-KERNEL-FUZZ-FINDINGS.md) | ACL2 `8.7+` | 0 | 0 | 4 (`W4-KF-1..4`) | `(:termination-theorem fn substn)` free-var `ASSERT$` & out-of-clique `FMT0` crashes, `defun-sk` `:constrain t` macroexpander crashes & malformed `(:stobjs ...)` splice, `:OMITTED` sentinel leak into `:backtrack` hints |
| [`reports/ACL2-FV-ENGINES.md`](reports/ACL2-FV-ENGINES.md) | `books/` (`centaur/`, `smtlink`, `SULFA`) | 5 (`FV-1..4`, `FV-6`) | 1 (`FV-5` Python injection) | 0 | `fast-alist-pop*` `invariant-risk` omission -> `NIL`, `SULFA` `eriks-ht-*` -> `NIL`, `SMTLink` `ACL2_to_Z3.py` bool/num conflation & `gensym_0` collision, `SATlink` prefix/exit-code bugs (`GL`/`FGL` verified CPs clean) |
| [`reports/ACL2S-AUDIT.md`](reports/ACL2S-AUDIT.md) | `books/acl2s/` (`defdata`, `definec`, `ccg`, `cgen`) | 1 (`ACL2S-2` formal swap & unsound `:exec`) | 0 | 3 (`ACL2S-1`, `ACL2S-3`, `ACL2S-4`, +5 minor static defects) | `defdata-attach`/`register-type` ambient `defttag` + `:skip-checks t` raw memory fault, `definec` `remove-duplicates` arg-order swap & contradictory guard fusion, `ccg` `loop$` crash, `defunc` `test?-phase` `storage-condition` stack overflow, + 4-pipeline fuzzing blueprint |
| [`reports/ACL2-ON-SBCL-2.6.10-SOUNDNESS.md`](reports/ACL2-ON-SBCL-2.6.10-SOUNDNESS.md) | ACL2 `8.7+` × SBCL `2.6.10` | *(consolidates `HC-W3-1`, `HC-W3-2`, `Z3-1-ACL2`)* | 0 | 0 | Standalone ACL2-maintainer digest of the **3 pure `:logic`-mode proofs of `NIL` on SBCL 2.6.10** + candidate `acl2-check.lisp` boot-time assertions |
| [`reports/HOST-COMPILERS-WAVE3.md`](reports/HOST-COMPILERS-WAVE3.md) | SBCL `2.6.10`, CCL `1.14`, ACL2 `8.7+` | 8 (`HC-W3-1..6`, `HC-W3-8..9`; 6 at `(safety 3)`) | 0 | 1 (`HC-W3-7` `bad regspec: NIL` at `(safety 3)`) | SBCL `ash-inverted` & `char-code` `constraint-back` (**both proving `NIL` in ACL2**), `set-exclusive-or`, `reduce #'logior`, titlecase `char-equal`; CCL x86-64 `vset1` dropped 64-bit store at `(safety 3)`, complex reg clobber & `COMISD` `NaN` |
| [`SBCL.md`](SBCL.md) & [`reports/SBCL-F18-ARM64-BRANCH-OVERFLOW.md`](reports/SBCL-F18-ARM64-BRANCH-OVERFLOW.md) | SBCL `2.6.8–2.6.10` | 1 (`SB1`, fixed in `2.6.10` via `0fd47cc68`) | 0 | 1 (`SB2`/`F18`, live `2.6.10`) | `x86-64` `ash-right-two-words-variable` `rcx` lifetime (`2.6.8–2.6.9`); `arm64` unrelaxed `(SIGNED-BYTE 19)` PC-relative branch/literal overflow (`2.6.10`) |
| [`reports/SBCL-2.6.10-FINDINGS.md`](reports/SBCL-2.6.10-FINDINGS.md) | SBCL `2.6.10` | 3 (`SB-2610-2..4`, all at `(safety 3)`) | 0 | 1 (`SB-2610-1`, pure ANSI CL segfault at `(safety 3)`) | `x86-64` `%more-arg-values-skip`, `arm64`/`x86-64` SIMD VOP `:from (:argument)` & backwards `move`, `arm64` `bignum-mult-and-add-4-arg` register clobber |
| [`CCL.md`](CCL.md) & [`CCL-OPTIMIZERS.md`](CCL-OPTIMIZERS.md) | CCL `1.14` | 2 (`CCL-3`/`CCL-OPT-2`, `CCL-OPT-1`) | 0 | 2 (`CCL-1`, `CCL-2`) | `save-application` arm64 W^X `mprotect` livelock, `(ash 1 (1- 2^60))` corrupt bignum, 15-op `require-type` multiple-values leak, 4-op unary `truncate`-family value drop |
| [`reports/CCL-CODEGEN-FINDINGS.md`](reports/CCL-CODEGEN-FINDINGS.md) | CCL `1.14` | 3 (`CCL-CG-1..3`, 2 at `(safety 3)`) | 0 | 1 (`CCL-CG-4a/4b`) | `arm64` 2D `aset2`/3D `aref3` reg clobber at `(safety 3)`, `nx1-expand-inline-call` copying `(space 0)` -> `(safety 0)`, unsound `(/ (* c1 x) c2)` float rewrite, P2 `%get-bit`/`%fixnum-ref-double-float` |
| [`reports/Z3-COMPILER-EQUIVALENCE.md`](reports/Z3-COMPILER-EQUIVALENCE.md) | SBCL `2.6.10`, CCL `1.14`, ACL2 `8.7+` | 3 (`Z3-1` + `Z3-1-ACL2`, `Z3-2`, `Z3-3`; all at `(safety 3)`) | 0 | *(bogus full `WARNING` in `Z3-2`)* | SBCL `inherit-equality-p` lattice bug proving `NIL` in ACL2 via `char-equal`, `same-arg` float `derive-type` `NaN`->`1.0d0`, CCL ARM64 `FCMP` unordered-`NaN` (17 bugs + Z3-proved fix) |

---

## Repository Layout & Running Reproducers

- [`repros/`](repros/) — Self-contained minimal reproducers, one directory per bug class. Each contains a `run.sh` driving the relevant ACL2 (`saved_acl2`) and/or standalone SBCL/CCL binaries and printing decisive pass/trigger lines.
- [`reports/`](reports/README.md) — Detailed technical writeups, root-cause source line citations, disassembly/traces, and suggested upstream fixes for all post-Batch-1 findings.
- [`hunts/`](hunts/), [`synth/`](synth/), [`derived-types/`](derived-types/), [`primitives/`](primitives/), [`routes/`](routes/) — Differential fuzzers (coverage-guided ACL2 IR, XDsmith negative-guard generators, anti-masking VOP lifetime probes, `.sao` binary/structural mutators, derived-type & primitive-route sweeps).
- [`RESEARCH.md`](RESEARCH.md), [`STRATEGY.md`](STRATEGY.md), [`LEDGER.md`](LEDGER.md) — Literature survey (XDsmith, Chibios/ACL2 fuzzing, Alive2/Z3 compiler verification, VOP register-allocation hazards) and surface-coverage ledger.
