# SBCL findings — one confirmed defect (x86-64)

On **arm64** (SBCL 2.6.10, Apple Silicon) SBCL came out clean across this entire
audit — no wrong value, no crash, no unsound compiler type-derivation — and it is the
**correct** party in every soundness finding of the project. The derived-type section
below records that negative in full. But the **x86-64** backend is a different
VOP/codegen path, and when it was finally exercised the non-integer differential fuzzer
found one real soundness bug (SB1 below). So the honest status is: arm64 clean, x86-64
has at least one miscompilation. See `X86-SBCL.md` for the full x86-64 cross-architecture
report (the ACL2 interface itself replayed clean on x86-64; this is a pure
host-compiler codegen bug).

## SB1 — variable-shift modular `ash` miscompiled in a `(unsigned-byte 64)` array (x86-64)

`repros/sbcl-x86-modular-ash-u64-array/` (`repro.lisp`, `run.sh`). **SBCL 2.6.8
x86-64. Confirmed firsthand on hbox** (wrong on 2.6.8 x86-64; correct on 2.2.9 x86-64
and on 2.6.10 arm64 — a between-versions x86-64 regression).

At `(speed 3)(safety 0)`, a `(simple-array (unsigned-byte 64))` of three elements is
built, each element a `(mod 2^64)` expression, one of them a **variable-shift** `ash`;
only that one element is read back with `aref`. The read returns a **wrong value**:
```lisp
(defun buggy (v0 v1)
  (declare (optimize (speed 3) (safety 0)) (type integer v0 v1))
  (let ((a (make-array 3 :element-type '(unsigned-byte 64)
             :initial-contents
             (list (logand v1 #xFFFFFFFFFFFFFFFF)
                   (logand (ash v1 (- (logand v0 63) 20)) #xFFFFFFFFFFFFFFFF)
                   (logand v1 #xFFFFFFFFFFFFFFFF)))))
    (aref a 1)))
(buggy 64 9223372036854775807)   ; SBCL 2.6.8 x86-64 => 0   ** wrong **
                                 ; correct value       => 8796093022207  (= (logand (ash (1- 2^63) -20) 2^64-1))
```
No contract is violated: `v0 v1` are plain integers, every element is masked into
`(unsigned-byte 64)`, the index is in bounds, and `buggy` differs from a correct
`(speed 0)(safety 3)` version only in its `optimize` policy. Reduction shows all three
conditions are essential: **≥ 3** modular array elements, the read element's `ash`
shift must be **variable** (a constant shift compiles correctly), and **only** that one
element may be read (reading all three is correct) — i.e. dead-store elimination of the
other two elements miscompiles the surviving variable-shift modular `ash`.

**ACL2 impact in the current setup: none** — the hbox ACL2 image embeds SBCL 2.2.9
(unaffected) and the Mac ACL2 is 2.6.10 arm64 (unaffected). But an ACL2 built on an
affected x86-64 SBCL (2.6.8, and plausibly 2.6.10 x86-64 — untested) would trust this
raw result, so it is a latent host-compiler soundness hazard and exactly the class this
audit exists to find. Worth reporting to `sbcl-devel` with the reproducer above.

## The arm64 negative (unchanged)

Across this audit on arm64, SBCL 2.6.10 was used as one of two differential oracles
against Clozure CL and came out clean; in every soundness finding of the project, SBCL
is the **correct** party.

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
