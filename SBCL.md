# SBCL findings

Across the initial Batch-1 differential audit (arm64 macOS on SBCL 2.6.10, and x86-64 Linux
on SBCL 2.2.9 / 2.6.8 / 2.6.9 / 2.6.10; see `X86-SBCL.md`), SBCL was the **correct** party in
every Batch-1 soundness finding where hosts disagreed (`ACL2-BUG-REPORT.md` S3, S6; `CCL.md`
CCL-1..CCL-3).

> **Subsequent Wave-1 & Wave-2 SBCL 2.6.10 findings:** See
> [`reports/SBCL-2.6.10-FINDINGS.md`](reports/SBCL-2.6.10-FINDINGS.md) (`SB-2610-1..4`: four
> live VOP register-lifetime soundness/segfault bugs at `(safety 3)`) and
> [`reports/Z3-COMPILER-EQUIVALENCE.md`](reports/Z3-COMPILER-EQUIVALENCE.md) (`Z3-1`,
> `Z3-1-ACL2`, `Z3-2`: live `(safety 3)` `inherit-equality-p` lattice bug in
> `equality-constraints.lisp` that directly proves `(defthm nil-proved nil)` in pure
> guard-verified ACL2 on SBCL 2.6.10 via `char-equal`, plus `same-arg` float misfolds).

Two SBCL compiler defects were found in the initial Batch-1 fuzzing sweep:

1. **SB1 (soundness, x86-64, SBCL 2.6.8–2.6.9 — ALREADY FIXED upstream in 2.6.10):**
   variable-shift modular `ash` miscompiled to `0` at `(speed 3)(safety 0)` due to a VOP
   register-lifetime bug in `ash-right-two-words-variable` (`0fd47cc68`). **Do not report
   to `sbcl-devel`** (already fixed in 2.6.10), though ACL2 users building on SBCL 2.6.8
   or 2.6.9 x86-64 are exposed.
2. **SB2 / F18 (robustness / compile-time crash, arm64, LIVE on SBCL 2.6.10):**
   recursive inline expansion on arm64 overflows the 19-bit signed conditional-branch
   displacement field, crashing the assembler with
   `The value -262148 is not of type (SIGNED-BYTE 19)` (`repros/recursive-defun-inline-sbcl-arm64/`).

---

## SB1 — variable-shift modular `ash` miscompiled in a `(unsigned-byte 64)` array (x86-64, 2.6.8–2.6.9; fixed in 2.6.10)

`repros/sbcl-x86-modular-ash-u64-array/` (`repro.lisp`, `v2probe.lisp`, `variants.lisp`,
`run.sh`). **Confirmed on SBCL 2.6.8 and 2.6.9 x86-64; root-fixed in SBCL 2.6.10.**

At `(speed 3)(safety 0)`, a `(simple-array (unsigned-byte 64) (3))` is constructed with
three modular `(logand … #xFFFFFFFFFFFFFFFF)` elements, the middle one a **variable-shift**
`ash`. Even when the array escapes (`v2probe.lisp`), element 1 evaluates to **`0`** instead
of **`8796093022207`**:

```lisp
(defconstant +m+ #xFFFFFFFFFFFFFFFF)
(defun v2-buggy (v0 v1)
  (declare (optimize (speed 3) (safety 0)) (type integer v0 v1))
  (make-array 3 :element-type '(unsigned-byte 64)
    :initial-contents (list (logand v1 +m+)
                            (logand (ash v1 (- (logand v0 63) 20)) +m+)
                            (logand v1 +m+))))

(aref (v2-buggy 64 9223372036854775807) 1)
;; SBCL 2.6.8 & 2.6.9 x86-64 => 0              ** wrong **
;; SBCL 2.2.9 & 2.6.10 x86-64, 2.6.10 arm64 => 8796093022207  (correct)
```

Two separate upstream commits explain the version matrix:
- **`e938a68479`** (2.6.8 → 2.6.9, *"(aref (vector a) 0) => a"*) folded away the non-escaping
  `repro.lisp` form, **masking** the bug in 2.6.9 without fixing it (`v2-buggy` above still
  returns `0` on 2.6.9).
- **`0fd47cc68d`** (2.6.9 → 2.6.10, Stas Boukarev, 2026-10-06, *"x86-64: a lifetime issue in
  ash-right-two-words-variable"*, `src/compiler/x86-64/arith.lisp:6306`) fixed the actual
  codegen bug (`(b :scs (unsigned-reg) :target result)` → `:to :save` so the fixed `rcx`
  shift-count temporary cannot clobber `b`).

---

## SB2 (F18) — arm64 assembler crashes with `(SIGNED-BYTE 19)` branch overflow on recursive inline expansion (LIVE in 2.6.10)

`repros/recursive-defun-inline-sbcl-arm64/` (`reduced.lisp`, `recursion-kept.lisp`,
`run.sh`). **Confirmed on SBCL 2.6.10 darwin-arm64.**

Admitting a recursive `defun-inline` whose body contains a `loop$` with a `df/`-computed
bound aborts compilation in SBCL's arm64 assembler:

```text
Error: The value -262148 is not of type (SIGNED-BYTE 19)
```

`-262148` is just past `-2^18` (`-262144`), the signed 19-bit word-offset limit (`±1 MiB`)
of an ARM64 conditional branch (`B.cond` / `CBZ` / `CBNZ`): SBCL's self-inlining of the
`$inline` function produces a component whose internal conditional branch exceeds 1 MiB
without branch-relaxation / veneer insertion. CCL 1.14 arm64 compiles the identical files
cleanly. Details and standalone reduction tracking live in
`reports/SBCL-F18-ARM64-BRANCH-OVERFLOW.md`.

---

## What was tested, and that SBCL 2.6.10 passed on soundness

| Differential test | Volume on SBCL | Result |
|---|---|---|
| Dietz `random-int-form` optimized vs unoptimized | 360k forms (arm64) | 0 divergences |
| Non-integer differential fuzzer (`fuzz-nonint.lisp`, x86-64) | arrays/strings/bitvectors/mv/modular | SB1 on 2.6.8–2.6.9; **0 on 2.6.10** |
| Coverage-guided ACL2 IR fuzzer (`synth/fuzz.lisp`, arm64) | 10,400 programs, 734,712 queries | 0 value diffs (found SB2/F18 crash) |
| Bounded-exhaustive small integer terms (`synth/exhaust.lisp`) | ~149k typed fns × 25–49 boundary inputs | 0 value diffs |
| ACL2 primitive value sweep, logical vs raw on every route | ~4.4M argument tuples, 1132 functions | 0 value mismatches |
| Derived-result-type oracle (`derived-types/`) | ~7M checks, 265 operators, 6,542 functions | 0 rows excluding a constructible value |

### Derived-type boundary examined in depth — `integer-length` resolved SAFE

`integer-length` derives `(unsigned-byte 38)` for an unconstrained integer input on 64-bit
SBCL (`derived-types/INTEGER-LENGTH.md`). Source trace confirms this is sound:
- Bounded inputs compute exact `(max (integer-length lo) (integer-length hi))`
  (`src/compiler/srctran.lisp:3359–3386`).
- Unbounded inputs fall back to `bit-index` (`fndb.lisp:543`, `vm-type.lisp:73–74`), derived
  from `maximum-bignum-length = #xFFFFFFFF` (`early-vm.lisp`), giving `2^38 − 1`.
- The largest representable SBCL bignum has `integer-length ≤ (2^32 − 1)·64 − 1 = 2^38 − 65 < 2^38 − 1`;
  anything larger signals an allocation/representation error before returning.
