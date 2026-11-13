# SBCL findings — status: no confirmed SBCL defect

This file is deliberately a **negative report**. Across this audit, SBCL 2.6.10
(x86-64 build hosting ACL2 on this machine — `uname`: darwin arm64, SBCL via Homebrew)
was used as one of two differential oracles against Clozure CL, and it came out clean:
no wrong value, no crash, and no unsound compiler type-derivation was found. In every
soundness finding of the project, SBCL is the **correct** party.

Recording this matters: "we looked hard and found nothing" is the useful thing to tell
a maintainer, and it keeps us from sending noise. If a concrete SBCL bug turns up
later, it gets its own section here with a reproducer.

- SBCL version: `SBCL 2.6.10` (`/opt/homebrew/Cellar/sbcl/2.6.10`).

**How SBCL tracks bugs (verify before sending — my information may be dated).**
Historically: the Launchpad tracker at <https://bugs.launchpad.net/sbcl> and the
`sbcl-devel` / `sbcl-bugs` mailing lists (see <http://www.sbcl.org/mailing-lists.html>).
A source mirror lives at <https://github.com/sbcl/sbcl>. For a *candidate* like the one
below, the `sbcl-devel` mailing list (which you mentioned) is the right first contact —
it is where a maintainer can say in one reply whether a derived type bound is
intentional, before anyone opens a tracker item.

---

## What was tested, and that SBCL passed

| Differential test | Volume on SBCL | Result |
|---|---|---|
| Dietz `random-int-form` optimized vs unoptimized | 360k forms (size ≤ 200, ≤ 4 vars) | 0 divergences |
| ACL2 primitive value sweep, logical vs raw on every route | ~4.4M argument tuples, 1132 functions | 0 value mismatches |
| Derived-result-type oracle (see below) | ~7M checks, 265 operators, 6,542 functions | 0 rows excluding a constructible value |

In the soundness findings (`ACL2-BUG-REPORT.md`): S1/S2/S4/S5 are ACL2 bugs where SBCL
is not at fault; S3 and S6 are **CCL-only** (SBCL returns the correct value and rejects
the bad theorem). The two host-compiler bugs (`CCL.md`) are both CCL's; SBCL correctly
signals an error in the `ash` case.

---

## The one boundary examined in depth — resolved SAFE

The derived-type oracle checked, for each primitive, whether the type SBCL *infers* for
a call under ACL2's compilation policy `(safety 0) (speed 3)` can exclude a value the
function can logically return — the class that could let ACL2 (which trusts those
derivations) prove `NIL`. It found **zero** such rows that exclude a *constructible*
value. The one bound I would not sign off on by eye, `integer-length` deriving roughly
`(unsigned-byte 38)` for an unconstrained integer input, was then traced through the
SBCL sources and confirmed sound (`derived-types/INTEGER-LENGTH.md`):

- Bounded inputs follow their own range: the derive-type optimizer
  (`src/compiler/srctran.lisp` ~3359–3386) sets the upper bound to
  `(max (integer-length lo) (integer-length hi))` — never a flat cap (e.g.
  `(integer 0 (expt 2 100))` → `(mod 102)`).
- An unbounded input falls through to the `defknown` type `bit-index`
  (`fndb.lisp:543`), which is **not** arbitrary: `bit-index` =
  `(integer 0 ((1+ maximum-bignum-length)·n-word-bits − 1))`
  (`vm-type.lisp:73–74`), and `maximum-bignum-length = #xFFFFFFFF` (`early-vm.lisp`),
  giving exactly `2^38 − 1` = `(unsigned-byte 38)`.
- Soundness: the largest representable integer occupies `2^32 − 1` words of 64 bits, so
  its `integer-length` is at most `(2^32 − 1)·64 − 1 = 2^38 − 65`, **strictly below**
  the cap `2^38 − 1`. The derived type over-approximates by 64 and contains every value
  SBCL can represent. A witness exceeding it would need `integer-length ≥ 2^38`
  (≈ 32 GiB), which also exceeds `maximum-bignum-length`; SBCL errors before building
  it. Unconstructible in principle — the same situation as `length`/`(unsigned-byte 45)`
  bounded by `array-dimension-limit`.

So this is confirmed safe, not merely "no witness found." No open SBCL lead remains from
the derived-type pass.

## Still to do (SBCL has only been tested on arm64)

Everything above ran on SBCL 2.6.10, Apple-Silicon (arm64). SBCL's x86-64 backend is a
different VOP/codegen path and has **not** been exercised by this audit yet; that work
is in progress on an x86-64 host (see the project notes). A clean arm64 result is not a
clean x86-64 result.
