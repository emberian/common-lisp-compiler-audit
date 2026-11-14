# ACL2 Stateful Caches, `memoize`, `invariant-risk`, `defattach`, and `hons` Soundness Audit (`RESEARCH.md` §§7–8 — Lane 2)

**Target:** ACL2 Version 8.7+ (`1d2b39a424eabeab269f189b37c29148d49fc516`)  
**Hosts Verified:** SBCL 2.6.10 (`darwin-arm64`) and Clozure Common Lisp 1.14 (`darwin-arm64`)  
**Hunt Probes:** `hunts/state-cache-risk/`  
**Standalone Reproducers:** `repros/memoize-aokp-apply-defattach/`, `repros/memoize-cl-cache-warrant-bypass/`, `repros/defattach-invariant-risk-bypass/`, `repros/serialize-read-hons-mode-never-crash/`

All findings below are brand-new and disjoint from the 4 bugs already sent to Eric (`put-defabsstobj-invariant-risk`, `maybe-flush-and-compress1`, interactive `proof-builder` `:prove`, hypothesis metafunction guard), `ACL2-BUG-REPORT.md` (`S1`–`S7`, `R1`–`R7`, `H1`), `reports/ACL2-BATCH-2.md` (`B2-R1`, `B2-R2`, `B2-S6b`), and `reports/ACL2-XDSMITH-GUARDS.md` (`XDS-S1`–`XDS-S5`, `XDS-R1`–`XDS-R3`).

Every soundness reproducer (`SCR-S1`, `SCR-S2`, `SCR-S3`) both:
1. Proves `(defthm nil-proved nil :rule-classes nil)` in a fresh ACL2 session on **both** SBCL 2.6.10 and CCL 1.14 with `(ttag (w state)) = NIL`, `(global-val 'ttags-seen (w state)) = NIL`, `(global-val 'skip-proofs-seen (w state)) = NIL`, and `(global-val 'redef-seen (w state)) = NIL`; **and**
2. Certifies cleanly as a standalone book via `(certify-book "book" 0 t :ttags nil)` on **both** SBCL 2.6.10 and CCL 1.14.

---

## 1. Executive Summary

| ID | Category | Construct / Subsystem | Root Cause (`head-worktree`) | Impact (SBCL 2.6.10 & CCL 1.14) | Standalone Reproducer |
|---|---|---|---|---|---|
| **SCR-S1** | **Soundness** (`NIL` proved, certifiable book, `:ttags nil`) | `(memoize fn :aokp t)` + `apply$` + `defattach` + `:clause-processor` | `doppelganger-apply$-userfn` is introduced via `partial-encapsulate` with `supporters = nil` (`other-events.lisp:33641-33647`), so `ext-ancestors-attachments` (`other-events.lisp:33756-33828`, stored in `:ext-anc-attachments` at `memoize-raw.lisp:3647`) misses attachable functions called inside warranted functions invoked via `apply$`. Subsequent `(defattach my-h my-h-false)` fails to clear `my-caller`'s `:aokp t` memo table (`memoize-raw.lisp:5207-5286`). | Verified `:clause-processor` (`prove.lisp:1079-1090`, run with `aok = t`) sees `(apply$-warrant-my-u) = T`, stale `(my-caller 10) = T`, and live `(my-h 10) = NIL`, returning `NIL` and proving `(defthm nil-proved nil)` + certifying `book.lisp` on both hosts | `repros/memoize-aokp-apply-defattach/` |
| **SCR-S2** | **Soundness** (`NIL` proved, certifiable book, zero `defattach`, zero `:clause-processor`, zero `:program` mode, `:ttags nil`) | Default `(memoize fn)` (`:aokp nil`) + `apply$-lambda` `*cl-cache*` | `memoize-fn-inner-body` (`memoize-raw.lisp:2850-2881`) guards `:aokp nil` memo tables by checking whether `*aokp*` became `:att` or `*warrant-reqs*` changed during a miss. However, `apply$-lambda` (`apply-raw.lisp:4189-4221`) fast-paths `:GOOD` `*cl-cache*` entries via direct `(apply :guard-code args)` / `(apply :lambda-code args)`, bypassing `doppelganger-apply$-userfn`, `update-attached-fn-called`, and `*warrant-reqs*`. On the 2nd call to `(my-caller 10)`, the `:aokp nil` memo table caches `10 -> 42` (and later `10 -> 99`) with **zero warrant hypotheses** (and also bypasses `*aokp*` attachment tainting!). | Two `encapsulate` blocks with local `my-u` definitions (`42` vs `99`) export `(equal (my-caller 10) 42)` and `(equal (my-caller 10) 99)` unconditionally, proving `(defthm nil-proved nil)` + certifying `book.lisp` on both hosts | `repros/memoize-cl-cache-warrant-bypass/` |
| **SCR-S3** | **Soundness** (`NIL` proved, certifiable book, `:ttags nil`) | `defattach` + `invariant-risk` + `:program` mode + stobj `:clause-processor` | Constrained functions introduced by `encapsulate` always have `'invariant-risk = nil`. When `(defattach my-st-fn my-st-impl)` attaches a stobj/array updater with non-nil `'invariant-risk` (`update-fld` / `aset1`) and a non-trivial guard (`(integerp x)`), `defattach` installs raw Lisp dispatch (`axioms.lisp:5341-5344`) without propagating `'invariant-risk` or enforcing guards/risk at dispatch. A `:program`-mode caller computes `'invariant-risk = nil` (`defuns.lisp:5994-6010`) and runs raw Lisp directly without `*1*` checks. | Corrupts live `st` (`(fld st)` becomes `'NOT-AN-INTEGER` while `(stp st)` evaluates to `T` via live-stobj shortcut); verified stobj `:clause-processor` returns `NIL`, proving `(defthm nil-proved nil)` + certifying `book.lisp` on both hosts | `repros/defattach-invariant-risk-bypass/` |
| **SCR-R1** | **Raw-Lisp Crash** (100% guard-verified top-level call) | `serialize-write` + `(serialize-read … :hons-mode :never)` | `ser-decode-and-restore-fals` (`serialize-raw.lisp:1403-1414`) places `(count (ser-decode-nat stream))` inside `(unless (eq hons-mode :never) …)`, contradicting its own comment on lines `1411-1412` and mis-parsing `COUNT` as the next `INDEX`. Whenever `COUNT = 0` (e.g., `(make-fast-alist '(nil))`), `loop until (= index 0)` exits early, leaving the terminating `0` byte unread ahead of the trailing magic bytes. | `(serialize-read "sample.sao" :hons-mode :smart)` succeeds (`(NIL)`), whereas `:hons-mode :never` passes full guard checking and aborts raw Lisp (`Invalid serialized object, magic number incorrect: 0 AC 12 B`) on both hosts | `repros/serialize-read-hons-mode-never-crash/` |
| **SCR-L1** | **Latent Code Defect** | `update-memo-entries-for-attachments` `:clear` mode | `memoize-raw.lisp:5267-5284` nests `(clear-one-memo-and-pons-hash entry :auto)` inside `(when (not (or (eq changedp t) (eq fns :clear))) …)`, so `:clear` prints `"Memoization tables for functions memoized with :AOKP T are being cleared"` (`lines 5254-5257`) while skipping the actual hash-table clear! | Latent stale `:aokp t` memo tables across `(update-memo-entries-for-attachments :clear wrld)` | Source audit (`memoize-raw.lisp:5254-5285`) |
| **SCR-L2** | **Latent Code Defect** | `stobj-let-fn-raw` + `defabsstobj-fn1` `congruent-stobj-rep` | `defabsstobj-fn1` (`other-events.lisp:25093-25096, 25167-25169`) sets `:congruent-stobj-rep` to the abstract stobj name `mom` (not `mom$c`) when `:congruent-to` is nil, and Pass 2 reuses Pass 1's `discriminator` when `att-name` is non-nil (`line 25160`), so `stobj-let-fn-raw` (`translate.lisp:17296-17300`) emits `(memoize-flush mom)` on a dummy `(st-lst 'mom)` variable that `memoize-fn` (`memoize-raw.lisp:3604`) never populates. | Masked in practice only because `(st-lst 'mom)` initializes via `hons-s` to `nil` (avoiding unbound-var crash) and `updated-consumer` subsequently invokes the parent's `:exec` child updater (`update-kid-c`), which flushes `mom$c` | Source & disassembly audit (`translate.lisp:17296-17300`, `other-events.lisp:25159-25172`) |
| **SCR-L3** | **Latent Code Defect** | `hl-rebuild-addr-ht` static-hons compacting GC | `hons-raw.lisp:3648-3653`: when `(hl-static-inverse-cons i)` is `nil` (freed static cons), `hl-rebuild-addr-ht` calls `(sbits-set sbits i 1)` instead of `(sbits-set sbits i 0)` while incrementing `num-dead-survivors`. | Leaves stale `1` bit in `sbits` for dead static-cons index `i` | Source audit (`hons-raw.lisp:3652`) |
| **SCR-L4** | **Latent Code Defect** | `serialize-read` `FAL` index `1` (`T`) & CL package symbol imports | (a) `ser-decode-and-restore-fals` (`serialize-raw.lisp:1403-1409`) rejects `index = 0` (`NIL`) but allows `index = 1` (`T`), inserting atom `T` into `hl-falslot` in violation of FALTABLE Invariant 1 (`hons-raw.lisp:2758`). (b) `serialize-read-fn` (`serialize.lisp:87`) skips `bad-lisp-objectp`, trusting `COMMON-LISP` package symbols to be `acl2-symbolp` (holds on SBCL 2.6.10 & CCL 1.14; fragile on CLs with extra `CL` exports). | Crafted `.sao` violates FALTABLE cons-key invariant (mitigated at lookup by `(atom alist)` guards in `hons-get`/`hons-acons`) | Source audit (`serialize-raw.lisp:1403-1410`, `serialize.lisp:87`) |
| **SCR-L5** | **Latent Code Defect** | `:tau-system` `MV-NTH` Form-2 contradiction check & `tau-boolean-formp` | (a) `tau-term` Form-2 `MV-NTH` branch (`tau.lisp:11582-11592`) omits `((eq actual-tau-lst *tau-contradiction*) (mv *tau-contradiction* calist))` (present in Form-1 at `tau.lisp:11684`), passing `:contradiction` into `apply-tau-bounders` -> `(car actual-taus)`. (b) `tau-boolean-formp` (`tau.lisp:7288-7302`) omits the `*non-tau-monadic-boolean-functions*` (`NOT`, `DEBUGGER-ENABLEDP`) and constant-`T`/`NIL` checks enforced by `monadic-boolean-fnp` (`tau.lisp:7138-7170`). | Potential raw `(car :contradiction)` hard error on multi-arg Form-2 bounder rules when arg 2+ yields `*tau-contradiction*` | Source audit (`tau.lisp:11582-11592, 7288-7302`) |

---

## 2. Systematic Surface Coverage Matrix

| Surface (`LEDGER.md` / Lane 2 Brief) | Files Audited | Mechanisms Checked | Outcome |
|---|---|---|---|
| **1. `memoize` × (`defattach`, `:aokp`, `apply$`, `:u`, `:condition`, `mbe`, `stobj`, `save-exec`, `encapsulate`)** | `memoize-raw.lisp`, `memoize.lisp`, `apply-raw.lisp`, `other-events.lisp`, `history-management.lisp` | `:aokp nil` vs `:aokp t` table segregation; `*aokp*` (`:att`) & `*warrant-reqs*` miss tracking; `ext-ancestors-attachments` across `defun-inline`, macros, `mbe`, and `apply$`; `apply$-lambda` `*cl-cache*` fast path; `update-memo-entries-for-attachments` (`:clear` vs fn list); `:condition` evaluation; `unmemoize-all-world-level` on `:u` / `encapsulate` rollback; `save-exec` `clear-memoize-tables` | **2 Soundness Bugs (`SCR-S1`, `SCR-S2`)** + **1 Latent Defect (`SCR-L1`)**. (`:u` rollback, `save-exec`, `defun-inline` `$inline` callers, and `mbe` `:exec` direct attachment calls properly clear/track except through `apply$` / `*cl-cache*`.) |
| **2. `invariant-risk` Propagation & Stobj Aliasing / Attachments** | `other-events.lisp`, `defuns.lisp`, `translate.lisp`, `axioms.lisp`, `basis-a.lisp`, `basis-b.lisp`, `interface-raw.lisp` | `invariant-risk-callees1`, `compute-invariant-risk`, `defattach` onto constrained stobj-updating functions, `defabsstobj` (`:recognizer`, `:creator`, exports, `attach-stobj`), `stobj-let`, `swap-stobjs`, `with-local-stobj`, `:congruent-to`, `:program` mode via `apply$`/`ec-call` | **1 Soundness Bug (`SCR-S3`)** + **1 Latent Defect (`SCR-L2`)**. (`defstobj` `:satisfies` + `apply$` is accidentally blocked because `apply$-userfn` has system attachment `concrete-apply$-userfn`; `swap-stobjs` checks `congruent-stobj-rep` & flushes memo tables.) |
| **3. `hons` / Fast-Alists / `:df` / Serialization** | `hons-raw.lisp`, `hons.lisp`, `serialize-raw.lisp`, `serialize.lisp`, `float-a.lisp`, `float-b.lisp`, `float-raw.lisp` | Norming tables across `eql` vs `equal` keys (non-normed conses, strings, chars, rationals, complexes, `-0.0d0`/`0.0d0`); `hons-acons`, `hons-get`, `fast-alist-fork`, `fast-alist-clean`, `fast-alist-free`; `hl-rebuild-addr-ht`; `serialize-write` / `serialize-read` V3 decoder (`:smart`, `:always`, `:never`) | **1 Guard-Verified Raw-Lisp Crash (`SCR-R1`)** + **2 Latent Defects (`SCR-L3`, `SCR-L4`)**. (Fast-alist `hons-get` norms keys on lookup when needed and `:df` unboxed floats cannot enter polymorphic `hons-acons`/`hons-get` without `from-df` rational conversion.) |
| **4. `:clause-processor` / Evaluator / Meta / `:tau-system`** | `prove.lisp`, `defthm.lisp`, `tau.lisp` | `apply-clause-processor-clause` (`aok = t` evaluation, stobj-taking clause processors, `clauses-result` contract, evaluator checks); `ev-fncall-w-tau-recog`, `tau-term` (`MV-NTH` Form-1/Form-2), `tau-boolean-formp`, `tau-bounder-formp` | **2 `:clause-processor` Exploitation Chains (`SCR-S1`, `SCR-S3`)** + **1 Latent `:tau-system` Defect (`SCR-L5`)**. |

---

## 3. Detailed Soundness Findings

### SCR-S1 — `(memoize fn :aokp t)` + `apply$` + `defattach` Fails to Clear Attachment-Dependent Memo Tables, Proving `NIL` (`:ttags nil` Certifiable Book)

- **Reproducer:** `repros/memoize-aokp-apply-defattach/` (`book.lisp`, `session.lisp`, `run.sh`)

#### Minimal Certifiable Book (`book.lisp`)
```lisp
(in-package "ACL2")

(defstub my-h (x) t)
(defun my-h-true (x) (declare (xargs :guard t) (ignore x)) t)
(defun my-h-false (x) (declare (xargs :guard t) (ignore x)) nil)
(defun my-u (x) (declare (xargs :guard t)) (my-h x))

(make-event
 (let ((badge '(APPLY$-BADGE 1 1 . T)))
   `(encapsulate ()
      ,@(defwarrant-events 'my-u '(x) badge)
      (table badge-table
             :badge-userfn-structure
             (put-badge-userfn-structure-tuple-in-alist
              (make-badge-userfn-structure-tuple 'my-u T ',badge)
              (cdr (assoc :badge-userfn-structure
                          (table-alist 'badge-table world)))
              'defwarrant)
             :put)
      (defattach ,(warrant-name 'my-u) true-apply$-warrant))))

(defun my-caller (x)
  (declare (xargs :guard t))
  (apply$ 'my-u (list x)))

(defevaluator my-ev my-ev-lst ((if x y z)))

(defun my-cp (clause)
  (declare (xargs :guard t))
  (if (or (not (apply$-warrant-my-u))
          (equal (my-caller 10) (my-h 10)))
      (list clause)
    nil))

(defthm my-cp-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (my-ev (conjoin-clauses (my-cp clause)) a))
           (my-ev (disjoin clause) a))
  :rule-classes :clause-processor)

(defattach my-h my-h-true)
(memoize 'my-caller :aokp t)

(make-event
 (let ((v (my-caller 10)))
   (declare (ignore v))
   '(value-triple :warmed)))

(defattach my-h my-h-false)

(defthm nil-proved
  nil
  :hints (("Goal" :clause-processor (my-cp clause)))
  :rule-classes nil)
```

#### Verification Output (SBCL 2.6.10 & CCL 1.14)
```text
== head (session)
 NIL-PROVED
ACL2 !>@CALLER-STALE T
ACL2 !>@MY-H-NOW NIL
ACL2 !>@NIL-FORMULA 'NIL
ACL2 !>@TTAG NIL
ACL2 !>@TTAGS-SEEN NIL
ACL2 !>@SKIP-PROOFS-SEEN NIL
ACL2 !>@REDEF-SEEN NIL
ACL2 !>@END
== head (certify-book)
Form:  (CERTIFY-BOOK "book" ...)
 "/Users/ember/dev/compiler-audit/repros/memoize-aokp-apply-defattach/book.lisp"
== ccl (session)
 NIL-PROVED
ACL2 !>@CALLER-STALE T
ACL2 !>@MY-H-NOW NIL
ACL2 !>@NIL-FORMULA 'NIL
ACL2 !>@TTAG NIL
ACL2 !>@TTAGS-SEEN NIL
ACL2 !>@SKIP-PROOFS-SEEN NIL
ACL2 !>@REDEF-SEEN NIL
ACL2 !>@END
== ccl (certify-book)
Form:  (CERTIFY-BOOK "book" ...)
 "/Users/ember/dev/compiler-audit/repros/memoize-aokp-apply-defattach/book.lisp"
```

#### Root Cause
1. When `(memoize 'my-caller :aokp t)` is admitted, `memoize-fn` (`memoize-raw.lisp:3647`) records the attachment dependencies of `my-caller` in `:ext-anc-attachments` using `(ext-ancestors-attachments 'my-caller wrld)` (`other-events.lisp:33756-33828`).
2. `my-caller` calls `apply$` -> `apply$-userfn`, whose attachment is `concrete-apply$-userfn`, which calls `doppelganger-apply$-userfn`. However, `other-events.lisp:33641-33647` introduces `doppelganger-apply$-userfn` via `partial-encapsulate` with `supporters = nil` because future warranted functions (`my-u`) do not even exist yet when ACL2 is built.
3. Consequently, `my-caller`'s `:ext-anc-attachments` contains only `((APPLY$-USERFN . CONCRETE-APPLY$-USERFN) (BADGE-USERFN . CONCRETE-BADGE-USERFN) (*SPECIAL-CLTL-CMD-ATTACHMENT-MARK* . <n>))` and **completely misses `my-h`** (called inside warranted `my-u`).
4. Under `(defattach my-h my-h-true)`, evaluating `(my-caller 10)` populates `my-caller`'s `:aokp t` memo table with `10 -> T`.
5. When `(defattach my-h my-h-false)` changes `my-h`'s attachment, `defattach` calls `(update-memo-entries-for-attachments '(my-h) wrld)` (`memoize-raw.lisp:5207-5286`). Because `my-h` is absent from `my-caller`'s `:ext-anc-attachments` (and no new badge/warrant mark was added), `update-memo-entry-for-attachments` returns `(mv nil entry)` and **does not clear `my-caller`'s memo table**.
6. ACL2 evaluates verified `:clause-processor` functions with `aok = t` (`prove.lisp:1079-1090`), trusting that all attachments and `:aokp t` memo tables reflect a single consistent attachment state of the logical world. Logically, under `(apply$-warrant-my-u)`, `(my-caller 10)` equals `(my-u 10)` = `(my-h 10)`, so `my-cp-correct` proves cleanly. At execution time inside `(defthm nil-proved nil :hints (("Goal" :clause-processor (my-cp clause))))`, `(apply$-warrant-my-u)` evaluates to `T`, `(my-caller 10)` hits the stale `:aokp t` memo entry `T`, and `(my-h 10)` evaluates via its current attachment to `NIL`, so `my-cp` returns `NIL` (the empty list of subgoals) and ACL2 proves `NIL`.

#### Suggested Fix
- Any function whose extended ancestors include `apply$-userfn` or `doppelganger-apply$-userfn` can dynamically dispatch via `apply$` to *any* warranted function, which in turn can call *any* attachable function. Therefore:
  1. Either `update-memo-entry-for-attachments` (`memoize-raw.lisp:5127-5205`) must clear the `:aokp t` memo table of any function whose `:ext-anc-attachments` contains `APPLY$-USERFN` whenever **any** attachment changes (`fns` non-empty); **or**
  2. Dynamic attachment dependencies actually encountered during a memo miss (via `update-attached-fn-called`) should be recorded into the caller's `:ext-anc-attachments` (or a dynamic per-table attachment dependency set) so subsequent `defattach` calls on any dynamically invoked attachment flush the table.

---

### SCR-S2 — Default `(memoize fn)` (`:aokp nil`) + `apply$-lambda` `*cl-cache*` Fast Path Drops Both Warrant Obligations and Attachment Tainting, Proving `NIL` (`:ttags nil` Certifiable Book)

- **Reproducer:** `repros/memoize-cl-cache-warrant-bypass/` (`book.lisp`, `session.lisp`, `run.sh`)

#### Minimal Certifiable Book (`book.lisp`)
```lisp
(in-package "ACL2")

(defun my-caller (x)
  (declare (xargs :guard t))
  (apply$ (cons 'LAMBDA '((Z) (MY-U Z))) (list x)))

(memoize 'my-caller)

(encapsulate ()
  (local (defun my-u (z) (declare (xargs :guard t) (ignore z)) 42))
  (local
   (make-event
    (let ((badge '(APPLY$-BADGE 1 1 . T)))
      `(encapsulate ()
         ,@(defwarrant-events 'my-u '(z) badge)
         (table badge-table
                :badge-userfn-structure
                (put-badge-userfn-structure-tuple-in-alist
                 (make-badge-userfn-structure-tuple 'my-u T ',badge)
                 (cdr (assoc :badge-userfn-structure
                             (table-alist 'badge-table world)))
                 'defwarrant)
                :put)
         (defattach ,(warrant-name 'my-u) true-apply$-warrant)))))
  (local
   (make-event
    (let* ((v1 (my-caller 10))
           (v2 (my-caller 10)))
      (declare (ignore v1 v2))
      '(value-triple :cached-42))))
  (defthm thm-42
    (equal (my-caller 10) 42)
    :hints (("Goal" :in-theory (disable my-caller)))))

(make-event
 (let ((ign (clear-memoize-tables)))
   (declare (ignore ign))
   '(value-triple :cleared)))

(encapsulate ()
  (local (defun my-u (z) (declare (xargs :guard t) (ignore z)) 99))
  (local
   (make-event
    (let ((badge '(APPLY$-BADGE 1 1 . T)))
      `(encapsulate ()
         ,@(defwarrant-events 'my-u '(z) badge)
         (table badge-table
                :badge-userfn-structure
                (put-badge-userfn-structure-tuple-in-alist
                 (make-badge-userfn-structure-tuple 'my-u T ',badge)
                 (cdr (assoc :badge-userfn-structure
                             (table-alist 'badge-table world)))
                 'defwarrant)
                :put)
         (defattach ,(warrant-name 'my-u) true-apply$-warrant)))))
  (local
   (make-event
    (let* ((v1 (my-caller 10))
           (v2 (my-caller 10)))
      (declare (ignore v1 v2))
      '(value-triple :cached-99))))
  (defthm thm-99
    (equal (my-caller 10) 99)
    :hints (("Goal" :in-theory (disable my-caller)))))

(defthm nil-proved
  nil
  :hints (("Goal" :in-theory (disable my-caller (my-caller))
                  :use (thm-42 thm-99)))
  :rule-classes nil)
```

#### Verification Output (SBCL 2.6.10 & CCL 1.14)
```text
== head (session)
 NIL-PROVED
ACL2 !>@THM-42 (EQUAL (MY-CALLER '10) '42)
ACL2 !>@THM-99 (EQUAL (MY-CALLER '10) '99)
ACL2 !>@NIL-FORMULA 'NIL
ACL2 !>@TTAG NIL
ACL2 !>@TTAGS-SEEN NIL
ACL2 !>@SKIP-PROOFS-SEEN NIL
ACL2 !>@REDEF-SEEN NIL
ACL2 !>@END
== head (certify-book)
Form:  (CERTIFY-BOOK "book" ...)
 "/Users/ember/dev/compiler-audit/repros/memoize-cl-cache-warrant-bypass/book.lisp"
== ccl (session)
 NIL-PROVED
ACL2 !>@THM-42 (EQUAL (MY-CALLER '10) '42)
ACL2 !>@THM-99 (EQUAL (MY-CALLER '10) '99)
ACL2 !>@NIL-FORMULA 'NIL
ACL2 !>@TTAG NIL
ACL2 !>@TTAGS-SEEN NIL
ACL2 !>@SKIP-PROOFS-SEEN NIL
ACL2 !>@REDEF-SEEN NIL
ACL2 !>@END
== ccl (certify-book)
Form:  (CERTIFY-BOOK "book" ...)
 "/Users/ember/dev/compiler-audit/repros/memoize-cl-cache-warrant-bypass/book.lisp"
```

#### Root Cause
1. Default `(memoize 'my-caller)` (`:aokp nil`) populates the primary memo table (`tablename`), whose entries ACL2's prover (`ev-fncall-rec` with `*aokp* = nil`) trusts **unconditionally** during theorem proving without adding any warrant hypotheses (`(apply$-warrant-my-u)`) or attachment caveats.
2. To keep `tablename` sound, `memoize-fn-inner-body` (`memoize-raw.lisp:2850-2881`) checks after computing a miss whether:
   - `*aokp*` changed to `:att` (meaning an attached function was called via `update-attached-fn-called`), or
   - `*warrant-reqs*` changed or became `:bad` (meaning a warranted function was dispatched via `doppelganger-apply$-userfn` during `ev$`).
   Only when neither changed does `memoize-fn-inner-body` write the computed result into the `:aokp nil` memo table!
3. Look at `apply$-lambda` in `apply-raw.lisp:4189-4221`:
   ```lisp
   (line (and *aokp* (fetch-cl-cache-line fn nil)))
   ...
   ((eq (access cl-cache-line line :status) :GOOD)
    (cond
     ((apply (access cl-cache-line line :guard-code) args)
      (return-from apply$-lambda
                   (apply (access cl-cache-line line :lambda-code) args)))
   ```
   When `(my-caller 10)` is evaluated at top-level or inside `make-event`, `*aokp*` is `T`:
   - On the **1st call** `v1 = (my-caller 10)`, `fetch-cl-cache-line` compiles `(LAMBDA (Z) (MY-U Z))` into a `:GOOD` `cl-cache-line` whose `:lambda-code` directly calls raw Lisp `MY-U`. During compilation, `fetch-cl-cache-line` runs `QUICK-AND-DIRTY-SRS`, which sets `*warrant-reqs* = :bad`, so `v1` is *not* stored in `tablename`.
   - On the **2nd call** `v2 = (my-caller 10)`, `(fetch-cl-cache-line fn nil)` immediately returns the cached `:GOOD` `cl-cache-line` and `apply$-lambda` directly calls `(apply :guard-code args)` and `(apply :lambda-code args)` -> `(MY-U 10)` -> `42`! Because `MY-U` is an ordinary user function (not `doppelganger-apply$-userfn`), **neither `*warrant-reqs*` nor `*aokp*` is modified!**
   - `memoize-fn-inner-body` concludes that `(my-caller 10) = 42` required **zero warrants** and **zero attachments**, and writes `10 -> 42` straight into `my-caller`'s `:aokp nil` memo table!
4. Inside the first `encapsulate`, `(defthm thm-42 (equal (my-caller 10) 42))` evaluates `(my-caller '10)` via its `:executable-counterpart` (`*aokp* = nil`), hits `10 -> 42` in `tablename` with **no `(apply$-warrant-my-u)` hypothesis**, and exports `(equal (my-caller 10) 42)` (`my-u` was `local` and `my-caller` only mentioned `'MY-U` inside a quoted cons!). Repeating with `local` `my-u = 99` exports `(equal (my-caller 10) 99)`, proving `(defthm nil-proved nil)` with zero `defattach` on user stubs, zero `:clause-processor`, and zero `:program` mode!
5. *(Double impact — attachment tainting bypass too!)* Even if `my-u` is defined globally (not locally) and calls an attachable stub `(my-h z)`, `fetch-cl-cache-line` only gates `:GOOD` compilation on `(valid-warrants-for-cl-cache-linep ...)` — and once `:lambda-code` runs `(MY-U 10)` -> `(MY-H 10)`... wait: `(MY-H 10)` *does* call `update-attached-fn-called` when `my-h` itself is an attached stub, whereas `my-u`'s own **warrant** (`apply$-warrant-my-u`, which is implemented as an attachment to `true-apply$-warrant`!) is **never** called on the `*cl-cache*` `:GOOD` fast path, completely bypassing both `update-attached-fn-called` on `apply$-warrant-my-u` and `*warrant-reqs*`!

#### Suggested Fix
- In `apply-raw.lisp` (`cl-cache-line` & `apply$-lambda`, lines `4189-4221`):
  1. Store the list of warranted user functions (or `warrants` already computed by `fetch-cl-cache-line` for `valid-warrants-for-cl-cache-linep`!) on the `cl-cache-line` struct.
  2. Before `apply$-lambda` takes the `:GOOD` fast path (lines `4217-4221`), if `warrants` is non-empty:
     - Call `(update-attached-fn-called)` (so `*aokp*` transitions `T -> :att`, just as calling `doppelganger-apply$-userfn` / `apply$-userfn` would have done!), **and**
     - Update `*warrant-reqs*` for every warranted function in `warrants` (or set `*warrant-reqs* = :bad` when `warrants` is non-nil), so `:aokp nil` memoization never records warrant-dependent values as unconditional theorems.

---

### SCR-S3 — `defattach` Fails to Propagate or Enforce `invariant-risk` on Constrained Stobj/Array Updaters, Allowing `:program` Mode to Corrupt Live Stobjs and Prove `NIL` (`:ttags nil` Certifiable Book)

- **Reproducer:** `repros/defattach-invariant-risk-bypass/` (`book.lisp`, `session.lisp`, `run.sh`)

#### Minimal Certifiable Book (`book.lisp`)
```lisp
(in-package "ACL2")

(defstobj st (fld :type integer :initially 0))

(encapsulate
  (((my-st-fn * st) => st
    :formals (x st)
    :guard (and (integerp x) (stp st))))
  (local (defun my-st-fn (x st)
           (declare (xargs :stobjs st :guard (integerp x)))
           (update-fld x st))))

(defun my-st-impl (x st)
  (declare (xargs :stobjs st :guard (integerp x)))
  (update-fld x st))

(defattach my-st-fn my-st-impl)

(defun corrupt (st)
  (declare (xargs :mode :program :stobjs st))
  (my-st-fn 'not-an-integer st))

(defevaluator my-ev my-ev-lst ((if x y z)))

(defun my-cp (clause hint st)
  (declare (xargs :stobjs st :guard t) (ignore hint))
  (if (or (not (stp st)) (integerp (fld st)))
      (mv nil (list clause))
    (mv nil nil)))

(defthm my-cp-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (my-ev (conjoin-clauses (clauses-result (my-cp clause hint st))) a))
           (my-ev (disjoin clause) a))
  :rule-classes :clause-processor)

(make-event
 (let ((st (corrupt st)))
   (mv nil '(value-triple :corrupted) state st)))

(defthm nil-proved
  nil
  :hints (("Goal" :clause-processor (my-cp clause nil st)))
  :rule-classes nil)
```

#### Verification Output (SBCL 2.6.10 & CCL 1.14)
```text
== head (session)
 NIL-PROVED
ACL2 !>@FN-RISK NIL
ACL2 !>@IMPL-RISK UPDATE-FLD
ACL2 !>@CORRUPT-RISK NIL
ACL2 !>@ST-FLD-RAW NOT-AN-INTEGER
ACL2 !>@NIL-FORMULA 'NIL
ACL2 !>@TTAG NIL
ACL2 !>@TTAGS-SEEN NIL
ACL2 !>@SKIP-PROOFS-SEEN NIL
ACL2 !>@REDEF-SEEN NIL
ACL2 !>@END
== head (certify-book)
Form:  (CERTIFY-BOOK "book" ...)
 "/Users/ember/dev/compiler-audit/repros/defattach-invariant-risk-bypass/book.lisp"
== ccl (session)
 NIL-PROVED
ACL2 !>@FN-RISK NIL
ACL2 !>@IMPL-RISK UPDATE-FLD
ACL2 !>@CORRUPT-RISK NIL
ACL2 !>@ST-FLD-RAW NOT-AN-INTEGER
ACL2 !>@NIL-FORMULA 'NIL
ACL2 !>@TTAG NIL
ACL2 !>@TTAGS-SEEN NIL
ACL2 !>@SKIP-PROOFS-SEEN NIL
ACL2 !>@REDEF-SEEN NIL
ACL2 !>@END
== ccl (certify-book)
Form:  (CERTIFY-BOOK "book" ...)
 "/Users/ember/dev/compiler-audit/repros/defattach-invariant-risk-bypass/book.lisp"
```

#### Root Cause
1. ACL2's `invariant-risk` mechanism (`defuns.lisp:5890-6050`) protects live stobj/array/abstract-stobj representation invariants against ill-typed `:program`-mode calls: any function that can mutate a stobj, 1D/2D array (`aset1`/`aset2`), or abstract stobj under a non-trivial guard receives a non-nil `'invariant-risk` property, forcing callers (including `:program`-mode callers!) to execute via `*1*` wrappers that check guards / `'check-invariant-risk` before touching raw Lisp state.
2. However, constrained functions introduced by `encapsulate` (`my-st-fn`) always have `(getpropc 'my-st-fn 'invariant-risk nil wrld) = NIL` — even when their signature returns a stobj (`(my-st-fn * st) => st`) and has a non-trivial guard (`(and (integerp x) (stp st))`)!
3. When `(defattach my-st-fn my-st-impl)` attaches `my-st-impl` (whose `'invariant-risk` is `UPDATE-FLD`), `defattach` generates a direct raw Lisp stub (`axioms.lisp:5341-5344`):
   ```lisp
   (defun my-st-fn (x st)
     (update-attached-fn-called)
     (my-st-impl x st))
   ```
   without checking `my-st-fn`'s guard in raw Lisp and without marking `my-st-fn` (or already-defined / future `:program`-mode callers) with `'invariant-risk`.
4. Consequently, `(defun corrupt (st) (declare (xargs :mode :program :stobjs st)) (my-st-fn 'not-an-integer st))` computes `'invariant-risk = NIL` (`defuns.lisp:5994-6010`), compiles directly to raw Common Lisp `(my-st-fn 'not-an-integer st)` -> `(my-st-impl 'not-an-integer st)` -> `(update-fld 'not-an-integer st)` at `(safety 0)`, and writes the symbol `'NOT-AN-INTEGER` directly into `st`'s `:type integer` slot!
5. Logically, `(implies (stp st) (integerp (fld st)))` is a theorem of `defstobj`, so `my-cp-correct` proves trivially. At runtime inside `:clause-processor (my-cp clause nil st)`, `(stp st)` evaluates to `T` in O(1) via ACL2's live-stobj identity check (`(eq st *the-live-st*)`), while `(integerp (fld st))` evaluates `(integerp 'not-an-integer)` = `NIL`, returning `(mv nil nil)` and proving `(defthm nil-proved nil)`.
6. *(Note: The exact same bypass applies to non-stobj `compress1`/`aset1` array invariant-risk as well: a constrained function `(encapsulate (((my-arr-fn * * *) => * :formals (name l x) :guard ...)) ...)` attached to `aset1` has `'invariant-risk = NIL`, allowing `:program`-mode code to corrupt backing raw arrays without triggering `invariant-risk`!)*

#### Suggested Fix
- Two complementary defenses are needed because `corrupt` may be defined *either* before *or* after `(defattach my-st-fn my-st-impl)`:
  1. **Static (`encapsulate`):** Any constrained function with a non-`t` guard (after removing `stobjp` recognizer conjuncts on live stobj formals) — or at minimum any constrained function whose `stobjs-out` contains a stobj, or that can be attached to an `'invariant-risk` implementation — must either be assigned `'invariant-risk` statically at `encapsulate` admission, **or**
  2. **Dynamic (`defattach`):** Whenever `(defattach f g)` attaches an implementation `g` with non-nil `(getpropc g 'invariant-risk nil wrld)` to `f` (whose guard is not trivially `t` modulo live-stobj recognizers), either disallow attaching an `'invariant-risk` implementation `g` to a non-`'invariant-risk` `f`, **or** have `defattach`'s generated raw Lisp wrapper for `f` check `f`'s guard (or delegate through `*1*g` when `'invariant-risk` is present) before calling raw `g`! Checking `f`'s guard (or disallowing `defattach` when `(and (getpropc g 'invariant-risk nil wrld) (not (getpropc f 'invariant-risk nil wrld)))` unless `f` received static `'invariant-risk` at `encapsulate` time) closes both pre-`defattach` and post-`defattach` `:program`-mode callers, including array (`aset1`/`aset2`) attachments.

---

## 4. Guard-Verified Raw-Lisp Crash & Latent Code Defects

### SCR-R1 — `(serialize-read file :hons-mode :never)` Aborts Raw Lisp on Valid `.sao` Files with Empty-Table Fast Alists

- **Reproducer:** `repros/serialize-read-hons-mode-never-crash/` (`session.lisp`, `run.sh`)

#### Minimal Reproducer (`session.lisp`)
```lisp
(serialize-write "sample.sao" (make-fast-alist '(nil)))
(mv-let (obj state)
  (serialize-read "sample.sao" :hons-mode :smart)
  (prog2$ (cw "@SMART-READ ~x0~%" obj)
          state))
(mv-let (obj state)
  (serialize-read "sample.sao" :hons-mode :never)
  (prog2$ (cw "@NEVER-READ ~x0~%" obj)
          state))
```

#### Verification Output (SBCL 2.6.10 & CCL 1.14)
```text
== head
ACL2 !>@SMART-READ (NIL)
************ ABORTING from raw Lisp ***********
Error:  Invalid serialized object, magic number incorrect: 0 AC 12 B
== ccl
ACL2 !>@SMART-READ (NIL)
************ ABORTING from raw Lisp ***********
Error:  Invalid serialized object, magic number incorrect: 0 AC 12 B
```

#### Root Cause & Suggested Fix
- `ser-encode-fals` (`serialize-raw.lisp:1376-1381`) writes a zero-terminated sequence of `(INDEX, COUNT)` pairs followed immediately by trailing magic bytes (`ser-encode-magic`, line `1499`).
- Look at `ser-decode-and-restore-fals` (`serialize-raw.lisp:1403-1414`):
  ```lisp
    (loop until (= index 0) do
          (unless (< index max)
            (error "FAL index to restore is too large!"))
          (unless (eq hons-mode :never)
            (let ((alist (svref array index))
                  (count (ser-decode-nat stream)))
              (hl-restore-fal-for-serialize alist count)))

  ; Notice that we make progress reading nats from stream even if hons-mode is
  ; :never; we just ignore those nats!

          (setq index (ser-decode-nat stream)))))
  ```
  Contrary to the comment on lines `1411-1412`, `(count (ser-decode-nat stream))` is **inside** `(unless (eq hons-mode :never) …)`! When `hons-mode` is `:never`, `count` is not read in the body, so `(setq index (ser-decode-nat stream))` reads `count` as the next `index`! For `(make-fast-alist '(nil))` (a fast alist with 0 cons pairs in its backing hash table, so `count = 0`), `index` becomes `0` one byte early, leaving the actual zero-terminator byte `#x00` unread in `stream`; `ser-decode-magic` then reads `0 AC 12 B` instead of `AC 12 B F` and aborts raw Lisp!
- **Fix:** Always read `count` unconditionally before checking `(unless (eq hons-mode :never) ...)`:
  ```lisp
    (loop until (= index 0) do
          (unless (< index max)
            (error "FAL index to restore is too large!"))
          (let ((count (ser-decode-nat stream)))
            (unless (eq hons-mode :never)
              (hl-restore-fal-for-serialize (svref array index) count)))
          (setq index (ser-decode-nat stream)))
  ```

---

### SCR-L1 — `update-memo-entries-for-attachments` Skips Clearing Tables When `fns` Is `:clear` (`memoize-raw.lisp:5267-5284`)

- **Location:** `memoize-raw.lisp:5254-5286`
- **Defect:** When `fns` is `:clear`, lines `5254-5257` print `"Memoization tables for functions memoized with :AOKP T are being cleared."`, and `update-memo-entry-for-attachments` returns `changedp = :clear` (or `t`). However, lines `5267-5284` place `(clear-one-memo-and-pons-hash entry :auto)` **inside** the per-function observation guard:
  ```lisp
  (when (not (or (eq changedp t)
                 (eq fns :clear)))
    (observation ctx ...)
    (clear-one-memo-and-pons-hash entry :auto))
  ```
  When `(eq fns :clear)` is true (or `(eq changedp t)` when `:ext-anc-attachments` is initially populated), `(clear-one-memo-and-pons-hash entry :auto)` is **skipped**!
- **Fix:** Move `(clear-one-memo-and-pons-hash entry :auto)` outside `(when (not (or (eq changedp t) (eq fns :clear))) ...)` (or guard it by `(unless (eq changedp t) (clear-one-memo-and-pons-hash entry :auto))` so `:clear` and symbol `changedp` both flush the table while initial `changedp = t` initialization does not needlessly flush).

---

### SCR-L2 — `stobj-let-fn-raw` and `defabsstobj-fn1` Target Dummy `(st-lst <absstobj>)` Instead of Foundational Concrete Stobj (`translate.lisp:17296-17300`, `other-events.lisp:25093-25096, 25159-25172`)

- **Locations:** `other-events.lisp:25093-25096, 25159-25172` and `translate.lisp:17296-17300`
- **Defect:**
  1. `defabsstobj` (`other-events.lisp:22592-22600`) intentionally omits `(defg *memoize-tables-for-<abs>* nil)` because `memoize-fn` (`memoize-raw.lisp:3604`) registers memo tables on `(congruent-stobj-rep (or (concrete-stobj st wrld) st) wrld)` (e.g. `mom$c`).
  2. However, `defabsstobj-fn1` (`other-events.lisp:25093-25096, 25167-25169`) sets `:congruent-stobj-rep` in `redundant-raw-lisp-discriminator` to `(or congruent-stobj-rep st-name-new)` = `mom` (NOT `mom$c`!) whenever `:congruent-to` is omitted, and reuses Pass 1's `discriminator` in Pass 2 when `att-name` is non-nil (`line 25160`).
  3. Consequently, `stobj-let-fn-raw` (`translate.lisp:17296-17300`) compiles `(memoize-flush mom)` referencing `ACL2_INVISIBLE::|HONS-S-"ACL2","MOM"|` — a symbol that is *never* populated by `memoize-fn`!
  4. Disassembly on SBCL 2.6.10 and CCL 1.14 confirmed why this does not currently produce a runtime crash or stale memo hit: `(st-lst 'mom)` interns via `hons-s` with initial value `nil` (avoiding `UNBOUND-VARIABLE`), and `stobj-let-fn-raw`'s `updated-consumer` subsequently invokes the parent abstract stobj's `:exec` child updater (`update-kid-c`), which itself executes `(memoize-flush mom$c)`.
- **Fix:** In `defabsstobj-fn1` (`other-events.lisp:25093-25096`), compute `congruent-stobj-rep` via `(congruent-stobj-rep (concrete-stobj st-name-new wrld2) wrld2)` (matching `memoize-fn` line `3604`), and recompute `:congruent-stobj-rep` in Pass 2 when `att-name` is non-nil.

---

### SCR-L3 — `hl-rebuild-addr-ht` Sets Dead Survivor Bit to `1` Instead of `0` (`hons-raw.lisp:3652`)

- **Location:** `hons-raw.lisp:3648-3653`
- **Defect:** During compacting GC rebuild of `addr-ht`, when `(sbits-ref sbits i)` is `1` and `(hl-static-inverse-cons i)` returns `nil` (indicating the static cons was freed), the code comments *"We amend SBITS on the fly to account for this"* but calls `(sbits-set sbits i 1)` instead of `(sbits-set sbits i 0)`.
- **Fix:** Change `(sbits-set sbits i 1)` at `hons-raw.lisp:3652` to `(sbits-set sbits i 0)`.

---

### SCR-L4 — `ser-decode-and-restore-fals` Accepts `index = 1` (`T`) into FALTABLE (`serialize-raw.lisp:1403-1410`)

- **Location:** `serialize-raw.lisp:1403-1410` (and `serialize.lisp:87`)
- **Defect:** In V2/V3 `.sao` streams, decoder array slot `0` holds `NIL` and slot `1` holds `T` (`serialize-raw.lisp:1487`). `ser-decode-and-restore-fals` terminates on `(= index 0)` and checks `(< index max)`, but does **not** reject `(= index 1)` (or `(atom alist)`). A crafted `.sao` stream with `index = 1` passes `T` to `hl-restore-fal-for-serialize`, storing atom `T` in `hl-falslot` / `FALTABLE` in violation of FALTABLE Invariant 1 (`hons-raw.lisp:2758`: *"Every key in the FALTABLE is a CONS"*). Lookups in `hons-get` and `hons-acons` happen to check `(atom alist)` before querying `FALTABLE`, preventing logic divergence, though `fast-alist-summary` / `FALTABLE` walkers assume cons keys. (Additionally, `serialize-read-fn` at `serialize.lisp:87` skips `bad-lisp-objectp`, relying on the host's `"COMMON-LISP"` package containing no non-`acl2-symbolp` imported symbols — verified safe on SBCL 2.6.10 and CCL 1.14, where all 978 CL symbols satisfy `symbolp`.)
- **Fix:** Check `(unless (and (< 1 index) (< index max) (consp (svref array index))) (error ...))` in `ser-decode-and-restore-fals`.

---

### SCR-L5 — `:tau-system` Missing `*tau-contradiction*` Check in `MV-NTH` Form-2 `tau-term` Branch & Missing Exclusions in `tau-boolean-formp` (`tau.lisp:11582-11592, 7288-7302`)

- **Locations:** `tau.lisp:11582-11592` and `tau.lisp:7288-7302`
- **Defect:**
  1. In `tau-term` (`tau.lisp:11582-11592`), the Form-2 `(MV-NTH 'k (fn ...))` branch calls `(tau-term-lst nil (fargs (fargn term 2)) ...)` and passes `actual-tau-lst` straight to `(apply-tau-bounders bounders actual-tau-lst ...)` without checking `((eq actual-tau-lst *tau-contradiction*) (mv *tau-contradiction* calist))` — unlike the symmetric Form-1 branch 100 lines below (`tau.lisp:11684`)! Because `tau-term-lst` returns the keyword `:contradiction` (`*tau-contradiction*`) when any argument has contradictory tau, a Form-2 `mv-nth` bounder whose 2nd+ argument yields `*tau-contradiction*` passes `:contradiction` into `apply-tau-bounders1` -> `(car actual-taus)`, triggering a raw `(car :contradiction)` guard/type error.
  2. In `tau-boolean-formp` (`tau.lisp:7288-7302`), `(BOOLEANP (f v))` checks only `(and (symbolp f) (symbolp v))` and omits the exclusions enforced by `monadic-boolean-fnp` (`tau.lisp:7138-7170`): `(not (member-eq fn *non-tau-monadic-boolean-functions*))` (`NOT`, `DEBUGGER-ENABLEDP`) and excluding functions known by type-prescription to be constant `T` or `NIL`.
- **Fix:** Add `((eq actual-tau-lst *tau-contradiction*) (mv *tau-contradiction* calist))` at `tau.lisp:11588` (matching line `11684`), and align `tau-boolean-formp` with `monadic-boolean-fnp`.
