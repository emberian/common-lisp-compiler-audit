# Wave-4 ACL2 8.7+ Deep Kernel Mechanical Fuzzing Report

**Target:** ACL2 8.7+ (`1d2b39a424`, built Nov 12 2026) on **SBCL 2.6.10 (`darwin-arm64`)** and **CCL 1.14 (`darwin-arm64`)**  
**Blueprint Implemented:** [ACL2-KERNEL-DEEP.md](ACL2-KERNEL-DEEP.md) §5 (`§5.1`–`§5.4`)  
**Fuzzer Suite:** `hunts/w4-kernel-fuzz/` (`fuzz_congruence_rewrite.py`, `fuzz_pcert_bookgraph.py`, `fuzz_fn_instance_sk.py`)  

All findings in this report are verified novel and de-duplicated against all 87 prior Wave 1–3 bug classes across `README.md`, `ACL2-BUG-REPORT.md`, `ACL2-PROVER-KERNEL.md`, `ACL2-KERNEL-DEEP.md`, `ACL2-WORLD-ROLLBACK.md`, `ACL2-STATE-CACHE-RISK.md`, `ACL2-PKG-SERIALIZE-CERT.md`, and `ACL2-XDSMITH-GUARDS.md`.

Across **964 generated theories and multi-book DAGs** (**9,750 concrete-witness-falsified conjectures, provisional certification DAG steps, and prover boundary checks**) executed on both SBCL 2.6.10 and CCL 1.14:
- **Logical Soundness (`:ttags nil`):** **0 soundness bypasses** (`0` proofs of concretely falsified formulas or `NIL`).
- **Novel Kernel Crash, Macroexpansion, and Hint-Boundary Bugs:** **4 novel core kernel bug classes** (`W4-KF-1` through `W4-KF-4`, spanning **3 distinct `HARD ACL2 ERROR` crash paths**, a malformed `defun-sk :constrain t` `encapsulate` signature generator, and two `:backtrack` waterfall `:OMITTED` sentinel leaks) were discovered, root-caused to exact ACL2 source lines, and packaged with standalone dual-host reproducers.

---

## 1. Executive Summary of Novel Wave-4 Findings

| ID | Subsystem | Bug Class | Severity | Trigger & Impact | Reproducer |
|----|-----------|-----------|----------|------------------|------------|
| **W4-KF-1** | Lemma-Instance Translator (`history-management.lisp:14864-14872`, `11503-11511`) | `HARD ACL2 ERROR in ASSERT$` (`(ASSERT$ (NULL VARS) RESULT)`) | **Medium** | `translate-lmi` allows pseudo-lambdas with free variables in `(:termination-theorem fn substn)` / `(:termination-theorem! fn substn)` (`symbol-doublet-listp` + `translate-functional-substitution`), then calls `sublis-fn-simple` **without** checking for bound-variable capture (unlike `:functional-instance`). When `fn` has a `let`-lambda governing a recursive call (`:ruler-extenders :all`/`:lambdas`), free-variable capture aborts in `assert$`. | [w4-kf-term-thm-capture](../repros/w4-kf-term-thm-capture/run.sh) |
| **W4-KF-2** | Lemma-Instance Error Formatter (`history-management.lisp:14873-14881`) | `HARD ACL2 ERROR in FMT0` (`Illegal Fmt Syntax`) | **Medium** | In `translate-lmi`, the error branch rejecting out-of-clique function symbols in `(:termination-theorem fn substn)` omits `(msg ...)` around its `~@1` sub-message, passing a raw format string as `~@1` and shifting `lmi` into `#\1`; `fmt0` crashes on `~&1` expecting a true-list. | [w4-kf-term-thm-fmt0](../repros/w4-kf-term-thm-fmt0/run.sh) |
| **W4-KF-3** | `defun-sk` Macroexpander (`other-events.lisp:19260, 19277, 19315-19316, 19374-19377`) | `HARD ACL2 ERROR` in Macroexpansion + Broken `:constrain t` `:stobjs`/`:dfs` Splice | **Medium** | (a) `defun-sk-fn` calls `(er hard ctx ...)` directly during macroexpansion on unrecognized/duplicate keywords (`:19260`, stale copy-paste from `defstobj`) or non-symbol `:constrain` (`:19277`) instead of returning `` `(er soft ',ctx ...) ``; (b) `fetch-dcl-field` collects multiple `:stobjs`/`:dfs` `xargs` declarations into a list that `` `(:stobjs ,@stobjs) `` splices flat (`:stobjs st1 st2`), rejecting valid multi-declaration `defun-sk` forms under `:constrain t` that succeed under `:constrain nil`. | [w4-kf-defun-sk-macro-crash](../repros/w4-kf-defun-sk-macro-crash/run.sh) |
| **W4-KF-4** | Waterfall `:backtrack` Hint Translator & Promotion (`history-management.lisp:16556-16591, 17720-17724`, `prove.lisp:3894, 3905, 4729-4731, 6329-6342`) | Internal `:OMITTED` Sentinel Leaked into User Hints & Guard Violations | **Medium** | (a) `translate-hint-expression` ignores `hint-type = 'backtrack` for 4-arg and 7-arg symbol hints, passing `:OMITTED` (truthy non-boolean!) as `stable-under-simplificationp`; (b) `:computed-hint-replacement t` (or a replacement list mentioning `clause-list`/`processor`) in a `:backtrack` hint translates with `hint-type = 'backtrack`, deletes `:backtrack` from `pspv`, and splices the hint into top-of-waterfall `hints`, evaluating `clause-list = :OMITTED` and `processor = :OMITTED` on subsequent subgoals. | [w4-kf-backtrack-omitted-leak](../repros/w4-kf-backtrack-omitted-leak/run.sh) |

---

## 2. Mechanical Fuzzing Suite & Campaign Results

All three fuzzers reside in `/Users/ember/dev/compiler-audit/hunts/w4-kernel-fuzz/`, wrap every `saved_acl2` invocation in `/opt/homebrew/bin/timeout --kill-after=5s 60s`, run certification workloads exclusively inside ephemeral `tempfile.mkdtemp` directories cleaned up on exit, and leave zero artifacts in the ACL2 or audit repositories.

| Harness (`hunts/w4-kernel-fuzz/`) | Blueprint § | Host | Seed | Theories / DAGs | Falsified Goals / Certs / Checks | Soundness Bugs | Unmasked Kernel Bugs / Masked Regressions |
|---|---|---|---|---:|---:|---:|---|
| `fuzz_congruence_rewrite.py` | §5.1 | SBCL 2.6.10 | `401001` | 182 theories | 2,710 witness-falsified goals | 0 | 0 anomalies |
| `fuzz_congruence_rewrite.py` | §5.1 | CCL 1.14 | `501001` | 182 theories | 2,728 witness-falsified goals | 0 | 0 anomalies |
| `fuzz_pcert_bookgraph.py` | §5.2 | SBCL 2.6.10 | `402001` | 60 DAGs | 176 book certs + clean includes | 0 | 0 anomalies |
| `fuzz_pcert_bookgraph.py` | §5.2 | CCL 1.14 | `502001` | 60 DAGs | 176 book certs + clean includes | 0 | 0 anomalies |
| `fuzz_fn_instance_sk.py` | §5.3 & §5.4 | SBCL 2.6.10 | `99` (unmasked) / `403001` (masked) | 240 theories | 1,980 checks (+ unmasked discovery) | 0 | Triggers **W4-KF-1..4** unmasked; **0** masked |
| `fuzz_fn_instance_sk.py` | §5.3 & §5.4 | CCL 1.14 | `99` (unmasked) / `503001` (masked) | 240 theories | 1,980 checks (+ unmasked discovery) | 0 | Triggers **W4-KF-1..4** unmasked; **0** masked |
| **Total** | **§5.1–§5.4** | **SBCL + CCL** | — | **964** | **9,750** | **0** | **4 novel kernel bug classes (`W4-KF-1`–`W4-KF-4`)** |

### Harness Design Highlights
1. **`fuzz_congruence_rewrite.py` (§5.1):**
   - Synthesizes finite modular equivalence lattices (`mod 2`, `mod 4`, `mod 8`, `mod 3`, `mod 6`, plus 2-slot pair projections) with proven `defequiv` and `defrefinement` chains.
   - Emits unary/binary operators with classic `defcong` and patterned congruences (nested `car`/`cdr` LHS paths, **duplicate pattern variables** `(f (cons x x))`, and multi-argument patterned congruences), `:outside-inside` rewrite rules, `double-rewrite`, `syntaxp`, `bind-free`, `:loop-stopper`, and `:rewrite-quoted-constant` Forms `[1]`, `[2]`, and `[3]`, plus `defun$`/`apply$`/`rewrite-lambda-object` rules tested across `:rewrite-lambda-object` modes `t`, `nil`, and `:once`.
   - Evaluates every candidate equality/equivalence conjecture over the exact concrete witness domain $D = \{-5,\dots,8\} \cup (S \times S)$ in Python first, transmitting **only concretely falsified conjectures** to `saved_acl2` inside `:u`/`encapsulate` isolation.
2. **`fuzz_pcert_bookgraph.py` (§5.2):**
   - Generates 2-to-4 node book DAGs (`chain2`, `chain3`, `diamond4`) combining `local` and non-`local` `include-book`, `:pcert :create` -> `:pcert :convert` (both topological and reverse-topological conversion schedules) -> `:pcert :complete`, two-pass `.acl2x` (`set-write-acl2x` + `:acl2x t`), `save-expansion-file`, portcullis `defpkg` symbols inside elided `defconst`s, nested `make-event` + `table` state, and constrained `encapsulate` + `defun-sk` exports (excluding already-known `KD-1` and `KD-3` triggers).
   - Resets the world (`ubt! 1`), includes the root book under `:load-compiled-file` $\in \{`t`, `:comp`, `nil`\}$, verifies runtime evaluation against the Python reference value, and verifies `(thm nil)` fails.
3. **`fuzz_fn_instance_sk.py` (§5.3 & §5.4):**
   - Exercises `defchoose` (`:strengthen {t, nil}`, 1- and 2-bound-variable witnesses), `defun-sk` (`:constrain {t, nil}`, `:rewrite :direct`, `defun-nx`, `:dfs`, `:stobjs`, `:split-types`), `defevaluator`, `defun$`/`apply$`/`defwarrant`, `proved-functional-instances-alist` across nested `local` `encapsulate` scopes, and `:functional-instance` / `:guard-theorem` / `:termination-theorem` substitutions with free-variable pseudo-lambdas (excluding known `KD-2` `:program`-mode symbol substitutions).
   - Pairs §5.3 with §5.4 prover boundary fuzzing: tight nested `with-prover-step-limit` (`0`..`250`), `add-custom-keyword-hint` + direct `table custom-keywords-table` entries, `set-override-hints`, `:or` / `:reorder` / `:rw-cache-state` / `:backtrack` hints, and `brr` + `wormhole-eval` state isolation.

---

## 3. Detailed Root-Cause Analysis of Novel Findings

### W4-KF-1: `HARD ACL2 ERROR in ASSERT$` via Unchecked Free-Variable Capture in `(:termination-theorem fn substn)`

- **Locations:**
  - `/Users/ember/dev/acl2-fix/head-worktree/history-management.lisp:14859-14872` (`translate-lmi`)
  - `/Users/ember/dev/acl2-fix/head-worktree/history-management.lisp:11503-11511` (`sublis-fn-simple`)
- **Root Cause:**
  When `translate-lmi` translates a 3-element `:termination-theorem` (or `:termination-theorem!`) lemma instance `(:termination-theorem fn substn)`:
  1. Lines `14859-14860` check `(symbol-doublet-listp (caddr lmi))`. Despite the error text saying `"pairs of the form (symbol x)"`, `symbol-doublet-listp` only checks that each element is a 2-element true-list whose `car` is a symbol — so `((rec-let (lambda (z) (if z v nil))))` passes.
  2. Lines `14866-14867` call `(translate-functional-substitution@par (caddr lmi) ctx wrld state)`, which translates `(lambda (z) (if z v nil))` into a `pseudo-lambdap` containing free variable `v`.
  3. Line `14871` then substitutes `alist` into `term` via `(sublis-fn-simple alist term)`, whose comment (`11505-11506`) explicitly states:
     ```lisp
     ; This is the normal case, in which we call sublis-fn with no bound vars and we
     ; expect no vars to be captured (say, because alist has no free variables).
     (mv-let (vars result)
             (sublis-fn-rec alist term nil t)
             (assert$ (null vars)
                      result))
     ```
  Unlike `translate-lmi/functional-instance` (`history-management.lisp:12418-12450`), which calls `sublis-fn` and emits a clean soft error when `vars` is non-nil, `translate-lmi`'s `:termination-theorem` branch assumes `alist` is pure symbol-to-symbol (like `termination-theorem-fn-subst` at `:14882`). When `fn` is admitted with `:ruler-extenders :all` (or `:lambdas`) and a `let`-bound variable `v` governs a recursive call, `(termination-theorem fn wrld)` retains `((lambda (v) ...) (car x))` as a governing test around `(rec-let (cdr x))`. Substituting `(rec-let (lambda (z) (if z v nil)))` captures `v` inside `sublis-fn-rec`, returning `vars = (V)` and crashing in `(assert$ (null vars) result)`.
- **Observed Failure (SBCL 2.6.10 & CCL 1.14):**
  ```
  HARD ACL2 ERROR in ASSERT$:  Assertion failed:
  (ASSERT$ (NULL VARS) RESULT)
  ```
- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/w4-kf-term-thm-capture/run.sh` (verified `PASS` on SBCL 2.6.10 and CCL 1.14).
- **Surgical Fix:**
  Either restrict `(caddr lmi)` in `(:termination-theorem fn substn)` to symbol-to-symbol pairs (`symbol-alistp` where every `cadr` is a `symbolp`, matching `:DOC lemma-instance`), or replace `(sublis-fn-simple alist term)` at `history-management.lisp:14871` with `(mv-let (vars result) (sublis-fn alist term nil) ...)` and signal a `soft` error when `vars` is non-nil (matching `translate-lmi/functional-instance` at `:12420-12445`).

---

### W4-KF-2: `HARD ACL2 ERROR in FMT0` in `(:termination-theorem fn substn)` Out-of-Clique Error Handler

- **Location:** `/Users/ember/dev/acl2-fix/head-worktree/history-management.lisp:14739, 14873-14881` (`translate-lmi`)
- **Root Cause:**
  In `translate-lmi`, `str` is bound at line `14739` to:
  ```lisp
  "The object ~x0 is an ill-formed lemma instance because ~@1.  See :DOC lemma-instance."
  ```
  Every other parameterized error branch in `translate-lmi` wraps its 5th argument in `(msg ...)`. At lines `14873-14881`, `(msg ...)` was omitted, and an extra `lmi` argument was passed as well:
  ```lisp
  (t (er@par soft ctx str lmi
       "its functional substitution is illegal: the ~
        function symbol~#1~[ ~&1 is~/s ~&1 are~] not ~
        introduced with the function symbol ~x2"
       lmi
       (set-difference-eq (strip-cars alist)
                          (getpropc fn 'recursivep nil wrld))
       fn))
  ```
  In `er@par soft`, `~x0` binds to `lmi` and `~@1` binds to the raw format string `"its functional substitution is illegal: ..."`. When `fmt0` splice-formats `~@1` against the outer fmt-alist, `#\1` inside that string resolves to **that string itself** rather than `(set-difference-eq ...)`, causing `~&1` to abort with an internal formatter syntax error.
- **Observed Failure (SBCL 2.6.10 & CCL 1.14):**
  ```
  HARD ACL2 ERROR in FMT0:  Illegal Fmt Syntax.  The tilde directive
  at location 104 in the fmt string below uses the variable #\1.  That
  ~& directive requires a true list, but it was supplied the value 
  "its functional substitution is illegal: the ~
  ```
- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/w4-kf-term-thm-fmt0/run.sh` (verified `PASS` on SBCL 2.6.10 and CCL 1.14).
- **Surgical Fix:**
  Wrap the sub-message in `(msg ...)` and drop the duplicate `lmi` argument at `history-management.lisp:14873-14881` (changing `~#1` / `~&1` / `~x2` to `~#0` / `~&0` / `~x1` inside `(msg ...)`):
  ```lisp
  (t (er@par soft ctx str lmi
       (msg "its functional substitution is illegal: the ~
             function symbol~#0~[ ~&0 is~/s ~&0 are~] not ~
             introduced with the function symbol ~x1"
            (set-difference-eq (strip-cars alist)
                               (getpropc fn 'recursivep nil wrld))
            fn)))
  ```

---

### W4-KF-3: `HARD ACL2 ERROR`s in `defun-sk` Macroexpander + Malformed `:constrain t` `:stobjs`/`:dfs` Signature Splice

- **Locations:**
  - `/Users/ember/dev/acl2-fix/head-worktree/other-events.lisp:19255-19280` (`defun-sk-fn` keyword & `:constrain` checks)
  - `/Users/ember/dev/acl2-fix/head-worktree/other-events.lisp:19315-19316, 19374-19377` (`defun-sk-fn` `:stobjs`/`:dfs` signature generation)
  - `/Users/ember/dev/acl2-fix/head-worktree/other-events.lisp:19569-19570` (`defmacro defun-sk`)
- **Root Cause:**
  1. **Direct `(er hard ctx ...)` inside macroexpander (`:19260`, `:19277`):** `defun-sk` is a macro whose body directly calls `(defun-sk-fn form name args rest)` (`:19569`). Later error checks in `defun-sk-fn` (`:19297`, `:19301`) properly return `` `(er soft ',ctx "~@0" ',msg) `` so malformed user forms produce normal soft event errors. However, lines `19256-19265` (copied from `defstobj`, complete with the stale comment `; If the defstobj has been admitted, this won't happen.` at `:19258`) and lines `19277-19280` call `(er hard ctx ...)` directly during macroexpansion whenever an unrecognized/duplicate/misplaced keyword or a non-symbol `:constrain` argument is supplied.
  2. **Malformed `:stobjs` / `:dfs` splicing under `:constrain t` (`:19315-19316`, `:19374-19377`):** `fetch-dcl-field` returns a list with one entry per matching declaration field — e.g., for `(declare (xargs :stobjs st1) (xargs :stobjs st2))`, `stobjs` is `(ST1 ST2)` (and for `(declare (xargs :stobjs (st1 st2)))`, `stobjs` is `((ST1 ST2))`). At lines `19374-19377`, `defun-sk-fn` emits:
     ```lisp
     ,@(and stobjs `(:stobjs ,@stobjs))
     ,@(and dfs `(:dfs ,@dfs))
     ```
     When two `:stobjs` (or `:dfs`) declarations are present, `` `(:stobjs ,@stobjs) `` splices `:STOBJS ST1 ST2` (an odd-length non-keyword-value list!) into the generated `encapsulate` signature `(name args t :stobjs st1 st2)`, causing `encapsulate` signature validation to reject a valid `defun-sk` under `:constrain t` even though the exact same `defun-sk` succeeds under `:constrain nil`.
- **Observed Failure (SBCL 2.6.10 & CCL 1.14):**
  ```
  HARD ACL2 ERROR in (DEFUN-SK SK-BAD-KW ...):  The keyword arguments
  to the DEFUN-SK event must appear after the body...

  HARD ACL2 ERROR in (DEFUN-SK SK-BAD-CONSTRAIN ...):  The :constrain
  argument of DEFUN-SK must be a symbol, but 123 is not.
  ```
  And on multi-`:stobjs` `:constrain t`: `encapsulate` fails signature keyword-value-list parsing on `ST2` while `:constrain nil` admits `SK-MULTI-OK` cleanly.
- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/w4-kf-defun-sk-macro-crash/run.sh` (verified `PASS` on SBCL 2.6.10 and CCL 1.14).
- **Surgical Fix:**
  1. At `other-events.lisp:19260` and `:19277`, return `` `(er soft ',ctx ...) `` instead of calling `(er hard ctx ...)`.
  2. Flatten/normalize `stobjs` and `dfs` (e.g., collecting symbol/list entries into a flat symbol list `stobj-syms` / `df-syms`) and emit `` `(:stobjs ,stobj-syms) `` and `` `(:dfs ,df-syms) `` at `other-events.lisp:19374-19377`.

---

### W4-KF-4: Internal `:OMITTED` Sentinel Leaked into `:backtrack` Hints via Symbol-Hint Arity Dispatch & `:computed-hint-replacement` Promotion

- **Locations:**
  - `/Users/ember/dev/acl2-fix/head-worktree/history-management.lisp:16556-16591` (`translate-hint-expression` symbol branch)
  - `/Users/ember/dev/acl2-fix/head-worktree/history-management.lisp:17717-17724` (`eval-and-translate-hint-expression`)
  - `/Users/ember/dev/acl2-fix/head-worktree/prove.lisp:3891-3908` (`process-backtrack-hint`)
  - `/Users/ember/dev/acl2-fix/head-worktree/prove.lisp:6325-6342` (`waterfall0`)
  - `/Users/ember/dev/acl2-fix/head-worktree/prove.lisp:4725-4734` (`find-applicable-hint-settings1`)
- **Root Cause:**
  ACL2's waterfall passes the internal keyword `:OMITTED` for computed-hint variables that do not exist in a given hint context (`stable-under-simplificationp` and `keyword-alist` are `:OMITTED` in `process-backtrack-hint` at `prove.lisp:3894-3896`; `clause-list`, `processor`, and `keyword-alist` are `:OMITTED` in `find-applicable-hint-settings1` at `prove.lisp:4729-4731`). Translation-time variable checks in `translate-hint-expression` (`history-management.lisp:16610-16657`) are supposed to guarantee no hint can ever read an `:OMITTED` variable. Two distinct bugs break that invariant:
  1. **4-arg / 7-arg function-symbol `:backtrack` hints (`history-management.lisp:16556-16591`):** When `term` is a symbol, `translate-hint-expression` ignores `hint-type` completely and accepts arity 3, 4, or 7, expanding arity 4/7 symbols into `(fn id clause world stable-under-simplificationp ...)`. When used as `:backtrack fn`, `process-backtrack-hint` (`prove.lisp:3894`) passes `:OMITTED` for `stable-under-simplificationp` — which evaluates **truthy** in `(if stable-under-simplificationp ...)` and violates `(booleanp stable-under-simplificationp)`.
  2. **`:computed-hint-replacement` promotion from `:backtrack` into top-of-waterfall `hints` (`prove.lisp:3905, 6329-6342` & `history-management.lisp:17720-17724`):** When a `:backtrack` hint referencing `clause-list` or `processor` returns `(:computed-hint-replacement t ...)` (or `(:computed-hint-replacement ((... clause-list ...)) ...)`), `eval-and-translate-hint-expression` (`:17720-17724`) translates replacement expressions with `hint-type = 'backtrack` (allowing `clause-list` and `processor`!), `process-backtrack-hint` (`:3905`) returns `(list backtrack-hint)` (or the `'backtrack`-translated replacement hints), and `waterfall0` (`:6329-6342`) **removes `:backtrack` from `pspv` and splices `new-hints` into top-of-waterfall `hints`**. On every subsequent subgoal, `find-applicable-hint-settings1` (`prove.lisp:4729-4731`) evaluates that hint with `clause-list = :OMITTED` and `processor = :OMITTED`, causing guard violations (e.g., `(CHK-CL :OMITTED)` under `with-guard-checking :all`) or bogus logic-mode evaluation on `:OMITTED`.
- **Observed Failure (SBCL 2.6.10 & CCL 1.14):**
  ```
  [W4-KF-4A] sus=:OMITTED
  [W4-KF-4B] cl=(((NOT (P1 X)) (EQUAL X '1)) ((NOT (P2 Y)) (EQUAL Y '2)))
  [W4-KF-4B] cl=:OMITTED proc=:OMITTED

  ACL2 Error in ( THM ...):  The guard for the function call (CHK-CL CLAUSE-LIST),
  which is (TRUE-LISTP CLAUSE-LIST), is violated by the arguments in the
  call (CHK-CL :OMITTED).
  ```
- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/w4-kf-backtrack-omitted-leak/run.sh` (verified `PASS` on SBCL 2.6.10 and CCL 1.14).
- **Surgical Fix:**
  1. In `translate-hint-expression` (`history-management.lisp:16556-16599`), restrict symbol hints when `(eq hint-type 'backtrack)` to 3-argument symbols `(id clause world)` (or define a dedicated `:backtrack` symbol signature `(id clause world clause-list processor)` and reject 4/7-arg `stable-under-simplificationp` symbols with a soft error).
  2. In `eval-and-translate-hint-expression` (`history-management.lisp:17717-17724`), because `:computed-hint-replacement` in `:backtrack` splices into top-of-waterfall `hints` (`waterfall0` `:6330`), pass `nil` (not `hint-type`) to `translate-hint-expressions@par` at `:17724`, and when `(and (eq hint-type 'backtrack) (eq (cadr val0) t))`, either reject `:computed-hint-replacement t` when `term` mentions `clause-list`/`processor` or preserve `:backtrack` inside `pspv` rather than moving `backtrack-hint` into top-of-waterfall `hints`.

---

## 4. Hardened Kernel Invariants Verified Clean

Across our 9,750 mechanical checks on SBCL 2.6.10 and CCL 1.14, the following high-risk kernel mechanisms WITHSTOOD targeted adversarial fuzzing with zero soundness bypasses:

1. **Duplicate-Variable & Nested Patterned Congruences (`defthm.lisp`, `rewrite.lisp`):**
   - `find-pequiv-pattern-unifier` and `apply-pequiv` accurately enforce equality of repeated pattern variables (e.g., `(f (cons x x))`) and propagate refined/coarse `geneqv` hypotheses through `geneqv-refinementp` without conflating distinct equivalence classes across **5,438** witness-falsified goals.
2. **`:rewrite-quoted-constant` Forms `[1]`, `[2]`, and `[3]` (`rewrite.lisp:23090-23637`):**
   - `rewrite-quoted-constant` preserves equivalence soundness across paired constants, canonicalizer predicates, and compound constructor terms even when multiple `defrefinement` edges and `:outside-inside` rules compete on the same target slot.
3. **`rewrite-lambda-object` & Warranted `apply$` (`rewrite.lisp:5400-5520`):**
   - Rewriting inside quoted `LAMBDA` objects under `rewrite-lambda-modep` $\in \{`t`, `nil`, `:once`\}$ and `ev$`/`apply$` beta-reduction respected warrant hypotheses (`(warrant fn)`) and never leaked unwarranted or ill-guarded rewrites into `equal`.
4. **Provisional Certification (`:pcert`), `.acl2x`, `save-expansion-file`, and `defpkg` Portcullis DAGs (`other-events.lisp`, `interface-raw.lisp`):**
   - Across **120** 2–4 node book DAGs (**352** book certifications across SBCL and CCL), both topological and reverse-topological `:pcert :convert` schedules, `.acl2x` two-pass certification, `local` `include-book` firewalling, and `defpkg` symbols inside `make-event`-generated elided `defconst`s preserved exact value and logical equivalence under `:load-compiled-file` $\in \{`t`, `:comp`, `nil`\}$.
5. **`:functional-instance` Capture Avoidance, `:df`/`stobj`/`mv` Signatures, and Local `proved-functional-instances-alist` (`history-management.lisp`, `other-events.lisp`):**
   - `sublis-fn` and `remove-capture-in-constraint-lst` cleanly blocked all free-variable capture attempts against `defchoose` (1- and 2-variable, `:strengthen t`/`nil`), `defun-sk` (`:constrain t`/`nil`, `:rewrite :direct`), `defevaluator`, and `:guard-theorem`; `proved-functional-instances-alist` entries proved inside `(local (encapsulate () ...))` never leaked across rollback boundaries; and `:reorder` + tight `with-prover-step-limit` rollbacks never dropped subgoals.
