# CCL compiler-macro / optimizer audit — `compiler/optimizers.lisp`

Target: `~/dev/ccl/compiler/optimizers.lisp` (Clozure CL 1.14, `darwinarm64`, the Mac
checkout). Oracle: SBCL 2.6.10 (`/opt/homebrew/bin/sbcl`). CCL binary:
`/Users/ember/dev/ccl/darm64cl`.

All forms below were compiled THREE ways and compared (differential method, §Method):
`OPT` = `(speed 3)(safety 0)`, `SAFE` = `(speed 0)(safety 3)`, `NI` = same form with
the operator declared `notinline` (which suppresses the compiler-macro and so gives
CCL's own ground-truth runtime semantics), plus SBCL `OPT`/`NI` as the cross oracle.

## Summary of confirmed bugs

Every confirmed soundness divergence is **`(speed 3)(safety 0)`-only**: the `SAFE`
column, the `NI` column and SBCL all agree and are correct. Two distinct defects:

1. **Value COUNT too few — `truncate`/`floor`/`round`/`ceiling` unary on a fixnum
   return ONE value, must return TWO.** `optimizers.lisp:1397–1435`. The unary branch
   of each macro is `(if (not n1p) n0 …)`, i.e. `(truncate x)` → `x`, dropping the
   second value. **Same defect as the already-reported `ceiling` bug** — here confirmed
   for the whole family. Repro: `repros/ccl-opt-truncate-family-values/`.
   - Nuance: with a *constant* arg, `truncate`/`floor`/`round` are constant-folded
     instead (they appear in `CAN-CONSTANT-FOLD`, `optimizers.lisp:77`) and return the
     correct two values; `ceiling` is **not** in that list, which is why `(ceiling 7)`
     shows the bug even on a constant while `(truncate 7)` does not. A non-constant
     fixnum exposes all four.

2. **Value COUNT too many (values leak) — a rewrite to a bare operand / `(require-type
   x T)` / `(the T x)` forwards ALL of the operand's values**, where the function must
   return exactly one. This is the **same defect as CCL-3** (`identity` +
   `logand/logior/logxor` identity-element elimination), here found on **11 additional
   operators**. Repro: `repros/ccl-opt-require-type-values-leak/`. Mechanism: the
   `require-type` compiler-macro (`optimizers.lisp:999`) returns its `arg` *bare* when
   the type is already known, and `(the <non-values-type> form)` is equivalent to
   `(the (values type &rest t) form)` — so it passes every value through.
   Operators (all confirmed leaking the extra value, `OPT` only):

   | operator | optimizers.lisp | rewrites unary/identity call to |
   |---|---|---|
   | `+`  | :1369 | `(require-type n0 'number)` |
   | `*`  | :1385 | `(require-type n0 'number)` |
   | `=`  | :1343 | `(require-type n0 'number)` |
   | `/=` | :1350 | `(require-type n0 'number)` |
   | `<` `>` `<=` `>=` | :292 (`transform-real-n-ary-comparision`) | `(require-type n0 'real)` |
   | `max` | :1779 | `(require-type n0 'real)` |
   | `min` | :1805 | `(require-type n0 'real)` |
   | `nthcdr` (count 0) | :968 | `(require-type list 'list)` |
   | `ash` (count 0, known-integer operand) | :323 | `n0` (bare) |
   | `identity` | :584 | `form` (bare) — **CCL-3** |
   | `logior`/`logand`/`logxor` (identity elt / unary) | :1483 (`transform-logop`) | `(require-type n0 'integer)` — **CCL-3** |

Both defects are in shared, source-level optimizer code with no architecture-specific
form, so they are **architecture-independent**; verified on **arm64** here, and by
construction they reproduce on x86-64 (matching CCL-3's "both arm64 and x86-64").

Note on the comparison operators: `(= x)` etc. also returns the operand's numeric value
(e.g. `2`) rather than `T`. That is **not** a separate wrong-value bug — these return a
`generalized-boolean`, and `2` is a valid true value; the leak (value count) is the bug.

## Candidate inventory

`optimizers.lisp` has **195 `define-compiler-macro` forms**, **12 `defsynonym`s**, and a
handful of shared transform helpers (`transform-logop`, `transform-real-n-ary-comparision`,
`some-xx-transform`, `remove-if-transform`, `fold-constant-subforms`, `%binop-cassoc`,
`generic-to-fixnum-n`). Of these I identified the candidates matching the four audit
failure modes and counted them by category (a form can appear in more than one):

- **(i) reduces a call to one operand / `(require-type …)` / `(the …)`** — ~24:
  `identity`, `ash`, `nthcdr`, `+`, `-`, `*`, `/`, `=`, `/=`, `<`, `>`, `<=`, `>=`,
  `max`, `min`, `gcd`, `lcm`, `logand`, `logior`, `logxor` (via `transform-logop`),
  `require-type`, `progn`, `list*` (1-arg → `values`), `truncate`/`floor`/`round`/`ceiling`.
- **(ii) handles/produces multiple values** — **4**: `truncate`, `floor`, `round`,
  `ceiling`. (No `fround`/`ffloor`/`decode-float`/`integer-decode-float`/`gethash`/
  `get-properties` optimizer exists in this file — see Scope.)
- **(iii) constant-fold / strength-reduce arithmetic/bit ops** — ~15: the
  `CAN-CONSTANT-FOLD` set (`:70–82`: `+ * logior logand logxor ash expt gcd ldb dpb
  floor mod truncate rem round max min …`), `%binop-cassoc`, `generic-to-fixnum-n`,
  `dpb`, `ldb`, `mask-field`, `nth`, `1+`, `1-`.
- **(iv) identity elements / empty-singleton / coercions** — ~16: `transform-logop`
  (0/1/−1), `cons`, `list`, `list*`, `append`, `float`, `coerce`, `make-array`,
  `make-string`, `length`, `zerop`, `minusp`, `plusp`, `oddp`, `evenp`, `eql`/`equal`.

I probed ~40 distinct forms (58 probe instances). **16 forms confirm a soundness
divergence** (above); the rest are clean.

## Results

Legend: `mode` L = values-leak (too many), C = value-count too few, V = value, O =
eval-order/side-effect. Verdict: **BUG** (confirmed, with defect class), **clean**
(agrees across all variants + SBCL), **legit** (divergence that is implementation-defined
and excluded, with reason).

| form (probe) | optimizers.lisp | mode | CCL OPT | CCL SAFE | CCL NI | SBCL | verdict |
|---|---|---|---|---|---|---|---|
| `(identity (floor 23 10))` | :584 | L | `(2 3)` | `(2)` | `(2)` | `(2)` | **BUG = CCL-3** |
| `(+ (floor 23 10))` | :1369 | L | `(2 3)` | `(2)` | `(2)` | `(2)` | **BUG, defect=CCL-3** |
| `(* (floor 23 10))` | :1385 | L | `(2 3)` | `(2)` | `(2)` | `(2)` | **BUG, defect=CCL-3** |
| `(= (floor 23 10))` | :1343 | L | `(2 3)` | `(T)` | `(T)` | `(T)` | **BUG, defect=CCL-3** |
| `(/= (floor 23 10))` | :1350 | L | `(2 3)` | `(T)` | `(T)` | `(T)` | **BUG, defect=CCL-3** |
| `(< (floor 23 10))` | :292 | L | `(2 3)` | `(T)` | `(T)` | `(T)` | **BUG, defect=CCL-3** |
| `(> (floor 23 10))` | :292 | L | `(2 3)` | `(T)` | `(T)` | `(T)` | **BUG, defect=CCL-3** |
| `(<= (floor 23 10))` | :292 | L | `(2 3)` | `(T)` | `(T)` | `(T)` | **BUG, defect=CCL-3** |
| `(>= (floor 23 10))` | :292 | L | `(2 3)` | `(T)` | `(T)` | `(T)` | **BUG, defect=CCL-3** |
| `(max (floor 23 10))` | :1779 | L | `(2 3)` | `(2)` | `(2)` | `(2)` | **BUG, defect=CCL-3** |
| `(min (floor 23 10))` | :1805 | L | `(2 3)` | `(2)` | `(2)` | `(2)` | **BUG, defect=CCL-3** |
| `(logior 0 (floor 23 10))` | :1483 | L | `(2 3)` | `(2)` | `(2)` | `(2)` | **BUG = CCL-3** |
| `(logand -1 (floor 23 10))` | :1483 | L | `(2 3)` | `(2)` | `(2)` | `(2)` | **BUG = CCL-3** |
| `(logxor 0 (floor 23 10))` | :1483 | L | `(2 3)` | `(2)` | `(2)` | `(2)` | **BUG = CCL-3** |
| `(logior (floor 23 10))` | :1483 | L | `(2 3)` | `(2)` | `(2)` | `(2)` | **BUG = CCL-3** |
| `(nthcdr 0 (the list (values …)))` | :968 | L | `((1 2)(3 4))` | `((1 2))` | `((1 2))` | `((1 2))` | **BUG, defect=CCL-3** |
| `(ash (the integer (values 5 6)) 0)` | :323 | L | `(5 6)` | `(5)` | `(5)` | `(5)` | **BUG, defect=CCL-3** |
| `(truncate x)` x fixnum var | :1401 | C | `(7)` | `(7 0)` | `(7 0)` | `(7 0)` | **BUG = ceiling** |
| `(floor x)` x fixnum var | :1411 | C | `(7)` | `(7 0)` | `(7 0)` | `(7 0)` | **BUG = ceiling** |
| `(round x)` x fixnum var | :1421 | C | `(7)` | `(7 0)` | `(7 0)` | `(7 0)` | **BUG = ceiling** |
| `(ceiling x)` x fixnum var | :1431 | C | `(7)` | `(7 0)` | `(7 0)` | `(7 0)` | **BUG = ceiling** |
| `(ceiling 7)` constant | :1431 | C | `(7)` | `(7 0)` | `(7 0)` | `(7 0)` | **BUG = ceiling** |
| `(truncate 7)` constant | :1401 | C | `(7 0)` | `(7 0)` | `(7 0)` | `(7 0)` | clean (constant-folded :77) |
| `(floor 7)`/`(round 7)` const | :1411/:1421 | C | `(7 0)` | `(7 0)` | `(7 0)` | `(7 0)` | clean (constant-folded :77) |
| `(ash (floor 23 10) 0)` | :323 | L | `(2)` | `(2)` | `(2)` | `(2)` | clean (type not inferred ⇒ no bare path) |
| `(- (floor 23 10))` | :1377 | L | `(-2)` | `(-2)` | `(-2)` | `(-2)` | clean (`%negate`, a fn call) |
| `(/ (floor 24 10))` | :1393 | L | `(1/2)` | `(1/2)` | `(1/2)` | `(1/2)` | clean (`%quo-1`, a fn call) |
| `(gcd (floor 23 10))` | :1760 | L | `(2)` | `(2)` | `(2)` | `(2)` | clean (`%integer-abs`, a fn call) |
| `(list* (floor 23 10))` | :671 | L | `(2)` | `(2)` | `(2)` | `(2)` | clean (1-arg→`(values x)`, coerces) |
| `(nth 0/2 (list …))` | :956 | V | `(A)`/`(C)` | = | = | = | clean |
| `(ldb (byte 4 4) 171)` | :617 | V | `(10)` | = | = | `(10)` | clean |
| `(ldb (byte 8 0) -1)` | :617 | V | `(255)` | = | = | `(255)` | clean |
| `(dpb 0 (byte 4 4) 255)` | :563 | V | `(15)` | = | = | `(15)` | clean |
| `(mask-field (byte 4 4) 255)` | :641 | V | `(240)` | = | = | `(240)` | clean (macro inert: byte is a form) |
| `(list* 1 2 (list 3 4))` | :663 | V | `((1 2 3 4))` | = | = | = | clean |
| `(append (list 1 2)(list 3))` | :327 | V | `((1 2 3))` | = | = | = | clean |
| `(cons 1 (cons 2 nil))` | :517 | V | `((1 2))` | = | = | = | clean |
| `(gcd -12)`/`(lcm -12)` | :1760/:1769 | V | `(12)` | = | = | `(12)` | clean |
| `(expt 2 10)` | folded | V | `(1024)` | = | = | = | clean |
| `(ash 1 10)` | :320 | V | `(1024)` | = | = | = | clean |
| `(1+ 5)`/`(1- 5)` | :317/:314 | V | `(6)`/`(4)` | = | = | = | clean |
| `(eql 3 3)` | :574 | V | `(T)` | = | = | = | clean |
| `(zerop 0.0)` | :1334 | V | `(T)` | = | = | = | clean |
| `(char= #\a #\a #\a)` / `#\a #\b #\a` | :2275 | V/O | `(T)`/`(NIL)` | = | = | = | clean (all three operands eval'd) |
| `(< 1 2 3)` / `(< 1 3 2)` | :278 | V | `(T)`/`(NIL)` | = | = | = | clean |
| `(< (a)(b)(cc))` order | :287 | O | `(T (A B C))` | = | = | = | clean (left→right, all eval'd) |
| `(logand 0 (incf n))` | :1472 | O | `(0 1)` | = | = | `(0 1)` | clean (side effect preserved) |
| `(max (incf n)…(incf n))` | :1784 | O | `(5 2)` | = | = | `(5 2)` | clean (left→right) |

## Repros (confirmed bugs)

- `repros/ccl-opt-truncate-family-values/` — `repro.lisp` + `run.sh [ccl|sbcl]`.
  Value-count-too-few; all four of `truncate`/`floor`/`round`/`ceiling`.
- `repros/ccl-opt-require-type-values-leak/` — `repro.lisp` + `run.sh [ccl|sbcl]`.
  Values-leak across the 11-operator + CCL-3 set.

Each `repro.lisp` is self-contained (no ACL2), compiles each form freshly with `compile`,
prints the `OPT` result beside the `notinline` ground truth, and runs in a fresh process
under `timeout`/`nice`. Re-confirmed fresh on both hosts 2026-11-13.

## Method, equality and legitimacy rules

- **Equality rule.** Two results agree iff `multiple-value-list` of the form is `equal`.
  This makes the **value count** first-class (the signal that caught CCL-3 and the
  ceiling bug): `(7)` ≠ `(7 0)`, `(2 3)` ≠ `(2)`.
- **Oracle.** A CCL `OPT` result is a bug iff it differs from *both* CCL `NI` (same
  implementation, compiler-macro suppressed) *and* SBCL. Requiring the within-CCL
  `notinline` disagreement rules out "SBCL and CCL just differ"; the compiler-macro is
  provably the cause because removing it (notinline) removes the divergence.
- **Legitimacy exclusions (NOT bugs).** Float rounding / format differences; `eq`/`eql`
  of immediates; unspecified argument-evaluation order *when no operand has a side
  effect*; and a function specified to return a `generalized-boolean` returning a
  non-`T` true value (so `(= x) ⇒ 2` is excluded as a *value* complaint — but its value
  *count* leak is not). Build fresh conses/lists at call time so list identity never
  rides on constant coalescing. None of the confirmed bugs fall in these classes.

## Scope / what was NOT tested

- Only **arm64** was executed (this machine). x86-64 inferred from the shared, arch-free
  source, not run.
- No `fround`/`ffloor`/`decode-float`/`integer-decode-float`/`gethash`/`get-properties`
  compiler-macro exists in `optimizers.lisp`, so the multiple-values family here is just
  `truncate`/`floor`/`round`/`ceiling`; other MV functions (if optimized) live in the
  backend `nx`/vinsn files, not audited here.
- The large sequence/`format`/`make-array`/`coerce`/CLOS-dispatch macros
  (`find`/`position`/`remove-if`/`some`/`optimize-format-call`/`make-array`/`slot-value`
  …) were read and reasoned about but only lightly probed for value-count/leak; a
  deeper differential pass on their inlined loops (esp. `:key`/`:test` side-effect
  ordering and empty/one-element sequences) is the obvious next vein.
- `require-type` itself (`:994`) is the shared mechanism but is CCL-internal, so it is
  documented as the root, not filed as a separate user-facing bug.
