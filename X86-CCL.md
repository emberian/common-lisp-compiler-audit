# Clozure CL (CCL) findings — linux x86-64

Differential consistency audit of **Clozure CL 1.14 on x86-64 Linux**, the counterpart
to the arm64 findings in `CCL.md`. CCL's x86-64 backend is a separate code generator
from arm64 and had not been exercised by this project.

- CCL build: `Clozure Common Lisp Version 1.14 (v1.14) linuxx8664`
  (asset `ccl-1.14-linuxx86.tar.gz`, kernel `lx86cl64`)
- Host: hbox (Intel i9-12900, Ubuntu 24.04, kernel 6.11), 4 KB pages, 61-bit fixnums
  (`most-positive-fixnum = 1152921504606846975 = 2^60 - 1`, same as arm64).
- Oracle: SBCL 2.6.8 x86-64 on the same host, running byte-identical generated forms.

## Summary

| item | result on x86-64 |
|------|------------------|
| **CCL-2** (`ash` near 2^60 returns malformed integer) | **does NOT reproduce — arm64-only** |
| **CCL-1** (saved-image inline-store hang)             | **does NOT reproduce — arm64-only** |
| **NEW — CCL-3**: identity-element / `identity` folding leaks an operand's extra values into a single-value context | **reproduces (soundness) — BOTH arm64 and x86-64** |

Both previously-reported CCL bugs are confirmed **specific to the Apple-Silicon
(darwin arm64) backend**; neither occurs on the x86-64 code generator. One new
soundness bug (multiple-values) was found and minimized; it lives in **shared**
compiler code and reproduces on **both** arm64 and x86-64 CCL 1.14, so it is logged
here as **CCL-3** and belongs in `CCL.md` as well.

---

## CCL-2 re-test — arm64-only (does NOT reproduce)

On arm64, `(integer-length (ash 1 (1- (expt 2 60))))` returns a negative (malformed)
integer. On x86-64 CCL 1.14, the same form **signals correctly** — it never produces a
value, so `integer-length` is never applied to garbage:

```
k = 2^60 - 1  (1152921504606846975): STORAGE-CONDITION  (SIMPLE-STORAGE-CONDITION:
                                      "Memory allocation request failed")
k = 2^60      :                       SIMPLE-ERROR
k = 2^60 + 1  :                       SIMPLE-ERROR
k = 2^60 - 2  :                       STORAGE-CONDITION
k = 2^61 - 1  :                       SIMPLE-ERROR
```

Running the repo's own `derived-types/repros/ccl-ash-near-fixnum-limit/plain-ccl.lisp`
unmodified on x86-64 CCL, form 1 raises `SIMPLE-STORAGE-CONDITION: Memory allocation
request failed` — the correct behaviour (SBCL signals likewise). This matches the
repro's own root-cause note: the arm64 bug is that `%ASH-LEFT` adds `(integer-length
int)` to the count in **fixnum** arithmetic and the sum wraps negative, bypassing the
"needs a bignum" size check; the x86-64 path performs the size check correctly and
refuses the (≈144 PB) allocation instead of wrapping.

Reproducer: `repros/ccl-x86-differential/ccl2-retest.txt` (transcript); re-run with the
existing `derived-types/repros/ccl-ash-near-fixnum-limit/plain-ccl.lisp`.

## CCL-1 re-test — arm64-only (does NOT reproduce)

The arm64 bug is a livelock: in a `save-application` image, an inline store into a
purified ivector that shares a 16 KB page with the storing code spins forever, because
Apple Silicon's W^X fault handler flip-flops the page's permissions at one PC. x86-64
Linux has no W^X page restriction, and the structural precondition does not even arise.

Test (`repros/ccl-x86-differential/ccl1-{build,test}.lisp`): build a `save-application`
image (`:purify t`) holding specialized vectors created *before* the save, bracketing
compiled inline store/read functions; restart and sweep **every** element of each
vector with the inlined store, then read every element back.

- Element types swept: `(unsigned-byte 8)`, `bit`, `(unsigned-byte 32)`,
  `(unsigned-byte 64)`, `(signed-byte 8)`, `single-float`, `double-float`
  (~1.5M elements total).
- Result: **no hang; zero read-back mismatches** on any type.
- The pre-save vectors are genuinely **purified** — they sit in a low static region
  (~`0x30000xxxxxxx`), are immovable across `(gc)`, and remain writable; fresh
  post-restart allocations land at `~0x30200xxxxxxx`.
- Code vectors land in a **separate region** from ivector data: the storing code's page
  never equals any element's page (`shares-code-page=NIL` for every type), so the
  arm64 same-page precondition cannot occur. (Writes into the purified vectors succeed;
  the page is writable, as expected without W^X.)

---

## NEW — CCL-3: `logior`/`logand`/`logxor` identity-element elimination and `identity` leak an operand's extra values (soundness; both arches)

### Symptom
When a compiler macro rewrites a form to one of its subforms, CCL forwards **all** of
that subform's values instead of coercing to the single value the context requires. The
affected rewrites are the bitwise identity-element eliminations (`(logior 0 x)`→`x`,
`(logand -1 x)`→`x`, `(logxor 0 x)`→`x`) and `(identity x)`→`x`. If the subform is
multiple-valued — `(round a b)`, `(truncate a b)`, `(values …)`, `(gethash …)`, a user
`values` function — its secondary values leak out of a single-value context.

```lisp
(defun f (x) (declare (integer x) (optimize (speed 3) (safety 0)))
  (logior 0 (round x 10)))        ; logior is single-valued: f MUST return exactly 1 value

(multiple-value-list (f 37))
;; CCL 1.14  (speed 3)(safety 0) => (4 -3)   ** wrong: 2 values; -3 is round's remainder
;; CCL 1.14  (speed 0)(safety 3) => (4)         correct
;; SBCL 2.6.8 (both policies)     => (4)         correct
```

Minimal, operand need not be a division — a bare `(values …)` leaks, proving the defect
is in the rewrite, not in `round`:

```lisp
(logior 0 (values 5 6))   ; CCL => 2 values (5 6);  SBCL => 1 value (5)
(logand -1 (values 5 6))  ; CCL => 2 values;        SBCL => 1
(logxor 0 (values 5 6))   ; CCL => 2 values;        SBCL => 1
(identity (values 5 6))   ; CCL => 2 values;        SBCL => 1
;; correct (coerce to one value) in CCL too:  (+ 0 (values 5 6)) => (5),  (* 1 (values 5 6)) => (5)
```

Observable wrong behavior in a conforming consumer:
`(multiple-value-call #'list (logior 0 (round 37 10)))` → CCL `(4 -3)`, correct `(4)`.

### Reproduces on BOTH arm64 and x86-64 (CCL 1.14)
- x86-64 (`lx86cl64`, this lane): values above; witness `repros/ccl-x86-differential/repro-mv.lisp`.
- arm64 (`darm64cl`, confirmed on the Mac), `(logior 0 (round x 10))` `(speed 3)(safety 0)`:
  `x=37 => (4 -3)`, `x=-17 => (-2 3)`, `x=100 => (10 0)`, `x=3 => (0 3)` — two values;
  `(safety 3)` and SBCL (both arches) give one value.

So it is **not** backend-specific: it is a general CCL compiler bug in shared optimizer
code. Logged as **CCL-3**.

### Root cause (read from `compiler/optimizers.lisp` in the shipped 1.14 source)
- `(define-compiler-macro identity (form) form)` — **line 584** — rewrites `(identity x)`
  to `x` verbatim, discarding the single-value coercion a function call implies.
- `transform-logop` — **line 1468**, driving the `logand`/`logior`/`logxor` compiler
  macros (**lines 1486 / 1490 / 1494**) — eliminates an identity-element argument:
  `(logior 0 x)` → `(logior x)`, and the single-argument case → `(require-type x 'integer)`.
  CCL's `require-type` returns **all** values of its first argument — confirmed:
  `(require-type (values 5 6) 'integer)` ⇒ 2 values — so the operand's extras propagate.
  Neither rewrite wraps the result to force one value (e.g. `(values (require-type …))`).

### Distinct from the already-reported unary `truncate/floor/round/ceiling` bug?
**Yes — a sibling, not the same entry.** Same *class* (a compiler macro that rewrites a
form to a subform without preserving the value count), but opposite direction and a
different source site:
- Reported bug (unary): the `(not n1p)` branch of the truncate/floor/round/ceiling
  compiler macros (**optimizers.lisp:1397–1437**) rewrites `(round n0)` [n0 fixnum] →
  `n0`, so a 2-valued operation returns **too FEW** values (1 instead of 2).
- CCL-3 (this bug): identity-element elimination in `transform-logop` (1468) and
  `identity` (584) return **too MANY** values (the operand's extras leak). The binary
  `round`/`truncate` compiler macro is **not** the culprit — in `(logior 0 (round x 10))`
  with `x : integer`, that macro returns the form unchanged and the leak is entirely the
  `logior`-fold.

### Classification
**Soundness (wrong number of return values).** A total, conforming CL expression that
must yield exactly one value yields two; a program that inspects the value count or
threads the result through `multiple-value-call` / `nth-value` / `multiple-value-list`
observes a wrong result. `(logior 0 x)` leaks only under optimization (opt-vs-unopt
divergence); `(identity x)` leaks under every policy including `(safety 3)`. SBCL is
correct in every case.

Reproducer: `repros/ccl-x86-differential/repro-mv.lisp` (self-checking; exits 1 on CCL,
0 on SBCL), plus `minimal.lisp` / `minimal2.lisp` (wrapper and policy characterization).

---

## Fuzzing — volume and method

Two deterministic differential passes. A custom 64-bit LCG (never `cl:random`) drives
generation, so CCL and SBCL run **byte-identical** form+input streams for a given seed
and outputs are line-comparable. Each generated function is compiled twice — once
`(speed 3)(safety 0)`, once `(speed 0)(safety 3)` — and applied to 6 input rows; the
serialization of all return values is compared four ways: CCL-safe vs SBCL-safe,
CCL-fast vs SBCL-fast (cross-implementation oracle), and CCL-safe vs CCL-fast,
SBCL-safe vs SBCL-fast (opt-vs-unopt). 24 cores, several `lx86cl64`/SBCL workers each
with a PID file, each worker resumable past a crash/hang (none occurred).

**Equality rule.** Integers/ratios/characters/strings/lists/vectors/structs: exact.
Floats: exact IEEE bits via `integer-decode-float` (sign·significand·exponent); a row
tainted by a non-finite (overflow/inf/nan) is skipped (float trap policy differs
between the implementations and is not a soundness question); `+0.0` and `-0.0` are
treated as equal (numerically equal, sign-of-zero from an operation is
implementation-defined).

### Pass A — arithmetic (2,000,000 seeds × 6 rows = 12M evaluations/impl)
Covered: fixnum/bignum arithmetic, `logand/logior/logxor/lognot/ash/ldb/dpb/mask-field/
logcount/integer-length`, `truncate/floor/ceiling/round/mod/rem` with constant and
variable divisors, single/double floats, comparisons into branches, correct and
boundary-tight `the`, `multiple-value-bind`, characters, specialized arrays + `aref`.
No crashes/hangs. **Finding: CCL-3** (above) surfaced here as CCL-fast returning an extra
value vs CCL-safe and vs SBCL (the generator emits `(logior … (round a b))`-shaped
forms). All other cross/opt differences were benign: single-float overflow trap policy
(CCL signals `FLOATING-POINT-OVERFLOW` on out-of-range `(float <bignum> single)` where
SBCL returns infinity), signed-zero in `max`, and a handful of forms SBCL rejects at
compile time (type error) that CCL compiles and runs.

### Pass B — targeted sweep (500,000 seeds × 6 rows = 3M evaluations/impl)
Per the steer that arithmetic is low-yield and the confirmed bugs were in
multiple-values/codegen, this pass weights: **multiple values**
(`floor/truncate/ceiling/round`, single-arg float `truncate/floor/round`,
`ftruncate/ffloor/fround`, `decode-float`, `integer-decode-float`, `values`,
`get-properties`, `gethash`, user mv functions) through the consumers
`multiple-value-list`, `nth-value`, `multiple-value-bind`, `multiple-value-call`,
`multiple-value-prog1`; **type dispatch** (`typecase`/`etypecase`/`typep`);
**sequence/string/character** ops; **struct and (multidim/specialized/bit) array**
access; and **control flow** (`block`/`return-from`, `catch`/`throw`, `tagbody`/`go`,
`loop`, `labels` recursion, `unwind-protect`). No crashes/hangs.
**Finding: no new bug.** `WITHIN CCL (safe vs fast)` = **0** — no opt-vs-unopt divergence
in any of these areas. Every CCL-vs-SBCL difference reduced to implementation-defined
behavior: `integer-decode-float`/`decode-float` of **zero** (CCL exponent `-1074`, SBCL
`0`, then summed through `multiple-value-call #'+`), signed-zero from `ftruncate`, and
`SIMPLE-ERROR` vs `TYPE-ERROR` condition class on inputs both implementations reject.
(Two `WITHIN CCL` hits were a harness artifact — a result string from `(coerce (list ch
…) 'string)` containing a literal `#\Tab` collided with the TSV field separator; CCL and
SBCL were byte-identical at both policies.) `multiple-value-call` consumers did **not**
surface a fresh CCL-3-style leak beyond what Pass A already showed.

## Honest negatives / implementation-defined (not bugs)
- `(float <huge-bignum> 1.0f0)` out of single-float range: CCL signals
  `FLOATING-POINT-OVERFLOW`, SBCL returns infinity. Trap/representation policy.
- `(max +0.0 -0.0)`: CCL returns `+0.0` at safety 3, `-0.0` at speed 3; both
  spec-conformant (`max` of equal values may return either); numerically equal.
- `integer-decode-float`/`decode-float` of `0.0`: CCL reports exponent `-1074`, SBCL
  `0`; the exponent/significand-sign of zero is implementation-defined.
- Error condition class on rejected inputs (`SIMPLE-ERROR` vs `TYPE-ERROR`).

## What was not done
- No ACL2 image on CCL x86-64 was built (heavy, disk-tight); the plain-CL reproducer
  for X86-1 is sufficient to file against Clozure.
- arm64 relevance of X86-1 not verified here (no Apple-Silicon host on hbox) — see the
  one-line check above.
