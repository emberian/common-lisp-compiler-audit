# SBCL 2.6.10 Live Compiler Soundness & Backend Audit Findings

- **Targets Audited:**
  - **macOS `arm64`:** SBCL `2.6.10` (`/opt/homebrew/bin/sbcl`)
  - **Linux `x86-64` (`hbox`):** SBCL `2.6.10` (`sbcl-2.6.10-x86-64-linux`)
  - **Source Reference:** SBCL git tag `sbcl-2.6.10` (`3223f5d21ff7fa3e15f7643400c4326e7b5e9f3a`, `HEAD` after `0fd47cc68daff8329bef1cdc40f35e616cf026e6`)
- **Audit Scope:**
  1. Standalone pure-CL reduction and assembler root-cause analysis for `SB2` / `F18` (`(SIGNED-BYTE 19)` overflow on `arm64`).
  2. Systematic static VOP register-lifetime and operand-clobber audit of **all 1,395 `define-vop` definitions** across `src/compiler/x86-64/*.lisp` (**756 VOPs**) and `src/compiler/arm64/*.lisp` (**639 VOPs**), searching for siblings of Stas Boukarev's `0fd47cc68d` fix (`ash-right-two-words-variable`).
  3. Anti-masking + consumer-context differential fuzzing (`8,000` compiled function pairs / `44,000` executions across `arm64` and `x86-64`).

---

## Executive Summary

Unlike `SB1` (`0fd47cc68d`, fixed in 2.6.10, which required `(speed 3) (safety 0)`), our VOP lifetime audit uncovered **four brand-new live compiler soundness bugs in SBCL 2.6.10** — **all four reproduce at `(safety 3)`**, **two reproduce at SBCL's out-of-the-box default optimization policy `(speed 1) (safety 1)`**, and **one crashes SBCL with an unmapped memory fault (`0xfffffffffffffff8`) in 100% pure ANSI Common Lisp with zero internal symbols**:

| ID | Arch | VOP(s) & Source (`sbcl-2.6.10`) | Policy Needed | Surface / Impact | Reproducer Directory |
|---|---|---|---|---|---|
| **SB-2610-1** | `x86-64` | `%more-arg-values-skip` (`x86-64/values.lisp:162–190`) | `(speed 3) (safety 3)` | **Pure ANSI CL** (`multiple-value-prog1` + `(values-list (cdr r))`): `count` (`:from :eval`) shares `RCX` with `context`; `XOR ECX, ECX` zeroes `context` before `LEA R11, [RCX-8]`, crashing with **`Memory fault at 0xfffffffffffffff8`** | `repros/sbcl-2.6.10-x86-64-more-arg-values-skip-crash/` |
| **SB-2610-2** | `arm64` (+ `x86-64` AVX-512 twin) | `%make-simd-pack-single` (`arm64/simd-pack.lisp:269–283`); `%make-simd-pack-512-single` (`x86-64/simd-pack-512.lisp:508–540`) | **Default `(speed 1) (safety 1)`** & `(safety 3)` | `sb-ext:%make-simd-pack-single`: 0-based `:from (:argument 2)` off-by-one lets `tmp` pack into 3rd arg `z` (`V0`), **silently overwriting lane 2 (`z`) with lane 0 (`x`)** (2-line function, zero declarations!) | `repros/sbcl-2.6.10-arm64-simd-pack-single-clobber/` |
| **SB-2610-3** | `arm64` | `bignum-mult-and-add-4-arg` (`arm64/arith.lisp:2790–2808`) | **Default `(speed 1) (safety 1)`** & `(safety 3)` | `sb-bignum:%multiply-and-add` (4-arg): **two simultaneous lifetime clobbers** (`hi` clobbers `y` in `UMULH`; 2nd result `lo` clobbers `prev` in `MUL` so `ADDS` adds `lo` to itself), **silently corrupting both high and low 64-bit limbs** | `repros/sbcl-2.6.10-arm64-bignum-multiply-and-add-clobber/` |
| **SB-2610-4** | `x86-64` & `arm64` | All **8** `%simd-pack{,-256,-512}-int-to-{single,double}` VOPs (`arm64/simd-pack.lisp:334–351`, `x86-64/simd-pack{,-256,-512}.lisp`) | `(speed 3) (safety 3)` | `(move dst src)` called **backwards** as `(move x y)`: copies uninitialized/stale result `y` **into input `x`**, simultaneously **corrupting the caller's live variable `x` AND returning stale register garbage in `y`** | `repros/sbcl-2.6.10-simd-int-to-float-backwards-move/` |
| **SB2 / F18** | `arm64` | `ldr` literal / `load-constant` / `b` cond (`arm64/insts.lisp:1577–1629, 1791–1800`) | **Default `(speed 1) (safety 1)`** | **Plain-SBCL reproducer (`plain-sbcl.lisp`, zero ACL2 dependency)** + exact root cause: unconditional `ldr` from segment trailer constant pool overflows 19-bit signed word offset (`±1 MiB`) before any branch is even emitted | `repros/recursive-defun-inline-sbcl-arm64/plain-sbcl.lisp` (`reports/SBCL-F18-ARM64-BRANCH-OVERFLOW.md`) |

In addition to the live bugs above, the static VOP audit identified **three latent VOP lifetime defects** (`bignum-add-loop` on `x86-64`, `bignum-negate-loop` on `x86-64`/`arm64`, and `#+bignum-assertions` `move-from-128` on `arm64`), documented in [Section 5](#5-additional-source-audited-latent-vop-defects-in-sbcl-2610).

---

## 1. `SB-2610-1` — Pure ANSI Common Lisp Segfault at `(SAFETY 3)` in `%more-arg-values-skip` (`x86-64`)

- **Reproducer:** `repros/sbcl-2.6.10-x86-64-more-arg-values-skip-crash/` (`repro.lisp`, `run.sh`)
- **Affected VOP:** `%more-arg-values-skip` in `src/compiler/x86-64/values.lisp:162–190`
- **Reachability:** **100% pure ANSI Common Lisp** — `(values-list (cdr r))` (or `(values-list (nthcdr k r))`) on an `&rest` parameter inside `multiple-value-prog1` / `multiple-value-call` at `(optimize (speed 3) (safety 3))`.

### Source Root Cause

In `src/compiler/srctran.lisp:8600`, `(values-list (cdr r))` on an `&rest` list is source-transformed into `(%rest-values r context 1 count)`, which IR2-translates (`src/compiler/ir2tran.lisp:2082`) to `%more-arg-values-skip`:

```lisp
;; src/compiler/x86-64/values.lisp:162-186
(define-vop (%more-arg-values-skip)
  (:args (context :scs (descriptor-reg any-reg) :target src)
         (skip :scs (any-reg immediate))
         (num :scs (any-reg)))
  (:arg-types * positive-fixnum positive-fixnum)
  (:temporary (:sc any-reg :from (:argument 0)) src)
  (:temporary (:sc descriptor-reg) temp)
  (:temporary (:sc unsigned-reg) loop-index)
  (:results (start :scs (any-reg) :from :eval)
            (count :scs (any-reg) :from :eval))
  (:generator 20
    (move loop-index num)
    (unless (eq (tn-kind count) :unused)
      (zeroize count))                                                   ; L175: XOR ECX, ECX — clobbers context/skip!
    (sc-case skip
      (immediate
       (inst lea src (ea (- (* (tn-value skip) n-word-bytes)) context))  ; L178: LEA R11, [RCX-8] — reads zeroed context!
       (inst sub loop-index skip)
       (inst jmp :le done))
      (any-reg
       (inst sub loop-index skip)
       (inst jmp :le done)
       (inst neg skip)                                                   ; L184: mutates `skip` in place without :to :save!
       (inst lea src (ea context skip (ash 1 (- word-shift n-fixnum-tag-bits))))))
```

Because `count` declares `:from :eval` (`born = :eval`), SBCL's `meta-vmdef` lifetime model (`src/compiler/meta-vmdef.lisp:606–615`) allows `count` to share the exact same register as `context` (`dies = (:argument 0)`) or `skip` (`dies = (:argument 1)`). Yet line 175 executes `(zeroize count)` **before** lines 178 and 185 read `context` and `skip`! *(Additionally, line 184 mutates `skip` in place via `(inst neg skip)` without `:to :save` or a temporary, corrupting any caller variable sharing `skip` when `skip` is non-constant.)*

### Minimal Pure ANSI CL Reproducer & Live Crash (`x86-64`, SBCL 2.6.10)

```lisp
(declaim (notinline sink))
(defun sink (x) x)

(defun buggy-speed3-safety3 (p0 p1 p2 p3 p4 p5 p6 p7 p8 p9 &rest r)
  (declare (optimize (speed 3) (safety 3))
           (type fixnum p0 p1 p2 p3 p4 p5 p6 p7 p8 p9))
  (let ((l0 (the fixnum (+ 1 p0)))
        (l1 (the fixnum (+ 2 p1)))
        (l2 (the fixnum (+ 3 p2)))
        (l3 (the fixnum (+ 4 p3)))
        (l4 (the fixnum (+ 5 p4)))
        (l5 (the fixnum (+ 6 p5))))
    (declare (type fixnum l0 l1 l2 l3 l4 l5))
    (multiple-value-prog1
        (values-list (cdr r))
      (sink (list l0 l1 l2 l3 l4 l5)))))

(buggy-speed3-safety3 0 1 2 3 4 5 6 7 8 9 :drop :keep-a :keep-b)
```

Disassembly and crash output on `hbox` (`SBCL 2.6.10 x86-64-linux`):

```text
; 32A: 4C8BF2           MOV R14, RDX
; 32D: 31C9             XOR ECX, ECX          ; zeroes count=RCX, clobbering context=RCX!
; 32F: 4C8D59F8         LEA R11, [RCX-8]      ; R11 = 0 - 8 = 0xfffffffffffffff8!
; 333: 4983EE02         SUB R14, 2
; 337: 7E23             JLE L3
...
; 34A: 4F8B3C33         MOV R15, [R11+R14]    ; dereferences 0xfffffffffffffff8!

CORRUPTION WARNING in SBCL pid 2801217 tid 2801217:
Memory fault at 0xfffffffffffffff8 (pc=0x10018a0c0a, fp=0x7f184776fe28, sp=0x7f184776fdd0) tid 2801217
The integrity of this image is possibly compromised.
Exiting.
```

### Suggested Upstream Fix

Move `(unless (eq (tn-kind count) :unused) (zeroize count))` after the `sc-case skip` block (or drop `:from :eval` on `count` so its default lifetime `:from :load` conflicts with all `:args`), and compute the non-immediate offset without mutating `skip` in place.

---

## 2. `SB-2610-2` — Default-Policy Silent Miscompilation in `%make-simd-pack-single` (`arm64`) + Exact `x86-64` AVX-512 Twin

- **Reproducer:** `repros/sbcl-2.6.10-arm64-simd-pack-single-clobber/` (`repro.lisp`, `run.sh`)
- **Affected VOPs:**
  1. **Live on `arm64`:** `%make-simd-pack-single` (`src/compiler/arm64/simd-pack.lisp:269–283`)
  2. **Disassembly-verified twin on `x86-64` (`avx2`+`avx512f`):** `%make-simd-pack-512-single` (`src/compiler/x86-64/simd-pack-512.lisp:508–540`)
- **Optimization Policy:** **Default policy** `(speed 1) (safety 1) (debug 1)` — **zero `declare` forms required!**

### Source Root Cause (`arm64`)

```lisp
;; src/compiler/arm64/simd-pack.lisp:269-283
(define-vop (%make-simd-pack-single)
  (:translate %make-simd-pack-single)
  (:policy :fast-safe)
  (:args (x :scs (single-reg) :target tmp)
         (y :scs (single-reg))
         (z :scs (single-reg))
         (w :scs (single-reg)))
  (:arg-types single-float single-float single-float single-float)
  (:temporary (:sc single-neon-reg :from (:argument 2)) tmp)             ; BUG: 0-indexed (:argument 2) == `z`!
  (:results (dst :scs (single-neon-reg) :from (:argument 2)))
  (:result-types simd-pack-single)
  (:generator 5
    (inst zip1 tmp x y :2s)                                              ; overwrites `z` when `tmp` packs into `z`!
    (inst zip1 dst z w :2s)                                              ; reads clobbered `z`!
    (inst zip1 dst tmp dst :2d)))
```

VOP operand numbers in `:from (:argument N)` are **0-based**: `x` is `0`, `y` is `1`, `z` is `2`, `w` is `3`. Because `z` dies at `(:argument 2)` and `tmp` is born at `(:argument 2)`, `meta-vmdef.lisp:606–615` treats their lifetimes as non-overlapping (`tmp.born == z.dies`). Whenever `x` remains live across the VOP (preventing `tmp` from packing into `:target` `x`) while `z` dies, `tmp` packs into `z`'s NEON register (`V0`), overwriting `z` with `(x, y)` before `(inst zip1 dst z w :2s)` reads `z`.

### Minimal 2-Line Default-Policy Reproducer & Live Output (`arm64`, SBCL 2.6.10)

```lisp
(defun make-pack-default (x y z w)
  (values (sb-ext:%make-simd-pack-single x y z w) x))

(make-pack-default 11.0f0 22.0f0 33.0f0 44.0f0)
;; Got     : #<SIMD-PACK f32.4 1.1000000e+1 2.2000000e+1 1.1000000e+1 4.4000000e+1>, 11.0
;; Expected: #<SIMD-PACK f32.4 1.1000000e+1 2.2000000e+1 3.3000000e+1 4.4000000e+1>, 11.0
```

Disassembly of `make-pack-default` on `SBCL 2.6.10 arm64`:

```text
; 48: 6038820E         ZIP1 V0.2S, V3.2S, V2.2S    ; tmp=V0 overwrites z=V0 with (x=11.0, y=22.0)!
; 4C: 0138810E         ZIP1 V1.2S, V0.2S, V1.2S    ; reads V0 (11.0) instead of z (33.0)!
; 50: 0138C14E         ZIP1 V1.2D, V0.2D, V1.2D
```

### Exact `x86-64` AVX-512 Twin (`%make-simd-pack-512-single`)

In `src/compiler/x86-64/simd-pack-512.lisp:508–540`, `%make-simd-pack-512-single` commits the identical 0-based index off-by-one on its 5th argument `p4` (`dies = (:argument 4)`):

```lisp
;; src/compiler/x86-64/simd-pack-512.lisp:530-536
(:results (dst :scs (single-avx512-reg) :from (:argument 4)))
...
  (inst vunpcklps tmp1 p0 p1)
  (inst vunpcklps tmp2 p2 p3)
  (inst vshufps dst tmp1 tmp2 #b01000100)  ; L535: writes `dst` BEFORE `p4` is read on L536!
  (inst vunpcklps tmp3 p4 p5)              ; L536: reads clobbered `p4`!
```

Verified by disassembling a `(safety 3)` function keeping `(+ p0 p1 p2 p3)` live on `hbox` (`SBCL 2.6.10 x86-64`):

```text
; 2AA: F30F1045F0       MOVSS XMM0, [RBP-16]            ; p4 loaded into XMM0 / ZMM0
; 2EA: 62611C4814FC     VUNPCKLPS ZMM31, ZMM12, ZMM13   ; p0, p1
; 2F0: 62610C4814F7     VUNPCKLPS ZMM30, ZMM14, ZMM15   ; p2, p3
; 2F6: 62910440C6C644   VSHUFPS ZMM0, ZMM31, ZMM30, 68  ; dst=ZMM0 overwrites p4=ZMM0!
; 2FD: 62617C4814E9     VUNPCKLPS ZMM29, ZMM0, ZMM1     ; reads clobbered ZMM0 instead of p4!
```

### Suggested Upstream Fix

- In `src/compiler/arm64/simd-pack.lisp:275`, change `(:temporary (:sc single-neon-reg :from (:argument 2)) tmp)` to `:from :eval` (or `:from (:argument 1)`).
- In `src/compiler/x86-64/simd-pack-512.lisp:530`, change `:from (:argument 4)` on `dst` to `:from :eval` (or `:from (:argument 3)`).

---

## 3. `SB-2610-3` — Double Register-Lifetime Clobber in `bignum-mult-and-add-4-arg` (`arm64`)

- **Reproducer:** `repros/sbcl-2.6.10-arm64-bignum-multiply-and-add-clobber/` (`repro.lisp`, `run.sh`)
- **Affected VOP:** `bignum-mult-and-add-4-arg` (`sb-bignum:%multiply-and-add`, `src/compiler/arm64/arith.lisp:2790–2808`)
- **Optimization Policy:** Reproduces at **default policy `(speed 1) (safety 1)`**, `(speed 3) (safety 3)`, and `(speed 3) (safety 0)`.

### Source Root Cause

```lisp
;; src/compiler/arm64/arith.lisp:2790-2808
(define-vop (bignum-mult-and-add-4-arg)
  (:translate sb-bignum:%multiply-and-add)
  (:policy :fast-safe)
  (:args (x :scs (unsigned-reg) :to :result)
         (y :scs (unsigned-reg) :target lo)             ; BUG 1: dies at (:argument 1), before `hi` (:eval)!
         (prev :scs (unsigned-reg) :to :result)         ; BUG 2: :to :result == (:result 0), before `lo` (:result 1)!
         (carry-in :scs (unsigned-reg) :to :result))    ; BUG 2: :to :result == (:result 0), before `lo` (:result 1)!
  (:arg-types unsigned-num unsigned-num unsigned-num unsigned-num)
  (:results (hi :scs (unsigned-reg) :from :eval)
            (lo :scs (unsigned-reg)))
  (:result-types unsigned-num unsigned-num)
  (:generator 20
    (inst umulh hi x y)                                 ; overwrites `y` when `hi` shares `y`'s reg!
    (inst mul lo x y)                                   ; reads clobbered `y`, AND overwrites `prev`/`carry-in`!
    (inst adds lo lo prev)                              ; adds `lo` to ITSELF when `lo` shares `prev`'s reg!
    (inst adc hi hi zr-tn)
    (inst adds lo lo carry-in)
    (inst adc hi hi zr-tn)))
```

This single VOP contains **two independent lifetime bugs**:
1. **`hi` clobbers `y`:** `y` has default death `(:argument 1)`, while `hi` has `:from :eval` (`:eval > (:argument 1)`). When `prev` or `lo` holds `lo`'s register so `y` does not pack with `lo`, `hi` and `y` pack into `NL0`; `(inst umulh hi x y)` overwrites `y` before `(inst mul lo x y)` executes!
2. **`lo` clobbers `prev` / `carry-in`:** In `meta-vmdef.lisp:916`, `:to :result` parses to **`(:result 0)`** (`hi`), whereas `lo` is the **second** result (`born = (:result 1)`). Because `(:result 1) > (:result 0)`, `lo` does **not** conflict with `prev` or `carry-in`! `lo` and `prev` pack into `NL1`, so `(inst mul lo x y)` overwrites `prev` and `(inst adds lo lo prev)` computes `lo + lo` instead of `lo + prev`!

*(Compare `bignum-mult-and-add-3-arg` immediately precedes it at lines 2772–2789, where the author noticed the clash for `x`/`y` and gave both `:from :eval` on `lo` and `:to :result`? Actually `3-arg` gave `(x :to :result) (y :to :result)` and `(hi :from :eval) (lo :from :eval)`, avoiding both bugs!)*

### Minimal Reproducer, Disassembly & Live Output (`arm64`, SBCL 2.6.10)

```lisp
(defun mul-add-compiled (x y prev cin)
  (declare (optimize (speed 3) (safety 3))
           (type (unsigned-byte 64) x y prev cin))
  (dotimes (i 1 (list y prev x))
    (multiple-value-setq (y prev)
      (sb-bignum:%multiply-and-add x y prev cin))))

(mul-add-compiled #x8000000000000003 #x4000000000000005
                  #x1111111111111111 #x2222222222222222)
;; Got     : (2305843009213693956 16294623931776770612 9223372036854775811)
;; Expected: (2305843009213693955  8301034833169298242 9223372036854775811)
```

Disassembly on `SBCL 2.6.10 arm64` showing **both** clobbers firing simultaneously:

```text
; 650: 407C409B         UMULH NL0, NL2, NL0     ; hi=NL0 overwrites y=NL0!
; 654: 417C009B         MUL NL1, NL2, NL0       ; multiplies x by hi (NOT y), AND lo=NL1 overwrites prev=NL1!
; 658: 210001AB         ADDS NL1, NL1, NL1      ; adds lo=NL1 to ITSELF instead of prev!
; 65C: 00001F9A         ADC NL0, NL0, ZR
; 660: 210003AB         ADDS NL1, NL1, NL3
; 664: 00001F9A         ADC NL0, NL0, ZR
```

### Suggested Upstream Fix

Match `bignum-mult-and-add-3-arg` (`src/compiler/arm64/arith.lisp:2772–2789`): give `x` and `y` `:to :result`, give `prev` and `carry-in` `:to :save`, and give `lo` `:from :eval` (removing `:target lo` on `y` or moving `:target lo` onto `prev` / `carry-in` after `mul`).

---

## 4. `SB-2610-4` — Cross-Architecture (`x86-64` & `arm64`) Backwards `(move x y)` in All 8 `%simd-pack{,-256,-512}-int-to-{single,double}` VOPs

- **Reproducer:** `repros/sbcl-2.6.10-simd-int-to-float-backwards-move/` (`repro.lisp`, `run.sh`)
- **Affected VOPs (8 total across `arm64` and `x86-64`):**
  1. `src/compiler/arm64/simd-pack.lisp:334–351` (`%simd-pack-int-to-double`, `%simd-pack-int-to-single`)
  2. `src/compiler/x86-64/simd-pack.lisp:362–379` (`%simd-pack-int-to-double`, `%simd-pack-int-to-single`)
  3. `src/compiler/x86-64/simd-pack-256.lisp:357–374` (`%simd-pack-256-int-to-double`, `%simd-pack-256-int-to-single`)
  4. `src/compiler/x86-64/simd-pack-512.lisp:631–648` (`%simd-pack-512-int-to-double`, `%simd-pack-512-int-to-single`)
- **Internal Callers in SBCL:** Used by SBCL's own debugger frame slot reader (`src/code/debug-int.lisp:2500,2505`) and `x86-64` signal context reader (`src/code/x86-64-vm.lisp:74,77`).
- **Optimization Policy:** Reproduces at `(optimize (speed 3) (safety 3))` (and at default policy whenever `x` is already unboxed in a SIMD register and remains live).

### Source Root Cause

In both SBCL's `x86-64` and `arm64` backends, `(defmacro move (dst src ...))` takes **destination first, source second**. All 8 SIMD int-to-float reinterpretation VOPs omit `:target y` on `:args (x ...)` and call `(move x y)` **backwards**:

```lisp
;; src/compiler/x86-64/simd-pack.lisp:362-379 (and identical in arm64, simd-pack-256, simd-pack-512)
(macrolet ((define-int-to-float (name type sc)
             `(define-vop (,name)
                (:translate ,name)
                (:policy :fast-safe)
                (:args (x :scs (int-sse-reg)))          ; missing `:target y`!
                (:arg-types simd-pack-int)
                (:results (y :scs (,sc)))
                (:result-types ,type)
                (:generator 1
                  (unless (location= x y)
                    (move x y))))))                     ; BACKWARDS: copies uninitialized `y` INTO `x`!
  (define-int-to-float %simd-pack-int-to-double simd-pack-double double-sse-reg)
  (define-int-to-float %simd-pack-int-to-single simd-pack-single single-sse-reg))
```

Whenever `x` dies at the VOP and packs into the same register as `y`, `(location= x y)` masks the bug. The moment `x` **stays live** after the VOP, `x` and `y` receive distinct registers (`XMM1` vs `XMM2` on `x86-64`; `V0` vs `V1` on `arm64`), and `(move x y)` emits:
- **`x86-64` SSE / AVX2:** `MOVDQA XMM1, XMM2` / `VMOVDQA YMM1, YMM2` — overwriting `x` (`XMM1`) with stale `y` (`XMM2`)!
- **`arm64` NEON:** `ORR V0.16B, V1.16B, V1.16B` (`MOV V0.16B, V1.16B`) — overwriting `x` (`V0`) with stale `y` (`V1`)!

This **mutates the caller's immutable live variable `x` in place** and **leaves `y` containing stale register garbage**.

### Live Verification on Both `x86-64` (`hbox`) and `arm64` (macOS)

Running `repros/sbcl-2.6.10-simd-int-to-float-backwards-move/run.sh`:
- **`arm64` (`SBCL 2.6.10`):**
  ```text
  ; 98: A01C614E         MOV V0.16B, V1.16B     ; overwrites p-int (V0) with stale poison in V1!
  Got p-flt     : #<SIMD-PACK f32.4 9.9900000e+2 9.9900000e+2 9.9900000e+2 9.9900000e+2>
  Expected p-flt: #<SIMD-PACK f32.4 1.1000000e+1 2.3500000e+1 3.3000000e+1 4.4000000e+1>
  after-from-p-int: 999.0 (expected 11.0)
  ```
- **`x86-64` (`SBCL 2.6.10` on `hbox`):**
  ```text
  ; 4F: 660F6FCA         MOVDQA XMM1, XMM2      ; overwrites p-int (XMM1) with stale poison in XMM2!
  Got p-flt     : #<SIMD-PACK 9.9900000e+2 9.9900000e+2 9.9900000e+2 9.9900000e+2>
  Expected p-flt: #<SIMD-PACK 1.1000000e+1 2.3500000e+1 3.3000000e+1 4.4000000e+1>
  after-from-p-int: 4934187815336656896 (expected 4736658619236384768)
  ```
  *(Also verified identically for 256-bit AVX2 `%simd-pack-256-int-to-single` on `hbox`: `VMOVDQA YMM1, YMM2`.)*

### Suggested Upstream Fix

Add `:target y` to `(:args (x :scs (...) :target y))` and change `(move x y)` to `(move y x)` (and `(move y x :16b)` in `src/compiler/arm64/simd-pack.lisp:348`) across all 8 VOPs.

---

## 5. Additional Source-Audited Latent VOP Defects in SBCL 2.6.10

Our static scanners (`hunts/sbcl-live/scan_vops.py` and `hunts/sbcl-live/scan_arg_writes.py`) also surfaced three latent VOP defects that are currently masked by register-packing preferences or build-time feature flags, but violate SBCL's VOP lifetime invariants:

1. **`bignum-add-loop` (`src/compiler/x86-64/arith.lisp:4808–4835`):**
   - `:arg-types` (`bignum bignum unsigned-num bignum unsigned-num`) swaps the 4th and 5th types relative to `:args` (`a b la lb r`, where `lb` is `unsigned-num` and `r` is `bignum`, saved only because `bignum-add-loop` has no `:translate`).
   - `:temporary` lifetimes are swapped relative to `:target`: `la` (`(:argument 2)`) has `:target remaining-length`, yet `remaining-length` has `:from (:argument 3)` (so `remaining-length` does not conflict with `lb` at `(:argument 3)`!), while `length` has `:from (:argument 2)`.
   - Lines 4827–4830 execute `(move remaining-length la :dword)` and `(move length lb :dword)` **before** reading `la` and `lb` in `(inst mov sign-digit-a (ea ... a la 8))` and `(inst mov sign-digit-b (ea ... b lb 8))` without `:to :save` on `la`/`lb`. Currently masked in `sb-bignum:add-bignums` because `la` and `lb` die at the VOP and `pack` honors their `:target` chains.
2. **`bignum-negate-loop` & `bignum-negate-last-two-loop` (`src/compiler/x86-64/arith.lisp:4977, 5017` and `src/compiler/arm64/arith.lisp:2611`):**
   - Execute `(zeroize last2)` / `(inst mov last2 0)` (`last2` born at `(:result 1)`) **before** `(move length l)` (`l` dies at `(:argument 1)`). If `l` fails to pack into `:target length` (e.g., `length` constrained elsewhere while `l` dies), `last2` can pack into `l` and zero `l` before `(move length l)`. *(Notably, `arm64`'s `bignum-negate-last-two-loop` at `arm64/arith.lisp:2652` already moved `(move length l)` above `(inst mov last2 0)`, leaving the other three loops unpatched.)*
3. **`move-from-128` under `#+bignum-assertions` (`src/compiler/arm64/move.lisp:781–796`):**
   - Declares `(:args ((lo hi) :scs (signed-128-reg) :to :save))` and, under `#+bignum-assertions` (disabled in standard builds), executes `(inst mov hi 0)` directly on the input register `hi` at the end of the VOP, which would zero the upper 64 bits of any live `(signed-byte 128)` variable.

---

## 6. Objective 1 Summary — Plain-SBCL Reproducer & Exact Root Cause for `SB2` / `F18`

Full details and backtraces are in `reports/SBCL-F18-ARM64-BRANCH-OVERFLOW.md` and `repros/recursive-defun-inline-sbcl-arm64/plain-sbcl.lisp`. Key takeaways:
- **Zero-ACL2 Standalone Reproducer (`plain-sbcl.lisp`):** A 19-line pure ANSI CL file (`(declaim (inline rec-f18))` + two call sites in `trigger-rec-f18`) triggers `The value -262149 is not of type (SIGNED-BYTE 19)` in ~2 seconds on `/opt/homebrew/bin/sbcl --noinform --non-interactive --load plain-sbcl.lisp`.
- **Exact Root Cause (`src/compiler/arm64/insts.lisp`):** Both the ACL2 crash (`SB-ARM64-ASM::LOAD-FROM-LABEL`, line 1791) and the plain-SBCL crash (`SB-ARM64-ASM::LOAD-CONSTANT`, line 1618) actually fail **before** conditional branches, inside PC-relative `LDR Rt, label` (`ldr-str-offset-enc`, lines 1152–1155), which uses the same 19-bit signed word displacement (`±1 MiB`) to reach constants/fixups placed in the component's trailer (`finalize-segment`) without mid-segment constant islands! Conditional `B.cond` (lines 1577–1610), `CBZ`/`CBNZ` (lines 1631–1647), and `ADR` (lines 1117–1128) share the same unrelaxed `(signed-byte 19)` displacement limit.

---

## 7. Methodology & Anti-Masking Differential Fuzzing Summary

All hunt tooling and logs reside in `/Users/ember/dev/compiler-audit/hunts/sbcl-live/`:

1. **Exact VOP Lifetime Static Analyzer (`scan_vops.py` & `scan_arg_writes.py`):**
   - Modeled `src/compiler/meta-vmdef.lisp:606–615` (`parse-vop-spec` time specs, `(:inherit ...)` per-operand inheritance at lines 910–936, `signed-128-reg` even/odd register-pair parity on `arm64`, wired `:offset` temporaries like `rcx-offset`/`rax-offset`/`rdx-offset`, and `(location= a b)` guard dominance).
   - Validated against `sbcl-2.6.9` (immediately flagged `ash-right-two-words-variable` at `x86-64/arith.lisp:6306`, i.e., `SB1` / `0fd47cc68d`) and then swept all **756 `x86-64` VOPs** and **639 `arm64` VOPs** in `sbcl-2.6.10` (`vop_scan_2.6.10.txt`).
2. **Anti-Masking + Consumer-Context Differential Fuzzing (`fuzz_sbcl_2_6_10.lisp` & `fuzz_wave2_2_6_10.lisp`):**
   - Implemented `RESEARCH.md` Recommendations #7 and #9: zero outer `fit-int` masking (returning intermediate `let*` bindings directly alongside final outputs), fixnum/u64/s128/bignum boundary inputs (`±2^61..±2^65`, `±2^127..±2^128`), variable/inverted shifts, modular `(logand ... (1- (ash 1 64)))` / `(ldb (byte 64 0) ...)` and `logbitp`/comparison consumers, dynamic & static `ldb`/`dpb`/`mask-field`/`deposit-field`, multiple-value `floor`/`ceiling`/`truncate`/`round` + `catch`/`throw`, specialized `u64`/`s64`/`u32`/`bit`/`double-float` arrays, 8–18 live variables + `multiple-value-setq` loop-backs, `&rest` transforms (`%rest-ref`, `%rest-length`, `%rest-null`, `%more-arg-values`, `reverse-values-list`), `complex single-float` spills, and non-buggy SIMD constructors (`%make-simd-pack-double`/`ub64`/`ub32`), comparing `(speed 3) (safety 0)` against `(speed 0) (safety 3) (debug 3)`:

| Campaign | Platform | Compiled Fn Pairs | Differential Calls | Runtime | Value Mismatches |
|---|---|---|---|---|---|
| Wave 1 (`fuzz_sbcl_2_6_10.lisp`) | `arm64` (`SBCL 2.6.10`) | 3,000 | 18,000 | 58.10s | `0` (`fuzz_arm64_2.6.10.log`) |
| Wave 1 (`fuzz_sbcl_2_6_10.lisp`) | `x86-64` (`SBCL 2.6.10`, `hbox`) | 3,000 | 18,000 | 37.60s | `0` (`fuzz_x86_64_2.6.10.log`) |
| Wave 2 (`fuzz_wave2_2_6_10.lisp`) | `arm64` (`SBCL 2.6.10`) | 1,000 | 4,000 | 2.96s | `0` (`fuzz_wave2_arm64.log`) |
| Wave 2 (`fuzz_wave2_2_6_10.lisp`) | `x86-64` (`SBCL 2.6.10`, `hbox`) | 1,000 | 4,000 | 1.88s | `0` (`fuzz_wave2_x86_64.log`) |
| **Total** | **`arm64` + `x86-64`** | **8,000** (`16,000` compiles) | **44,000** | **100.54s** | **`0`** |

This confirms that standard integer, modular, bitfield, specialized-array, division, and non-skip `&rest` paths in SBCL 2.6.10 are solid after `0fd47cc68d`, while the static VOP lifetime audit pinpointed the exact remaining register-lifetime and backwards-move bugs (`SB-2610-1` through `SB-2610-4`) across `values.lisp`, `simd-pack*.lisp`, and `sb-bignum:%multiply-and-add`.
