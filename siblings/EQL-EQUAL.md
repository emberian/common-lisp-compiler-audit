# The eql/equal defect class: raw code compares with a different equality than the logic

ACL2 commit `1d2b39a424` (Version 8.7), two images: SBCL 2.6.10
(`acl2-fix/head-worktree/saved_acl2`) and CCL 1.14 (`acl2-fix/ccl-worktree/saved_acl2`).
Run of 2026-11-13.

## The defect, stated as a class

Some ACL2 names are macros defined **only** under `#+acl2-loop-only`, expanding to a
logical `-fn` (`count` -> `count-fn`, `search` -> `search-fn`). In the logic the `-fn`
compares sequence elements with `EQUAL` (`count-listp`, `search-from-start`). In raw
Lisp the macro does not exist, so a compiled, guard-verified call is the Common Lisp
function of the same name, which compares with `EQL`. Because the `-fn`'s guard does
**not** restrict the compared item to `eqlablep`, a guard-verified function can be called
on an item that is `EQUAL` but not `EQL` to a list element, and the two definitions then
return different values. The item that separates the two is a freshly built cons or
string (structurally equal, not the same object), constructed at call time.

This is the same shape as the seed defect F14 (`count`). The sweep below confirms the
class has exactly two members among all ACL2 built-ins; the rest of the `eql`-defaulting
family is immune, for a reason worth recording (next section).

## Enumeration method and count

Three independent enumerations, intersected:

1. **Symbols defined only under `#+acl2-loop-only`.** Textual scan of `axioms.lisp`,
   `basis-a.lisp`, `basis-b.lisp`, `acl2-fns.lisp`, `apply-prim.lisp`, `other-events.lisp`,
   `translate.lisp` for a `defun`/`defmacro`/... immediately inside a `#+acl2-loop-only`
   reader form: **244 names** (`scratchpad/loop-only-defs.txt`). Of these, **148** are
   symbols in the `COMMON-LISP` package (asked of the live SBCL image), i.e. names that in
   raw Lisp resolve to a CL function/macro rather than ACL2 code.
2. **ACL2 names sharing a name with a CL function whose default `:test` is `eql`:** member,
   assoc, rassoc, position, remove, remove1, remove-duplicates, search, subsetp, union,
   intersection, set-difference, substitute, count, sublis, subst, add-to-set, intersectp,
   no-duplicatesp, put-assoc, remove-assoc, remove1-assoc, delete/adjoin (not ACL2 names).
3. **Macros dispatching on a `:test` keyword** (grep `(test ''eql)` / `(test ''equal)`):
   16 macros -- member, subsetp, assoc, no-duplicatesp, rassoc, remove, remove1,
   remove-duplicates, set-difference$, add-to-set, intersectp, position-ac, position,
   remove1-assoc, remove-assoc, put-assoc (plus `search` with `(test ''equal)`).

Each candidate was turned into a guard-verified `defun` whose guard is only `(true-listp l)`
or `(alistp l)` -- i.e. a guard that does **not** assert `eqlablep` of the compared values --
and ACL2 asked for its symbol-class:

| name | guard-verifies on an unconstrained guard? | why |
|---|---|---|
| **count** | **yes** (`:common-lisp-compliant`) | `count-fn` guard `(true-listp sequence)`; item unconstrained -> **sibling** |
| **search** | **yes** (`:common-lisp-compliant`) | `search-fn-guard` requires true-lists/strings, not eqlable elements -> **sibling** |
| member, position, remove, remove1, remove-duplicates, subsetp, add-to-set, intersectp, no-duplicatesp | no (`:not-admitted`) | default `:test 'eql` path is a `let-mbe` whose `:exec` (`member-eql-exec`, ...) guard is `eqlable-listp`; it refuses the aliasing input |
| assoc, rassoc, put-assoc, remove-assoc, remove1-assoc | no (`:not-admitted`) | same `mbe` + `eqlablep` guard on the key |
| sublis, subst | yes, but immune | guard forces `eqlable-alistp alist` / `eqlablep old`; the logic itself uses `eql`, so `eql` == `equal` on exactly the admitted inputs |

`:test 'equal` variants of the whole family route to the `-equal` function in both logic and
raw (or to `cl:member ... :test 'equal`), so they agree -- verified for member/assoc/rassoc/
position/subsetp/remove/remove-duplicates/remove1/add-to-set/intersectp/union$/intersection$/
set-difference$/no-duplicatesp/put-assoc/remove-assoc/remove1-assoc (all gv == nogv).

**The discriminator of the class:** `count` and `search` are the only built-ins that (a) are
macros present only under `#+acl2-loop-only`, expanding directly to a `-fn` with **no** `mbe`
`:exec` guard, and (b) whose `-fn` guard does not force the compared value to be `eqlablep`.
Every other `eql`-named macro protects itself with an `mbe` `:exec` guard of `eqlablep`/
`eqlable-listp` (which blocks the aliasing input at guard-verification time) or, for
`sublis`/`subst`, uses `eql` in the logic under an `eqlablep` guard (so no divergence exists).
**Count of confirmed siblings: 2** (`count`, the seed; `search`, new).

## Table of confirmed siblings

| function | raw source | logical equality | raw equality | SBCL gv / nogv | CCL gv / nogv | verdict |
|---|---|---|---|---|---|---|
| `count` | `cl:count` (macro absent in raw) | `equal` (`count-listp`) | `eql` | `0` / `1` (cons); `0` / `1` (string) | `0` / `1`; `0` / `1` | wrong value, both hosts |
| `search` | `cl:search` (macro absent in raw, so `(search x y)` reads as `cl:search` with its own `:test eql`) | `equal` (`search-from-start`) | `eql` | `NIL` / `1` (cons); `NIL` / `0` (string); `NIL` / `1` (from-end) | `NIL` / `1`; `NIL` / `0`; `NIL` / `1` | wrong value, both hosts |

Both reproduce a proof of `NIL` in the logic: the guard-verified function ground-evaluates
to the raw value (`0` / `NIL`) and is simultaneously provable equal to the logical value
(`1`) with its executable counterpart disabled; the two theorems `:use` each other to prove
`nil`. See each directory's `test.lsp` (`RESULT theorems admitted: evaluated T logical T nil T`).

Each sibling has a directory `siblings/eql-equal/<name>/` with `test.lsp` and `run.sh`
(`run.sh [ccl|sbcl]`).

## The sweep finding: why the primitive sweep missed this

`primitives/sweep.lisp` evaluated 1132 **functions** on a 30-object universe and reported 0
mismatches. The guess in the brief was that the universe never held two objects that are
`equal` but not `eq`. That guess is **only half the story**, and the sweep proves it:

`primitives/sweep-aliased.lisp` (copy; original untouched) adds 9 objects to the universe that
are `EQUAL` but never `EQ` to an object already there -- fresh `"abc"`/`""`, fresh `(1 2 3)`,
fresh dotted and alist conses, and containers holding them (universe 30 -> 39, 34 distinct).
It restricts the sweep to the **783** functions whose logical body reaches `EQUAL` or `EQL`
(closure of `body` over `all-fnnames`), and adds one positive control, `PSW-CTL-POS-ALIAS`,
whose raw definition uses `EQL` where its logic uses `EQUAL`. Run by `run-aliased.sh` into
`primitives/results-aliased/`.

- **The aliasing control fires:** `PSW-CTL-POS-ALIAS` records **30 value mismatches** on each
  image (routes `:none`, `:t`, `:raw`). So the universe now does contain `equal`-not-`eq`
  pairs and the harness detects an `eql`/`equal` divergence when a swept **function** has one.
- **Still zero real mismatches.** SBCL: 788 rows (783 functions + 5 controls), `0` non-control
  `:mismatch` (777 OK, 6 PARTIAL from pre-existing timeouts -- all `:act-timeout`/`:log-err`/
  `:sub-guard`, none a value mismatch). CCL: identical -- 788 rows, 779 OK, 4 PARTIAL
  (`STRING-PREFIXP-1`, `CONS-SUBTREES`, `FAST-ALIST-FORK`, `FAST-ALIST-FORK!`), `0` non-control
  `:mismatch`, `PSW-CTL-POS-ALIAS` fires 30x. Both hosts agree.

**The real reason the sweep missed `count`:** `count` and `search` diverge in the **macro**
layer, not the function layer. `count-fn` and `search-fn` are swept, and each uses `EQUAL`
in its logic; `search-fn`'s raw body, when the sweep calls it with an explicit `test = equal`
argument, runs `cl:search :test #'equal`, which also compares with `equal` -- so as functions
they agree, correctly. The divergence only appears for the **macros** `count` / `search`:
inside the loop a form `(count i l)` is the macro, expanding to the `-fn`; in raw Lisp the
macro does not exist, so the guard-verified compiled code reads `(count i l)` as the bare
`cl:count` with its own `eql` default (and `(search x y)` as `cl:search`, `eql`). The
sweep enumerates only symbols with a `formals` property (functions); it never expands a
macro, so no amount of universe enrichment could have surfaced this. Enriching the universe
was necessary to be sure the function layer is clean, and it now is -- but the defect lives a
layer above, in the `#+acl2-loop-only` macro/raw split.

## Files

- `siblings/eql-equal/count/` -- self-contained reproducer for the seed defect.
- `siblings/eql-equal/search/` -- new sibling.
- `primitives/sweep-aliased.lisp`, `primitives/run-aliased.sh` -- aliased sweep (copies).
- `primitives/results-aliased/{sbcl,ccl}/` -- its output.
