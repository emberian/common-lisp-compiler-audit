# SBCL x86-64 wrong value: variable-shift modular ASH in a multi-element (unsigned-byte 64) array

**Classification: soundness** (wrong value at `(speed 3)(safety 0)`; no error, no
undefined behaviour). Found by the non-integer differential fuzzer (`fuzz-nonint.lisp`).

## What

`repro.lisp` defines the same body under two policies. The body builds a
`(simple-array (unsigned-byte 64) (3))` whose three elements are modular
(`(logand … #xFFFFFFFFFFFFFFFF)`) expressions — the middle one a **variable-shift**
`(ash v1 (- (logand v0 63) 20))` — then reads back **only** element 1.

```
(buggy   64 9223372036854775807)  ; (speed 3)(safety 0) => 0            WRONG
(correct 64 9223372036854775807)  ; (speed 0)(safety 3) => 8796093022207
```
`8796093022207 = (logand (ash (1- (expt 2 63)) -20) (1- (expt 2 64)))` is the
correct value (shift = `(- (logand 64 63) 20) = -20`).

## Where it reproduces

| SBCL | arch | result |
|---|---|---|
| 2.6.8 | x86-64 | **WRONG (0)** |
| 2.2.9 | x86-64 | correct |
| 2.6.10 | arm64 | correct |

x86-64 SBCL 2.6.10 / current was not available on the test host; **check it
before reporting upstream** — the bug may be fixed after 2.6.8 or may be
x86-64-specific. Neither ACL2 image used in this audit is affected (hbox ACL2
embeds SBCL 2.2.9; the Mac ACL2 is SBCL 2.6.10 arm64), so no proof of `nil`
arises in the current setup; this is a latent host-compiler hazard for an ACL2
built on the affected SBCL.

## Essential conditions (each confirmed by reduction)

- The array needs **>= 3 elements**, each a modular expression (2 elements, or
  siblings that are literal `0`, do not trigger it).
- The read element's `ash` shift must be **variable** (a constant shift is correct).
- **Only that one element** is read; reading all three elements is correct —
  so dead-store elimination of the unused sibling stores is implicated.
- `(logand … 2^64-1)` or the equivalent `(ldb (byte 64 0) …)` both trigger it;
  the `(simple-array …)` type declaration is not required.

Likely area: the modular-arithmetic transform of `ASH` (mod-2^64) interacting
with elimination of the unread `(unsigned-byte 64)` array initial-contents stores.


## Persistence across SBCL versions

Checked 2026-11-13 on hbox (x86-64 Linux, i9-12900) against the official SBCL
binary releases plus a source bisect. The 2.2.9 and 2.6.8 rows re-confirm the
original finding with the same harness (`repro.lisp`, VERDICT line).

| SBCL | arch | result |
|---|---|---|
| 2.2.9 | x86-64 | correct |
| 2.6.8 | x86-64 | **WRONG (0)** |
| 2.6.9 | x86-64 | correct |
| **2.6.10 (current release)** | x86-64 | **correct** |

**Current-SBCL verdict: CORRECT on 2.6.10 x86-64** (the latest SBCL release as
of 2026-11-13). The repro no longer diverges, so there is nothing to report to
sbcl-devel *as written*.

### Fix window (bisect)

`git bisect` over the 290 commits in `sbcl-2.6.8..sbcl-2.6.9`, building each
candidate with a 2.2.9 host and classifying by the repro's VERDICT line, pins
the transition to a single commit:

- last BUGGY: `d1b2b076bc95d36d046bd8cadcecc7506e4204bc`
- first FIXED: **`e938a68479153d11479ff77071e88e08768dfb0f`** — Stas Boukarev,
  2026-08-30, *"(aref (vector a) 0) => a"*, `src/compiler/generic/vm-tran.lisp`.

### What the fix actually does — caveat: it MASKS, it does not root-fix

The commit adds a `deftransform` on `data-vector-ref-with-offset` (x86/x86-64;
`data-vector-ref` on other arches): when the array is an `initialize-vector`
combination (what `make-array` + a constant `:initial-contents` lowers to) **and
the index is a constant**, it splices the element expression out directly —
`(aref (vector a b c) 1) => b` — eliminating the vector allocation and every
store. Our repro reads a *constant* index (1) of a freshly built vector, so
after this transform there is no array and no dead stores at all, and the buggy
dead-store-elimination / modular-`ASH` code path is simply never reached.

Evidence this is a peephole, not a soundness fix: the commit's only added test
(`:aref-vector-fold` in `tests/compiler-ir.pure.lisp`) asserts the vector folds
to *zero* IR calls — an optimization assertion, not a value-correctness one —
and the change is **not listed in the 2.6.9 NEWS** as a bug fix.

**Implication for the upstream report.** The underlying miscompilation of a
variable-shift modular `ASH` under dead-store elimination of unread
`(unsigned-byte 64)` array stores is very likely still latent on current SBCL;
this commit only removed the one shape our reduced repro happened to use. A
shape that does **not** fold to the new transform (e.g. a non-constant `aref`
index, an array that escapes, or an array read through a path the transform
cannot see) could still trigger it. That was **not** re-verified here —
constructing a non-foldable repro and testing it on current x86-64 SBCL is the
right next step before concluding the hazard is gone. The introduction window
(2.2.9 correct → 2.6.8 wrong) was also not bisected.
