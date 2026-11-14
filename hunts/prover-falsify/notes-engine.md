# ACL2 Prover Engine Soundness Audit (`prover-audit-engine`)

- **Target Repository**: `/Users/ember/dev/acl2-fix/head-worktree` & `/Users/ember/dev/acl2-fix/ccl-worktree`
- **ACL2 Version**: `8.7+` (`1d2b39a424eabeab269f189b37c29148d49fc516`)
- **Host Lisps Verified**: SBCL `2.6.10` and Clozure Common Lisp (CCL) `1.14` (`darwinarm64`)
- **Scope**: Interactive Proof-Builder (`proof-builder-a.lisp`, `proof-builder-b.lisp`, `verify` / `:instructions` handoff), Rewriter & Congruence/Equivalence/Meta/Linear Engine (`rewrite.lisp`, `ld.lisp`, `boot-strap-pass-2-a.lisp`), Clause Simplifier & Forcing/Tag-Tree Engine (`simplify.lisp`, `prove.lisp`), BDD Engine (`bdd.lisp`), Preprocessor (`induct.lisp`), and Dirty Lambda Cleanup (`translate.lisp`).

---

## Executive Summary

Full line-by-line audit of the pure-kernel proof-builder, rewriter, simplifier, meta-context (`mfc`), BDD, and forcing/tag-tree subsystems uncovered **two novel, standalone `NIL`-proving soundness bugs** in ACL2 8.7+ (`1d2b39a424`). Neither bug uses trust tags (`:ttag nil`), `skip-proofs` (`:skip-proofs-seen nil`), redefinition (`:redef-seen nil`), raw Lisp, `include-book`, `save-exec`, or filesystem races. Both bugs have been verified to prove `(defthm nil-proved nil :rule-classes nil)` cleanly in a single fresh ACL2 session on both SBCL 2.6.10 and CCL 1.14, and neither overlaps with `ACL2-BUG-REPORT.md`, `ACL2-BATCH-2.md`, `note-8-8`, or `books/system/tests/`.

| # | Bug | Subsystem / Exact `file:line` | Exploit Script | SBCL 2.6.10 | CCL 1.14 |
|---|-----|-------------------------------|----------------|-------------|----------|
| 1 | Proof-builder `:apply-linear` (`:al`) leaks branch-local conclusion `governors` into top-level goal `:hyps` | `proof-builder-b.lisp:3226, 3244, 3284, 3322, 3326-3332` | `/Users/ember/dev/compiler-audit/hunts/prover-falsify/tmp-engine/test-apply-linear.lisp` | `NIL-PROVED` (`0.00s`) | `NIL-PROVED` (`0.01s`) |
| 2 | `meta-extract-contextual-fact` silently drops forced `'assumption` tags inherited via `mfc` `:type-alist` / `:simplify-clause-pot-lst` | `boot-strap-pass-2-a.lisp:1290-1333`, `ld.lisp:4561-4897`, `interface-raw.lisp:8355-8394`, `rewrite.lisp:19077-19091`, `defthm.lisp:4433-4462` | `/Users/ember/dev/compiler-audit/hunts/prover-falsify/tmp-engine/test-meta-extract-forced-ta.lisp` | `NIL-PROVED` (`0.05s`) | `NIL-PROVED` (`0.13s`) |

---

## Bug #1: Proof-Builder `:apply-linear` (`:al`) Promotes Branch-Local `governors` to Top-Level Goal `:hyps`

### Affected Locations
- `proof-builder-b.lisp:3204-3349` (`define-pc-primitive apply-linear` and macro `al`)
  - Line `3226`: `(assumptions (union-equal hyps (governors conc current-addr)))`
  - Line `3244`: `(hyps-type-alist assumptions pc-ens w state)`
  - Lines `3284-3286`: `(unrelieved-hyps lemma-rune lemma-hyps alist hyps-type-alist instantiate-free w state pc-ens nil)`
  - Lines `3322-3325`: `(make-new-goals-fixed-hyps subst-hyps assumptions goal-name depends-on)`
  - Lines `3326-3334`: `(change goal (car goals) :hyps (append hyps (list (sublis-var unify-subst lemma-concl))) ...)`

### Root Cause
`define-pc-primitive apply-linear` (`proof-builder-b.lisp:3204`) carries the comment `; Warning: Keep this in sync with the proof-builder rewrite command.` (`:3206`) and copies `rewrite`'s context construction (`proof-builder-b.lisp:3057`):
```lisp
(current-term (fetch-term conc current-addr))
(assumptions (union-equal hyps (governors conc current-addr)))
```
When the user dives (`:dv`) into a subterm of the goal conclusion `conc`—for example, into the `THEN` branch `Q` of `(if P Q R)` at `current-addr = (2)`—`(governors conc current-addr)` returns `(P)`. Including `P` in `assumptions` is **sound for `rewrite`** (`proof-builder-b.lisp:3159-3165`), because `rewrite` only replaces `current-term` **at `current-addr`** (`(replace-subterm conc current-addr new-term)`), where `P` genuinely governs the subterm!

In `:apply-linear`, however:
1. `hyps-type-alist` is built from `assumptions = hyps ∪ governors(conc, current-addr)` (`:3244`).
2. The `:linear` rule's hypotheses `lemma-hyps` are relieved against `hyps-type-alist` (`:3284`), and any unrelieved-hyp subgoals are given `:hyps assumptions` (`:3322-3325`), so `lemma-hyps` are only proved under `hyps ∧ governors(conc, current-addr)`.
3. Yet at lines `3326-3332`, `:apply-linear` does **not** restrict the instantiated conclusion `(sublis-var unify-subst lemma-concl)` to `current-addr`; instead, it appends it unconditionally to the **top-level goal `:hyps`**:
   ```lisp
   (changed-goal
    (change goal (car goals)
            :hyps
            (append hyps
                    (list
                     (sublis-var unify-subst
                                 lemma-concl)))
            :depends-on
            (+ depends-on (length new-goals))))
   ```

Consequently, for **any** false proposition `P` (e.g., `(< (trig) 0)` where `(defun trig () 0)`), one can prove the tautologous `:linear` rule `(implies (< (trig) 0) (< (trig) 0))`, state a false theorem `(if (< (trig) 0) (equal (trig) 0) nil)`, dive into the unreachable `THEN` branch `(:dv 2) (:dv 1)` where `(governors conc '(2 1)) = ((< (trig) 0))`, and execute `(:apply-linear trig-lin)`. The hypothesis `(< (trig) 0)` of `trig-lin` is immediately relieved by the branch governor `(< (trig) 0)`, and the false conclusion `(< (trig) 0)` is appended to the top-level `:hyps` of the goal! Returning to `:top`, enabling `(:executable-counterpart trig)`, and running `:s` discharges the goal by `"Contradiction in the hypotheses!"`, proving `(if (< (trig) 0) (equal (trig) 0) nil)` (which evaluates to `nil`), and immediately yielding `(defthm nil-proved nil :rule-classes nil)`.

### Standalone Exploit (`/Users/ember/dev/compiler-audit/hunts/prover-falsify/tmp-engine/test-apply-linear.lisp`)
```lisp
(in-package "ACL2")

(defun trig () 0)

(defthm trig-lin
  (implies (< (trig) 0)
           (< (trig) 0))
  :rule-classes ((:linear :trigger-terms ((trig)))))

(in-theory (disable trig (:executable-counterpart trig) (:type-prescription trig)))

(defthm false-thm
  (if (< (trig) 0) (equal (trig) 0) nil)
  :rule-classes nil
  :instructions ((:dv 2)
                 (:dv 1)
                 (:apply-linear trig-lin)
                 :top
                 (:in-theory (enable (:executable-counterpart trig)))
                 :s))

(in-theory (enable (:executable-counterpart trig)))

(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal" :use false-thm)))

(assert-event
 (and (null (ttag (w state)))
      (null (global-val 'skip-proofs-seen (w state)))
      (null (global-val 'redef-seen (w state)))
      (equal (formula 'nil-proved t (w state)) ''nil)))
```

### Verification Output
- **SBCL 2.6.10** (`/Users/ember/dev/acl2-fix/head-worktree/saved_acl2`): `FALSE-THM` `Q.E.D.` (`0.00s`), `NIL-PROVED` `Q.E.D.` (`0.00s`), `ASSERT-EVENT` `:PASSED`, exit code `0`.
- **CCL 1.14** (`/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2`): `FALSE-THM` `Q.E.D.` (`0.01s`), `NIL-PROVED` `Q.E.D.` (`0.00s`), `ASSERT-EVENT` `:PASSED`, exit code `0`.

### Recommended Fix
Either:
1. Bind `assumptions` in `apply-linear` (`proof-builder-b.lisp:3226`) to `hyps` alone (matching how top-level `:hyps` are scoped—`current-addr` is still used to select `current-term` for trigger matching, while hypotheses are relieved strictly from top-level `hyps`); **or**
2. If `(governors conc current-addr)` is non-nil, either prepend `(implies (conjoin govs) ...)` around the added top-level hypothesis or rewrite `conc` at `current-addr` from `subterm` to `(implies inst-concl subterm)` instead of mutating top-level `:hyps`.

---

## Bug #2: `meta-extract-contextual-fact` Silently Drops Forced `'assumption` Tags Inherited via `mfc`

### Affected Locations
- `boot-strap-pass-2-a.lisp:1290-1333` (`meta-extract-contextual-fact`)
- `defthm.lisp:4433-4462, 4506-4509` (`remove-meta-extract-contextual-hyps`, `meta-rule-hypothesis-functions`)
- `rewrite.lisp:19077-19091, 19496-19503` (`rewrite-with-lemma` `:meta` subclass `mfc` construction and `ttree` return)
- `ld.lisp:4516-4570` (`mfc-ts-raw`), `4601-4671` (`mfc-rw-raw`), `4687-4791` (`mfc-relieve-hyp-raw`), `4801-4897` (`mfc-ap-raw`), `4910-4960` (`mfc-*` macros), `5003-5017` (`mfc-force-flg`, `update-rncst-for-forcep`)
- `interface-raw.lisp:8355-8394` (`defun-overrides` for `mfc-ts-fn`, `mfc-rw-fn`, `mfc-rw+-fn`, `mfc-relieve-hyp-fn`, `mfc-ap-fn`)

### Root Cause
When a `:meta` rule has hypotheses of the form `(ev (meta-extract-contextual-fact obj mfc state) a)`, `remove-meta-extract-contextual-hyps` (`defthm.lisp:4433-4462`, called from `meta-rule-hypothesis-functions` at `:4508`) **erases those hypotheses** when storing the `:meta` rule, so `rewrite-with-lemma` (`rewrite.lisp:19213-19220`) does **not** generate or relieve them at rule-application time.

The metatheoretical soundness of erasing `(ev (meta-extract-contextual-fact obj mfc state) a)` rests on the invariant stated in `boot-strap-pass-2-a.lisp:1294-1304`:
```lisp
; This function may be called in the hypothesis of a meta rule, because we know
; it always produces a term that evaluates to non-nil under the mfc where the
; metafunction is called, using the specific alist A for which we're proving
; (evl x a) = (evl (metafn x) a). ...
;
; This function avoids forcing and does not return a tag-tree.
```
To "avoid forcing", `meta-extract-contextual-fact` (`boot-strap-pass-2-a.lisp:1309-1333`) calls all five `mfc` query operators with `:forcep nil` and `:ttreep nil`:
- `(:typeset term . &)` -> `(mfc-ts term mfc state :forcep nil :ttreep nil)`
- `(:rw+ term alist obj equiv . &)` -> `(mfc-rw+ term alist obj equiv mfc state :forcep nil :ttreep nil)`
- `(:rw term obj equiv . &)` -> `(mfc-rw term obj equiv mfc state :forcep nil :ttreep nil)`
- `(:ap term . &)` -> `(mfc-ap term mfc state :forcep nil)`
- `(:relieve-hyp hyp alist rune target bkptr . &)` -> `(mfc-relieve-hyp hyp alist rune target bkptr mfc state :forcep nil :ttreep nil)`

**The fatal flaw**: `:forcep nil` only sets `force-flg` to `nil` (`mfc-force-flg`, `ld.lisp:5003-5006`) and `(access rewrite-constant rcnst :force-info)` to `'weak` (`update-rncst-for-forcep`, `ld.lisp:5008-5017`). That prevents *new* `force-assumption` calls during the `mfc-*` query itself, **but it does NOT prevent `type-set`, `rewrite`, `relieve-hyp`, `linearize`, or `add-polys` from consuming contextual facts already present in `(access metafunction-context mfc :type-alist)` and `(access metafunction-context mfc :simplify-clause-pot-lst)` whose per-entry `ttree`s ALREADY contain forced `'assumption` records!**

Specifically:
1. **Lazy Forced Assumptions in Clause Context**: During `simplify-clause1` (`simplify.lisp:8170-8240`)—as well as during `assume-true-false` on `IF` tests—`forward-chain-top` (`simplify.lisp:8171-8189`) and `setup-simplify-clause-pot-lst` (`simplify.lisp:8220-8226`) run with forcing enabled (`(ok-to-force local-rcnst)`). When a `:forward-chaining` or `:linear` rule forces a hypothesis `(force P)`, the resulting `'assumption` tag is stored **only inside the individual `type-alist` entry `(term ts . entry-ttree)` or `poly` `:ttree`**, NOT in the clause's top-level `ttree`. ACL2 relies on any downstream consumer (`type-set`, `lookup-hyp`, `rewrite`, `linear`) merging `entry-ttree` / `poly-ttree` into the active proof `ttree` if and only if that forced fact is actually used.
2. **Unfiltered `mfc` Construction**: When `rewrite-with-lemma` (`rewrite.lisp:19077-19091`) invokes an extended metafunction, it passes the active `:type-alist type-alist` (`:19079`) and `:simplify-clause-pot-lst simplify-clause-pot-lst` (`:19086-19087`) verbatim into `mfc`, including all forced entries.
3. **Silent Tag-Tree Drop in `mfc-*-fn` / `mfc-ap-raw`**:
   - Inside `mfc-ts-raw` (`ld.lisp:4561-4570`), `mfc-rw-raw` (`ld.lisp:4626-4671`), and `mfc-relieve-hyp-raw` (`ld.lisp:4753-4791`), `type-set`, `rewrite`, and `relieve-hyp` read the forced `type-alist` / `simplify-clause-pot-lst` entries and faithfully propagate their `'assumption` records into the local `ttree`.
   - `mfc-ts-fn`, `mfc-rw-fn`, `mfc-rw+-fn`, and `mfc-relieve-hyp-fn` (`interface-raw.lisp:8355-8387`) then **discard `ttree`** via `(declare (ignore ttree))`!
   - Likewise, `mfc-ap-raw` (`ld.lisp:4815-4897`) drops the second return value (`ttree`) of `linearize` (`:4817`) and returns the `contradictionp` `poly` record from `add-polys` (`:4851, :4896`) as a truthy boolean without checking whether `(access poly contradictionp :ttree)` contains `'assumption` tags!
   - Finally, `rewrite-with-lemma` (`rewrite.lisp:19496-19503`) receives no `ttree` from `ev-fncall-meta` and completes the rewrite with zero `'assumption` tags in the clause's `ttree`.

Note the stark contrast with `tau` (`induct.lisp:934-968` and `tau.lisp:11842-11856`), where the ACL2 authors explicitly noted this exact hazard (`induct.lisp:939-943`):
> `; We ensure that the type-alist has no assumptions or forced hypotheses. FYI: Just to be doubly sure that we are not ignoring assumptions and forced hypotheses, you will note that in relieve-dependent-hyps, after calling type-set, we check that no such entries are in the returned ttree.`

`mfc-*` / `meta-extract-contextual-fact` lacks both protections: it neither strips forced entries from `mfc` when `:forcep nil` nor checks `(assumption-free-ttreep ttree)` / `(not (contains-assumptionp ttree))` before discarding `ttree`.

### End-to-End Exploit Trace
1. Define `(trig x) = t`, `(false-fn x) = nil`, `(goal-fn x) = nil`, and `(wrap-fn x) = (goal-fn x)`.
2. Prove the valid theorem `fc-goal`:
   ```lisp
   (implies (and (trig x) (force (false-fn x)))
            (equal (goal-fn x) t))
   ```
   as a `:forward-chaining` rule triggered by `(trig x)` (trivially valid since `(false-fn x)` is `nil`).
3. Disable `trig`, `false-fn`, `goal-fn`, and `wrap-fn` (along with their executable counterparts and type prescriptions).
4. Define an evaluator `mev` over `(equal a b)`, `(goal-fn x)`, `(wrap-fn x)`, and a verified `:meta` rule `mf-correct` on `wrap-fn` whose metafunction `mf` checks:
   ```lisp
   (equal (mfc-rw (list 'goal-fn (cadr term)) '? nil mfc state :forcep nil :ttreep nil) ''t)
   ```
   and rewrites `(wrap-fn x)` to `'t`, justified by `(mev (meta-extract-contextual-fact (list ':rw (list 'goal-fn ...) '? nil) mfc state) a)`.
5. Prove `(defthm false-thm (implies (trig '0) (wrap-fn '0)) :rule-classes nil)`:
   - `forward-chain-top` fires `fc-goal` on `(trig '0)`, forcing `(false-fn '0)` and adding `((goal-fn '0) *ts-t* . <ttree-with-forced-assumption-(false-fn '0)>)` to `type-alist`.
   - Rewriting `(wrap-fn '0)` invokes `mf`, which calls `(mfc-rw '(goal-fn '0) '? nil mfc state :forcep nil :ttreep nil)`.
   - `mfc-rw-raw` rewrites `(goal-fn '0)` to `'t` using the forced `type-alist` entry; `mfc-rw-fn` discards the resulting `ttree` containing `'assumption` `(false-fn '0)`.
   - `mf` returns `'t`, `false-thm` succeeds immediately (`Q.E.D.`) with **zero forcing rounds**, never proving `(false-fn '0)`!
6. Enable the executable counterparts of `trig`, `wrap-fn`, and `goal-fn`, and `:use false-thm` to prove `(defthm nil-proved nil :rule-classes nil)`.

### Standalone Exploit (`/Users/ember/dev/compiler-audit/hunts/prover-falsify/tmp-engine/test-meta-extract-forced-ta.lisp`)
```lisp
(in-package "ACL2")

(defun trig (x)
  (declare (xargs :guard t) (ignore x))
  t)

(defun false-fn (x)
  (declare (xargs :guard t) (ignore x))
  nil)

(defun goal-fn (x)
  (declare (xargs :guard t) (ignore x))
  nil)

(defun wrap-fn (x)
  (declare (xargs :guard t))
  (goal-fn x))

(defthm fc-goal
  (implies (and (trig x)
                (force (false-fn x)))
           (equal (goal-fn x) t))
  :rule-classes ((:forward-chaining :trigger-terms ((trig x)))))

(in-theory (disable trig false-fn goal-fn
                    (:executable-counterpart trig)
                    (:executable-counterpart false-fn)
                    (:executable-counterpart goal-fn)
                    (:type-prescription trig)
                    (:type-prescription false-fn)
                    (:type-prescription goal-fn)))

(defevaluator mev mev-lst
  ((equal a b)
   (goal-fn x)
   (wrap-fn x))
  :namedp t)

(defun mf (term mfc state)
  (declare (xargs :stobjs state))
  (if (and (consp term)
           (eq (car term) 'wrap-fn)
           (consp (cdr term))
           (null (cddr term))
           (equal (mfc-rw (list 'goal-fn (cadr term)) '? nil mfc state
                          :forcep nil :ttreep nil)
                  ''t))
      ''t
    term))

(defthm mf-correct
  (implies (mev (meta-extract-contextual-fact
                 (list ':rw
                       (list 'goal-fn (if (and (consp term) (consp (cdr term)))
                                          (cadr term)
                                        nil))
                       '?
                       nil)
                 mfc state)
                a)
           (equal (mev term a)
                  (mev (mf term mfc state) a)))
  :rule-classes ((:meta :trigger-fns (wrap-fn))))

(in-theory (disable wrap-fn
                    (:executable-counterpart wrap-fn)
                    (:type-prescription wrap-fn)))

(defthm false-thm
  (implies (trig '0)
           (wrap-fn '0))
  :rule-classes nil)

(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal" :use false-thm
                  :in-theory (enable (:executable-counterpart trig)
                                     (:executable-counterpart wrap-fn)
                                     (:executable-counterpart goal-fn)))))

(assert-event
 (and (null (ttag (w state)))
      (null (global-val 'skip-proofs-seen (w state)))
      (null (global-val 'redef-seen (w state)))
      (equal (formula 'nil-proved t (w state)) ''nil)))
```

### Verification Output
- **SBCL 2.6.10** (`/Users/ember/dev/acl2-fix/head-worktree/saved_acl2`): `FALSE-THM` `Q.E.D.` (`0.00s`, 0 forcing rounds), `NIL-PROVED` `Q.E.D.` (`0.00s`), `ASSERT-EVENT` `:PASSED`, exit code `0`.
- **CCL 1.14** (`/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2`): `FALSE-THM` `Q.E.D.` (`0.00s`, 0 forcing rounds), `NIL-PROVED` `Q.E.D.` (`0.01s`), `ASSERT-EVENT` `:PASSED`, exit code `0`.

### Recommended Fix
When `forcep` is `nil` in `mfc-ts-raw`, `mfc-rw-raw`, `mfc-relieve-hyp-raw`, and `mfc-ap-raw` (`ld.lisp:4516-4908`)—and/or whenever `ttree` is discarded in `mfc-*-fn` (`interface-raw.lisp:8355-8394`):
1. **Filter the input context** when `(null forcep)`: strip from `(access metafunction-context mfc :type-alist)` any `(term ts . ttree)` entry where `(contains-assumptionp ttree)` is non-nil, and strip from `(access metafunction-context mfc :simplify-clause-pot-lst)` any `poly` where `(contains-assumptionp (access poly p :ttree))` is non-nil (lazily caching or filtering on demand when `forcep = nil`).
2. **Defense-in-depth output check** when `(null forcep)` (matching `tau`'s `relieve-dependent-hyps` discipline):
   - In `mfc-ts-raw`: if `(contains-assumptionp ttree)` is true, return `(mv *ts-unknown* nil)`.
   - In `mfc-rw-raw`: if `(contains-assumptionp ttree)` is true, return `(mv (if (eq fn 'mfc-rw) term (sublis-var alist term)) nil)`.
   - In `mfc-relieve-hyp-raw`: if `(contains-assumptionp ttree)` is true, return `(mv nil nil)`.
   - In `mfc-ap-raw`: bind `(mv linearized-list lin-ttree) (linearize ...)` instead of dropping `lin-ttree`, and require `(not (contains-assumptionp lin-ttree))` as well as `(not (contains-assumptionp (access poly contradictionp :ttree)))` (for both disjuncts when `(cdr linearized-list)` is non-nil) before returning non-nil.

---

## Minor Non-Soundness Observations

1. **`rewrite-quoted-constant-with-lemma` No-Change Loser Tag-Tree Leak (`rewrite.lisp:23280`)**:
   - At `rewrite.lisp:23126-23128`, `rewrite-quoted-constant-with-lemma` documents that it is a *"No-Change Loser, modulo the rw-cache"* (meaning on `flg = nil` failure it should return the caller's unchanged `ttree`).
   - In the form `[2]` branch (`n = 2`, `rewrite.lisp:23244-23280`), `relieve-hyps` (`:23254`) and `rewrite` (`:23271`) rebind local `ttree` (potentially adding forced `'assumption` records). If `rewritten-rhs` either equals `term` or is not `quotep` (`:23274-23275`), line `23280` returns `(mv step-limit nil term ttree)` with the mutated `ttree` instead of the entry `ttree`. If a subsequent rule in `rewrite-quoted-constant-with-lemmas` (`:23295-23302`) succeeds, those unused forced `'assumption` tags remain in `ttree`. This only over-approximates forced obligations (spurious forcing round / completeness issue, not unsoundness).
2. **Typo in `bdd.lisp:2320` (`combine-op-csts2`)**:
   - Line `2320` tests `(quotep arg2)` where `arg2` is a `cst` record (`(trm id . rules)`), rather than `(quotep (trm arg2))` (compare lines `2316-2318`). Since `(car cst)` is a term rather than `'quote` (unless `trm` happens to be the symbol `quote`), `(quotep arg2)` evaluates to `nil`, harmlessly skipping a canonicalization swap before `(< (unique-id arg1) (unique-id arg2))`.

---

## Summary of Audited Subsystems & Ruled-Out Hypotheses

| Subsystem / Files | Key Functions Audited | Verdict |
|-------------------|-----------------------|---------|
| Proof-Builder (`proof-builder-a.lisp`, `proof-builder-b.lisp`, `other-events.lisp:27590-28499`, `ld.lisp:1390-1435`) | `verify`, `defthm-fn1` `:instructions` handoff (`equal-x-cons-x-yp` / `pc-prove`), `rewrite`, `apply-linear`, `equiv`, `claim`, `casesplit`, `split`, `induct`, `bash`, `bdd`, `prove`, `define-pc-macro` / `define-pc-atomic-macro` | **Bug #1 confirmed** in `apply-linear` (`proof-builder-b.lisp:3226-3332`). Other PC primitives properly respect `governors` or restrict mutations to `current-addr`. |
| Extended Metafunction Context & `meta-extract` (`boot-strap-pass-2-a.lisp:1260-1420`, `ld.lisp:4500-5020`, `interface-raw.lisp:8355-8395`, `defthm.lisp:4433-4560`, `rewrite.lisp:19065-19505`) | `meta-extract-contextual-fact`, `remove-meta-extract-contextual-hyps`, `mfc-ts-raw`, `mfc-rw-raw`, `mfc-relieve-hyp-raw`, `mfc-ap-raw`, `rewrite-with-lemma` (`meta` subclass) | **Bug #2 confirmed** across `meta-extract-contextual-fact` / `mfc-*` (`:forcep nil :ttreep nil` inherits forced `'assumption`s from `mfc`). |
| Rewriter, Equivalence/Congruence, `bind-free`/`synp`, Dirty Lambdas (`rewrite.lisp:1-23637`, `translate.lisp:5305-6250`) | `rewrite`, `geneqv-lst`, `rewrite-solidify`, `rewrite-equal`, `rewrite-if`, `relieve-hyp-synp`, `bind-free-info`, `rewrite-fncall`, `rewrite-with-lemmas`, `rewrite-quoted-constant`, `rewrite-lambda-object`, `clean-up-dirty-lambda-objects` | Sound. `bind-free` alist validation (`bind-free-info`) checks `termp`/`logic-termp`/symbol keys; `clean-up-dirty-lambda-object-body` enforces `well-formed-lambda-objectp` and `(subsetp-equal warrants hyps)`. Minor `ttree` leak on failed form [2] `:rewrite-quoted-constant` (`:23280`). |
| Clause Simplifier, Forward-Chaining & Assumption Tracking (`simplify.lisp:1-10029`) | `process-assumptions`, `forward-chain-top`, `expunge-fc-derivations`, `find-trivial-equivalence`, `every-occurrence-equiv-hittablep`, `subst-equiv-and-maybe-delete-lit`, `resume-suspended-assumption-rewriting`, `rewrite-clause`, `process-equational-polys`, `simplify-clause1` | Sound in isolation (`expunge-fc-derivations` recursively cleans nested `'assumption` `:type-alist`s; `hide` and `geneqv` refinement checks in `subst-equiv-and-maybe-delete-lit` are sound; `resume-suspended-assumption-rewriting` re-records non-`*t*` rewritten assumptions). |
| Waterfall, Hints & Forcing Loop (`prove.lisp:1-8601`, `induct.lisp:934-1360`) | `prove`, `prove-loop`, `prove-loop1` (`forcing-round`), `waterfall`, `:by` subsumption (`subsumes`), `:use`, `:clause-processor`, `:custom-keyword-hints`, `:or` hints, `preprocess-clause`, `cheap-type-alist-and-pot-lst` | Sound. Forcing rounds properly collect and clausify all `'assumption` tags present in surviving proof `ttree`s (`extract-and-clausify-assumptions`). |
| OBDD Prover (`bdd.lisp:1-3288`) | `bdd-clause`, `chk-bdd-Constructors`, `first-boolean-type-prescription`, `combine-if-csts1`, `combine-op-csts1`, `bdd-term` | Sound (`booleanp` guards on `EQUAL` and `IF` collapses are properly enforced via `known-boolean` / `first-boolean-type-prescription`). Minor harmless typo at `bdd.lisp:2320`. |
