# ACL2 8.7+ Unraked Core Kernel Subsystems Audit & Mechanical Fuzzing Report

**Target:** ACL2 8.7+ (`1d2b39a424`, built Nov 12 2026) on **SBCL 2.6.10 (`darwin-arm64`)** and **CCL 1.14 (`darwin-arm64`)**  
**Scope:** Wave-3 Deep Audit of core ACL2 kernel subsystems left unraked by Waves 1–2:
1. Provisional Certification (`pcert`), `.cert`/`.port`/`@expansion.lsp`, `defconst` elision, `local` `include-book`, `:ttags` / `:skip-proofs-okp` / `:defaxioms-okp` checking (`other-events.lisp`, `acl2.lisp`)
2. Equivalence, Refinement, Classic & Patterned Congruence (`pequivs`), `geneqv` propagation, `:outside-inside` rewrite rules, `:rewrite-quoted-constant` Forms `[1]`/`[2]`/`[3]`, and `rewrite-lambda-object` (`defthm.lisp`, `rewrite.lisp`)
3. Witness Skolemization (`defchoose`, `defun-sk`) & `:functional-instance` edge cases (`other-events.lisp`, `history-management.lisp`)
4. Hint/Debugging/Parallel/Oracle Boundaries (`override-hints`, `custom-keyword-hints`, computed-hint `xtrans-eval` & `*protected-system-state-globals*`, `brr`/`wormhole-eval`, `fms`/`fmt-to-comment-window`, `spec-mv-let`/`plet`/`pargs`/`pand`/`por`, `with-prover-step-limit`, `with-prover-time-limit`, `sys-call+`/`read-acl2-oracle`)

All findings in this report are distinct from Waves 1–2 (verified against existing reports in `/Users/ember/dev/compiler-audit/reports/`). No soundness bypass (`NIL` theorem under `:ttag nil`, `:ttags-seen nil`, `:skip-proofs-seen nil`, `:redef-seen nil`) was found across the 4 audited subsystems; **3 concrete core kernel bugs** (one raw-Lisp `CL:ERROR` compiled-book load failure via `defconst` elision desync, one `HARD ACL2 ERROR` in `EXPAND-ABBREVIATIONS` via unchecked `:program`-mode `:functional-instance` symbols, and one `:pcert :complete` sub-book certificate annotation verification gap) were confirmed and cross-verified on both SBCL 2.6.10 and CCL 1.14.

---

## 1. Executive Summary

| ID | Subsystem | Bug Class | Severity | Trigger / Impact | Reproducer |
|----|-----------|-----------|----------|------------------|------------|
| **KD-1** | `hcomp` `defconst` Elision (`other-events.lisp`, `acl2.lisp`) | Raw Lisp `CL:ERROR` + `HARD ACL2 ERROR` on `include-book` | **High** | `hcomp-elided-defconst-alist2` (`other-events.lisp:12181-12204`) and `subst-by-position-eliding-defconst2` (`15093-15115`) desync on `with-output`, `with-prover-step-limit`, and `with-guard-checking-event`/`with-guard-checking`; `acl2::elided-defconst` (`acl2.lisp:1006-1016`) throws raw Lisp `ERROR` when loading compiled `.fasl`/`.dx64fsl` | [kernel-elided-defconst-wrapper-desync](../repros/kernel-elided-defconst-wrapper-desync/run.sh) |
| **KD-2** | `:functional-instance` Substitution (`history-management.lisp`) | `HARD ACL2 ERROR` (`Implementation error` in `EXPAND-ABBREVIATIONS`) | **Medium** | `translate-functional-substitution` (`history-management.lisp:11307-11314`) omits `(logicp fn2 wrld)` when `fn2` is a symbol, injecting `:program`-mode symbols into prover goal clauses | [kernel-fi-program-mode-crash](../repros/kernel-fi-program-mode-crash/run.sh) |
| **KD-3** | Provisional Certification (`other-events.lisp`) | Certification Integrity Gap (`:pcert :complete`) | **Medium** | `certify-book-finish-complete` -> `include-book-alist-uncertified-books` (`other-events.lisp:16180-16207, 16307-16370`) only checks file mtimes before renaming `.pcert1` -> `.cert`, ignoring sub-book `.cert` annotation/hash changes (`:skip-proofs-okp`, `:defaxioms-okp`, `:ttags`) | [kernel-pcert-complete-stale-annotations](../repros/kernel-pcert-complete-stale-annotations/run.sh) |

---

## 2. Verified Findings

### KD-1: `hcomp-elided-defconst-alist2` vs. `subst-by-position-eliding-defconst2` Desync Breaks Compiled Book Loading (`with-output`, `with-prover-step-limit`, `with-guard-checking-event`)

- **Locations:**
  - `/Users/ember/dev/acl2-fix/head-worktree/other-events.lisp:12181-12204` (`hcomp-elided-defconst-alist2`)
  - `/Users/ember/dev/acl2-fix/head-worktree/other-events.lisp:15093-15115` (`subst-by-position-eliding-defconst2`)
  - `/Users/ember/dev/acl2-fix/head-worktree/acl2.lisp:1006-1016` (`acl2::elided-defconst`)
- **Root Cause:**
  To avoid duplicating large quoted `defconst` values into compiled book code/expansion files, `subst-by-position-eliding-defconst2` rewrites eligible `defconst` forms inside expansion records into `(defconst name (cadr (elided-defconst 'name index)))`, while `hcomp-elided-defconst-alist2` extracts the corresponding `(index name . (quote val))` alist from `:expansion-alist`. Both functions explicitly warn: `; Warning: Keep this in sync with ...`. Despite that warning, three separate desynchronizations exist:
  1. **`with-output` (`other-events.lisp:12199` vs `15113-15114`):** `hcomp-elided-defconst-alist2` matches `(('with-output . lst) (hcomp-elided-defconst-alist2-lst index (car (last lst)) alist))` — calling the **list**-traversing helper `hcomp-elided-defconst-alist2-lst` on `(car (last lst))`, which is a **single event form** (e.g., `(defconst *c1* '42)`), whereas `subst-by-position-eliding-defconst2` calls the single-form function on `(car (last ev))`. Only when `(progn ...)` happens to wrap the body does `-lst` accidentally skip `'progn` and traverse the tail.
  2. **`with-prover-step-limit` (`other-events.lisp:12200-12203` vs `15113-15114`):** `hcomp-elided-defconst-alist2` likewise passes the single body form `x` to `hcomp-elided-defconst-alist2-lst`, missing any `defconst` (or `encapsulate`) not wrapped in `progn`, while `subst-by-position-eliding-defconst2` elides it.
  3. **`with-guard-checking-event` vs `with-guard-checking` (`other-events.lisp:12194` vs `15109`):** `hcomp-elided-defconst-alist2` matches `'with-guard-checking-event` (recording the `defconst` onto `*hcomp-elided-defconst-alist*`), whereas `subst-by-position-eliding-defconst2` matches `'with-guard-checking` (leaving the `defconst` un-elided!). When any subsequent `defconst` in the same book is elided, `acl2::elided-defconst` pops the wrong entry from `*hcomp-elided-defconst-alist*`.
- **Observed Failure (SBCL 2.6.10 & CCL 1.14):**
  Certifying [book.lisp](../repros/kernel-elided-defconst-wrapper-desync/book.lisp) with `(certify-book "book" 0 t)` succeeds, then `(include-book "book" :load-compiled-file t)` (or `:load-compiled-file :comp`) aborts with:
  ```
  ACL2 Warning [Compiled file] in ( INCLUDE-BOOK "book" ...):  The following
  raw Lisp error occurred when loading file .../book.fasl:
  An unexpected error was encountered when trying to obtain a 
  value for the constant, *C1*.  If you have not deliberately 
  messed with write-dates of files, please report this error to 
  the ACL2 implementors.

  HARD ACL2 ERROR in ( INCLUDE-BOOK "book" ...):  Unable to load compiled
  file .../book.lisp because an error occurred in raw Lisp (see above).
  ```
- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/kernel-elided-defconst-wrapper-desync/run.sh` (verified PASS on SBCL 2.6.10 and CCL 1.14).
- **Surgical Fix:**
  1. In `hcomp-elided-defconst-alist2` (`other-events.lisp:12199-12203`), call `hcomp-elided-defconst-alist2` (not `-lst`) on `(car (last lst))` / `x`.
  2. In `subst-by-position-eliding-defconst2` (`other-events.lisp:15109`), match `with-guard-checking-event` (or `(with-guard-checking with-guard-checking-event)` if both forms can appear) in sync with `hcomp-elided-defconst-alist2`.

---

### KD-2: `translate-functional-substitution` Accepts `:program`-Mode Function Symbols -> `HARD ACL2 ERROR in EXPAND-ABBREVIATIONS`

- **Location:** `/Users/ember/dev/acl2-fix/head-worktree/history-management.lisp:11303-11331` (`translate-functional-substitution`)
- **Root Cause:**
  In `translate-functional-substitution`, when validating a substitution pair `(fn1 fn2)`:
  - The pseudo-lambda branch (`fn2 = (lambda ...)`, lines `11319-11330`) invokes `translate` in logic mode, which properly rejects `:program`-mode calls.
  - The symbol branch (`(symbolp fn2)`, lines `11307-11314`) checks `(function-symbolp fn2 wrld)` and `chk-equal-arities@par`, **omitting** `(logicp fn2 wrld)`.
  Consequently, a `:functional-instance` hint can substitute any `:program`-mode function symbol of matching arity into a constrained theorem or lemma instance. Note that `:program`-mode functions carry no defining axioms in ACL2's logic and did not yield a soundness bypass when `preprocess` was skipped (`:do-not '(preprocess)`), because `rewrite` / `expand-abbreviations` rejects or leaves them uninterpreted; however, default proving hits `expand-abbreviations` on the resulting clause and aborts with an internal implementation error.
- **Observed Failure (SBCL 2.6.10 & CCL 1.14):**
  ```
  HARD ACL2 ERROR in EXPAND-ABBREVIATIONS:  Implementation error: encountered
  :program mode function symbol, PROG-ID
  ```
- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/kernel-fi-program-mode-crash/run.sh` (verified PASS on SBCL 2.6.10 and CCL 1.14).
- **Surgical Fix:** In `translate-functional-substitution` (`history-management.lisp:11309`), require `(and (function-symbolp fn2 wrld) (logicp fn2 wrld))` (emitting a clean translation error explaining that `:program`-mode functions are disallowed in functional substitutions).

---

### KD-3: `certify-book :pcert :complete` Promotes `.pcert1` -> `.cert` Without Validating Sub-Book Certificate Annotations or Book Hashes

- **Locations:**
  - `/Users/ember/dev/acl2-fix/head-worktree/other-events.lisp:16180-16207` (`include-book-alist-uncertified-books`)
  - `/Users/ember/dev/acl2-fix/head-worktree/other-events.lisp:16307-16370` (`certify-book-finish-complete`)
- **Root Cause:**
  When `certify-book` runs with `:pcert :complete`, `certify-book-finish-complete` calls `include-book-alist-uncertified-books` on the `include-book-alist` stored in `top.pcert1`. That check verifies only file existence and write-date monotonicity (`<= book-date cert-date` and `<= book-date pcert1-date`); it does **not** re-read each sub-book's `.cert` header to check whether its `book-hash` or trust annotations (`:skip-proofs-okp`, `:defaxioms-okp`, `:ttags`) match what `top.pcert1` expected.
  If a sub-book `sub1` (whose `.lisp` mtime did not advance — e.g., because `sub1.lisp` uses `make-event` to read an external payload file, or includes a `local` helper book) is re-certified with `:skip-proofs-okp t`, `:defaxioms-okp t`, or `:ttags :all` after `top.pcert1` was generated, `(certify-book "top" 0 nil :pcert :complete)` nonetheless promotes `top.pcert1` to `top.cert` claiming `:ttags nil`, `:skip-proofs-okp nil`, `:defaxioms-okp nil`. For non-`local` includes, a later `(include-book "top")` still checks `sub1.cert` at load time via `chk-cert-annotations-post-alist`; however, for `(local (include-book "sub1"))`, `(include-book "top" :ttags nil)` never loads `sub1.cert` and succeeds with `ttag=NIL, ttags-seen=NIL, skip-proofs-seen=NIL`. (Note: `top`'s proofs ran during `:pcert :create` when `sub1` was clean, so this is a certification-metadata/provenance integrity gap rather than an arbitrary `NIL` proof.)
- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/kernel-pcert-complete-stale-annotations/run.sh` (verified PASS on SBCL 2.6.10 and CCL 1.14).
- **Surgical Fix:** In `certify-book-finish-complete` (`other-events.lisp`), validate the `cert-obj` headers (`book-hash`, `:ttags`, `:skip-proofs-okp`, `:defaxioms-okp`, `portcullis-cmds` checksums) of every entry in `include-book-alist` before renaming `.pcert1` to `.cert`.

---

## 3. Audited Subsystem Coverage Matrix

| Subsystem | Source Files & Symbols Audited | Checks Performed & Defenses Verified | Findings |
|-----------|-------------------------------|---------------------------------------|----------|
| **1. Provisional Cert, `@expansion.lsp`, `local` `include-book`, `:ttags`** | `other-events.lisp` (`certify-book-finish-complete`, `include-book-alist-uncertified-books`, `hcomp-elided-defconst-alist2`, `subst-by-position-eliding-defconst2`, `write-expansion-file`, `include-book-pcert-p`, `include-book-install-event`), `acl2.lisp` (`elided-defconst`) | Checked `:pcert :create`/`:convert`/`:complete` across `.pcert0`/`.pcert1`/`.cert`, `make-event` + `local (include-book ...)` with `defpkg`, `defttag` propagation in `local` books (properly rejected under `:ttags nil` at `certify-book`), `with-output`/`with-prover-step-limit`/`with-guard-checking-event` `defconst` elision | **KD-1**, **KD-3** |
| **2. Equivalence, Refinement, Patterned Congruence, `geneqv`, `:outside-inside`, RQC** | `defthm.lisp` (`interpret-term-as-rewrite-rule*`, `form-of-rewrite-quoted-constant-rule`, `covered-geneqv-alist`, `replace-duplicate-vars-with-anonymous-var`, `interpret-term-as-congruence-rule`, `defequiv`, `defrefinement`, `defcong`), `rewrite.lisp` (`union-geneqv`, `geneqv-lst`, `subst-equiv-expr`, `next-pequivs*`, `pequivs-for-rewrite-args`, `rewrite-fncall`, `rewrite-quoted-constant*`, `rewrite-lambda-object`) | Tested `defrefinement` hierarchies (`eq4` -> `eq2`), shallow/deep/duplicate-var `pequivs`, `:outside-inside` rules on `IF`/nested calls, `:rewrite-quoted-constant` Forms `[1]`–`[3]` + `bind-free`, `double-rewrite`, `rewrite-lambda-modep` disabled + `mbe`/`ec-call`/`declare`; no soundness or crash faults observed across 60+ falsification trials | Sound in tested scope |
| **3. Witness Skolemization & `:functional-instance`** | `other-events.lisp` (`defchoose-fn`, `defchoose-constraint*`, `defun-sk-fn`, `make-apply$-warrant-defun-sk`), `history-management.lisp` (`translate-functional-substitution`, `sublis-fn-rec`, `relevant-constraints*`, `remove-capture-in-constraint-lst`, `translate-lmi*`) | Tested `defchoose` (multi-var, `:strengthen t`), `defun-sk` (`:rewrite :direct`, `:constrain t`, `defun-nx`), `defevaluator`, `apply$`/`defwarrant` (`defun$`), `stobj` & `mv` signature mismatches, `proved-functional-instances-alist` across local `encapsulate`, and `:program`-mode function substitutions | **KD-2** |
| **4. Hint / Debugging / Parallel / Oracle Boundaries** | `history-management.lisp` (`*protected-system-state-globals*`, `protect-system-state-globals`, `xtrans-eval`, `eval-and-translate-hint-expression`, `apply-override-hint*`, `with-prover-step-limit-fn`), `prove.lisp`, `parallel.lisp`, `interface-raw.lisp`, `axioms.lisp` | Verified untouchable-vars block `ttags-allowed`/`writes-okp`/`certify-book-info` inside `xtrans-eval` and `protect-system-state-globals` restores `ld-skip-proofsp`, `guard-checking-on`, `current-acl2-world`; tested `override-hints`, `custom-keyword-hints`, `backtrack`, `brr`/`wormhole-eval`, `with-prover-step-limit :start`, rational `with-prover-time-limit`, `fms`/`fmt-to-comment-window`, `read-acl2-oracle`/`sys-call+` | Sound in tested scope |

*(Note: Unbound `~y1` in `fms` / `fmt-to-comment-window` triggers `HARD ACL2 ERROR in FMT-VAR` cleanly via ACL2's `fmt` validator, and non-protected globals like `default-backtrack-hint` or `override-hints` are touchable by design in computed hints.)*

---

## 4. Prototype Mechanical Fuzzer Campaign Summary

All hunt harnesses and prototype fuzzers reside in `/Users/ember/dev/compiler-audit/hunts/kernel-deep/`:

| Script | Target Subsystem | Runs / Cases | Result Summary |
|--------|------------------|--------------|----------------|
| `fuzz2_cong_rqc.py` | Equivalence, `defrefinement`, patterned `pequivs`, `:outside-inside`, RQC `[1]`–`[3]`, `double-rewrite`, `rewrite-lambda-object` | 60 randomized trials | `anomalies=0` (all falsified goals rejected cleanly) |
| `fuzz_pcert_fsm.py` & `fuzz2_pcert_fsm.py` | `:pcert :create/:convert/:complete`, `make-event`, `local include-book`, `:ttags`, `:skip-proofs-okp`, `:defaxioms-okp` | 9 FSM workflows | Exposed **KD-3** (`top.cert` promoted despite stale `sub1.cert` annotations) |
| `probe_elide_defconst*.py` (`1`–`3`) | `hcomp-elided-defconst-alist2` vs `subst-by-position-eliding-defconst2` | 15 wrapper/load-mode combinations | Exposed **KD-1** (`with-output`, `with-prover-step-limit`, `with-guard-checking-event` raw Lisp `CL:ERROR` in `acl2::elided-defconst`) |
| `fuzz_sk_fi.py`, `fuzz2_sk_fi.py`, `probe_fi_*.lisp` | `defchoose`, `defun-sk`, `:functional-instance`, `defevaluator`, `apply$`, `stobj`, `mv`, `:program` mode | 8 targeted + 25 randomized trials | Exposed **KD-2** (`HARD ACL2 ERROR in EXPAND-ABBREVIATIONS` on `:program`-mode symbol) |
| `fuzz_hints_dbg.py`, `fuzz2_hints_dbg.py`, `probe_hint_globals.lisp` | `xtrans-eval` state-global protection, `override-hints`, `brr`/`wormhole-eval`, `step-limit`/`time-limit`, `fms`, `oracle` | 19 targeted probes | Confirmed `untouchable-vars` + `protect-system-state-globals` invariants hold against prover-hint escapes |

---

## 5. Systematic Mechanical Fuzzing Blueprint

To exhaustively test the remaining combinatorial surface of ACL2's kernel subsystems beyond prototype runs, we recommend four automated fuzzers built around concrete soundness/crash oracles:

### 5.1 Grammar + Counterexample-Guided Falsification Fuzzer (`pequivs` / `geneqv` / `:outside-inside` / RQC)
- **Generator:** Sample a finite congruence theory over integer/pair domains `(Z_2, Z_4, trees)` with known ground semantics:
  - Equivalence relations `E_1 \subset E_2` (`defequiv` + `defrefinement`).
  - Randomly generated 2-arg and 3-arg functions with `defcong` and patterned congruences (`(implies (E y1 y2) (E' (f pat ... y1 ...) (f pat ... y2 ...)))`), including **nested paths** (`car`/`wrap`) and **duplicate pattern variables** (`(dupf w w z)`).
  - Random rule bank mixing `:outside-inside` rules, `:rewrite-quoted-constant` Forms `[1]`/`[2]`/`[3]` with `bind-free`/`syntaxp` hyps, `double-rewrite`, and `rewrite-lambda-object` with toggled `(:definition rewrite-lambda-modep)` / `(:executable-counterpart rewrite-lambda-modep)`.
- **Conjecture Generation & Oracle:**
  1. Generate candidate goals via AST mutation on the RHS/LHS of valid identities, breaking a pattern slot (`pat' != pat`), refinement direction (`E_2` where only `E_1` holds), or duplicate-var constraint (`(dupf u v z)`).
  2. Evaluate each candidate goal in a fast Python/SBCL concrete evaluator at random finite witnesses `(x, y, z \in {-2..5, nil, '(0 . 1)})` to retain **only falsified goals** (known-false statements).
  3. Submit surviving falsified goals to `saved_acl2`: any `Q.E.D.`, `HARD ACL2 ERROR`, or unhandled Lisp error is an immediate soundness or robustness bug.
- **Minimization:** Delta-debug (`ddmin`) the theory's rule list (deleting one `defthm`/`in-theory` event at a time) while preserving `Q.E.D.` or crash.

### 5.2 Stateful Book-Graph & Certificate State-Machine Fuzzer (`pcert`, `@expansion.lsp`, `hcomp`)
- **State Model:** Directed acyclic book graphs of 2–4 nodes (`sub2 -> sub1 -> top`), where edges are randomly `include-book` vs `(local (include-book ...))`, optionally paired with `defpkg`, `defttag`, `skip-proofs`, `defaxiom`, and nested `make-event` wrappers (`with-output`, `with-prover-step-limit`, `with-guard-checking-event`, `skip-proofs`, `encapsulate`, `progn`) containing quoted `defconst`s, `defun`s, and `defthm`s.
- **Action Space:** Random sequences of:
  - `certify-book(..., compile={t,nil}, pcert={nil, :create, :convert, :complete}, save-expansion-file={t,nil}, ttags=...)`
  - External mutation between `:create` and `:complete` (modifying external payload files, re-certifying sub-books with elevated privileges, deleting `.port`/`.fasl`, toggling `:load-compiled-file {t, :comp, nil}` on `include-book`).
- **Oracles:**
  1. **Load/Compile Consistency:** `(include-book top :load-compiled-file t)` and `:comp` must never emit raw Lisp `CL:ERROR`s (caught **KD-1**).
  2. **Provenance Monotonicity:** No `.cert` with `:ttags nil`, `:skip-proofs-okp nil`, `:defaxioms-okp nil` may be promoted by `:pcert :complete` if any dependency `.cert` has altered hash or elevated annotations (caught **KD-3**).
  3. **Zero-Tag Soundness:** No `(include-book top :ttags nil)` session with `:ttag nil, ttags-seen=nil, skip-proofs-seen=nil, redef-seen=nil` may admit `(defthm nil-chk nil :rule-classes nil)`.

### 5.3 Differential & Adversarial Signature Fuzzer (`defchoose` / `defun-sk` / `:functional-instance`)
- **Generator:** Cross-product of:
  - Target theorem origin: `encapsulate` constraint, `defchoose` (single/multi-var, `:strengthen {t,nil}`), `defun-sk` (`:rewrite {:direct, expr}`, `:constrain {t,nil}`, `defun-nx`), `defevaluator`, `apply$`/`defwarrant` (`defun$`), local `encapsulate` theorems (`proved-functional-instances-alist`).
  - Substitution RHS: `:program`-mode symbol, `:non-executable` symbol, `stobj`-taking/returning symbol, `mv`-returning vs single-value symbol, pseudo-lambda with `mbe`/`stobj`/free-vars, and mismatched arity/world-visibility.
  - Proof context: default preprocess, `:do-not '(preprocess)`, `:guard-hints`, `:by`, `:use`, and `verify-guards`.
- **Oracles:** Any `HARD ACL2 ERROR` (caught **KD-2**), raw Lisp type error during `*1*` execution, stobj single-threadedness violation, or falsifiable `Q.E.D.`.

### 5.4 Boundary & Resource-Interruption Fuzzer (`xtrans-eval`, `brr`, Parallel & Step/Time Limits)
- **Generator:** Randomized prover hints (`computed-hints`, `override-hints`, `custom-keyword-hints`, `:backtrack`) attempting state-global mutations across all globals in `(w state)`/`@`-tables; nested `with-prover-step-limit` (`0..50`, `:start`) and `with-prover-time-limit` (`1/10000`) wrapping `encapsulate`/`make-event`/`certify-book`; parallel macros (`spec-mv-let`/`plet`/`pargs`/`pand`/`por`) under varying guard assumptions; and `brr t` + `wormhole-eval` during rewrite loops.
- **Oracles:** Post-proof invariance of `*protected-system-state-globals*`, clean unwind without world/stobj corruption after step-limit/time-limit abort, and absence of uncaught raw Lisp errors.
