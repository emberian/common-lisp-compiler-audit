# ACL2 World-Rollback & Imperative Raw Side-Table Audit (`ACL2-WORLD-ROLLBACK`)

**Target**: ACL2 8.7+ (`1d2b39a424`) on **SBCL 2.6.10** (`head-worktree/saved_acl2`, arm64) and **CCL 1.14** (`ccl-worktree/saved_acl2`, arm64)
**Methodology**: Source-level rollback-boundary audit (`history-management.lisp`, `ld.lisp`, `interface-raw.lisp`, `basis-a.lisp`, `other-events.lisp`, `translate.lisp`, `memoize-raw.lisp`, `apply-raw.lisp`, `hons-raw.lisp`, `axioms.lisp`) + Observational Rollback Equivalence State-Machine Fuzzer (`/Users/ember/dev/compiler-audit/hunts/world-rollback/gen_world_rollback.py`) comparing `(Fresh -> B -> P)` vs `(Fresh -> B -> H -> Rollback(H) -> P)` across 7 world-reversion boundaries on both SBCL and CCL.

---

## 1. Executive Summary

ACL2's logical world `(w state)` is a persistent functional alist rolled back atomically across `:u` / `:ubt`, `(encapsulate () (local H))` pass-1 $\to$ pass-2 reversion, failed multi-event `progn` / `encapsulate` / `ld` (`revert-world-on-error`), failed `include-book` (`hcomp-restore-defs`), and post-`certify-book` world reset. By contrast, Common Lisp's runtime and compiler side tables (`*user-stobj-alist*`, `*non-executable-user-stobj-lst*`, `*current-stobj-gensym-ht*`, `'redundant-raw-lisp-discriminator` plists, `(st-lst name)` memoize-flush lists, `*memoize-info-ht*`, `*cl-cache*`, symbol function/macro cells, compiler `ftype` proclamations) are imperative and global.

Excluding previously reported bugs (`S6` / `B2-S6b` `proclaim-dfs` `double-float` `ftype` survival, `R7` SBCL `redef!`+`:u` `ftype` crash, `S7` `defun-inline` `$inline` undo survival, and `SCR-*` / `XDS-*`), this audit uncovered **7 brand-new rollback bugs verified on BOTH SBCL 2.6.10 and CCL 1.14**, including **4 pure-kernel soundness bugs proving `(defthm nil-proved nil)` with `:ttags nil`** (3 of which certify directly as standalone `:ttags nil` `.cert` books, and 1 of which uses **zero** `memoize`, **zero** `:clause-processor`, **zero** `apply$`, and **zero** `defattach`):

| ID | Class | Summary | Rollback Boundary | SBCL 2.6.10 | CCL 1.14 | Standalone Reproducer |
|---|---|---|---|---|---|---|
| **WRB-S1** | **Pure-Kernel Soundness (`NIL` proved, `:ttags nil` `.cert` book)** | Shallow `*user-stobj-alist*` snapshot on `*undo-stack*` (`interface-raw.lisp:7330`) + `trans-eval` functional `put-assoc-eq-alist` spine copy + in-place `stobj-let` / `swap-stobjs` parent slot mutation aliases two sibling child stobj fields (`parent.k1` and `parent.k2` become `eq`), violating Stobj Evaluation Invariant `(C1)`. | `:u` / `:ubt`, `(encapsulate () (local ...))` (`certify-book :ttags nil`) | **`NIL` proved + `.cert`** | **`NIL` proved + `.cert`** | `repros/rollback-nested-stobj-swap-alias/` |
| **WRB-S2** | **Pure-Kernel Soundness (`NIL` proved, `:ttags nil` `.cert` book)** | Rolling back a child stobj executes `(remhash ',name *current-stobj-gensym-ht*)` (`interface-raw.lisp:3651`, logically modeled by `retract-stobj-tables` in `history-management.lisp:3946`), mutating `tbl-keys` / `tbl-count` of every live `stobj-table` **without calling `memoize-flush`**. Memoized reader retains `'(KID)` while `tbl-keys` returns `NIL`. | `:u` / `:ubt`, `(encapsulate () (local ...))` (`certify-book :ttags nil`) | **`NIL` proved + `.cert`** | **`NIL` proved + `.cert`** | `repros/rollback-stobj-table-memoize-flush/` |
| **WRB-S3** | **Pure-Kernel Soundness (`NIL` proved, `:ttags nil`, zero `memoize` / `:clause-processor` / `apply$` / `defattach`)** | When `include-book` fails after early-loading a compiled book (`include-book-raw-top`), raw `defstobj` (`basis-a.lisp:9614`) / `defabsstobj` (`other-events.lisp:22629`) overwrites `(get '*the-live-kid* 'redundant-raw-lisp-discriminator)` (`:creator`, `:non-memoizable`, `:congruent-stobj-rep`), and `hcomp-restore-defs` (`interface-raw.lisp:5646-5706`) **never restores `*the-live-<stobj>*`**. Defining `(defstobj mom (k :type kid))` calls `(get-stobj-creator 'kid nil)` (`basis-a.lisp:8472`), initializing `mom`'s child via `CREATE-BOGUS-ST` (`#(99)`) while logically `(create-mom)` is `'((0))`. | Failed `include-book` (`hcomp-restore-defs` + `revert-world-on-error`) | **`NIL` proved (`:ttags nil`)** | **`NIL` proved (`:ttags nil`)** | `repros/rollback-failed-include-stobj-discriminator/` |
| **WRB-S4** | **Pure-Kernel Soundness (`NIL` proved, `:ttags nil` `.cert` book)** | Raw `defstobj` (`basis-a.lisp:9567`) emits unconditional `(defg ,(st-lst name) nil)` (`defparameter` / `ccl::defstatic`, `acl2-fns.lisp:2224-2236`) into every compiled book, unlike session `defstobj` (`interface-raw.lisp:7338-7339`), which guards with `(or (boundp var) ...)`. Rolling back `(encapsulate () (local (include-book ...)))` (or failing `include-book`) wipes `'READ-ST` from `(st-lst 'st)` so `update-fld` stops flushing `read-st`'s memo table. | `(encapsulate () (local (include-book ...)))` (`certify-book :ttags nil`), failed `include-book` | **`NIL` proved + `.cert`** | **`NIL` proved + `.cert`** | `repros/rollback-include-book-st-lst-wipe/` |
| **WRB-R1** | **Guard-Verified Raw Lisp Crash (`:ttags nil`)** | `other-events.lisp:20675-20695` omits `(symbolp k)` and live-stobj-ness of `k` from `common-guard` of `stobj-table` `boundp` / `remove` (`:guard (parentp parent)`, `:verify-guards t`), yet raw `tbl-boundp` / `tbl-remove` (`basis-a.lisp:8821`) calls `(current-stobj-gensym k)` (`basis-a.lisp:8620-8639`), aborting into raw Common Lisp `cl:error` once `k` is rolled back (or for any non-stobj / non-symbol key). | `(encapsulate () (local (defstobj kid ...)) ...)`, `:u` / `:ubt` | **Raw Lisp `cl:error`** | **Raw Lisp `cl:error`** | `repros/rollback-stobj-table-guard-crash/` |
| **WRB-R2** | **Raw Lisp `cl:assert` Crash (`:ttags nil`)** | `defstobj` / `defabsstobj` undo pushes `(maybe-push-undo-stack 'defconst '*user-stobj-alist*)` (`interface-raw.lisp:7330`) **without** saving `*non-executable-user-stobj-lst*`, and `remove-global-stobj` / `add-global-stobj` (`other-events.lisp:37419-37500`) push zero `*undo-stack*` entries. Rolling back across `add-global-stobj` / `remove-global-stobj` puts `st` in neither or both lists, triggering raw `cl:assert` failure `(MEMBER-EQ NAME *NON-EXECUTABLE-USER-STOBJ-LST*)`. | `(encapsulate () (local ...))`, `:u` / `:ubt` | **Raw Lisp `cl:assert` crash** | **Raw Lisp `cl:assert` crash** | `repros/rollback-global-stobj-nonexec-desync/` |
| **WRB-R3** | **Wrong Guard-Verified Value (`redef!` + `:u`)** | `maybe-push-undo-stack` (`interface-raw.lisp:3651`) unconditionally pushes `(remhash ',name *current-stobj-gensym-ht*)` instead of saving/restoring any prior gensym for `name`. Redefining stobj `kid` under `(redef!)` and undoing via `:u` reverts `(w state)` to the pre-redefinition world where `kid` was never undone, yet wipes `kid`'s gensym and silently erases live `stobj-table` entries (`(KID)` / `99` / `1` $\to$ `NIL` / `0` / `0`). | `(redef!)` + `(defstobj kid ...)` + `:u` | **Wrong value (`99` $\to$ `0`)** | **Wrong value (`99` $\to$ `0`)** | `repros/rollback-stobj-table-redef-gensym/` |

---

## 2. Rollback Boundary & Imperative Raw Side-Table Audit Matrix

We audited all world-reversion entry points (`retract-world1` / `undo-trip` / `maybe-pop-undo-stack`, `encapsulate` pass-1 $\to$ pass-2 reversion, `revert-world-on-error` in `ld` / `progn` / `encapsulate`, `hcomp-restore-defs` in failed `include-book`, and post-`certify-book` reset) against ACL2's raw Common Lisp side tables:

| # | Raw Imperative State | Location | Rollback Handler | Audit Status |
|---|---|---|---|---|
| 1 | `*user-stobj-alist*` spine & nested array slots | `interface-raw.lisp:3636, 7330`, `translate.lisp` (`trans-eval` `put-assoc-eq-alist`) | Shallow `defconst` value save of alist head pointer only | **VULNERABLE (`WRB-S1`)** — shallow spine save + functional `put-assoc-eq-alist` + in-place child array swap aliases nested stobjs (`C1` violation $\to$ `NIL` proved) |
| 2 | `*non-executable-user-stobj-lst*` & `add`/`remove-global-stobj` | `interface-raw.lisp:7330, 7356-7375`, `other-events.lisp:37419-37500` | **NONE** (`*user-stobj-alist*` saved without `*non-executable-user-stobj-lst*`; `add`/`remove-global-stobj` push nothing) | **VULNERABLE (`WRB-R2`)** — desynchronizes the partition invariant between `*user-stobj-alist*` and `*non-executable-user-stobj-lst*` ($\to$ raw `cl:assert` crash) |
| 3 | `*current-stobj-gensym-ht*` vs `memoize` tables | `interface-raw.lisp:3651-3653`, `basis-a.lisp:8616-8661`, `history-management.lisp:3946` | `(remhash ',name *current-stobj-gensym-ht*)`, **zero `memoize-flush` calls** | **VULNERABLE (`WRB-S2`)** — mutates `tbl-keys` / `tbl-count` of live `stobj-table`s on rollback without flushing memoized readers ($\to$ `NIL` proved) |
| 4 | `*current-stobj-gensym-ht*` under `redef!` + `:u` | `interface-raw.lisp:3651-3653` | Unconditional `remhash` instead of restoring previous gensym | **VULNERABLE (`WRB-R3`)** — `redef!` + `:u` deletes surviving stobj's gensym, wiping live `stobj-table` entries |
| 5 | `stobj-table` `boundp`/`remove` raw `current-stobj-gensym` lookup | `other-events.lisp:20675-20695`, `basis-a.lisp:8620-8639, 8821` | Guard checks only `(parentp parent)`; raw code errors if `k` is not in `*current-stobj-gensym-ht*` | **VULNERABLE (`WRB-R1`)** — guard-verified `tbl-boundp`/`tbl-remove` crashes raw Lisp after key stobj `k` is rolled back |
| 6 | `(get '*the-live-<stobj>* 'redundant-raw-lisp-discriminator)` | `basis-a.lisp:8472, 9614`, `other-events.lisp:22629`, `interface-raw.lisp:5646-5706` | Saved on `*undo-stack*` for session `defstobj`, **omitted from `hcomp-restore-defs`** on failed `include-book` | **VULNERABLE (`WRB-S3`)** — failed `include-book` permanently poisons `:creator`/`:non-memoizable`/`:congruent-stobj-rep` ($\to$ `NIL` proved without `memoize` or `:clause-processor`) |
| 7 | `(st-lst name)` per-stobj memoize-flush symbol list | `basis-a.lisp:9567`, `acl2-fns.lisp:2224-2236`, `interface-raw.lisp:7337-7339` | Session `defstobj` checks `(boundp var)`, but compiled raw `defstobj` emits `(defg ,(st-lst name) nil)` | **VULNERABLE (`WRB-S4`)** — rolled-back `(local (include-book ...))` or failed `include-book` resets `(st-lst name)` to `NIL` ($\to$ `NIL` proved) |
| 8 | Compiler `double-float` `ftype` proclamations (`proclaim-dfs`) | `interface-raw.lisp:3791, 6168` | None on CCL (`ftype` persists); `redef!`+`:u` crash on SBCL | Previously reported (`S6`, `B2-S6b`, `R7`) — excluded from our findings |
| 9 | `defun-inline` `$inline` raw function & compiler macro | `interface-raw.lisp:3620-3660` | `undo-name` strips `$inline` before pushing `*undo-stack*` | Previously reported (`S7`) — excluded from our findings |
| 10 | `*1*` executable-counterpart stubs & arity/mv wrappers | `interface-raw.lisp:3580-3625, 5668-5691` | `maybe-push-undo-stack` + `hcomp-fn-macro-restore-ht` (`fmakunbound!` / `symbol-function` restore) | **CLEAN** (verified by source audit + 210-seed arity/mv/mode/macro-swap fuzzer campaign) |
| 11 | `*cl-cache*` (`apply$` / `lambda$` compiled lambda cache) | `apply-raw.lisp:140-310` | Entries tagged with world `evno`; `invalidate-some-cl-cache-lines` invalidates `evno > current-evno` on retraction | **CLEAN** on rollback (note orthogonal non-rollback warrant gap `SCR-S2` in `ACL2-STATE-CACHE-RISK.md`) |
| 12 | `defattach` attachment symbols & `:aokp t` memo tables | `interface-raw.lisp:3662-3708, 7770`, `memoize-raw.lisp:5207-5285` | Undo pushes onto `*defattach-fns*` and runs `update-memo-entries-for-attachments` | **CLEAN** on rollback (verified by source audit + fuzzer `reattach_ds1` + `memoize :aokp t` probes) |
| 13 | `*memoize-info-ht*` on `defun` / `unmemoize` rollback | `memoize-raw.lisp`, `interface-raw.lisp:3695-3725` | `unmemoize-fn` / `clear-memoize-table` invoked when memoized function or `memoize-table` entry retracts | **CLEAN** for direct function retraction (stobj side-channels `WRB-S2` and `WRB-S4` bypass this) |
| 14 | `*ever-known-package-alist*` (`defpkg`) | `axioms.lisp`, `interface-raw.lisp` | Monotonic by design: ACL2 checks package consistency against `*ever-known-package-alist*` across `:u` to prevent symbol-interning Capture | **BY DESIGN** (documented intentional monotonicity in ACL2) |

---

## 3. Detailed Findings

---

### WRB-S1: Shallow `*user-stobj-alist*` Undo Snapshot + `trans-eval` Spine Copy Aliases Sibling Nested Stobj Fields (`(defthm nil-proved nil)`, `:ttags nil` `.cert` book)

- **Severity**: Critical — **Pure-Kernel Soundness Bug** (`(defthm nil-proved nil)` certified as a standalone `.cert` book with `:ttags nil`, `:skip-proofs-seen nil`, `:redef-seen nil` on both SBCL 2.6.10 and CCL 1.14).
- **Location**:
  - `interface-raw.lisp:7330` — `(maybe-push-undo-stack 'defconst '*user-stobj-alist*)`
  - `interface-raw.lisp:3636-3645` — `defconst` undo saves `',(symbol-value name)` (only the top-level cons cell pointer of `*user-stobj-alist*`, **not** the contents of live stobj arrays or detached spine cells)
  - `translate.lisp` (`trans-eval` stobj write-back via functional `put-assoc-eq-alist`)
- **Root Cause**:
  ACL2's soundness proof for `stobj-let` relies on **Stobj Evaluation Invariant `(C1)`**: every live global stobj array and every nested child stobj array inside any parent stobj are pairwise distinct (`not eq`) Lisp vectors. `swap-stobjs` preserves `(C1)` during forward execution because swapping `kid` (`#<V0>`) with `parent.k1` (`#<V1>`) puts `#<V0>` into `parent[0]` and `#<V1>` into `kid`'s binding in `*user-stobj-alist*`.

  However:
  1. Suppose `kid` (`#<V0>`), congruent `kid2`, and `parent` (`#(#<V1> #<V2>)`) are live in `*user-stobj-alist*`:
     `((parent . #(#<V1> #<V2>)) (kid2 . #<V3>) (kid . #<V0>))`.
  2. Inside `(encapsulate () (local ...))` (or before `:u`), `(local (defstobj tmp dummy))` executes `(maybe-push-undo-stack 'defconst '*user-stobj-alist*)`, saving the old list pointer `L0 = ((parent . #(#<V1> #<V2>)) (kid2 . #<V3>) (kid . #<V0>))`, and prepends `(tmp . #<VT>)`.
  3. Still inside `(local ...)`, `trans-eval` executes `(swap-k1 parent kid)`:
     - `parent`'s raw vector `#(#<V1> #<V2>)` is **mutated in place** to `#(#<V0> #<V2>)`!
     - `trans-eval` updates `*user-stobj-alist*` via **functional** `put-assoc-eq-alist`, which copies the cons spine down to `kid` so the new alist has `(kid . #<V1>)`, while **leaving `L0`'s original cons cell `(kid . #<V0>)` untouched**!
  4. When `encapsulate` finishes Pass 1 (or `:u` runs), `*undo-stack*` restores `(setq *user-stobj-alist* L0)`:
     - In `L0`, `kid` points to `#<V0>` again, **and** `parent[0]` (`parent.k1`) **still points to `#<V0>`**!
  5. Now executing `(swap-k2 parent kid)` swaps `kid` (`#<V0>`) into `parent[1]` (`parent.k2`). Now **`(eq (svref parent 0) (svref parent 1))` is `T`**: `parent.k1` and `parent.k2` are the **same raw vector `#<V0>`**!
  6. Setting `k1 := 1` and `k2 := 2` overwrites `k1` to `2` at runtime while logically `(get-k1 (set-k2 2 (set-k1 1 parent))) == 1`, allowing a verified 4-line `:clause-processor` to prove `(defthm nil-proved nil)` in a `:ttags nil` certified book.
- **Reproducer**: `/Users/ember/dev/compiler-audit/repros/rollback-nested-stobj-swap-alias/run.sh` (`repro.lisp` certifies with `(certify-book "repro" 0 t :ttags nil)` on both SBCL and CCL).
- **Recommended Fix**:
  Never restore `*user-stobj-alist*` by saving/restoring an old list spine pointer (`(maybe-push-undo-stack 'defconst '*user-stobj-alist*)`). Instead, when undoing `(defstobj <name> ...)` or `(defabsstobj <name> ...)`, remove `<name>`'s entry from the *current* `*user-stobj-alist*` via `(setq *user-stobj-alist* (remove1-assoc-eq ',name *user-stobj-alist*))` (or restore the previous stobj descriptor only on `redef!`, allocating a fresh initial stobj vector so no live array pointer can ever be duplicated across `*user-stobj-alist*` and a nested parent slot).

---

### WRB-S2: `stobj-table` Child-Stobj Retraction Mutates Live `stobj-table`s Without Calling `memoize-flush` (`(defthm nil-proved nil)`, `:ttags nil` `.cert` book)

- **Severity**: Critical — **Pure-Kernel Soundness Bug** (`(defthm nil-proved nil)` certified as a standalone `.cert` book with `:ttags nil` on both SBCL 2.6.10 and CCL 1.14).
- **Location**:
  - `interface-raw.lisp:3651-3653` — `(push '(remhash ',name (the hash-table *current-stobj-gensym-ht*)) *undo-stack*)`
  - `basis-a.lisp:8642-8661` — `clean-stobj-table` lazily purges retracted gensyms when `tbl-keys` / `tbl-count` runs
  - `history-management.lisp:3946` — `retract-stobj-tables` models this mutation logically on world retraction
- **Root Cause**:
  In ACL2's logic (`retract-stobj-tables` in `history-management.lisp:3946`), retracting `(defstobj kid ...)` logically mutates every live stobj that contains a `stobj-table` field by deleting any `'kid` entry from that table (`(tbl-keys parent)` changes from `'(KID)` to `NIL`, and `(tbl-count parent)` changes from `1` to `0`).
  In raw Common Lisp (`interface-raw.lisp:3651-3653`), ACL2 implements this retraction in $O(1)$ time by executing `(remhash 'kid *current-stobj-gensym-ht*)`, so the next call to `(tbl-keys parent)` runs `(clean-stobj-table ht)` (`basis-a.lisp:8642`), deletes the orphaned gensym from `ht`, and returns `NIL`.

  **The missing invariant**: Normally, any mutation to a live stobj `parent` invokes `(memoize-flush *st-lst-for-parent*)`. Because stobj retraction mutates `parent` *implicitly* via `*current-stobj-gensym-ht*` without calling any updater of `parent`, **`(memoize-flush ...)` is never called for any stobj containing a `stobj-table`**!
  - Inside `(encapsulate () (local (defstobj kid fld)) ...)`: populate `'kid` in `parent` and evaluate memoized `(parent-keys parent)` $\implies$ caches `#<parent-ptr> -> '(KID)`.
  - `encapsulate` exits Pass 1, rolling back `kid`: `(tbl-keys parent)` is now `NIL`, while `(parent-keys parent)` still returns cached `'(KID)`!
  - Logically `(equal (parent-keys parent) (tbl-keys parent))` is `(equal (tbl-keys parent) (tbl-keys parent)) = T`, so a verified `:clause-processor` immediately proves `(defthm nil-proved nil)` with `:ttags nil`.
- **Reproducer**: `/Users/ember/dev/compiler-audit/repros/rollback-stobj-table-memoize-flush/run.sh` (`repro.lisp` certifies with `(certify-book "repro" 0 t :ttags nil)` on both SBCL and CCL).
- **Recommended Fix**:
  Whenever `(remhash name *current-stobj-gensym-ht*)` executes during stobj undo/retraction (`interface-raw.lisp:3651` / `undo-trip`), either flush memo tables for all stobjs with `stobj-table` fields (via `(memoize-flush ...)` across `*user-stobj-alist*`) or call `(clear-memoize-tables)` unconditionally on stobj retraction.

---

### WRB-S3: Failed `include-book` Poisons `*the-live-<stobj>*` `'redundant-raw-lisp-discriminator` (`(defthm nil-proved nil)`, `:ttags nil`, Zero `memoize` / `:clause-processor` / `apply$` / `defattach`)

- **Severity**: Critical — **Pure-Kernel Soundness Bug** (`(defthm nil-proved nil)` with `:ttag nil`, `:ttags-seen nil`, `:skip-proofs-seen nil`, `:redef-seen nil`, **without** `memoize`, `:clause-processor`, `apply$`, or `defattach` on both SBCL 2.6.10 and CCL 1.14).
- **Location**:
  - `interface-raw.lisp:5527-5540, 5646-5706` — `hcomp-init` and `hcomp-restore-defs`
  - `basis-a.lisp:9591-9623` — raw `defstobj` (`(setf (get ',the-live-name 'redundant-raw-lisp-discriminator) ...)`)
  - `other-events.lisp:22609-22639` — raw `defabsstobj` (identical overwrite)
  - `basis-a.lisp:8471-8477, 9103` — `get-stobj-creator` reads `:creator` from `(get (the-live-var name) 'redundant-raw-lisp-discriminator)`
- **Root Cause**:
  During `(include-book "B")`, `include-book-raw-top` loads `"B"`'s compiled `.fasl`/`.da64fsl` **before** logically replaying `"B"`'s portcullis/event forms. If `"B"` subsequently fails logical admission (for example, due to a conflicting event in the current world), `hcomp-restore-defs` (`interface-raw.lisp:5646-5706`) attempts to roll back all raw Lisp side effects of loading `"B"`'s compiled file.

  However, `hcomp-init` (`interface-raw.lisp:5527-5540`) only populates `*hcomp-const-restore-ht*` from `*hcomp-const-alist*` (`defconst` `add-trip` entries) — **not** `*the-live-<stobj>*` symbols! (Moreover, even in `*hcomp-const-restore-ht*`, lines 5699-5704 only `remprop` `'redundant-raw-lisp-discriminator` when the symbol was previously unbound.)
  Meanwhile, in `"B"`'s compiled file, raw `defstobj` (`basis-a.lisp:9591-9623`) checks `(old-pair (assoc-eq ',name *user-stobj-alist*))`. Whenever `kid` is currently not in `*user-stobj-alist*` (e.g., `kid` was declared `:non-executable t` or temporarily detached via `(remove-global-stobj 'kid state)`), `old-pair` is `NIL`, so loading `"B"`'s compiled file executes:
  ```lisp
  (setf (get '*the-live-kid* 'redundant-raw-lisp-discriminator)
        (cons 'defstobj (make defstobj-redundant-raw-lisp-discriminator-value
                              :creator create-bogus-st ...)))
  ```
  before `"B"` fails logical admission on `kid` redefinition! `hcomp-restore-defs` restores `create-bogus-st`'s function cell (from an earlier valid `(defstobj bogus-st (bogus-fld :type integer :initially 99))`), while **leaving `*the-live-kid*`'s `'redundant-raw-lisp-discriminator` permanently pointing `:creator` at `CREATE-BOGUS-ST`**!

  When `(defstobj mom (k :type kid))` is then admitted:
  - Logically, `(create-mom)` is `'((0))`, so `(read-fresh-mom)` (using `with-local-stobj mom`) unfolds to `0` (`read-fresh-mom-is-0`).
  - In raw Lisp, `defstobj-raw-init-fields` (`basis-a.lisp:9103`) calls `(get-stobj-creator 'kid nil)` (`basis-a.lisp:8472`), which reads `:creator` from `*the-live-kid*`'s poisoned discriminator and emits `(CREATE-BOGUS-ST)` (`#(99)`) inside `CREATE-MOM`! Guard-verified executable-counterpart evaluation proves `(equal (read-fresh-mom) 99)` (`read-fresh-mom-is-99`), and `:use (read-fresh-mom-is-0 read-fresh-mom-is-99)` proves `(defthm nil-proved nil)`.
  - Note: `:non-memoizable` (`translate.lisp:17163`) and `:congruent-stobj-rep` (`basis-a.lisp:9516`) on `*the-live-<stobj>*` are equally poisoned by the same missing restoration.
- **Reproducer**: `/Users/ember/dev/compiler-audit/repros/rollback-failed-include-stobj-discriminator/run.sh`.
- **Recommended Fix**:
  1. Record `*the-live-<stobj>*` (for every `defstobj` and `defabsstobj` in a book's `hcomp` metadata) in a dedicated `*hcomp-discriminator-restore-ht*` saved by `hcomp-init` (storing `(cons present-p (get sym 'redundant-raw-lisp-discriminator))`) and restored unconditionally in `hcomp-restore-defs` (also fixing the `boundp` branch at `interface-raw.lisp:5699-5704` for `defconst`!).
  2. In raw `defstobj` (`basis-a.lisp:9591`) and raw `defabsstobj` (`other-events.lisp:22609`), also check `(member-eq ',name *non-executable-user-stobj-lst*)` alongside `old-pair` so an incompatible stobj cannot overwrite an existing non-executable/removed stobj's discriminator during early compiled-book load.

---

### WRB-S4: Compiled Raw `defstobj` Emits Unconditional `(defg ,(st-lst name) nil)`, Wiping `memoize-flush` Tracking Across `(local (include-book ...))` or Failed `include-book` (`(defthm nil-proved nil)`, `:ttags nil` `.cert` book)

- **Severity**: Critical — **Pure-Kernel Soundness Bug** (`(defthm nil-proved nil)` certified as a standalone `.cert` book with `:ttags nil` on both SBCL 2.6.10 and CCL 1.14).
- **Location**:
  - `basis-a.lisp:9559-9567` — ``,@(and (null congruent-to) `((defg ,(st-lst name) nil)))``
  - `acl2-fns.lisp:2224-2236` — `defg` expands to `(defparameter ...)` (`#-ccl`) and `(ccl::defstatic ...)` (`#+ccl`), **not** `defvar` / `defv`!
  - Contrast `interface-raw.lisp:7337-7339` — session `defstobj` carefully guards `(or (boundp var) (eval `(defg ,var nil)))`
- **Root Cause**:
  Every memoized function `read-st` that takes a stobj `st` is registered on the global variable `(st-lst 'st)` by `memoize-fn` (`memoize-raw.lisp:3604`). Whenever any updater of `st` mutates `st` in place, it calls `(memoize-flush <st-lst-var>)` to invalidate `read-st`'s memo table.

  In `interface-raw.lisp:7337-7339`, ACL2 initializes `(st-lst name)` with `(or (boundp var) (eval `(defg ,var nil)))` so an existing list of memoized functions is preserved.
  However, in raw `defstobj` (`basis-a.lisp:9567`), compiled into every book's `.fasl` / `.da64fsl`, ACL2 emits a top-level `(defg <st-lst-var> nil)` **before** even checking redundancy or conflict! Because `defg` is `defparameter` on SBCL and `ccl::defstatic` on CCL (`acl2-fns.lisp:2224-2236`), loading **any** compiled book containing `(defstobj st ...)` — including:
  - `(encapsulate () (local (include-book "st_lst_helper_book")))` (rolled back at the end of Pass 1!),
  - a **failed** `(include-book "conflicting_st_book")` where `st` has completely incompatible fields and `include-book` aborts at `basis-a.lisp:9610`, or
  - a redundant `(include-book "st_lst_helper_book")` after `(memoize 'read-st)` —
  **unconditionally resets `(st-lst 'st)` to `NIL`**, detaching `'read-st` from `memoize-flush`! Subsequent `(update-fld 1 st)` mutates `st` in place without flushing `read-st`, so `(read-st st)` returns `0` while `(fld st)` returns `1`, proving `(defthm nil-proved nil)` in a `:ttags nil` certified book.
- **Reproducer**: `/Users/ember/dev/compiler-audit/repros/rollback-include-book-st-lst-wipe/run.sh` (`repro.lisp` certifies with `(certify-book "repro" 0 t :ttags nil)` on both SBCL and CCL).
- **Recommended Fix**:
  In `basis-a.lisp:9567`, replace `(defg ,(st-lst name) nil)` with `(defv ,(st-lst name) nil)` (or `(unless (boundp ',(st-lst name)) (setq ,(st-lst name) nil))` after a `declaim special`/`defv`), matching `interface-raw.lisp:7338-7339` so loading a compiled book never clobbers an already-bound `(st-lst name)` list.

---

### WRB-R1: Guard-Verified `stobj-table` `boundp` / `remove` Raw Lisp Crash After Rolling Back Key Stobj (`:ttags nil`)

- **Severity**: High — **Guard-Verified Raw Common Lisp Crash** (`cl:error` / `TYPE-ERROR` in 100% guard-verified `:logic` code with `:ttags nil` on both SBCL 2.6.10 and CCL 1.14).
- **Location**:
  - `other-events.lisp:20675-20695` — `common-guard` for `stobj-table` `boundp` / `remove`
  - `basis-a.lisp:8821` — raw `tbl-boundp` / `tbl-remove` emits `(current-stobj-gensym k)`
  - `basis-a.lisp:8620-8639` — `current-stobj-gensym` calls `(the hash-table *current-stobj-gensym-ht*)` and `(error "Attempted to access a stobj-table entry for ~s, which is not currently the name of a stobj." name)`
- **Root Cause**:
  In `other-events.lisp:20675-20685`, `common-guard` explicitly omits any guard on `k` when `hash-test` is `'stobj-table`, giving `(tbl-boundp k parent)` and `(tbl-remove k parent)` the guard `(parentp parent)` with `:verify-guards t` — based on the comment that in raw Lisp all keys in the hash-table are symbols from `current-stobj-gensym`.
  However, `defstobj-field-fns-raw-defs` (`basis-a.lisp:8821`) translates `k` in raw `tbl-boundp` and `tbl-remove` to `(current-stobj-gensym k)`, which:
  1. Checks `(gethash name *current-stobj-gensym-ht*)`, and if absent, looks up `(stobjp name nil (w *the-live-state*))` (`basis-a.lisp:8633`).
  2. When `name` is `'kid` and `(defstobj kid ...)` was rolled back via `(encapsulate () (local (defstobj kid fld)) ...)` or `:u` (or if `k` was never a stobj, or is a non-symbol like `42`), `stobjp` is `NIL`, and `current-stobj-gensym` signals raw Common Lisp `(error "Attempted to access a stobj-table entry for KID, which is not currently the name of a stobj.")`!
  - Before rollback (inside `encapsulate`), `(check-kid-verified parent)` returns `NIL` cleanly.
  - After rollback of `kid`, calling guard-verified `(check-kid-verified parent)` (or even `:verify-guards nil` callers, since `tbl-boundp` itself has `:verify-guards t`!) crashes in raw Common Lisp.
- **Reproducer**: `/Users/ember/dev/compiler-audit/repros/rollback-stobj-table-guard-crash/run.sh`.
- **Recommended Fix**:
  For `tbl-boundp` and `tbl-remove` (which only query or delete an existing entry and never insert a new stobj), replace `(current-stobj-gensym k)` in `basis-a.lisp:8821` with a non-erroring lookup helper `(lookup-stobj-gensym-or-nil k)`: if `(not (symbolp k))` or `(gethash k *current-stobj-gensym-ht*)` is `NIL`, `tbl-boundp` immediately returns `NIL` and `tbl-remove` returns `parent` unchanged, matching the logical definitions `(boundp-equal k alist)` and `(remassoc-equal k alist)` for all ACL2 values `k`.

---

### WRB-R2: `*user-stobj-alist*` vs `*non-executable-user-stobj-lst*` Undo Desynchronization Triggers Raw Lisp `cl:assert` Crash (`:ttags nil`)

- **Severity**: Medium-High — **Raw Common Lisp `cl:assert` Failure & Missing Global Stobj** (`:ttags nil` on both SBCL 2.6.10 and CCL 1.14).
- **Location**:
  - `interface-raw.lisp:7330, 7356-7375` — `defstobj` / `defabsstobj` undo pushes `(maybe-push-undo-stack 'defconst '*user-stobj-alist*)` without saving `*non-executable-user-stobj-lst*`
  - `other-events.lisp:37419-37500` (`interface-raw.lisp` raw counterparts) — `add-global-stobj` and `remove-global-stobj` mutate `*user-stobj-alist*` and `*non-executable-user-stobj-lst*` with zero `*undo-stack*` tracking
- **Root Cause**:
  ACL2 enforces an invariant in raw Lisp (`assert`s at `interface-raw.lisp:7356`, `basis-a.lisp:9647`, and `add-global-stobj` / `remove-global-stobj`) that every user stobj is in **exactly one** of `*user-stobj-alist*` or `*non-executable-user-stobj-lst*`.
  1. Start with `(defstobj st ...)` and `(remove-global-stobj 'st state)`: `st` is in `*non-executable-user-stobj-lst*` and not in `*user-stobj-alist*`.
  2. Inside `(encapsulate () (local (defstobj tmp dummy)) (local (make-event (er-progn (add-global-stobj 'st state) ...))))`:
     - `(defstobj tmp dummy)` snapshots `*user-stobj-alist*` (where `st` is absent), **not** `*non-executable-user-stobj-lst*`.
     - `(add-global-stobj 'st state)` removes `st` from `*non-executable-user-stobj-lst*` and adds `(st . #(42))` to `*user-stobj-alist*`.
  3. Pass 2 of `encapsulate` rolls back `(local (defstobj tmp dummy))`, restoring `*user-stobj-alist*` (removing `st`), while `*non-executable-user-stobj-lst*` was **not** restored! Now `st` is in **neither** list, and calling `(add-global-stobj 'st state)` aborts in raw Common Lisp with `The assertion (MEMBER-EQ NAME *NON-EXECUTABLE-USER-STOBJ-LST*) failed`.
  - Dual symmetric sequence (`(local (defstobj tmp dummy))` + `(local (remove-global-stobj 'st state))`) puts `st` in **both** lists simultaneously, failing `(assert (not (member-eq name *non-executable-user-stobj-lst*)))`!
  - Furthermore, as our random state-machine fuzzer autonomously discovered in `seed=520`, rolling back `(make-event (er-progn (remove-global-stobj 'st1 state) ...))` via `:ubt!` even *without* `defstobj tmp` leaves `st1` logically live in `(w state)` while absent from `*user-stobj-alist*`.
- **Reproducer**: `/Users/ember/dev/compiler-audit/repros/rollback-global-stobj-nonexec-desync/run.sh`.
- **Recommended Fix**:
  Maintain `*non-executable-user-stobj-lst*` and `*user-stobj-alist*` in lockstep on rollback: when removing an undone stobj `tmp`, remove `tmp` from whichever of `*user-stobj-alist*` or `*non-executable-user-stobj-lst*` currently holds it (rather than overwriting the entire `*user-stobj-alist*` with a stale snapshot), and disallow or revert `add-global-stobj` / `remove-global-stobj` across `make-event` / `local` rollback boundaries.

---

### WRB-R3: `redef!` + `:u` Unconditionally Deletes Surviving Stobj from `*current-stobj-gensym-ht*`, Wiping Live `stobj-table` Entries

- **Severity**: Medium — **Wrong Guard-Verified Return Value under `redef!` + `:u`** (sibling to `S7`; verified on both SBCL 2.6.10 and CCL 1.14).
- **Location**:
  - `interface-raw.lisp:3651-3653` — `maybe-push-undo-stack` for `defstobj` / `defabsstobj`
- **Root Cause**:
  When `maybe-push-undo-stack` runs for `(defstobj kid ...)` (`interface-raw.lisp:3651`), it unconditionally pushes:
  ```lisp
  (push `(remhash ',name (the hash-table *current-stobj-gensym-ht*)) *undo-stack*)
  ```
  even when `name` (`'kid`) **already had a gensym** `G0` in `*current-stobj-gensym-ht*` prior to redefinition under `(redef!)`!
  - Define `parent` (`stobj-table`) and `kid`, and store `(put-kid 99 parent)` under `G0`: `(list (tbl-keys parent) (get-kid parent) (tbl-count parent))` evaluates to `'((KID) 99 1)`.
  - Execute `(redef!)`, `(defstobj kid (fld :type integer :initially 5))`, `:u`, `(redef-)`.
  - Logically, `:u` reverts `(w state)` to the exact landmark before `(defstobj kid (fld ... 5))` — in that world, the original `(defstobj kid ...)` was **never retracted**!
  - In raw Lisp, `:u` executes `(remhash 'kid *current-stobj-gensym-ht*)` instead of restoring `'kid -> G0`. Calling `(list (tbl-keys parent) (get-kid parent) (tbl-count parent))` now purges `G0` via `clean-stobj-table` and returns `'(NIL 0 0)` instead of `'((KID) 99 1)`.
- **Reproducer**: `/Users/ember/dev/compiler-audit/repros/rollback-stobj-table-redef-gensym/run.sh`.
- **Recommended Fix**:
  In `maybe-push-undo-stack` (`interface-raw.lisp:3651`), check `(multiple-value-bind (old-g present-p) (gethash name *current-stobj-gensym-ht*) ...)`: if `present-p` is true, push `(setf (gethash ',name *current-stobj-gensym-ht*) ',old-g)`; otherwise push `(remhash ',name *current-stobj-gensym-ht*)` (and flush `stobj-table` memo tables per `WRB-S2`).

---

## 4. World-Rollback State-Machine Fuzzer (`hunts/world-rollback/`)

### 4.1 Design & Oracle
We built a standalone state-machine fuzzer in `/Users/ember/dev/compiler-audit/hunts/world-rollback/gen_world_rollback.py` (with runner `/Users/ember/dev/compiler-audit/hunts/world-rollback/run_world_rollback.sh`) implementing the QuickCheck / Jepsen StateMachine observational rollback equivalence oracle:
$$\text{Observe}(\text{Fresh} \to B \to P) \;\stackrel{?}{=}\; \text{Observe}(\text{Fresh} \to B \to H \to \text{Rollback}(H) \to P)$$
on **both** SBCL 2.6.10 and CCL 1.14 in isolated per-seed child processes (every `saved_acl2` invocation wrapped in `/opt/homebrew/bin/timeout --kill-after=10s 120s`).

- **Reused Identifier Pool**: `f1`, `f2`, `f3`, `m1` (overlapping `f1` to force `defun` $\leftrightarrow$ `defmacro` transitions across rollback), `*c1*`, `st1`, `st2`, `tbl1`, `nest1`, `abs1` / `abs1$c`, `ds1` / `call-ds1`, `"WRB-PKG1"`.
- **Action Grammar (`B` and `H`)**:
  - `defun` (1-arg, 2-arg, multi-value `mv`, `:mode :program` vs `:logic`, `:verify-guards t/nil`, `mbe` + `the`), `defund`, `defun-nx`, `defmacro`, `defconst`
  - `verify-guards`, `comp`, `memoize`, `unmemoize`
  - `defstobj` (scalar, resizable `(array integer (4))` + `resize-*`, `:inline t` `signed-byte 32`, `:non-executable t`, `:congruent-to` + `swap-stobjs`, nested stobj `nest1`, `stobj-table` `tbl1` + `stobj-let` population)
  - `defabsstobj` (concrete foundation + correspondence/preservation theorems + exported recognizer/creator/accessor/updater)
  - `remove-global-stobj` / `add-global-stobj`
  - Constrained `encapsulate` stub `ds1` + `defattach` re-attachment + `memoize :aokp t` caller
  - `defun$` + `apply$` + `lambda$` (`*cl-cache*` warm-up) + `defbadge` / `defwarrant`
  - `defpkg`, `table` (`acl2-defaults-table`), `add-custom-keyword-hint`
- **7 Rollback Operators Tested**:
  1. `ubt`: `(deflabel wrb-rb-mark)` $\to H \to$ `:ubt! wrb-rb-mark`
  2. `encap-local`: `(encapsulate () (local ...H...) ...)` (pass-1 $\to$ pass-2 rollback)
  3. `encap-fail`: failing mid-`encapsulate` `(make-event (er soft ...))` (`revert-world-on-error`)
  4. `progn-fail`: failing multi-event `progn` (`revert-world-on-error`)
  5. `ld-fail`: failing nested `(ld '(...H... (make-event (er soft ...))) :ld-error-action :error)` (`ld` `revert-world-on-error`)
  6. `certify-reset`: `(certify-book "wrb_cert_s<seed>" 0 t)` post-certification world reset
  7. `include-fail`: pre-certified book containing `H` + conflicting anchor so `(include-book ...)` early-loads the compiled `.fasl`/`.da64fsl` and then aborts & runs `hcomp-restore-defs`

### 4.2 Campaign Results
1. **Positive Oracle Validation (`--mode regression`)**:
   - All **7** new bugs (`WRB-S1`, `WRB-S2`, `WRB-S3`, `WRB-S4`, `WRB-R1`, `WRB-R2`, `WRB-R3`) were run through the differential oracle on both SBCL 2.6.10 and CCL 1.14; **14/14 host-case pairs** (`7 bugs x 2 hosts`) were automatically flagged as observational rollback divergences in 7.8s.
2. **Unfiltered Random State-Machine Fuzzing (`--allow-found-triggers`, 40 seeds = 160 ACL2 runs)**:
   - Autonomously synthesized `seed=520` (`op=ubt`), exposing that `(make-event (er-progn (remove-global-stobj 'st1 state) ...))` rolled back via `:ubt!` leaves `st1` logically live in `(w state)` while deleted from `*user-stobj-alist*` even without an intervening `defstobj`.
3. **Clean-Grammar Exploratory Campaign (`allow_found_triggers=False`, 210 seeds $\times$ 2 hosts $\times$ 2 worlds = 840 isolated ACL2 runs)**:
   - Operator distribution: `progn-fail` (38), `encap-fail` (33), `ubt` (32), `ld-fail` (32), `encap-local` (27), `certify-reset` (26), `include-fail` (22).
   - Completed in 30.4s with **0 unexpected divergences across all 840 runs** once `WRB-S1`–`WRB-S4`, `WRB-R1`–`WRB-R3`, `S6`, and `S7` are masked — providing strong empirical confirmation that ACL2's `*1*` stub restoration, `fn`/`macro` reclassification, `*cl-cache*` `evno` invalidation, and `defattach` `:aokp t` memoize invalidation behave consistently across all 7 rollback boundaries on both SBCL and CCL.

---

## 5. Reproduction Index

Every reproducer runs out-of-the-box on both SBCL 2.6.10 and CCL 1.14 under `/opt/homebrew/bin/timeout --kill-after=10s 120s` and cleans up all temporary `.cert`/`.port`/`.fasl`/`.da64fsl`/`.out` files on exit:

```bash
/Users/ember/dev/compiler-audit/repros/rollback-nested-stobj-swap-alias/run.sh
/Users/ember/dev/compiler-audit/repros/rollback-stobj-table-memoize-flush/run.sh
/Users/ember/dev/compiler-audit/repros/rollback-failed-include-stobj-discriminator/run.sh
/Users/ember/dev/compiler-audit/repros/rollback-include-book-st-lst-wipe/run.sh
/Users/ember/dev/compiler-audit/repros/rollback-stobj-table-guard-crash/run.sh
/Users/ember/dev/compiler-audit/repros/rollback-global-stobj-nonexec-desync/run.sh
/Users/ember/dev/compiler-audit/repros/rollback-stobj-table-redef-gensym/run.sh

# State-machine fuzzer (runs 7x2 positive oracle checks + N*4 dual-host fuzzer runs):
/Users/ember/dev/compiler-audit/hunts/world-rollback/run_world_rollback.sh 210 6
```
