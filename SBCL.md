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

## The one boundary worth a maintainer's eye (examined; NOT a confirmed bug)

The derived-type oracle checked, for each primitive, whether the type SBCL *infers* for
a call under ACL2's compilation policy `(safety 0) (speed 3)` can exclude a value the
function can logically return — the class that could let ACL2 (which trusts those
derivations) prove `NIL`. It found **zero** such rows that exclude a *constructible*
value. Two inferred bounds are narrower than the mathematical range but were classed as
safe because a witness cannot be built:

- `integer-length` of an integer argument derives a result in roughly `(unsigned-byte 38)`.
- `length` derives roughly `(unsigned-byte 45)`.

`length` is unquestionably safe: a list or vector of length ≥ 2^45 would need ~2^45
elements and cannot exist. `integer-length` is the **one edge** I would not swear is
unreachable: a value with `integer-length ≥ 2^38` is a bignum of ≥ 2^38 bits ≈ 32 GiB.
That is at the very limit of what a large-memory machine could allocate, not obviously
impossible the way a 2^45-element list is. We could **not** construct a witness on this
hardware, so there is no reproducer and no confirmed bug — but if SBCL genuinely derives
`integer-length ⊆ (unsigned-byte 38)` for an *unconstrained* integer input (rather than
one whose own range already bounds it), that is the question worth asking `sbcl-devel`:

> Under `(speed 3) (safety 0)`, what result type does the compiler derive for
> `(integer-length x)` with `x` of type `integer` (no range), and is it bounded below
> `(integer-length most-positive-bignum)`? If so, is that intentional given that a
> ≥ 32 GiB bignum is in principle allocatable?

To turn this into either a real report or a clean dismissal, the next step (not yet
done) is to read SBCL's `integer-length` deftransform / `derive-type` method in
`src/compiler/` directly and see whether the bound is tied to the input's own bounds
(safe) or is a flat constant (potentially not). That inspection, plus an attempt to
allocate the witness on a big-memory box, is what would settle it.
