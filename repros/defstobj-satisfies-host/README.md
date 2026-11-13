# SATISFIES predicates and type specifiers handed to the host

ACL2 `6c0f3448f6` (head-worktree), SBCL 2.6.10, CCL 1.14 darwinarm64 at `23c9edcf`.
`./run.sh` runs the three findings on both hosts; `./run.sh all` adds every file in `cases/`.
`./run-case.sh NAME.lisp` runs one case and diffs the marker lines.

## Root cause of F4

ACL2 never asks the host to test the value. It only writes the user's type specifier
into raw code, and CCL's type-specifier parser calls the predicate.

- ACL2 side: `defstobj-raw-init-fields` (`basis-a.lisp:9166`) emits
  `(make-stobj-scalar-field (or null (satisfies p)) 'nil)`, which expands
  (`basis-a.lisp:8534`) to `(the (or null (satisfies p)) 'nil)`. The same specifier
  goes into `(declare (type ...))` and `(the ...)` in the raw accessor and updater
  (`basis-a.lisp:9063-9076`) and into `make-array :element-type` (`basis-a.lisp:9142`).
  Both hosts run at safety 0 and neither checks the value at run time.
- CCL side: parsing `(or null (satisfies p))` builds a union of the member type `{NIL}`
  and a hairy type. `type-union2` (`level-1/l1-typesys.lisp:1204`) asks `csubtypep`,
  which reaches `ctypep` (`l1-typesys.lisp:3635`); its `satisfies` branch
  (`l1-typesys.lisp:3679-3686`) does `(ignore-errors (funcall fun obj))` on each
  member constant. The `(member :complex-intersection)` method (`l1-typesys.lisp:3021`)
  does the same. So `P` is called on `NIL`, several times, while the event is being
  compiled, whatever the field's value is. ACL2's raw definition of a `defstub` exits
  with a `throw`, which `ignore-errors` does not catch, so the event fails.
- SBCL side: `ctypep` (`src/code/typep.lisp:326-335`) only calls a `satisfies`
  predicate when `sb-c::constant-function-call-p` (`src/compiler/constantp.lisp:74`)
  says it is a known foldable function. A user function is never called.

ACL2's own story predicts SBCL's behaviour. `chk-stobj-field-type-term`
(`other-events.lisp:19686`) evaluates the translated guard
`(or (eq x nil) (p x))` on the initial value left to right, never reaches `(p nil)`,
and accepts the event. Nothing in the logical admission evaluates `P`.

Only constants that are not numbers become CCL member types, so the predicate is
called on `NIL` (from `null`, `list`, `symbol` unions) and on symbols and characters
in `(member ...)`; numbers in `(member ...)` are parsed as numeric ranges and are
not passed to the predicate.

## Findings

| # | class | hosts | reproducer |
|---|---|---|---|
| 1 | robustness (admission) | CCL rejects, SBCL admits | `cases/c01-stub-scalar.lisp` and c02, c03, c04, c07, c09, c13, c19, c21 |
| 2 | soundness, `NIL` proved and certified | CCL only | `stale-type-cache/nil-via-local.lisp`, `stale-type-cache/nil-book.lisp` |
| 3 | soundness, `NIL` proved | both hosts | `string-stobj/string-stobj.lisp` |

### 2. Stale CCL type cache (soundness on CCL)

CCL caches parsed specifiers by `equal` on the specifier (`l1-typesys.lisp:1480-1530`),
and a type simplified by calling the predicate is cacheable (`cacheable-ctype-p`,
`l1-typesys.lisp:1437`). With `p = integerp`, `(and (or null (integer 0 1)) (satisfies p))`
is cached as `(and (satisfies p) bit)`, because `(p nil)` was false at that moment.
If `p` is later a different function that accepts `NIL`, the cached entry is wrong.
`make-array :element-type SPEC` hits the cache and makes a bit vector; the accessor's
`(the (simple-array SPEC (*)) fld)` parses the element type again without the cache,
gets a type that includes `NIL`, and is compiled as a general vector access. The
accessor then reads the bit vector's data words as Lisp pointers.

No undo, trust tag or redefinition is needed: `p` is first defined `local`ly in an
`encapsulate` (a type declaration naming it is compiled there), then defined
differently at top level. `(g)` reads `(equal (ari 0 st) 1)` from a fresh local stobj
whose array is `:initially 1`, and returns `NIL`. `g-is-t` is proved by rewriting,
`g-is-nil` by `(:e g)`, and `contradiction` is `NIL`. `certify-book` accepts
`nil-book.lisp` on CCL. SBCL returns `T` and rejects `g-is-nil`. Plain-CCL version
of the stale entry: `(defun p (x) (integerp x))`, parse the specifier, redefine `p`,
and `upgraded-array-element-type` still answers `BIT`.

With a single-field stobj the same staleness gives a raw Lisp error instead
(`cases/c20-stale-cache-array.lisp`, `NIL doesn't match array element type of #*0000`).

### 3. Single-field stobj that is a string (soundness on both hosts)

Not a host divergence; found while trying array element types. `single-field-type-p`
(`basis-a.lisp:8594`) uses `maybe-contained-in-character` (`basis-a.lisp:8548`) to
decide whether a one-array stobj may be the bare array. For
`(or character (and integer symbol))` it answers no, because it does not see that
`(and integer symbol)` is empty. Both hosts do, upgrade the element type to
`character`, and the live stobj is a string, which `live-stobjp` treats as not live.
`(s8p s8)` is `NIL` at top level, a guard-verified `(h)` returning `(s8p s8)` of a
local stobj is `NIL`, and `NIL` is proved on SBCL and on CCL.

## Cases tried

"calls" = the predicate printed `CALLED` during the event or run.

| case | what | SBCL-hosted | CCL-hosted |
|---|---|---|---|
| c01 | `defstub p`; scalar field `(or null (satisfies p))`, `:initially nil` | admitted | rejected, `cannot ev ... P` |
| c02 | same type in a `defun` type declaration | admitted | rejected |
| c03 | same type in `the` | admitted | rejected |
| c04 | same type in a `let` type declaration | admitted | rejected |
| c19 | same type as array element type; as hash-table value type | both admitted | array rejected, hash table admitted |
| c21 | `defun-nx` predicate in a type declaration, guards not verified | admitted | rejected |
| c07 | guard-verified predicate that calls `hard-error` on `NIL` | admitted | rejected, `HARD ACL2 ERROR in PH` |
| c13 | predicate using `time-tracker` | admitted | rejected (repeated calls make `time-tracker` illegal) |
| c09 | program-mode predicate with `er hard`, in a program-mode `defun` | admitted | rejected |
| c10 | `defstub p` with `defattach`, in a `defun` type declaration | admitted, 0 calls | admitted, attachment called 8 times at compile time (c02 without the attachment is rejected) |
| c12 | predicate that computes `(fib 36)` on `NIL` | `defun` 0.00 s | `defun` 0.93 s |
| c05 | printing predicate, scalar field; updater, accessor, recognizer at guard-checking `t`, `:all`, `nil`, `:none`, good and bad values | 0 extra calls | 32 extra calls on `NIL`; all values and errors equal |
| c06 | printing predicate, resizable array field, update, resize, bad value | same | 66 extra calls; values equal |
| c14 | `defabsstobj` over such a foundation | same | 32 extra calls; values equal |
| c15 | child stobj field and array of child stobjs, `stobj-let` | same | 32 extra calls; values equal |
| c18 | nine orderings of `or`/`and`/`not`/`null`/`list`/`symbol`/`atom` with the predicate; `member` with symbol, character, number | same admissions | extra calls on `NIL`, `:A`, `#\b`, never on `7`; values equal |
| c08 | `defconst` with `the` and a `let` declaration | same | same |
| c11 | memoized predicate | same | same |
| c16 | reverse direction: unreachable `(the (integer 0 5) 7)`, empty types `(integer 5 3)`, `(and integer symbol)`, `(satisfies keywordp)`, `(satisfies symbolp)` | same | same |
| c17 | program-mode caller storing a bad value at guard-checking `nil` and `:none` | guard error | same |
| c22 | array element types whose upgrade differs by host: `member`, `(or null bit)`, ratio, mixed | same values | same values |
| c20 | stale cache, single-field array stobj | `(g)` = `NIL`, correct | raw Lisp error |

Nothing was found that CCL admits and SBCL rejects. No wrong value was found from
the extra calls themselves: at run time neither host tests the declared types, and
CCL does not fold `integerp`, `symbolp`, `null` and 14 other predicates on a declared
type (SBCL does, but SBCL's declared types are never computed by calling the predicate).

No `:DOC` text was found that covers any of this, so nothing is classified as documented.

## Not tried

- A program-mode predicate that does not terminate on `NIL` (expected: CCL hangs in `defun`; c12 only shows the cost).
- `include-book` of a certified book on CCL: whether the predicate is called again at load time, and finding 2 across two books instead of `local`.
- Finding 2 with `defattach` instead of `local` (c10 shows the attachment is consulted at compile time; stobj field types refuse attached predicates, `defun` declarations do not).
- Eviction from the 4096-entry type cache as another way to make two uses of one specifier disagree.
- Other specifiers that fool `maybe-contained-in-character` (`(or character (integer 5 3))` was admitted and fails its guard the same way; no proof was attempted).
- `check-dcl-guardian` directly, `:stobj-table` fields, `:non-executable` stobjs, `defstobj :congruent-to`, GCL, Allegro and LispWorks.
- Whether ACL2 and CL agree on every non-`satisfies` specifier (`real`, `ratio`, `(complex rational)`, `standard-char`, `(string n)`).
