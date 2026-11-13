# Stale raw-Lisp state after undo: siblings of F13

Source: `/Users/ember/dev/acl2-fix/head-worktree/` (ACL2 8.7+, commit 1d2b39a4 images).
Hosts: SBCL `head-worktree/saved_acl2`, CCL 1.14 darwinarm64 `ccl-worktree/saved_acl2`.
Every test ran in a fresh session per host (`run.sh [ccl|sbcl]`), 2026-11-13.

## Mechanism

ACL2 undoes the raw-Lisp side of an event in exactly one way: `add-trip` calls
`maybe-push-undo-stack` (interface-raw.lisp:3529) before smashing a cell, and
`undo-trip` (interface-raw.lisp:7671) calls `maybe-pop-undo-stack`
(interface-raw.lisp:3731), which evaluates the saved form. The saved forms
restore symbol-function, macro-function, `*1*` function, symbol-value,
attachment, memoization and stobj-alist cells. Nothing on that path touches
host proclamations or the host's per-name compiler data. So:

1. **`proclaim-dfs` ftype** (interface-raw.lisp:6989-7034) is never retracted.
   When a name is later defined without a df signature, it only does
   `(remhash fn *proclaim-dfs-ht*)` (7032-7033) and leaves the proclamation.
   Called from `add-trip` for defuns (7234) and for defstobj raw accessors (7417).
2. **Inline expansions** of `*$inline` names (`defun-inline`, proclaimed inline at
   6629-6635) are recorded by the host when the `defun` is evaluated. Undo of a
   redefinition restores `symbol-function` with `setf` (3616) and does not restore
   the recorded inline expansion.

When a name was not fboundp before the event, the undo form is `fmakunbound!`
(3624-3627). Observed (consistent with every row below, not traced in SBCL source): on SBCL,
`fmakunbound` drops the proclaimed ftype, so SBCL is correct on every route that
ends in `fmakunbound`. CCL keeps the proclamation
either way. On routes that never `fmakunbound` the name (redefinition overwrite;
undo back to an earlier definition via `setf symbol-function`), SBCL is wrong too.

## Inventory (how enumerated)

`grep -n "(proclaim \|(declaim \|define-compiler-macro\|(setf (get \|(setf (gethash "`
over the top-level `*.lisp` sources, then reading every `cltl-command` case of
`add-trip` (7036-7669), `install-defs-for-add-trip` (6567-6786),
`maybe-push-undo-stack` and `undo-trip`. 14 kinds of raw state written by events:

| # | Raw state written by an event | Source | Retracted on undo? |
|---|---|---|---|
| 1 | `(proclaim '(ftype ... double-float ...))` from `proclaim-dfs`, defuns | interface-raw.lisp:7017-7031, called 7234 | **No.** `remhash` only on later non-df definition (7032) |
| 2 | same, defstobj/defabsstobj raw accessors of `:df` fields | 7417 | **No** (covered by `repros/stale-df-ftype-stobj/`, another lane) |
| 3 | `(proclaim '(inline f$inline))` + host inline expansion | 6629-6635 | Proclamation: no. Expansion: replaced by the next `defun`, **not** by the undo-stack `setf symbol-function` (3616) |
| 4 | `(proclaim '(notinline f$notinline))` | 6636-6642 | No; semantically harmless (notinline only) |
| 5 | `(proclaim '(notinline f))` for `:defproxy` functions | 6619-6627 | No; harmless (notinline) |
| 6 | `(proclaim '(notinline f))` for `ext-gen-barriers` (attachable stobjs) | 6749-6762 | No; harmless (notinline) |
| 7 | `make-defun-declare-form` ftype declaims | 6738-6742, 6771 | No, but non-nil only on GCL (not tested; no GCL image) |
| 8 | symbol-function / `*1*` / macro-function cells | 3589-3628 | Yes (undo stack) |
| 9 | `defconst` raw `defparameter` value + `redundant-raw-lisp-discriminator` | 7562-7577, 3629-3644 | Value: yes. The `special` proclamation stays, unreachable (ACL2 variables cannot be `*x*`) |
| 10 | defattach attachment symbols, `*defattach-fns*` | 7599-7623, 3662-3684 | Yes |
| 11 | memoize / unmemoize, `*memoize-info-ht*`, memo tables | 7624-7658, 3685-3725 | Yes; redefining a memoized function is refused |
| 12 | defstobj `*user-stobj-alist*`, `*current-stobj-gensym-ht*`, `:inline t` defabbrev macros | 7296-7462, 3645-3653 | Yes |
| 13 | defpkg packages | 7463-7467 | Never removed, by design (re-defpkg must match) |
| 14 | `(proclaim (list 'special key))` for `lock-table` | axioms.lisp:19716 | No; `#+acl2-par` only |

Not events / need a trust tag (not tested): `add-raw-arity` (books/hacking, ttag),
`set-raw-mode` / `progn!` raw code, `define-compiler-macro` (no event writes one;
only `acl2-fns.lisp:2566`, GCL boot), `*hcomp-*` tables (bound per
include-book/certify-book by `with-hcomp-ht-bindings`, not persistent),
`return-last-table` (a world table; the raw `return-last` macro reads the world).
`with-local-stobj` and `mbe` write no persistent raw state.

## Results

Expected value in every df/inline row: `2361183241434822606850` (= 2(1+2^70)) except
`inline-undo-restore` (expected `4`). "redef" = the user ran `(redef!)` (equivalently
`(set-ld-redefinition-action '(:warn! . :overwrite) state)`).

| Test (`siblings/stale-raw-state/...`) | State | Route | Redefinition needed? | SBCL gv / no-gv | CCL gv / no-gv | Verdict |
|---|---|---|---|---|---|---|
| `df-ftype-encapsulate-local` | 1 | `local` df defun in `encapsulate`, then plain `defun f` | **No** (no undo command either) | correct / correct | `1.0E-323` / correct | **wrong value, CCL** |
| `df-ftype-failed-progn` | 1 | df defun inside a `progn` whose later `defthm` fails | **No** | correct / correct | `1.0E-323` / correct | **wrong value, CCL** |
| `df-ftype-certify-local` | 1 | `certify-book` of a book with a `local` df defun, then `defun f` in the same session | **No** | correct / correct | `1.0E-323` / correct | **wrong value, CCL** |
| `df-ftype-include-book-u` | 1 | `include-book` of a certified book defining df `f`, `:u` | **No** | correct / correct | `1.0E-323` / correct | **wrong value, CCL** |
| `df-ftype-redef-overwrite` | 1 | df `f`, `(redef!)`, integer `f` (no undo) | Yes | **memory fault** (`Unhandled memory fault at #xFFFFFFFFFFFFFFFB`) | `1.0E-323` / correct | **crash SBCL, wrong value CCL** |
| `df-ftype-undo-restore` | 1 | integer `f`, `(redef!)`, df `f`, `:u` (back to integer `f`) | Yes (for the middle step; the undo itself is plain `:u`) | `1.0e-323` / correct | `1.0E-323` / correct | **wrong value, both hosts** |
| `inline-undo-restore` | 3 | `defun-inline f` (+1), `(redef!)`, `defun-inline f` (+2^70), `:u` | Yes (middle step) | `2361183241434822606850` / `4` | same | **wrong value, both hosts** |
| `no-defect/inline-plain-u` | 3 | `defun-inline`, `:u`, different arity and body | No | correct / correct | correct / correct | none |
| `no-defect/inline-encapsulate-local` | 3 | `local` `defun-inline` in `encapsulate`, other body at top | No | 4 / 4 | 4 / 4 | none |
| `no-defect/inline-then-macro` | 3 | `defun-inline`, `:u`, `f$inline` as a macro | No | 4 / 4 | 4 / 4 | none |
| `no-defect/type-decl-u` | 7 | `(unsigned-byte 8)` declared `f`, `:u`, bignum `f` | No | correct / correct | correct / correct | none (GCL path untested) |
| `no-defect/defconst-u` | 9 | `defconst`, `:u`, new value | No | correct | correct | none |
| `no-defect/defconst-encapsulate-local` | 9 | `local` defconst, then other value | No | correct | correct | none |
| `no-defect/defattach-u` | 10 | `defattach h h1`, `:u`, `defattach h h2` | No | 2^71 / 2^71 | same | none |
| `no-defect/defattach-u-none` | 10 | `defattach`, `:u`, call | No | both: no-attachment error | same | none (correct error) |
| `no-defect/memoize-ubt` | 11 | memoize + populate, `:ubt! f`, new `f`, memoize | No | correct | correct | none |
| `no-defect/memoize-redef` | 11 | memoized `f`, `(redef!)` | Yes | redefinition refused ("currently memoized") | same | none |
| `no-defect/memoize-undo-unmemoize` | 11 | memoize, unmemoize, `:u` | No | 4 / 4 | 4 / 4 | none |
| `no-defect/defstobj-field-type-inline` | 12 | `:inline t` `(unsigned-byte 8)` field, `:u`, `integer` field | No | 2^70+1 both | same | none |
| `no-defect/defstobj-field-type-noinline` | 12 | same without `:inline` | No | 2^70+1 both | same | none |
| `no-defect/defmacro-to-defun-u` | 8 | macro `f`, `:u`, function `f` | No | correct | correct | none |

## Notes for the fix

- Every route to state 1 is one bug: the proclamation outlives the definition.
  Four routes need neither undo commands nor redefinition on CCL
  (`encapsulate` + `local`, failed `progn`, `certify-book` with `local`, and
  `include-book` + `:u`). A retraction would have to run from the undo stack
  (push a form that proclaims `(ftype function f)` or the previous ftype) and also
  from the non-df branch of `proclaim-dfs` (7032), which today only `remhash`es.
- `df-ftype-redef-overwrite` and `df-ftype-undo-restore` show that SBCL is not
  immune; it is protected only when undo ends in `fmakunbound`.
- `inline-undo-restore`: undo of a redefinition of a `defun-inline` restores the
  old `symbol-function` but the host keeps the new inline expansion, so later
  guard-verified callers inline the undone body (`2^71+2` instead of `4`) on both
  hosts. Requires the user to enable redefinition for the redefining step; the
  undo is plain `:u`. Re-evaluating the saved `defun` instead of `setf
  symbol-function` for `*$inline` names would fix it.
