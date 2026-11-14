# Pure-Kernel Rule Admission, Evaluators, `encapsulate`, `apply$`/`defwarrant`, `defattach`, and Lemma-Instance Audit (`prover-audit-rules`)

**Target:** ACL2 8.7+ (`1d2b39a424`) on SBCL 2.6.10 (`/Users/ember/dev/acl2-fix/head-worktree/saved_acl2`) and CCL 1.14 (`/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2`)
**Scope:** Pure-kernel first-order prover & logical event admission (`:ttag nil`, `:skip-proofs-seen nil`, `:redef-seen nil`, zero external books, zero serialization/reader/FFI).

---

## Executive Summary

Auditing rule-class translators/admission (`defthm.lisp`), evaluators (`defevaluator` / `meta-extract-global-fact+` / `ev-fncall+`), quantifiers (`defun-sk`, `defchoose`), `encapsulate` constraint export, `apply$` / `defbadge` / `defwarrant` / `badge-table`, `defattach`, and lemma instances (`:functional-instance`, `:guard-theorem`, `:termination-theorem`) uncovered **two distinct novel pure-kernel `NIL`-proving soundness bugs** and **one pure-kernel evaluation-theory / guard-compliance soundness bug**:

| ID | Classification | Primary Kernel Locations | Pure-Kernel Reproducer (`tmp-rules/`) | SBCL 2.6.10 & CCL 1.14 |
| :--- | :--- | :--- | :--- | :--- |
| **Bug R1** | **Critical — Pure-Kernel `NIL` Proof** (`(defthm nil-proved nil)` `Q.E.D.`) | `history-management.lisp:13303-13304, 13413-13414, 14550-14596, 14810-14837`; `defuns.lisp:4310-4327` | `exploit-local-warrant-guard-thm.lisp` | **Confirmed (`:PASSED`)** — `:ttag nil`, `:skip-proofs-seen nil`, `:redef-seen nil`, zero books, zero `badge-table` reset |
| **Bug R2** | **Critical — Pure-Kernel `NIL` Proof** (`(defthm nil-proved nil)` `Q.E.D.`) | `apply.lisp:1966-1972, 2061-2081`; `history-management.lisp:13413, 14810`; `other-events.lisp:33628-33633` | `exploit-guard-thm-warrant.lisp` | **Confirmed (`:PASSED`)** — `:ttag nil`, `:skip-proofs-seen nil`, `:redef-seen nil`, zero books, zero `encapsulate` |
| **Finding R3** | **High — Evaluation-Theory / Attachment Inconsistency & Vacuous `:guard nil` Verification** (falsifies `Proposition (Attachment Consistency)`) | `apply.lisp:1242, 1262, 1773, 1867`; `other-events.lisp:30435, 31432-31445, 32347-32358` | `test-bad-ancestor-liar.lisp` | **Confirmed (`:PASSED`)** — proves `(not (apply$-warrant-liar))` while `(apply$-warrant-liar)` evaluates to `T` under `defattach` |

All three findings are novel relative to `ACL2-BUG-REPORT.md`, `reports/ACL2-BATCH-2.md`, and sibling lane findings (`#9`, `#11`).

---

## Bug R1 (`NIL`-Proving): `local` Warrant World-Drift in `:guard-theorem` + Incomplete Pass-2 Warrant Check

### Root Cause

1. **World-Dependent Warrant Hypotheses in `special-conjectures` (`history-management.lisp:13276-13349, 13409-13415`):**
   When `guard-clauses-for-clique` generates guard proof obligations for a `loop$` scion call (`collect$`, `sum$`, `always$`, `thereis$`, `do$`, etc.), `special-conjectures` (`history-management.lisp:13409`) computes:
   ```lisp
   (warrant-hyps (collect-negated-warrants term wrld nil))
   (warranted-clause (add-literals warrant-hyps clause))
   ```
   `collect-warranted-fns` (`history-management.lisp:13276-13349`) walks **every** argument of `term` whose ilk is `:FN` or `:EXPR` — not merely well-formed quoted lambda objects, but also **non-lambda expressions** inside the `loop$` target/alist arguments (such as `(list (apply$ 'g '(nil)))` in `(collect$ (lambda$ (x) ...) (list (apply$ 'g '(nil))))`). Whenever it encounters a quoted symbol `'g` in an `:FN` slot, line `13303-13304` checks `(get-warrantp val wrld)`:
   - If `(get-warrantp 'g wrld)` is `T`, `(not (apply$-warrant-g))` is added to `warranted-clause` (i.e., `(apply$-warrant-g)` becomes a hypothesis of the guard obligation).
   - If `(get-warrantp 'g wrld)` is `NIL`, **no warrant hypothesis is added**.

2. **Incomplete Pass-2 Compliance Check in `encapsulate` (`defuns.lisp:4310-4327`):**
   Suppose `g` is defined and badged (`warrantp = nil`) before an `(encapsulate () ...)`. Inside Pass 1 of the `encapsulate`:
   - `(local ...)` introduces `apply$-warrant-g` and updates `badge-table` to mark `g` with `warrantp = t`.
   - A non-local `(defun fn () (declare (xargs :guard t)) (collect$ (lambda$ (x) (declare (xargs :guard (equal x 0))) x) (list (apply$ 'g '(nil)))))` is admitted. During Pass 1, `(get-warrantp 'g wrld)` is `T`, so `fn`'s guard conjecture includes hypothesis `(apply$-warrant-g)`, under which `(apply$ 'g '(nil))` simplifies to `(g nil) = 0`, discharging `(equal newv 0)` (`Q.E.D.`).
   - During Pass 2 of `encapsulate` (`ld-skip-proofsp = 'include-book`), the `local` warrant events are skipped, `fn`'s guard proof is skipped, and `chk-common-lisp-compliant-subfunctions-cmp` (`defuns.lisp:4310-4327`) checks **only**:
     ```lisp
     (warrants-for-tamep-lambdap-lst
      (collect-certain-lambda-objects :well-formed (car terms) wrld nil)
      wrld nil nil)
     ```
     Here, the only lambda object in `fn` is `(lambda$ (x) (declare (xargs :guard (equal x 0))) x)`, which does **not** mention `g`! Meanwhile, `(apply$ 'g '(nil))` in the second argument of `collect$` is outside any lambda object; `all-fnnames!` only requires `'g` to have a *badge* (which it has outside the `encapsulate`), not a *warrant*. Thus Pass 2 exports `fn` with `symbol-class = :common-lisp-compliant` into a world where `apply$-warrant-g` does not even exist and `(get-warrantp 'g wrld)` is `NIL`!

3. **Unsound Lemma Generation in `:guard-theorem` (`history-management.lisp:14550-14596, 14810-14837`):**
   `translate-lmi` (`history-management.lisp:14810-14837`) trusts `(guard-theorem fn ... wrld state)` whenever `(eq (symbol-class fn wrld) :common-lisp-compliant)`. Because `guard-theorem` (`history-management.lisp:14581`) recomputes `(guard-clauses-for-clique ... wrld ...)` in the **outer** world `wrld` where `(get-warrantp 'g wrld)` is `NIL`, `collect-negated-warrants` returns `NIL`! Thus `(:guard-theorem fn)` produces the **unconditional** theorem:
   ```lisp
   (implies (member-equal newv (list (apply$ 'g '(nil))))
            (equal newv 0))
   ```
   Instantiating `newv` with `(apply$ 'g '(nil))` proves `(equal (apply$-userfn 'g '(nil)) 0)` with **no warrant hypothesis**. Because `badge-userfn` and `apply$-userfn` are unconstrained functions (`apply-constraints.lisp:91-97`), `:functional-instance` with `(badge-userfn (lambda (f) nil))` and `(apply$-userfn (lambda (f args) 1))` immediately derives `(equal 1 0)`, proving `NIL` (`Q.E.D.`).

### Standalone Pure-Kernel Exploit (`tmp-rules/exploit-local-warrant-guard-thm.lisp`)

```lisp
(in-package "ACL2")

(defun g (x)
  (declare (ignore x) (xargs :guard t))
  0)

(table badge-table :badge-userfn-structure
  (put-badge-userfn-structure-tuple-in-alist
   (make-badge-userfn-structure-tuple 'g nil '(APPLY$-BADGE 1 1 . T))
   (cdr (assoc-eq :badge-userfn-structure (table-alist 'badge-table world)))
   'defbadge)
  :put)

(encapsulate ()
  (local
   (defun-sk apply$-warrant-g ()
     (forall (args)
       (and (equal (badge-userfn 'g) '(APPLY$-BADGE 1 1 . T))
            (equal (apply$-userfn 'g args) (g (car args)))))
     :constrain t))
  (local
   (in-theory (disable apply$-warrant-g-definition)))
  (local
   (defthm apply$-g
     (implies (force (apply$-warrant-g))
              (and (equal (badge 'g) '(APPLY$-BADGE 1 1 . T))
                   (equal (apply$ 'g args) (g (car args)))))
     :hints (("Goal" :use apply$-warrant-g-necc
              :expand ((:free (x) (hide (badge x))))
              :in-theory (e/d (badge apply$) (apply$-warrant-g-necc g))))))
  (local
   (table badge-table :badge-userfn-structure
     (put-badge-userfn-structure-tuple-in-alist
      (make-badge-userfn-structure-tuple 'g t '(APPLY$-BADGE 1 1 . T))
      (cdr (assoc-eq :badge-userfn-structure (table-alist 'badge-table world)))
      'defwarrant)
     :put))
  (defun fn ()
    (declare (xargs :guard t))
    (collect$ (lambda$ (x) (declare (xargs :guard (equal x 0))) x)
              (list (apply$ 'g '(nil))))))

(defthm step1
  (equal (apply$-userfn 'g '(nil)) 0)
  :rule-classes nil
  :hints (("Goal"
           :use (:instance (:guard-theorem fn)
                           (newv (apply$ 'g '(nil))))
           :in-theory (e/d (apply$)
                           ((:executable-counterpart apply$))))))

(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal"
           :use (:functional-instance
                 step1
                 (badge-userfn (lambda (f) nil))
                 (apply$-userfn (lambda (f args) 1))))))

(assert-event
 (and (null (ttag (w state)))
      (null (global-val 'skip-proofs-seen (w state)))
      (null (global-val 'redef-seen (w state)))))
```

### Recommended Fix

1. **Record or enforce guard-verification warrants across `encapsulate` / `include-book`:**
   - Either store the exact list of warranted function symbols assumed when verifying the guards of `fn` as a world property (e.g., `'guard-warrants`) during `verify-guards` / `defun`, check in `chk-common-lisp-compliant-subfunctions-cmp` (`defuns.lisp:4310`) and `bogus-exported-compliants` (`other-events.lisp:3004`) that every function in `'guard-warrants` still has `(get-warrantp g wrld) = t`, and have `guard-theorem` use that stored warrant set (or additionally verify in `chk-common-lisp-compliant-subfunctions-cmp` that every userfn in any `:FN`/`:EXPR` slot of any `special-loop$-scion-callp` in `terms` is warranted if it was warranted in Pass 1).
   - Alternatively, compute `collect-warranted-fns` in `chk-common-lisp-compliant-subfunctions-cmp`? Note: in Pass 2 `(get-warrantp 'g wrld)` is already `NIL`, so checking `collect-warranted-fns` in Pass 2 alone would miss `'g` unless `collect-warranted-fns` has a mode that collects **all** non-primitive symbols in `:FN`/`:EXPR` slots (whether currently warranted or not), or Pass 1 records the assumed warrants! Specifically, recording the warrant list used by `guard-clauses-for-clique` (or rejecting any unwarranted userfn inside a `special-loop$-scion-callp` during `chk-common-lisp-compliant-subfunctions-cmp`) closes the Pass-1/Pass-2 gap completely.
2. **Prevent warrant abandonment in `badge-table` (see Bug R2)** so warrants can never disappear in later world extensions.

---

## Bug R2 (`NIL`-Proving): Unrestricted `badge-table` Reset in `badge-table-guard1` Abandons Warrants Post-Bootstrap

### Root Cause

1. **Missing `boot-strap-flg` Guard in `badge-table-guard1` (`apply.lisp:1966-1972`):**
   `badge-table` is protected by `(set-table-guard badge-table (badge-table-guard key val ens world) ...)` (`apply.lisp:2078-2081`), which delegates `:badge-userfn-structure` updates to `badge-table-guard1` (`apply.lisp:1965-2059`). Lines `1966-1972` read:
   ```lisp
   (cond
    ((null new-lst)

   ; It is legal simply to abandon all userfn badges and warrants!  But generally
   ; this is only done during bootstrapping to initialize the table.

     t)
    (t ...))
   ```
   Because `badge-table-guard1` does **not** check `(global-val 'boot-strap-flg wrld)`, any ordinary user session or certified book (`:ttag nil`) can execute:
   ```lisp
   (table badge-table :badge-userfn-structure nil :put)
   ```
   to wipe `:badge-userfn-structure` at any point!

2. **Broken Monotonicity Invariants Across the Kernel:**
   Multiple kernel subsystems rely for soundness on the invariant that once `(get-warrantp fn wrld)` becomes `T`, it remains `T` in all extension worlds:
   - **`:guard-theorem` (`history-management.lisp:13413, 14550-14596, 14810-14837`):** Even without `encapsulate` and even when `'g` occurs **inside a well-formed lambda object** `'(lambda (x) (g x))` (so `defuns.lisp:4313`'s `warrants-for-tamep-lambdap-lst` check *is* satisfied at definition time!), guard-verifying `(defun fn () (declare (xargs :guard t)) (sum$ '(lambda (x) (g x)) '(nil)))` proves `(acl2-numberp (apply$ '(lambda (x) (g x)) (list newv)))` **under the hypothesis `(apply$-warrant-g)`**. Wiping `:badge-userfn-structure` to `nil` and re-registering `g`'s badge with `warrantp = nil` leaves `(symbol-class 'fn wrld) = :common-lisp-compliant` while `(get-warrantp 'g wrld)` is now `NIL`! Calling `(:guard-theorem fn)` then recomputes `guard-clauses-for-clique` without `(apply$-warrant-g)`, yielding:
     ```lisp
     (implies (equal (badge-userfn 'g) '(APPLY$-BADGE 1 1 . T))
              (acl2-numberp (apply$-userfn 'g '(nil))))
     ```
     which `:functional-instance` with `(badge-userfn (lambda (f) '(APPLY$-BADGE 1 1 . T)))` and `(apply$-userfn (lambda (f args) t))` immediately refutes to prove `NIL` (`Q.E.D.`).
   - **Memoization `:aokp t` Attachment Tracking (`other-events.lisp:33628-33633`):** `add-trip` explicitly states in its soundness comment:
     `; Note that warrants can only be added as the world extends; that is, collect-warranted-fns increases monotonically as the world grows.`
     Wiping `badge-table` falsifies this invariant as well (and permanently destroys built-in startup warrants such as `do$`, `stobj-print-name`, etc., which cannot even be re-added due to `apply.lisp:2050-2057`).

### Standalone Pure-Kernel Exploit (`tmp-rules/exploit-guard-thm-warrant.lisp`)

```lisp
(in-package "ACL2")

(defun g (x)
  (declare (ignore x) (xargs :guard t))
  0)

(defun-sk apply$-warrant-g ()
  (forall (args)
    (and (equal (badge-userfn 'g) '(APPLY$-BADGE 1 1 . T))
         (equal (apply$-userfn 'g args) (g (car args)))))
  :constrain t)

(in-theory (disable apply$-warrant-g-definition))

(defthm apply$-g
  (implies (force (apply$-warrant-g))
           (and (equal (badge 'g) '(APPLY$-BADGE 1 1 . T))
                (equal (apply$ 'g args) (g (car args)))))
  :hints (("Goal" :use apply$-warrant-g-necc
           :expand ((:free (x) (hide (badge x))))
           :in-theory (e/d (badge apply$) (apply$-warrant-g-necc g)))))

(table badge-table :badge-userfn-structure
  (put-badge-userfn-structure-tuple-in-alist
   (make-badge-userfn-structure-tuple 'g t '(APPLY$-BADGE 1 1 . T))
   (cdr (assoc-eq :badge-userfn-structure (table-alist 'badge-table world)))
   'defwarrant)
  :put)

(defun fn ()
  (declare (xargs :guard t
                  :guard-hints (("Goal" :in-theory (enable apply$ apply$-lambda ev$)))))
  (sum$ '(lambda (x) (g x)) '(nil)))

(table badge-table :badge-userfn-structure nil :put)

(table badge-table :badge-userfn-structure
  (list (make-badge-userfn-structure-tuple 'g nil '(APPLY$-BADGE 1 1 . T)))
  :put)

(defthm step1
  (implies (equal (badge-userfn 'g) '(APPLY$-BADGE 1 1 . T))
           (acl2-numberp (apply$-userfn 'g '(nil))))
  :rule-classes nil
  :hints (("Goal"
           :use (:instance (:guard-theorem fn) (newv nil))
           :expand ((:free (x a) (ev$ x a))
                    (:free (x a) (ev$-list x a)))
           :in-theory (e/d (apply$ apply$-lambda badge)
                           (apply$-g
                            (:executable-counterpart apply$)
                            (:executable-counterpart apply$-lambda)
                            (:executable-counterpart ev$))))))

(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal"
           :use (:functional-instance
                 step1
                 (badge-userfn (lambda (f) '(APPLY$-BADGE 1 1 . T)))
                 (apply$-userfn (lambda (f args) t))))))

(assert-event
 (and (null (ttag (w state)))
      (null (global-val 'skip-proofs-seen (w state)))
      (null (global-val 'redef-seen (w state)))))
```

### Recommended Fix

In `badge-table-guard1` (`apply.lisp:1967`), restrict `:badge-userfn-structure` initialization to bootstrap:
```lisp
((null new-lst)
 (or (global-val 'boot-strap-flg wrld)
     (er hard 'badge-table-guard
         "~@0resetting :BADGE-USERFN-STRUCTURE to NIL is only permitted during bootstrapping."
         *badge-table-guard-msg*)))
```

---

## Finding R3 (Evaluation-Theory Inconsistency & Vacuous `:guard nil` Verification): `bad-ancestor1` Ignores Constrained Functions When Classifying G1 Functions

*(Note: This finding does **not** prove `NIL` in pure first-order logic because ACL2 intentionally prevents evaluator calls during proofs on functions depending on `defattach` unless `:aokp` is trusted, and blocks `apply$-userfn` from evaluating attached functions via `attachment- disallowed` checks in `ev-fncall+` (`rewrite.lisp:2956`) and `concrete-apply$-userfn` (`apply-raw.lisp:158`). However, it directly falsifies `Proposition (Attachment Consistency)` (`other-events.lisp:30435`) in the pure kernel with `:ttag nil` and permits vacuous guard verification of `:guard nil`.)*

### Root Cause

1. **Constrained Functions Invisible to `bad-ancestor1` (`apply.lisp:1242, 1262`):**
   `apply$`'s doppelganger consistency proof requires that no warranted function can depend on `apply$-userfn` or `badge-userfn` except tamely in G2. For G1 classification, `ok-defbadge` (`apply.lisp:1773`) and `chk-acceptable-defwarrant1` (`apply.lisp:1867`) call:
   ```lisp
   (bad-ancestor nil (body fn nil wrld) *apply$-userfn-callers* wrld)
   ```
   `bad-ancestor1` (`apply.lisp:1230-1271`) recurses on subcalls `(ffn-symb x)` **solely via `(body (ffn-symb x) nil wrld)`** (`'unnormalized-body`). For a constrained function `stub` introduced by `encapsulate`, `(body 'stub nil wrld)` is `NIL`! Thus `bad-ancestor1` immediately returns `NIL` without inspecting `stub`'s exported `constraint-lst` (or `(ancestors 'stub wrld)`), even when `stub`'s constraint explicitly calls `apply$`!
   *(Contrast this with the G2 path `not-pre-apply$-definable` at `apply.lisp:1909-1960`, which explicitly rejects constrained functions because `(null (getpropc fn 'unnormalized-body nil wrld))`.)*

2. **Unsound `true-apply$-warrant` Attachment (`other-events.lisp:31432-31445, 32347-32358`):**
   Let `stub` be constrained by `(implies (symbolp fn) (equal (stub fn x) (not (apply$ fn (list x)))))` (witnessed locally by `(if (symbolp fn) (not (apply$ fn (list x))) nil)`), and define `(defun liar (x) (declare (xargs :guard t)) (stub 'liar x))`.
   - `ok-defbadge` and `chk-acceptable-defwarrant1` classify `liar` as **G1** because `(body 'stub nil wrld)` is `NIL`!
   - `badge-table-guard` admits `liar`'s warrant `apply$-warrant-liar`.
   - `(defattach apply$-warrant-liar true-apply$-warrant)` succeeds with **zero proof obligation** because `defattach-constraint-rec` (`other-events.lisp:31432-31445`) exempts `(eq (cdar alist) 'true-apply$-warrant)` on the assumption that *"in the doppelganger model, every warrant is true"*, and `attachment-records` (`other-events.lisp:32347-32358`) exempts it from cycle checks!
   - Yet in first-order logic, `(apply$-warrant-liar)` implies `(apply$ 'liar '(nil)) = (liar nil) = (stub 'liar nil) = (not (apply$ 'liar '(nil)))`, so `(defthm not-warrant-liar (not (apply$-warrant-liar)))` is proved (`Q.E.D.`)!
   - Meanwhile, top-level evaluation `(apply$-warrant-liar)` returns `T` (via `true-apply$-warrant`), directly falsifying `Proposition (Attachment Consistency)` (`other-events.lisp:30435`: the evaluation theory `E` contains both `(not (apply$-warrant-liar))` and `(equal (apply$-warrant-liar) t)`!).
   - Furthermore, any `loop$` whose body or target mentions `(apply$ 'liar '(nil))` gains hypothesis `(apply$-warrant-liar)` in `special-conjectures` (`history-management.lisp:13413`); because `(not (apply$-warrant-liar))` is a theorem, **arbitrary `:guard nil` lambda bodies guard-verify vacuously** (`defun vacuous-guard-verified` in `tmp-rules/test-bad-ancestor-liar.lisp`). And if `stub` is also `defattach`ed to `(defun stub-impl (fn x) (declare (xargs :guard t)) (if (symbolp fn) (not (apply$ fn (list x))) nil))`, calling `(liar nil)` in raw Lisp diverges in an unguarded infinite loop (`liar -> stub-impl -> apply$ -> concrete-apply$-userfn -> liar -> ...`) because `attachment-records` has no cycle edge through `apply$`!

### Recommended Fix

In `bad-ancestor1` (`apply.lisp:1238-1271`), reject (or treat as bad) any constrained function `(and (not (body fn nil wrld)) (not (pre-apply$-prim-p fn wrld)))` (matching the G2 check in `not-pre-apply$-definable` at `apply.lisp:1909-1960`), or at minimum traverse `(ancestors (ffn-symb x) wrld)` so constrained functions whose constraints mention `*apply$-userfn-callers*` cannot be called from warranted G1/G2 functions; and disallow `defattach` on any constrained ancestor of a warranted function if the attachment calls `*apply$-userfn-callers*`.

---

## Subsystem Audit Coverage Table

| Subsystem | Kernel Files & Key Functions Audited | Verdict & Soundness Notes |
| :--- | :--- | :--- |
| **`:rewrite` / `:linear` / `:forward-chaining` / `:elim` / `:generalize` / `:type-prescription` rule admission** | `defthm.lisp:1-7500`; `rewrite.lisp` (`add-linear-lemma-finish`, free-var/backchain/loop-stopper handling) | **Sound.** Verified corollary implication checks (`implies-corollary`), variable containment, equivalence-relation checks (`geneqv`), `:type-prescription` bitwise subset encoding against `basic-type-set`, and `:elim` destructor variable distinctness/occurrence checks. |
| **`:definition` rules & `subversive-cliquep`** | `defthm.lisp:5000-5600`; `defuns.lisp:3650-3850` (`put-induction-info-recursive`, `subversive-cliquep`) | **Sound.** `:install-body` requires exact signature/clique/controller checks; `subversive-cliquep` prevents installing unverified recursive cliques into the induction/measure machinery without ruler-extenders/measure validation. |
| **`:induction` & `:clause-processor` & `:meta` rules + `defevaluator` + `meta-extract`** | `defthm.lisp:7500-12857`; `boot-strap-pass-2-a.lisp` (`meta-extract-contextual-fact`, `meta-extract-global-fact+`); `boot-strap-pass-2-b.lisp` | **Sound in rule admission / `meta-extract-global-fact+`.** Verified `chk-acceptable-meta-rule`, `chk-acceptable-clause-processor-rule`, `ev-Simple` evaluator recognizer (`defevaluator` arity, `quote`/`if` clauses, constraint matching), `meta-extract-formula` (`formula` vs `unnormalized-body` vs `defchoose`/`defun-sk` axioms), `:fncall` (`ev-fncall-w` rejecting attachments/untouchables/stobjs), and cross-world `wrld` parameter soundness via `meta-extract-global-fact+` when `obj` is forged. *(Contextual `mfc` forced-assumption drop in `meta-extract-contextual-fact` is covered by sibling `prover-audit-engine` in `#9`.)* |
| **`:tau-system` rule admission** | `tau.lisp` (`chk-acceptable-tau-rule`, `tau-visit-event`) | **Sound.** All signature shapes (boolean predicates, `implies` pairs, `and`/`or` conjunctions, bound intervals, complementary predicates) strictly derive from the proved corollary. |
| **`defun-sk` & `defchoose`** | `other-events.lisp:7300-8650` (`defchoose`, `chk-acceptable-defchoose`, `defun-sk`, `make-apply$-warrant-defun-sk`) | **Sound.** Verified bound-variable capture avoidance, `all-vars1` free-variable framing in `defchoose` strengthening axioms, stobj/mv-violation checks, and `:constrain t` witness generation in `defun-sk`. |
| **`encapsulate` constraint export (`encapsulate-constraint`, Pass-1/Pass-2 invariants)** | `other-events.lisp:2400-3550` (`encapsulate-constraint`, `bogus-exported-compliants`, `bogus-exported-measures`); `defuns.lisp:4280-4350` | **Bug R1 Found (`defuns.lisp:4310-4327`).** `encapsulate-constraint` properly catches subversive indirect definitions via transitive `ancestors` closure, `bogus-exported-compliants` catches locally `verify-guards`ed functions, and `bogus-exported-measures` catches local measure theorems — **except** `chk-common-lisp-compliant-subfunctions-cmp` (`defuns.lisp:4313`) only checks `warrants-for-tamep-lambdap-lst` on well-formed lambda objects, missing `local` warrants consumed by `special-conjectures` on non-lambda `loop$` scion arguments (Bug R1). |
| **`:functional-instance` & constraint collection** | `history-management.lisp:10300-11550` (`relevant-constraints`, `remove-capture-in-constraint-lst`, `instantiate-lemma`) | **Sound.** Verified transitive ancestor constraint collection (`relevant-constraints`), bound-variable renaming (`remove-capture-in-constraint-lst`) when functional substitutions contain free variables or `defchoose`/`defun-sk` witnesses, arity/mv/stobj checks, and restriction against instantiating primitives (`*primitive-logic-fns-with-raw-code*`). |
| **`:termination-theorem` & `:guard-theorem` lemma instances** | `history-management.lisp:12100-14900` (`termination-theorem`, `collect-warranted-fns`, `special-conjectures`, `guard-clauses`, `guard-theorem`, `translate-lmi`) | **Bugs R1 & R2 Found (`history-management.lisp:13303-13304, 13413, 14550-14596, 14810-14837`).** `termination-theorem` uses stored `'justification` and `'unnormalized-body` independent of mutable warrant tables. By contrast, `guard-theorem` recomputes `guard-clauses-for-clique` in the **current** world `wrld` using `(get-warrantp val wrld)`, dropping warrant hypotheses whenever a warrant was `local` to an `encapsulate` (Bug R1) or wiped via `badge-table` reset (Bug R2). |
| **`apply$`, `defbadge`, `defwarrant`, `badge-table`** | `apply.lisp:1-3300`; `apply-constraints.lisp:1-276`; `apply-raw.lisp:120-530`; `translate.lisp` | **Bug R2 & Finding R3 Found (`apply.lisp:1242, 1262, 1966-1972`).** `badge-table-guard1` allows `(table badge-table :badge-userfn-structure nil :put)` post-bootstrap (Bug R2), and `bad-ancestor1` ignores constrained functions because `(body fn nil wrld)` is `NIL` (Finding R3). |
| **`defattach` & evaluation/memoization interaction** | `other-events.lisp:30400-33800` (`defattach`, `defattach-constraint-rec`, `attachment-records`, `add-trip`); `rewrite.lisp` (`ev-fncall+`); `axioms.lisp` (`return-last-arg2`, `throw-or-attach`); `memoize-raw.lisp` | **Finding R3 Found (`other-events.lisp:31432-31445, 32347-32358`).** `ev-fncall+` properly gates attachment execution behind `aokp` and collects `*warrant-reqs*` into `ttree` `'assumption` records during proofs; however, `defattach`'s exemption for `true-apply$-warrant` becomes unsound for top-level evaluation when combined with `bad-ancestor1`'s constrained-function blind spot (Finding R3), and `add-trip`'s warrant-monotonicity assumption (`other-events.lisp:33628-33633`) is violated by Bug R2. |
