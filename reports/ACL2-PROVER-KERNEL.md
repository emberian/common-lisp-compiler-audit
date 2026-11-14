# ACL2 8.7+ Pure-Kernel Prover Soundness Audit & Counterexample-Guided Falsification

- **Target Version:** ACL2 `8.7+` (git commit `1d2b39a424eabeab269f189b37c29148d49fc516`)
- **Verified Host Images:**
  - SBCL `2.6.10` (`darwin-arm64`): `/Users/ember/dev/acl2-fix/head-worktree/saved_acl2`
  - Clozure Common Lisp (CCL) `1.14` (`darwinarm64`): `/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2`
- **Scope:** Pure-kernel first-order prover subsystems and logical event admission (`:ttag nil`, `:ttags-seen nil`, `:skip-proofs-seen nil`, `:redef-seen nil`, zero books, zero raw Lisp, zero host-compiler UB, zero reader/serialization/filesystem gadgets).
- **Fuzzer & Audit Artifacts:** `/Users/ember/dev/compiler-audit/hunts/prover-falsify/` (`fuzzer.py`, `fuzzer_v2.py`, `fuzzer_v2_results.json`, `campaign-*.log`, `notes-engine.md`, `notes-rules.md`)
- **Standalone Reproducers:** `/Users/ember/dev/compiler-audit/repros/prover-*/`

---

## 1. Executive Summary

Forty-three of ACL2's 278 historical soundness bugs reside inside the **pure prover kernel** rather than raw Common Lisp code generation, serialization, or the book-certification filesystem layer. Combining a line-by-line source audit of ACL2's core prover subsystems with two automated **Counterexample-Guided Prover Fuzzers** (`41,400` concrete-witness-falsified candidate theorems tested across SBCL 2.6.10 and CCL 1.14) uncovered:

- **Six (6) novel, standalone pure-kernel `(defthm nil-proved nil :rule-classes nil)` soundness bugs (`PK-S1` – `PK-S6`)** — every single one verified in a single fresh ACL2 session on **both SBCL 2.6.10 and CCL 1.14** with `:ttag nil`, `:ttags-seen nil`, `:skip-proofs-seen nil`, `:redef-seen nil`, zero `include-book`s, and zero host-specific reader conditionals;
- **One (1) novel pure-kernel Evaluation-Theory / Attachment-Consistency & Vacuous `:guard nil` Verification soundness bug (`PK-E1`)** — proving `(defthm not-warrant-liar (not (apply$-warrant-liar)))` in pure first-order logic while `(apply$-warrant-liar)` evaluates to `T` at the top level, directly falsifying ACL2's metatheoretic `Proposition (Attachment Consistency)` (`other-events.lisp:30435`) and vacuously verifying `:guard nil`; and
- **Five (5) minor non-soundness kernel logic defects (`PK-M1` – `PK-M5`)** in `:tau-system`, non-linear arithmetic, OBDD canonicalization, and `:rewrite-quoted-constant`.

### Summary Table of Soundness Findings

| ID | Severity | Subsystem | Primary Kernel Locations | Standalone Reproducer | SBCL 2.6.10 | CCL 1.14 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **PK-S1** | **Critical (`NIL` Proved)** | Type-Set + Free Vars + `force` | `type-set-b.lisp:8654, 8428` (`type-set-relieve-hyps`, `type-set-relieve-hyps-free`) | `repros/prover-tp-free-force-ttree/` | `NIL-PROVED` (`0.00s`) | `NIL-PROVED` (`0.00s`) |
| **PK-S2** | **Critical (`NIL` Proved)** | Rewriter / Linear / Meta + `bind-free` + `force` | `rewrite.lisp:18395` (`relieve-hyps1-unify-subst-lst`) | `repros/prover-rw-bind-free-force-ttree/` | `NIL-PROVED` (`0.00s`) | `NIL-PROVED` (`0.00s`) |
| **PK-S3** | **Critical (`NIL` Proved)** | `meta-extract-contextual-fact` + `mfc-*` + `force` | `boot-strap-pass-2-a.lisp:1290-1333`, `interface-raw.lisp:8355-8394`, `ld.lisp:4516-4908`, `rewrite.lisp:19077-19091`, `defthm.lisp:4433-4462` | `repros/prover-mfc-forced-context-leak/` | `NIL-PROVED` (`0.00s`) | `NIL-PROVED` (`0.01s`) |
| **PK-S4** | **Critical (`NIL` Proved)** | Proof-Builder `:apply-linear` (`:al`) | `proof-builder-b.lisp:3226, 3244, 3284, 3322, 3326-3332` (`apply-linear`) | `repros/prover-pb-apply-linear-governors/` | `NIL-PROVED` (`0.00s`) | `NIL-PROVED` (`0.01s`) |
| **PK-S5** | **Critical (`NIL` Proved)** | `encapsulate` Pass 2 + `loop$` Warrants + `:guard-theorem` | `defuns.lisp:4310-4327`, `history-management.lisp:13303-13304, 13413-13414, 14550-14596, 14810-14837` | `repros/prover-encap-local-warrant-guard-thm/` | `NIL-PROVED` (`0.00s`) | `NIL-PROVED` (`0.00s`) |
| **PK-S6** | **Critical (`NIL` Proved)** | `badge-table-guard1` + `:guard-theorem` | `apply.lisp:1966-1972`, `history-management.lisp:13413, 14810`, `other-events.lisp:33628-33633` | `repros/prover-badge-table-guard-thm-warrant/` | `NIL-PROVED` (`0.00s`) | `NIL-PROVED` (`0.01s`) |
| **PK-E1** | **High (Attachment Inconsistency & Vacuous `:guard nil`)** | `bad-ancestor1` + Constrained Fns + `defwarrant` | `apply.lisp:1242, 1262, 1773, 1867`, `other-events.lisp:30435, 31432-31445, 32347-32358` | `repros/prover-bad-ancestor-constrained-liar/` | Confirmed (`0.00s`) | Confirmed (`0.01s`) |

All seven findings were cross-checked against `/Users/ember/dev/compiler-audit/ACL2-BUG-REPORT.md`, `/Users/ember/dev/compiler-audit/reports/ACL2-BATCH-2.md`, `ACL2-STATE-CACHE-RISK.md` (specifically distinguishing `PK-S5`/`PK-S6`/`PK-E1` from `SCR-S2` / `memoize-cl-cache-warrant-bypass`), `ACL2-XDSMITH-GUARDS.md`, `ACL2-PKG-SERIALIZE-CERT.md`, `Z3-COMPILER-EQUIVALENCE.md`, `doc.lisp` (`note-8-8`), and the three previously reported bugs (`#2055` `:linear` `:null-lst` leak, `defthm.lisp:5381` `:meta` `hyp-fn` guard check, and `proof-builder-a.lisp:1593` `(verify t)` empty goal stack). Zero duplicates exist.

---

## 2. Detailed Soundness Bug Analyses

### PK-S1: `type-set-relieve-hyps` Overwrites Accumulated `ttree` with `ttree0` When Backtracking Across Free-Variable Matches

- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/prover-tp-free-force-ttree/` (`repro.lisp`, `run.sh`)
- **Affected Source:** `type-set-b.lisp:8649-8673` (`type-set-relieve-hyps`) and `type-set-b.lisp:8427-8448` (`type-set-relieve-hyps-free`)

#### Root Cause
When relieving hypotheses of a `:type-prescription` rule, `type-set-relieve-hyps` threads two tag-tree parameters:
- `ttree`: the accumulated tag-tree for hypotheses relieved **so far** (including forced `'assumption` records pushed by `force-assumption` when an earlier hypothesis `(force P)` or `(case-split P)` was forced);
- `ttree0`: the entry tag-tree before the `:type-prescription` rule began (`nil` in `type-set-with-rule` at `type-set-b.lisp:8744`), to be returned **only if the entire rule fails**.

When a hypothesis `(p x y)` binds a new free variable `y` via `search-type-alist-with-rest` (`type-set-b.lisp:8644`) and `rest-type-alist` is non-empty, `type-set-relieve-hyps` tries the remaining hypotheses `(cdr hyps)` under `alist+`, and on failure falls through to `type-set-relieve-hyps-free` (`:8653-8673`):

```lisp
(mv-let
  (relieve-hyps-ans type-alist ttree) ; <--- BUG: shadows `ttree` with `ttree0` on failure!
  (type-set-relieve-hyps rune target (cdr hyps) (cdr backchain-limit-lst)
                         force-flg dwp alist+ type-alist ancestors ens wrld
                         ttree ttree0 pot-lst pt backchain-limit bkptr+1)
  (cond
   (relieve-hyps-ans (mv relieve-hyps-ans type-alist ttree))
   (t (type-set-relieve-hyps-free term typ rest-type-alist
                                  rune target hyps backchain-limit-lst
                                  force-flg dwp alist
                                  type-alist ancestors ens wrld
                                  ttree ttree0 ; <--- `ttree` is now `ttree0` (NIL)!
                                  pot-lst pt backchain-limit bkptr+1))))
```

Because a failed call to `type-set-relieve-hyps` returns `(mv nil type-alist ttree0)` (`type-set-b.lisp:8564, 8684, 8687`), rebinding `(mv-let (relieve-hyps-ans type-alist ttree) ...)` at **line `8654`** (and identically inside `type-set-relieve-hyps-free` at **line `8428`**) overwrites `ttree` with `ttree0` (`nil`)! When `type-set-relieve-hyps-free` subsequently finds a second match on `rest-type-alist` that satisfies `(cdr hyps)`, `type-set-with-rule` succeeds and returns a `ttree` from which **every forced `'assumption` (as well as `'fc-derivation`, `'pt`, and `'lemma` tags) from hypotheses preceding the free-variable hypothesis has been erased**.

#### Minimal Exploit Walkthrough
1. Define `(h1 x) = (equal x 99)`, `(p x y) = (and (integerp x) (integerp y))`, `(q y) = (equal y 2)`, and `(foo x) = (not (h1 x))`.
2. Admit the valid `:type-prescription` rule:
   ```lisp
   (defthm foo-tp-false-when-h1
     (implies (and (force (h1 x)) (p x y) (q y))
              (not (foo x)))
     :rule-classes ((:type-prescription :typed-term (foo x))))
   ```
3. Disable `h1`, `p`, `q`, `foo` and prove the false conjecture:
   ```lisp
   (defthm unsound-tp-free-force
     (implies (and (p x 2) (p x 1) (not (q 1)) (q 2))
              (not (foo x)))
     :rule-classes nil)
   ```
   - `assume-true-false` pushes `(p x 2)` then `(p x 1)` onto `type-alist`, so `(p x 1)` sits ahead of `(p x 2)`.
   - `type-set` on `(foo x)` forces `(h1 x)` into `ttree`, then matches `(p x y)` with `y = 1` first.
   - `(q 1)` fails (`(not (q 1))` is on `type-alist`), returning `ttree0 = nil` and wiping the forced `(h1 x)` assumption from `ttree`.
   - `type-set-relieve-hyps-free` next matches `(p x 2)` (`y = 2`), relieves `(q 2)`, and concludes `(foo x)` has type `*ts-nil*` with **zero `'assumption` tags** (`Q.E.D.`, 0 forcing rounds)!
4. Instantiating `unsound-tp-free-force` at `x = 0` (where `(p 0 2)`, `(p 0 1)`, `(not (q 1))`, `(q 2)` are all `T` and `(not (foo 0))` is `NIL`) proves `(defthm nil-proved nil :rule-classes nil)`.

#### Surgical Fix
In both `type-set-relieve-hyps` (`type-set-b.lisp:8654`) and `type-set-relieve-hyps-free` (`type-set-b.lisp:8428`), bind the recursive tag-tree return value to a fresh variable `ttree1`, return `ttree1` when `relieve-hyps-ans` is non-nil, and pass the **unchanged** `ttree` to `type-set-relieve-hyps-free` on failure.

---

### PK-S2: `relieve-hyps1-unify-subst-lst` Passes `ttree0` Instead of `ttree` on `bind-free` Backtracking

- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/prover-rw-bind-free-force-ttree/` (`repro.lisp`, `run.sh`)
- **Affected Source:** `rewrite.lisp:18384-18395` (`relieve-hyps1-unify-subst-lst`)

#### Root Cause
When a `:rewrite`, `:linear`, or `:meta` rule contains a `(bind-free ...)` hypothesis returning multiple candidate binding alists `(s1 s2 ...)`, `relieve-hyps1` delegates to `relieve-hyps1-unify-subst-lst` (`rewrite.lisp:18345-18395`). When `s1` fails a subsequent hypothesis (`(null ans)`), lines `18384-18395` advance to `(cdr unify-subst-lst)`:

```lisp
(t ; try the next unify-subst in unify-subst-lst
 (rewrite-entry-extending-failure
  new-unify-subst
  failure-reason
  (relieve-hyps1-unify-subst-lst
   (cdr unify-subst-lst)
   rune target hyps backchain-limit-lst
   unify-subst bkptr
   unify-subst0 ttree0 allp
   rw-cache-alist rw-cache-alist-new)
  :obj nil :geneqv nil :pequiv-info nil ; all ignored
  :ttree (accumulate-rw-cache t ttree1 ttree0))) ; <--- BUG: `ttree0` instead of `ttree`!
```

Compare this directly with `relieve-hyps1-free-1` at `rewrite.lisp:18678`, which correctly writes:
```lisp
:ttree (accumulate-rw-cache t ttree1 ttree)
```

Passing `ttree0` instead of `ttree` at `rewrite.lisp:18395` resets the active tag-tree back to the pre-lemma `ttree0` (preserving only `'rw-cache` entries from `ttree1`), silently discarding all forced `'assumption` records accumulated from hypotheses **preceding** `bind-free` whenever candidate alist `s1` fails and candidate alist `s2` succeeds!

#### Minimal Exploit Walkthrough
1. Define `(h1 x) = (equal x 99)` and `(foo x) = (not (h1 x))`.
2. Admit the valid `:rewrite` rule:
   ```lisp
   (defthm foo-rw-false-via-bind-free
     (implies (and (force (h1 x))
                   (bind-free '(((y . '1)) ((y . '2))) (y))
                   (equal y 2))
              (equal (foo x) nil)))
   ```
   *(The same bug also triggers on `:linear` rules via `add-linear-lemma` and `:meta` rules with hypotheses, as verified in `fuzzer_v2.py`.)*
3. Disable `h1` and `foo`, then prove `(defthm unsound-bind-free-lemma (equal (foo x) nil) :rule-classes nil)`:
   - Hypothesis 1 forces `(h1 x)` into `ttree`.
   - Hypothesis 2 (`bind-free`) yields `(((y . '1)) ((y . '2)))`.
   - Candidate `((y . '1))` fails `(equal '1 2)`. Line `18395` recurses on `(((y . '2)))` with `:ttree (accumulate-rw-cache t ttree1 ttree0)`, wiping the forced `(h1 x)` `'assumption`.
   - Candidate `((y . '2))` satisfies `(equal '2 2)`, rewriting `(foo x)` to `nil` unconditionally (`Q.E.D.`, 0 forcing rounds)!
4. Instantiating at `x = 0` proves `(defthm nil-proved nil :rule-classes nil)`.

#### Surgical Fix
At `rewrite.lisp:18395`, replace `ttree0` with `ttree`:
```diff
- :ttree (accumulate-rw-cache t ttree1 ttree0)))))))))))))
+ :ttree (accumulate-rw-cache t ttree1 ttree)))))))))))))
```

---

### PK-S3: `meta-extract-contextual-fact` & `mfc-*` (`:forcep nil`) Inherit Forced Contextual Assumptions and Silently Discard Their Tag-Trees

- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/prover-mfc-forced-context-leak/` (`repro.lisp`, `run.sh`)
- **Affected Source:**
  - `boot-strap-pass-2-a.lisp:1290-1333` (`meta-extract-contextual-fact`)
  - `defthm.lisp:4433-4462, 4506-4509` (`remove-meta-extract-contextual-hyps`)
  - `rewrite.lisp:19077-19091, 19496-19503` (`rewrite-with-lemma` `:meta` `mfc` construction)
  - `ld.lisp:4516-4570` (`mfc-ts-raw`), `4601-4671` (`mfc-rw-raw`), `4687-4791` (`mfc-relieve-hyp-raw`), `4801-4897` (`mfc-ap-raw`), `5003-5017` (`mfc-force-flg`, `update-rncst-for-forcep`)
  - `interface-raw.lisp:8355-8394` (`mfc-ts-fn`, `mfc-rw-fn`, `mfc-rw+-fn`, `mfc-relieve-hyp-fn`, `mfc-ap-fn`)

#### Root Cause
When a `:meta` rule has hypotheses of the form `(ev (meta-extract-contextual-fact obj mfc state) a)`, `remove-meta-extract-contextual-hyps` (`defthm.lisp:4433-4462`) **erases those hypotheses** from the stored `:meta` rule so they are not relieved at rule-application time. As documented in `boot-strap-pass-2-a.lisp:1294-1304`, erasing these hypotheses is sound *only* if `meta-extract-contextual-fact` produces formulas guaranteed to hold in the active `mfc` context without unrecorded forced assumptions. To that end, `meta-extract-contextual-fact` calls `mfc-ts`, `mfc-rw+`, `mfc-rw`, `mfc-ap`, and `mfc-relieve-hyp` with `:forcep nil` (and `:ttreep nil`).

**The flaw:** `:forcep nil` only sets `force-flg = nil` (`ld.lisp:5003`) and `(access rewrite-constant rcnst :force-info) = 'weak` (`ld.lisp:5008`), which prevents **new** `force-assumption` calls during the `mfc-*` query itself. It does **not** filter or reject pre-existing contextual entries inside `mfc` that **already carry forced `'assumption` records in their per-entry `ttree`s**:

1. During `simplify-clause1` (`simplify.lisp:8170-8240`) and `assume-true-false` on `IF` tests, `forward-chain-top` and `setup-simplify-clause-pot-lst` run with forcing enabled. When a `:forward-chaining` or `:linear` rule forces `(force P)`, ACL2 stores the `'assumption` record **lazily inside that individual `type-alist` entry `(term ts . entry-ttree)` or `poly` `:ttree`** — *not* in the clause's top-level `ttree`. Soundness depends on any consumer merging `entry-ttree` / `poly-ttree` into the active proof `ttree` if that fact is used.
2. `rewrite-with-lemma` (`rewrite.lisp:19077-19091`) passes `:type-alist type-alist` and `:simplify-clause-pot-lst simplify-clause-pot-lst` verbatim into `mfc`.
3. `mfc-ts-raw`, `mfc-rw-raw`, and `mfc-relieve-hyp-raw` read those forced entries and propagate their `'assumption` records into a local `ttree` — which `mfc-ts-fn`, `mfc-rw-fn`, `mfc-rw+-fn`, and `mfc-relieve-hyp-fn` (`interface-raw.lisp:8355-8387`) **immediately discard via `(declare (ignore ttree))`**!
4. Likewise, `mfc-ap-raw` (`ld.lisp:4817, 4851, 4896`) drops the `ttree` returned by `linearize` and treats a `contradictionp` `poly` from `add-polys` as unconditionally true without checking `(access poly contradictionp :ttree)` for `'assumption` tags!

*(Contrast this with `tau` in `induct.lisp:939-943` and `tau.lisp:11842-11856`, where ACL2 explicitly strips forced assumptions before building `tau`'s `type-alist` AND checks `(not (contains-assumptionp ttree))` after `type-set`.)*

#### Minimal Exploit Walkthrough
`repros/prover-mfc-forced-context-leak/repro.lisp` demonstrates three distinct `meta-extract-contextual-fact` operators (`:typeset` via `mfc-ts`, `:rw+` via `mfc-rw+`, and `:ap` via `mfc-ap`) laundering forced assumptions from both `type-alist` (`:forward-chaining`) and `simplify-clause-pot-lst` (`:linear`) with zero failed events:
1. Admit valid `:forward-chaining` rules `(implies (and (trig x) (force (h1 x))) (not (aux x)))` and `(implies (and (trig x) (force (h1 x))) (equal (aux-t x) t))`, and a valid `:linear` rule `(implies (and (< 0 x) (force (h1 x))) (< (val x) 0))` where `(h1 x) = (equal x 99)` and `(val x) = (if (h1 x) -1 10)`.
2. Admit verified `:meta` rules `meta-ts-correct`, `meta-rw-correct`, and `meta-ap-correct` backed by `meta-extract-contextual-fact`.
3. Prove all three false lemmas (`unsound-mfc-ts-lemma`, `unsound-mfc-rw-lemma`, `unsound-mfc-ap-lemma`) with **zero forcing rounds**, and instantiate at `x = 0` to prove `(defthm nil-proved nil :rule-classes nil)`.

#### Surgical Fix
Whenever `(null forcep)` in `mfc-ts-raw`, `mfc-rw-raw`, `mfc-relieve-hyp-raw`, and `mfc-ap-raw` (`ld.lisp:4516-4908`):
1. Strip entries whose `ttree` satisfies `(contains-assumptionp ttree)` from the `type-alist` and `simplify-clause-pot-lst` consulted by the `mfc-*` query; **and**
2. Check `(contains-assumptionp ttree)` on the resulting `ttree` (including `linearize`'s `ttree` and `(access poly contradictionp :ttree)` in `mfc-ap-raw`): if non-nil, refuse the derivation (returning `(mv *ts-unknown* nil)` for `mfc-ts-raw`, the unrewritten input term for `mfc-rw-raw`, and `(mv nil nil)` / `nil` for `mfc-relieve-hyp-raw` and `mfc-ap-raw`).

---

### PK-S4: Proof-Builder `:apply-linear` (`:al`) Promotes Branch-Local `governors` to Top-Level Goal `:hyps`

- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/prover-pb-apply-linear-governors/` (`repro.lisp`, `run.sh`)
- **Affected Source:** `proof-builder-b.lisp:3226, 3244, 3284, 3322, 3326-3332` (`define-pc-primitive apply-linear`)

#### Root Cause
`define-pc-primitive apply-linear` (`proof-builder-b.lisp:3204-3349`) copies the context setup of the proof-builder `rewrite` primitive:
```lisp
(current-term (fetch-term conc current-addr))
(assumptions (union-equal hyps (governors conc current-addr)))
```
When dived (`:dv`) into a subterm of the conclusion `conc` — e.g., into the `THEN` branch `Q` of `(if P Q R)` — `(governors conc current-addr)` includes the branch test `P`. Using `P` in `assumptions` is sound for `rewrite` (`proof-builder-b.lisp:3159-3165`) because `rewrite` replaces `current-term` **in place at `current-addr`**, which is governed by `P`.

By contrast, `:apply-linear`:
1. Builds `hyps-type-alist` from `assumptions = hyps ∪ governors(conc, current-addr)` (`:3244`),
2. Relieves the `:linear` rule's hypotheses `lemma-hyps` against `hyps-type-alist` (`:3284`) (and assigns `assumptions` to any unrelieved-hyp subgoals at `:3322-3325`), **yet**
3. Appends the instantiated conclusion `(sublis-var unify-subst lemma-concl)` unconditionally to **top-level goal `:hyps`** (`:3326-3332`):
   ```lisp
   (changed-goal
    (change goal (car goals)
            :hyps (append hyps (list (sublis-var unify-subst lemma-concl)))
            :depends-on (+ depends-on (length new-goals))))
   ```

#### Minimal Exploit Walkthrough
1. Define `(defun trig () 0)` and prove the tautologous `:linear` rule `(defthm trig-lin (implies (< (trig) 0) (< (trig) 0)) :rule-classes ((:linear :trigger-terms ((trig)))))`.
2. Disable `trig` and prove `(if (< (trig) 0) (equal (trig) 0) nil)` (which evaluates to `nil`!) via `:instructions`:
   - `(:dv 2) (:dv 1)` dives to `(trig)` inside `(equal (trig) 0)`, where `(governors conc '(2 1)) = ((< (trig) 0))`.
   - `(:apply-linear trig-lin)` relieves `(< (trig) 0)` from the branch governor and appends the false fact `(< (trig) 0)` to top-level `:hyps`!
   - `:top`, `(:in-theory (enable (:executable-counterpart trig)))`, `:s` discharges the goal by `"Contradiction in the hypotheses!"`, immediately yielding `(defthm nil-proved nil :rule-classes nil)`.

#### Surgical Fix
In `apply-linear` (`proof-builder-b.lisp:3226`), either bind `assumptions` to `hyps` alone (using `current-addr` strictly to select `current-term` for trigger matching), or when `(governors conc current-addr)` is non-nil, guard the added top-level hypothesis as `(implies (conjoin (governors conc current-addr)) (sublis-var unify-subst lemma-concl))` (or rewrite `current-term` at `current-addr` to `(implies inst-concl current-term)`).

---

### PK-S5: `local` Warrant World-Drift Across `encapsulate` Pass 2 + `:guard-theorem`

- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/prover-encap-local-warrant-guard-thm/` (`repro.lisp`, `run.sh`)
- **Affected Source:**
  - `history-management.lisp:13290-13320` (`collect-warranted-fns`), `13409-13415` (`special-conjectures`), `14550-14596` (`guard-theorem`), `14810-14837` (`translate-lmi` `:guard-theorem`)
  - `defuns.lisp:4310-4327` (`chk-common-lisp-compliant-subfunctions-cmp`)

#### Root Cause
1. When generating guard proof obligations for a `loop$` scion call (`collect$`, `sum$`, `always$`, `do$`, etc.), `special-conjectures` (`history-management.lisp:13409-13415`) adds negated warrant literals `(collect-negated-warrants term wrld nil)` by walking all `:FN` and `:EXPR` slots of `term` — **including non-lambda expressions** such as `(list (apply$ 'g '(nil)))` in the target list of `collect$` — and testing `(get-warrantp val wrld)` (`:13303-13304`).
2. Inside Pass 1 of an `encapsulate`, a `(local ...)` block can introduce `apply$-warrant-g` and mark `g` warranted (`warrantp = t`), allowing a non-local `(defun fn () (declare (xargs :guard t)) (collect$ (lambda$ (x) (declare (xargs :guard (equal x 0))) x) (list (apply$ 'g '(nil)))))` to verify its guard **using the hypothesis `(apply$-warrant-g)`**.
3. During Pass 2 of `encapsulate` (`ld-skip-proofsp = 'include-book`), the `local` warrant events and `fn`'s guard proof are skipped, while `chk-common-lisp-compliant-subfunctions-cmp` (`defuns.lisp:4313-4317`) checks warrants **only on well-formed quoted lambda objects**:
   ```lisp
   (warrants-for-tamep-lambdap-lst
    (collect-certain-lambda-objects :well-formed (car terms) wrld nil)
    wrld nil nil)
   ```
   Because `'g` appears in `(list (apply$ 'g '(nil)))` outside any lambda object (and `g` already had a `warrantp = nil` badge before the `encapsulate`), Pass 2 exports `fn` with `symbol-class = :common-lisp-compliant` into an outer world where `(get-warrantp 'g wrld)` is `NIL`!
4. Invoking `(:guard-theorem fn)` (`history-management.lisp:14810-14837`) trusts `(eq (symbol-class fn wrld) :common-lisp-compliant)` and recomputes `guard-clauses-for-clique` in the outer world (`:14581`), where `(get-warrantp 'g wrld) = nil` omits `(apply$-warrant-g)`! This produces the unconditional theorem `(implies (member-equal newv (list (apply$ 'g '(nil)))) (equal newv 0))`, proving `(equal (apply$-userfn 'g '(nil)) 0)` with zero warrant hypotheses; `:functional-instance` on the unconstrained `badge-userfn` and `apply$-userfn` immediately proves `(defthm nil-proved nil :rule-classes nil)`.

#### Surgical Fix
Record the exact list of warranted functions assumed during guard verification of `fn` (e.g., in a world property `'guard-warrants` populated from `collect-warranted-fns` across `fn`'s clique), verify in `chk-common-lisp-compliant-subfunctions-cmp` (`defuns.lisp:4310`) and `bogus-exported-compliants` (`other-events.lisp:3004`) that every function in `'guard-warrants` remains warranted in Pass 2 / exported worlds, and include `'guard-warrants` when reconstructing `(guard-theorem fn ...)`.

---

### PK-S6: Unrestricted `badge-table` Reset in `badge-table-guard1` Abandons Warrants Post-Bootstrap

- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/prover-badge-table-guard-thm-warrant/` (`repro.lisp`, `run.sh`)
- **Affected Source:** `apply.lisp:1966-1972` (`badge-table-guard1`), `history-management.lisp:13413, 14810` (`guard-theorem`), `other-events.lisp:33628-33633` (`add-trip`)

#### Root Cause
`badge-table-guard1` (`apply.lisp:1966-1972`) begins with:
```lisp
(cond
 ((null new-lst)
; It is legal simply to abandon all userfn badges and warrants!  But generally
; this is only done during bootstrapping to initialize the table.
  t)
 (t ...))
```
Because `(global-val 'boot-strap-flg wrld)` is **not** checked, any user session or certified book (`:ttag nil`, with **zero `encapsulate`s**) can execute `(table badge-table :badge-userfn-structure nil :put)` to wipe all badges and warrants after a function `fn` has already been guard-verified under `(apply$-warrant-g)` — **even when `'g` is inside a quoted lambda object** `'(lambda (x) (g x))`! Re-adding `g`'s badge with `warrantp = nil` leaves `fn` `:common-lisp-compliant` while `(get-warrantp 'g wrld)` is `nil`. Calling `(:guard-theorem fn)` then drops `(apply$-warrant-g)`, proving `(implies (equal (badge-userfn 'g) '(APPLY$-BADGE 1 1 . T)) (acl2-numberp (apply$-userfn 'g '(nil))))`, which `:functional-instance` with `(apply$-userfn (lambda (f args) t))` refutes in 11 prover steps to prove `(defthm nil-proved nil :rule-classes nil)`. *(This also falsifies `add-trip`'s explicit soundness invariant at `other-events.lisp:33628-33633` that `collect-warranted-fns` grows monotonically with the world.)*

#### Surgical Fix
Restrict `((null new-lst) ...)` in `badge-table-guard1` (`apply.lisp:1967`) to bootstrap:
```lisp
((null new-lst)
 (or (global-val 'boot-strap-flg wrld)
     (er hard 'badge-table-guard
         "~@0resetting :BADGE-USERFN-STRUCTURE to NIL is only permitted during bootstrapping."
         *badge-table-guard-msg*)))
```

---

### PK-E1: `bad-ancestor1` Constrained-Function Blind Spot Falsifies `Proposition (Attachment Consistency)` and Vacuously Verifies `:guard nil`

- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/prover-bad-ancestor-constrained-liar/` (`repro.lisp`, `run.sh`)
- **Affected Source:** `apply.lisp:1242, 1262, 1773, 1867` (`bad-ancestor1`, `ok-defbadge`, `chk-acceptable-defwarrant1`); `other-events.lisp:30435, 31432-31445, 32347-32358` (`defattach-constraint-rec`, `attachment-records`)

#### Root Cause
ACL2's doppelganger model for `apply$` requires that no G1 warranted function depend ancestrally on `*apply$-userfn-callers*` (`apply$-userfn`, `badge-userfn`, `apply$`, etc.). Both `ok-defbadge` (`apply.lisp:1773`) and `chk-acceptable-defwarrant1` (`:1867`) check `(bad-ancestor nil (body fn nil wrld) *apply$-userfn-callers* wrld)`. However, `bad-ancestor1` (`apply.lisp:1242, 1262`) traverses callees **solely via `(body (ffn-symb x) nil wrld)`**, which returns `nil` for any constrained function introduced by `encapsulate`! *(By contrast, the G2 check `not-pre-apply$-definable` at `apply.lisp:1909-1960` explicitly rejects constrained functions.)*

Introducing a constrained function `stub` with constraint `(implies (symbolp fn) (equal (stub fn x) (not (apply$ fn (list x)))))` and defining `(defun liar (x) (stub 'liar x))`:
1. `ok-defbadge` and `chk-acceptable-defwarrant1` misclassify `liar` as **G1** because `(body 'stub nil wrld)` is `nil`, admitting `apply$-warrant-liar`.
2. `(defattach apply$-warrant-liar true-apply$-warrant)` is accepted **with zero proof obligation** (`other-events.lisp:31432-31445`).
3. First-order logic proves `(defthm not-warrant-liar (not (apply$-warrant-liar)))` (`Q.E.D.`) by Russell/Cantor diagonalization on `(apply$ 'liar '(nil))`, while top-level evaluation `(apply$-warrant-liar)` returns `T` — directly falsifying `Proposition (Attachment Consistency)` (`other-events.lisp:30435`).
4. Any `loop$` mentioning `(apply$ 'liar '(nil))` gains hypothesis `(apply$-warrant-liar)` in `special-conjectures`, which contradicts `not-warrant-liar` and **vacuously guard-verifies arbitrary `:guard nil` lambda bodies** (`vacuous-guard-verified` in `repro.lisp`). *(Note: unlike `PK-S1`–`PK-S6`, `PK-E1` does not prove `NIL` in pure first-order logic because ACL2 blocks `aokp = nil` evaluator attachment execution and rejects `:guard-code = nil` in `*cl-cache*`.)*

#### Surgical Fix
In `bad-ancestor1` (`apply.lisp:1238-1271`), treat any constrained non-primitive function `(and (null (body fn nil wrld)) (not (pre-apply$-prim-p fn wrld)))` as disallowed for G1 badging/warranting (matching G2's `not-pre-apply$-definable` discipline at `apply.lisp:1909-1960`).

---

## 3. Minor Non-Soundness Kernel Logic Defects

1. **PK-M1 (`tau.lisp:7208-7222` — `tau-visit-function-introduction` Stale Property Names in `(regenerate-tau-database)`):**
   `tau-visit-function-introduction` clears `'TAU-POS-IMPLICANTS` and `'TAU-NEG-IMPLICANTS` (`:7211-7213`), which **do not exist anywhere else in ACL2**; the actual world properties populated by `tau` are `'POS-IMPLICANTS` and `'NEG-IMPLICANTS` (`tau.lisp:7240-7256`), and `'TAU-BOUNDERS-FORM-1` / `'TAU-BOUNDERS-FORM-2` are also omitted from the reset list.
2. **PK-M2 (`tau.lisp:5436-5440` — `neg-evgs-near-subsetp` Prematurely Advances `neg-evgs2`):**
   In the `<` branch of `neg-evgs-near-subsetp` (`(car neg-evgs1) < (car neg-evgs2)`), when `(car neg-evgs1)` is subsumed by `interval2` or `pos-pairs2`/`neg-pairs2`, line `5437` passes `(cdr neg-evgs2)` instead of `neg-evgs2`, skipping `(car neg-evgs2)` without matching it! Because `neg-evgs-near-subsetp` is used to recognize conjunctive/equality collapses, skipping `(car neg-evgs2)` can only cause `neg-evgs-near-subsetp` to fail later (completeness loss on conjunctive tau rules, not unsoundness).
3. **PK-M3 (`non-linear.lisp:143` & `432-437` — `invert-var` Dead `eql` on Cons & `inverse-vars-p` Truthy `cons-term`):**
   At `non-linear.lisp:143`, `(eql exponent ''-1)` tests `eql` against a two-element list `'(QUOTE -1)`, which is `nil` unless constants happen to be coalesced; it falls through to `:149-152` returning `(EXPT base '1)` instead of `(varify! base)`. At `non-linear.lisp:437`, the fallback clause of predicate `inverse-vars-p` returns `(cons-term 'UNARY-/ (list var))` (always a non-nil cons!) instead of `(equal inv-var (cons-term 'UNARY-/ (list var)))` — benign only because its sole caller guarantees `inv-var = (invert-var var)`.
4. **PK-M4 (`bdd.lisp:2320` — `combine-op-csts2` Calls `quotep` on CST Record Instead of `(trm arg2)`):**
   Line `2320` tests `(quotep arg2)` on a `cst` structure `(trm id . rules)` rather than `(quotep (trm arg2))` (cf. lines `2316-2318`), skipping a commutative constant-swap heuristic before comparing `(unique-id arg1)` and `(unique-id arg2)`.
5. **PK-M5 (`rewrite.lisp:23280` — `rewrite-quoted-constant-with-lemma` Tag-Tree Leak on Form `[2]` Failure):**
   Although documented as a *"No-Change Loser, modulo the rw-cache"* (`:23126-23128`), when a form `[2]` `:rewrite-quoted-constant` rule relieves hypotheses (potentially forcing assumptions into local `ttree`) and then produces an unchanged or non-quoted `rewritten-rhs`, line `23280` returns the mutated `ttree` instead of the entry `ttree` (at worst causing a spurious forcing round if a subsequent rule succeeds).

---

## 4. Counterexample-Guided Prover Falsification Campaigns

Two complementary YinYang / witness-guided fuzzers were built in `/Users/ember/dev/compiler-audit/hunts/prover-falsify/`:

### Campaign 1: Decision-Procedure Polarity-Aligned Fuzzer (`fuzzer.py` — 40,000 Conjectures)
- **Technique:** Generates random arithmetic (`+`, `-`, `*`, `/`, `floor`, `mod`, `truncate`, `rem`, `ash`, `logand`, `logior`, `logxor`, `lognot`, `expt`, `abs`, `realpart`, `imagpart`), recognizer, custom `defequiv`/`defcong`/`defrefinement`, `defun-sk`, and `IF` expressions paired with concrete witnesses `(vx, vy, vz)` drawn from integers, rationals, complex rationals, booleans, symbols, chars, strings, and conses. Inside ACL2, `trans-eval` evaluates every hypothesis `ei(w)` and conclusion `target(w)` on `w`, flipping signs so `HYPS(w) == T` (never vacuous!) and `CONCL(w) == NIL` (`100%` witness-falsified by construction), then bombards ACL2 with `:tau-system`, `:linear`, non-linear arithmetic (`:nonlinearp t`), `:bdd`, `:forward-chaining`, and `:instructions`.
- **Execution (`campaign-sbcl-mixed-7001.log`, `campaign-ccl-mixed-8002.log`):**
  - **SBCL 2.6.10:** `20,000` witness-falsified conjectures (`250` batches x `80` candidates) — `0` soundness bugs in core arithmetic/tau/linear/non-linear/BDD decision procedures, `0` raw Lisp crashes.
  - **CCL 1.14:** `20,000` witness-falsified conjectures (`250` batches x `80` candidates) — `0` soundness bugs in core arithmetic/tau/linear/non-linear/BDD decision procedures, `0` raw Lisp crashes.

### Campaign 2: Multi-Rule Interaction & Meta/Warrant Falsification Fuzzer (`fuzzer_v2.py` — 1,400 Harnesses)
- **Technique:** Synthesizes self-contained `(encapsulate () ...)` multi-rule harnesses across 7 rule-interaction families (`tp-free-force`, `bind-free-force`, `mfc-contextual`, `pb-instructions`, `warrant-guard-thm`, `tau-eqv-cong`, `skolem-fc-bdd`), randomly toggling forced vs. unforced hypotheses, single vs. multi-candidate free/bind-free matches, `:apply-linear` vs. `:casesplit`/`:bash` instructions, and non-lambda vs. lambda `encapsulate` warrant scopes, checking `(getpropc 'nil-proved-K 'theorem :none (w state))` after each trial.
- **Execution (`fuzzer_v2_results.json`, seeds `9001` & `9002`, `700` harnesses/host = `1,400` total):**
  - **Automatically rediscovers all 6 `NIL`-proving bug classes** (`447` genuine `NIL` proofs across SBCL + CCL: `tp-free-force` `54`, `bind-free-force` `68`, `mfc-contextual/{typeset,rw+,ap}` `111`, `pb-instructions` `95`, `warrant-guard-thm/encap-nonlambda` `57`, `warrant-guard-thm/badge-reset` `62`).
  - **Zero false positives (`0` hits)** on all negative controls (`tau-eqv-cong = 0`, `skolem-fc-bdd = 0`, `warrant-guard-thm/encap-lambda-ctrl = 0`, and all unforced / non-backtracking variants = `0`), and **`0` hard errors** on both SBCL (`10.12s`) and CCL (`24.37s`).

---

## 5. Audited Pure-Kernel Subsystems Matrix

| Subsystem | Files Audited | Outcome |
| :--- | :--- | :--- |
| Type-Set & Free-Variable Backtracking | `type-set-a.lisp`, `type-set-b.lisp` | **PK-S1 (`NIL` proved)** at `type-set-b.lisp:8654, 8428`. Primitive `type-set-*` bitwise operations verified sound. |
| Rewriter, Equivalence/Congruence (`geneqv`/`pequiv`), `bind-free`, Dirty Lambdas | `rewrite.lisp`, `translate.lisp` | **PK-S2 (`NIL` proved)** at `rewrite.lisp:18395`; minor `PK-M5` at `:23280`. Congruence, `pequiv`, `bind-free-info`, and `clean-up-dirty-lambda-objects` verified sound. |
| Extended Metafunctions, `defevaluator`, `meta-extract`, `:clause-processor` | `boot-strap-pass-2-a.lisp`, `boot-strap-pass-2-b.lisp`, `ld.lisp`, `interface-raw.lisp`, `defthm.lisp` | **PK-S3 (`NIL` proved)** across `meta-extract-contextual-fact` / `mfc-*`. `meta-extract-global-fact+` (including cross-world `wrld` parameter) and `:clause-processor` admission verified sound. |
| Interactive Proof-Builder & `:instructions` | `proof-builder-a.lisp`, `proof-builder-b.lisp`, `other-events.lisp` | **PK-S4 (`NIL` proved)** in `:apply-linear` (`proof-builder-b.lisp:3226-3332`). Other PC primitives (`rewrite`, `equiv`, `claim`, `casesplit`, `split`, `induct`, `bdd`, `bash`, `prove`) verified sound. |
| `encapsulate` Export, `:functional-instance`, `:guard-theorem`, `:termination-theorem` | `other-events.lisp`, `defuns.lisp`, `history-management.lisp` | **PK-S5 (`NIL` proved)** in `encapsulate` Pass 2 + `:guard-theorem`. `:functional-instance` capture avoidance (`remove-capture-in-constraint-lst`) and `:termination-theorem` verified sound. |
| `apply$`, `defbadge`, `defwarrant`, `badge-table`, `defattach` | `apply.lisp`, `apply-constraints.lisp`, `apply-raw.lisp`, `other-events.lisp` | **PK-S6 (`NIL` proved)** in `badge-table-guard1` (`apply.lisp:1966-1972`) and **PK-E1 (Attachment Inconsistency)** in `bad-ancestor1` (`apply.lisp:1242, 1262`). |
| Tau System | `tau.lisp`, `induct.lisp` | Verified sound (`relieve-dependent-hyps` checks `contains-assumptionp`; interval/bounder arithmetic sound); minor defects `PK-M1` (`:7208-7222`) & `PK-M2` (`:5436-5440`). |
| Linear & Non-Linear Arithmetic | `linear-a.lisp`, `linear-b.lisp`, `non-linear.lisp` | Polynomial cancellation, cross-multiplication, `add-linear-lemma`, and rationals/integers rounding verified sound; minor defect `PK-M3` (`non-linear.lisp:143, 437`). |
| Ordered Binary Decision Diagrams (`:bdd`) | `bdd.lisp` | Boolean guards (`known-boolean`) on `EQUAL` and `IF` reductions verified sound; minor typo `PK-M4` (`bdd.lisp:2320`). |
| Quantifiers (`defun-sk`, `defchoose`), Waterfall, Forcing Rounds | `other-events.lisp`, `simplify.lisp`, `prove.lisp` | `defchoose` free-variable framing, `expunge-fc-derivations`, and `extract-and-clausify-assumptions` verified sound. |
