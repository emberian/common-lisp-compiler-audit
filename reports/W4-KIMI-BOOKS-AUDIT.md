# Wave-4 Lane 4 (`w4-kimi-books`): Kimi K3 Community Books Audit

- **Auditor:** `w4-kimi-books` (Carbon verification + Kimi K3 `k3.1-pro` via `claude-kimi`)
- **Scope:** 71 untouched ACL2 Community Books files across 9 slices (`books/std/`, `books/tools/`, `books/centaur/{aig,bitops,misc,ubdds}`, `books/make-event/`, `books/misc/`), excluding previously audited engines (`fast-alist-pop*`, `SULFA`, `SMTLink`, `SATlink`, `ACL2s`).
- **Driver & Slice Summary:** [rake_kimi_books.py](file:///Users/ember/dev/compiler-audit/hunts/w4-kimi-books/rake_kimi_books.py), [slice_summary.md](file:///Users/ember/dev/compiler-audit/hunts/w4-kimi-books/slice_summary.md)
- **Verification Hosts:**
  - ACL2 8.7+ on **SBCL 2.6.10** (`darwin-arm64`): `/Users/ember/dev/acl2-fix/head-worktree/saved_acl2`
  - ACL2 8.7+ on **Clozure CL 1.14** (`darwin-arm64`): `/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2`
- **Reproducers:** 8 standalone executable reproducers in `/Users/ember/dev/compiler-audit/repros/w4-kb-*/run.sh`, all verified exiting `0` on **both SBCL 2.6.10 and CCL 1.14** against isolated shadow `ACL2_SYSTEM_BOOKS` directories (strictly read-only `books/`).

---

## Executive Summary

Kimi K3 (`k3.1-pro`) surfaced high-signal raw Lisp, soundness, and macro-contract bugs across `centaur/aig`, `centaur/misc`, `std/stobjs`, `std/util`, `tools/`, and `misc/`, while also producing several false positives where ACL2's kernel (`bad-lisp-objectp`, `*acl2-readtable*`) or dead `#+hons` guards already mitigate the risk. Every claimed bug below was inspected in source and empirically reproduced on both SBCL 2.6.10 and CCL 1.14.

### Highest-Severity Confirmed Findings

1. **`NIL` Proved Two Ways + Guard-Verified Raw-Lisp Memory Fault in `centaur/aig/aig-vars-fast`** (`w4-kb-aig-vars-fast-unsound`)
   - **Files:** [aig-vars-fast-raw.lsp](file:///Users/ember/dev/acl2-fix/head-worktree/books/centaur/aig/aig-vars-fast-raw.lsp#L120-L160), [aig-vars-fast.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/centaur/aig/aig-vars-fast.lisp)
   - **Bugs:**
     1. `aig-vars-unordered-list` raw Lisp definition omits `hons-copy` on atomic AIGs, so `(aig-vars-unordered-list 'a)` returns `(A)` in raw Lisp while `:logic` returns `NIL` — proving `NIL` (`NIL-PROVED-AVUL-ATOM`, `Q.E.D.`) on both SBCL and CCL.
     2. `aig-vars-unordered-list` uses `eql` (via `fast-cons-memo`) instead of `equal` for string AIG variables, so `(aig-vars-unordered-list (list (coerce '(#\v) 'string) "v"))` returns `("v" "v")` in raw Lisp while `:logic` deduplicates to `("v")` — proving `NIL` (`NIL-PROVED-AVUL-STRINGS`, `Q.E.D.`) on both SBCL and CCL.
     3. Guard-verified `(aig-vars-fast '((nil . 2) . (nil . 1)))` (`:guard t`) routes valid cons AIG variables through `alphorder-sort -> atom< -> bad-atom<=`, crashing in raw Lisp on both hosts (`Unhandled memory fault at #x13.` on SBCL; `The value 15 is not of the expected type SYMBOL.` on CCL).
   - **Reproducer:** [w4-kb-aig-vars-fast-unsound/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kb-aig-vars-fast-unsound/run.sh)

2. **Nested `with-fast-cons-memo` Corrupts Outer Memo Array & Smashes User Cons Cells** ([fast-cons-memo-raw.lsp](file:///Users/ember/dev/acl2-fix/head-worktree/books/centaur/misc/fast-cons-memo-raw.lsp#L89-L99), `w4-kb-fast-cons-memo-nesting`)
   - **Bug:** Line 89 executes `(setq *fast-cons-memo-array* ,restore-array)` (overwriting the global with the outer array before saving the inner state, or clobbering the restore binding) and lines 95 & 99 restore `*fast-cons-memo-array*` instead of `,restore-array`. Nesting `with-fast-cons-memo` permanently leaves the outer cons cell mutated to `(:SMASHED-MEMO FCM-MARKER)` after exit.
   - **Reproducer:** [w4-kb-fast-cons-memo-nesting/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kb-fast-cons-memo-nesting/run.sh)

3. **Three Bugs in `tools/oracle-timelimit`** ([oracle-timelimit.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/tools/oracle-timelimit.lisp#L250-L269), [oracle-timelimit-raw.lsp](file:///Users/ember/dev/acl2-fix/head-worktree/books/tools/oracle-timelimit-raw.lsp#L146-L290), `w4-kb-oracle-timelimit-bugs`)
   - **Bugs:**
     1. **Forced error suppression:** `oracle-timelimit-raw.lsp:190,222` tests `,(if suppress-lisp-errors ...)` at macroexpansion time where `suppress-lisp-errors` is a `gensym` (line 73), **always** truthy. Even `:suppress-lisp-errors nil` silently catches raw Lisp errors and returns `okp=NIL, ans=NIL`.
     2. **Negative time limit bypass:** Line 146 `(when (< ,limit 1) (sleep ,limit) (loop-finish))` passes negative `limit` (e.g. `-1`) to `sleep` in the background thread, crashing the timeout thread (`Invalid argument to SLEEP: -1` on SBCL / `The value -1 is not of the expected type (REAL 0 *)` on CCL) so the timed form runs to completion and returns `okp=T`.
     3. **`:ret (mv ans state)` crash on failure/timeout:** `oracle-timelimit-raw.lsp:285` returns `(values-list (make-list ,num-returns))` (`(values nil nil)`), binding `state` to `NIL` before `oracle-timelimit-extract` runs, aborting raw Lisp (`ABORTING from raw Lisp` / `The value NIL is not of type REAL`).
   - **Reproducer:** [w4-kb-oracle-timelimit-bugs/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kb-oracle-timelimit-bugs/run.sh)

4. **`std/stobjs/2d-arr` Live-Stobj `ec-call` Crash (`:ttags nil`)** ([2d-arr.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/std/stobjs/2d-arr.lisp#L890-L907), `w4-kb-2d-arr-ec-call-crash`)
   - **Bug:** `def-2d-arr` generates `resize-rows`/`resize-cols`/`set2` with `:guard (natp nrows)` and an `:exec` branch that falls back to `(ec-call (_prefix_-resize-rows$g nrows _stobj-name_))` when `nrows >= 2^60` (or `nrows * ncols >= 2^60`). Calling `(any2d-resize-rows (expt 2 60) any2d)` satisfies the guard yet fails ACL2's live-stobj `ec-call` restriction on both SBCL and CCL.
   - **Reproducer:** [w4-kb-2d-arr-ec-call-crash/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kb-2d-arr-ec-call-crash/run.sh)

5. **Host Printer Corruption & Broken Predicate in `tools/plev-ccl` & `tools/advise`** ([plev-ccl-raw.lsp](file:///Users/ember/dev/acl2-fix/head-worktree/books/tools/plev-ccl-raw.lsp#L53-L78), [advise-raw.lsp](file:///Users/ember/dev/acl2-fix/head-worktree/books/tools/advise-raw.lsp#L33-L46), `w4-kb-plev-advise-oprof-raw`)
   - **Bugs:**
     1. `plev-fn` assigns `*print-length*`, `*print-level*`, `*print-lines*`, etc. before any type validation (`(plev :length 'not-an-integer)` corrupts `*print-length*` on both SBCL and CCL). Additionally `plev-info` line 53 prints `ccl::*print-simple-vector*` instead of `ccl::*print-simple-bit-vector*`.
     2. `advisedp$-fn` discards `(eval `(ccl::advisedp ...))` and unconditionally returns `NIL` on CCL; on SBCL `advise-raw.lsp` is `#+Clozure`-only, so `advise$`/`advisedp$` abort with `Raw lisp definition not installed?`.
   - **Reproducer:** [w4-kb-plev-advise-oprof-raw/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kb-plev-advise-oprof-raw/run.sh)

6. **`std/util/bstar` `def-b*-decomp` Variable Capture & `access` Duplicate RHS Evaluation (`:ttags nil`)** ([bstar.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/std/util/bstar.lisp#L1512-L1522), [bstar.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/std/util/bstar.lisp#L1749-L1754), `w4-kb-bstar-decomp-capture`)
   - **Bugs:**
     1. `b*-decomp-fn` hardcodes the un-gensymmed symbol `b*-decomp-temp-var` when RHS is non-symbolic, capturing any outer `b*-decomp-temp-var` binding (`(test-decomp-capture 999)` returns `(1 (1 . 2))`).
     2. `patbind-access` substitutes `(car forms)` directly into every bound field lookup instead of binding a temp variable, evaluating side-effectful RHS expressions twice.
   - **Reproducer:** [w4-kb-bstar-decomp-capture/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kb-bstar-decomp-capture/run.sh)

7. **`tools/stobj-frame` Copy-Paste Bug Leaves Formal `V` Unrenamed (`:ttags nil`)** ([stobj-frame.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/tools/stobj-frame.lisp#L316-L319), `w4-kb-stobj-frame-v-collision`)
   - **Bug:** Line 316 checks `(position 'n formals)` instead of `(position 'v formals)` before generating `genvar 'v`, leaving formal `v` unrenamed and causing `(def-stobj-frame set-slot0-v my-stobj)` to fail its own generated `DEFTHM NTH-MY-STOBJ-OF-SET-SLOT0-V` on both SBCL and CCL.
   - **Reproducer:** [w4-kb-stobj-frame-v-collision/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kb-stobj-frame-v-collision/run.sh)

8. **Macro & Contract Bugs Across `misc/defattach-bang`, `std/util/defenum`, `tools/rewrite-dollar`, `tools/def-functional-instance` (`:ttags nil`)** (`w4-kb-tools-macro-contracts`)
   - **Bugs (all 5 verified on SBCL & CCL):**
     1. [defattach-bang.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/misc/defattach-bang.lisp#L16-L25): `defattach!-defun` omits `:stobjs` in `fn$GUARD-VERIFIED`, failing translation on any stobj-taking function.
     2. [defenum.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/std/util/defenum.lisp): `:member t` on string members fails guard verification in `:logic` mode (`DEFUN STR-ENUM-P`).
     3. [defenum.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/std/util/defenum.lisp): `:default :not-a-member` outside the enum fails `DEFTHM RETURN-TYPE-OF-BAD-DEFAULT-FIX`.
     4. [rewrite-dollar.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/tools/rewrite-dollar.lisp#L1346-L1350): `rewrite$-translate-hints` passes 13 arguments (extra leading `ctx`) to 12-arg `rewrite$-translate-hints-fn` (lines 955-959).
     5. [def-functional-instance.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/tools/def-functional-instance.lisp#L91): `(sublis alist body)` rewrites quoted constants (e.g. `'f-stub -> 'g-impl`), causing `DEFTHM NEW-THM` to fail.
   - **Reproducer:** [w4-kb-tools-macro-contracts/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-kb-tools-macro-contracts/run.sh)

---

## Additional Source-Confirmed & Debunked Kimi K3 Leads

| Book / File | Lead | Verdict | Notes |
|---|---|---|---|
| [with-supporters.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/tools/with-supporters.lisp#L665-L770) | `defattach-event-lst` checks only first fn; stray quote `'pe-table` at line 770 | **Source-Confirmed** | Line 770 `(member-eq name '(acl2-defaults-table xdoc 'pe-table))` checks `'PE-TABLE` as `(QUOTE PE-TABLE)`. |
| [prove-dollar.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/tools/prove-dollar.lisp#L70-L72) | `:skip-proofs` doc vs implementation inverted | **Source-Confirmed** | Lines 70-72 assign non-`:same` `:skip-proofs` directly to `ld-skip-proofsp`, opposite of XDOC lines 225-230. |
| [remove-hyps.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/tools/remove-hyps.lisp#L172-L230) | `make-defthm` emits `(declare (ignorable (mv x y)))`; mutates `our-steps` | **Source-Confirmed** | `strip-cars` over `b*` destructuring bindings produces invalid `ignorable` declarations. |
| [elide-event.lisp](file:///Users/ember/dev/acl2-fix/head-worktree/books/tools/elide-event.lisp#L26-L35) | `elide-defthm` scans flat `cdddr` with `member-eq` | **Carbon Extension** | Scans keyword values too, not just keyword keys. |
| [count-branches-fast.lsp](file:///Users/ember/dev/acl2-fix/head-worktree/books/centaur/aig/count-branches-fast.lsp) | `count-branches-to` `n=0` OOB | **Dead Code (`#+hons`)** | Wrapped in `#+hons`; inactive on modern ACL2 8.7+. |
| [fast-cat-raw.lsp](file:///Users/ember/dev/acl2-fix/head-worktree/books/std/strings/fast-cat-raw.lsp) | Non-simple strings reach `schar` | **False Positive** | ACL2's `bad-lisp-objectp` (`axioms.lisp:23328`) rejects displaced/adjustable/fill-pointer strings in pure ACL2. |
| [read-string-raw.lsp](file:///Users/ember/dev/acl2-fix/head-worktree/books/std/io/read-string-raw.lsp) | `*read-eval*` arbitrary eval | **False Positive** | `*acl2-readtable*` (`acl2.lisp:2264`, `acl2-fns.lisp:1384`) binds `#.` to `sharp-dot-read` (only `defconst` constants). |

---

## Recommended Upstream Fixes

1. **`centaur/aig/aig-vars-fast-raw.lsp`:** Use `equal`-based hashing/dedup (or `hons-copy` + `equal` check) in `aig-vars-unordered-list`, and ensure `aig-vars-fast` guards or handles cons/bad-atom variables safely without passing non-symbol/non-string bad-atoms into unsafe `bad-atom<=`.
2. **`centaur/misc/fast-cons-memo-raw.lsp`:** Save the old `*fast-cons-memo-array*` into `,restore-array` before replacing it, and restore `,restore-array` in both the normal and `unwind-protect` exit paths.
3. **`tools/oracle-timelimit.lisp` & `oracle-timelimit-raw.lsp`:** Check `(if ,suppress-lisp-errors ...)` at **runtime** (not macroexpansion time on the gensym); reject or immediately time out on `(<= ,limit 0)`; and either disallow `state` in `:ret` or thread `state` into `oracle-timelimit-exec` and return live `state` on timeout.
4. **`std/stobjs/2d-arr.lisp`:** Tighten `:guard` on `resize-rows`/`resize-cols`/`set2` to include the `(< ... (expt 2 60))` bounds, or avoid `(ec-call ...$g)` on a live stobj.
5. **`tools/plev-ccl-raw.lsp` & `tools/advise-raw.lsp`:** Validate `*print-length*` / `*print-level*` / etc. before `setq`; fix `ccl::*print-simple-bit-vector*` in `plev-info`; return the `eval` result in `advisedp$-fn` instead of `nil`.
6. **`std/util/bstar.lisp`:** Gensym the temp var in `b*-decomp-fn`, and bind a temp var for non-symbol RHS in `patbind-access`.
7. **`tools/stobj-frame.lisp`:** Change `(position 'n formals)` on line 316 to `(position 'v formals)`.
8. **`misc/defattach-bang.lisp`, `std/util/defenum.lisp`, `tools/rewrite-dollar.lisp`, `tools/def-functional-instance.lisp`:** Preserve `:stobjs` in `defattach!-defun`; reject non-symbol `:member t` / out-of-enum `:default` in `defenum`; remove the extra `ctx` argument in `rewrite$-translate-hints`; and replace `sublis` in `def-functional-instance` with a term/function-position-aware substitution that skips `quote` and bound variables.
