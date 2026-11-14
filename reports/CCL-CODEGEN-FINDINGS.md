# Clozure CL 1.14 Compiler & ARM64 Backend Soundness Audit (`nx0`, `nx1`, `acode-rewrite`, `arm642`, `level-0/ARM64`)

## Overview

This report documents the findings of a full-source soundness audit and targeted differential fuzzing campaign of Clozure Common Lisp **1.14** beyond `compiler/optimizers.lisp`, covering:

- **Frontend & IR / Algebraic Rewrites:** `compiler/nx0.lisp`, `compiler/nx1.lisp`, `compiler/nx2.lisp`, `compiler/nx-basic.lisp`, `compiler/acode-rewrite.lisp`
- **ARM64 Code Generator & Vinsns:** `compiler/ARM64/arm642.lisp` (10,221 LOC), `compiler/ARM64/arm64-vinsns.lisp` (7,484 LOC), cross-referenced against `compiler/X86/x862.lisp`, `compiler/ARM/arm2.lisp`, and `compiler/PPC/ppc2.lisp`
- **ARM64 Runtime / Level-0 Primitives:** `level-0/ARM64/*.lisp` (`arm64-numbers`, `arm64-bignum`, `arm64-array`, `arm64-float`, `arm64-misc`, `arm64-pred`, etc.), `level-0/l0-numbers.lisp`, and `level-0/l0-bignum64.lisp`
- **Binaries Tested:**
  - CCL 1.14 `darwin-arm64` (`/Users/ember/dev/ccl/darm64cl`)
  - CCL 1.14 `linux-x86_64` (`lx86cl64` on `hbox`)
  - Cross-oracle: SBCL 2.6.10 `darwin-arm64` (`/opt/homebrew/bin/sbcl`)

We found **four new compiler bug families** (none duplicating previously known CCL-1, CCL-2, CCL-3, or the unary `truncate` family). Notably, **the three soundness bugs all trigger even at `(optimize (safety 3))`**, not merely at reckless `(safety 0)`.

---

## Executive Summary Matrix

| ID | Severity | Component & Exact Location | Policy Trigger | ARM64 CCL 1.14 | x86-64 CCL 1.14 | Summary | Reproducer |
|---|---|---|---|---|---|---|---|
| **CCL-CG-1** | **CRITICAL** (Wrong-index read/write & OOB heap corruption) | `arm642-four-untargeted-reg-forms` (`compiler/ARM64/arm642.lisp:3954`; also `ARM/arm2.lisp:3814`) | **All policies**, including `(safety 3) (speed 1)` | **FAILS** | Passes (`x862.lisp:4577` is correct) | Typo `(same-arm64-reg-p ddest breg)` instead of `cdest` clobbers index `j` with index `i` in 2D `(setf (aref ...))` and 3D `(aref ...)`. Writes/reads `[i, i]` / `[i, i, k]`; bogus `ARRAY-BOUNDS` at `(safety 3)` or silent OOB heap write at `(safety 0)` on valid indices. | `repros/ccl-arm64-aset2-aref3-reg-clobber/` |
| **CCL-CG-2** | **CRITICAL** (Silent `(safety 0)` memory unsafety at `(safety 3)`) | `nx1-expand-inline-call` (`compiler/nx0.lisp:2453`) | `(safety 3)` whenever `(space 0)` is active | **FAILS** (returns bogus objects / OOB heap words) | **FAILS** (OOB read -> `SIGBUS` core dump) | Copy-paste bug sets `(safety . ,(space-optimize-quantity old-env))` in the inlined lexical environment. Every user `inline` function (`defun`, `flet`, `labels`) is compiled at `(safety 0)` whenever `(space 0)` is active, silently eliding all bounds and type checks. | `repros/ccl-inline-space-overwrites-safety/` |
| **CCL-CG-3** | **HIGH** (IEEE-754 overflow & `-0.0` corruption) | `acode-rewrite-div2` (`compiler/acode-rewrite.lisp:369-386`) & `arm642-div2` (`arm642.lisp:7376-7386`) | `(speed >= 1)`, including `(safety 3) (speed 1)` | **FAILS** (`+Inf` -> finite; `-0.0d0` -> `+0.0d0`) | **FAILS** (suppresses `FLOATING-POINT-OVERFLOW`; `-0.0d0` -> `+0.0d0`) | Rewrites `(/ (* c1 x) c2)` -> `(* (/ c1 c2) x)` without checking that `x` is `rational`. Erases float overflow on `(/ (* 3 x) 3)` and flips `-0.0d0` to `+0.0d0` on `(/ (* 0 x) -3)`. | `repros/ccl-div2-float-rewrite-unsound/` |
| **CCL-CG-4a** | **MEDIUM** (ICE / `COMPILER-BUG`) | `arm642-fixnum-ref-double-float` (`arm642.lisp:9637-9638`, `x862.lisp:11880-11881`, `arm2.lisp:9772-9773`) | All policies (for-effect context) | **FAILS** (`COMPILER-BUG`) | **FAILS** (`COMPILER-BUG`) | Passes `(base seg nil nil)` with `base` and `seg` reversed when `vreg` is `nil`, crashing `compile`. | `repros/ccl-arm64-lowlevel-p2-bugs/` |
| **CCL-CG-4b** | **MEDIUM** (ICE + unsigned negative bit-offset shift) | `arm642-get-bit` / `arm642-set-bit` (`arm642.lisp:8161, 9131`) & `mem-*-bit*` (`arm64-vinsns.lisp:6374+`) | All policies | **FAILS** (`:U16CONST` crash) | Passes (`:s32const`) | Missing `(<= 0 byte-index)` check crashes `compile` on negative constant bit offsets (`%get-bit p -8`). Runtime `mem-*-bit*` vinsns also use `lsr #3` instead of `asr #3` (masked on macOS only by `TCR_EL1.TBI0=1`). | `repros/ccl-arm64-lowlevel-p2-bugs/` |

---

## Detailed Findings

### Finding 1 (`CCL-CG-1`): `arm642-four-untargeted-reg-forms` Register-Clobber Typo Corrupts 2D `(setf aref)` and 3D `aref` Even at `(safety 3)`

- **Location:** `compiler/ARM64/arm642.lisp:3953-3955` (also present in 32-bit ARM `compiler/ARM/arm2.lisp:3813-3815`)
- **Affected Callers:**
  - `arm642-aset2` (`compiler/ARM64/arm642.lisp:2013`) — 2D `(setf (aref ...))` on typed arrays (`fixnum`, `(unsigned-byte 8/16/32/64)`, `(signed-byte 8/16/32/64)`, `bit`, `single-float`, `double-float`, `character`, and non-memoized `t` stores)
  - `arm642-aref3` (`compiler/ARM64/arm642.lisp:2202`) — 3D `(aref ...)` on all typed arrays (including `(simple-array t (* * *))`)
- **Reproducer:** `repros/ccl-arm64-aset2-aref3-reg-clobber/`

#### Root Cause & Historical Provenance

`arm642-four-untargeted-reg-forms (seg aform areg bform breg cform creg dform dreg)` evaluates up to four subexpressions (`aform`, `bform`, `cform`, `dform`) while avoiding unnecessary register moves. When an inner subexpression naturally lands in one of the preferred target registers (`areg`, `breg`, `creg`, `dreg`) reserved for an outer deferred/pushed operand, it renames the outer operand's target register to the inner operand's unused default register.

Comparing `x862.lisp:4574-4579` against `arm2.lisp:3810-3815` and `arm642.lisp:3950-3955` exposes the exact copy-paste bug:

```lisp
;; CORRECT in compiler/X86/x862.lisp:4574-4578:
      (unless adest
        (when (same-x86-reg-p cdest areg)
          (setq areg creg)))
      (unless bdest
        (when (same-x86-reg-p cdest breg)
          (setq breg creg)))

;; BUGGY in compiler/ARM64/arm642.lisp:3950-3955 (copied from ARM/arm2.lisp:3810-3815):
      (unless adest
        (when (same-arm64-reg-p cdest areg)
          (setq areg creg)))
      (unless bdest
        (when (same-arm64-reg-p ddest breg)   ; <-- TYPO: `ddest` instead of `cdest`!
          (setq breg creg)))
```

Trace of the failure in `arm642-aset2` on `(setf (aref arr2 (funcall fn 0) cvar) (setf (svref vec cvar) 99))`:
1. Target hints: `areg = temp0` (`arr2`), `breg = arg_y` (`i`), `creg = arg_x` (`j`), `dreg = arg_z` (`newval`).
2. `aform` (`arr2`) is `aconst = T` (vstack lexical variable, deferred).
3. `bform` (`(funcall fn 0)`) is non-trivial and non-constant (`btriv = NIL`, `bconst = NIL`), so it is evaluated first and pushed/held (`bpushed`), leaving `bdest = NIL` and `breg = arg_y`.
4. `cform` (`cvar`) is `cconst = T` (vstack lexical variable not mutated by `dform`, deferred).
5. `dform` (`(setf (svref vec cvar) 99)`) loads `vec` into `arg_x`, loads `cvar` from the vstack into **`arg_y`** (recording `cvar -> arg_y` in `*arm642-gpr-locations*`), writes `99`, and places its result in `ddest = arg_x` (`ddest != breg`).
6. Now `cform` (`cvar`) is evaluated (`arm642.lisp:3947`): `arm642-one-untargeted-reg-form` finds `cvar` already live in `arg_y`, returning **`cdest = arg_y`** (`== breg`!).
7. Line 3954 checks `(same-arm64-reg-p ddest breg)` (`arg_x == arg_y` -> `NIL`) instead of `(same-arm64-reg-p cdest breg)` (`arg_y == arg_y` -> `T`), so `breg` remains `arg_y` instead of switching to `creg`.
8. Line 3959 pops/moves `bform` (`i = 0`) into `bdest = breg = arg_y`, **overwriting `cdest` (`j = 1`) with `i = 0`**!

In the resulting ARM64 machine code (`disassemble`), both `unscaled-i` and `unscaled-j` are `arg_y`:

```armasm
  (mov arg_y arg_z)             ; bdest := arg_y, CLOBBERING cdest (cvar) in arg_y!
  ...
  (asr imm0 imm0 (:$ 3))        ; dim1
  (mul imm0 arg_y imm0)         ; i * dim1
  (add arg_y imm0 arg_y)        ; i * dim1 + i  (instead of i * dim1 + j!)
```

#### Impact

1. **Silent wrong-element read/write at `(optimize (safety 3) (speed 1))`:**
   - 2D `(setf (aref arr2 (funcall fn 0) 1) ...)` writes `99` to `arr2[0, 0]`, leaving `arr2[0, 1] = 0`.
   - 3D `(aref arr3 (funcall fn 0) 1 (prog1 0 (funcall fn 0) (setf (aref u8 0 1) 0)))` returns `arr3[0, 0, 0]` (`:A000`) instead of `arr3[0, 1, 0]` (`:A010`).
2. **Bogus bounds error at `(safety 3)` & silent out-of-bounds heap memory corruption at `(safety 0)` on valid indices:**
   - On a `(5 2)` array (total size = 10 elements) with completely valid in-bounds indices `(i = 4, j = 1)`:
     - At `(safety 3)`, `check-2d-bound` checks `arg_y < dim1` (`4 < 2`) and signals a bogus `Array index 4 out of bounds` error.
     - At `(safety 0)`, `2d-unscaled-index` computes linear index `4 * 2 + 4 = 12 >= 10` and writes past the end of the array into adjacent heap memory!

#### Suggested Fix

In `compiler/ARM64/arm642.lisp:3954` (and `compiler/ARM/arm2.lisp:3814`):

```diff
       (unless bdest
-        (when (same-arm64-reg-p ddest breg)
+        (when (same-arm64-reg-p cdest breg)
           (setq breg creg)))
```

---

### Finding 2 (`CCL-CG-2`): `nx1-expand-inline-call` Copies `SPACE` Into `SAFETY`, Compiling All Inlined Functions at `(safety 0)` Under `(space 0)`

- **Location:** `compiler/nx0.lisp:2450-2455` (shared frontend — affects **all architectures**)
- **Reproducer:** `repros/ccl-inline-space-overwrites-safety/`

#### Root Cause

When CCL expands any user-defined inline function (`(declaim (inline f))` + `(defun f ...)` or local `(flet ((f ...)) (declare (inline f)) ...)` / `labels`), `nx1-expand-inline-call` (`compiler/nx0.lisp:2443-2462`) creates a fresh `lexenv` encapsulating the saved lambda expression and copies the caller's optimize quantities into `(lexenv.mdecls new-env)`:

```lisp
;; compiler/nx0.lisp:2450-2455
(setf (lexenv.mdecls new-env)
      `((speed . ,(speed-optimize-quantity old-env))
        (space . ,(space-optimize-quantity old-env))
        (safety . ,(space-optimize-quantity old-env)) ; <-- BUG: space-optimize-quantity!
        (compilation-speed . ,(compilation-speed-optimize-quantity old-env))
        (debug . ,(debug-optimize-quantity old-env))))
```

Line 2453 calls `(space-optimize-quantity old-env)` instead of `(safety-optimize-quantity old-env)`!

Consequently, whenever `(space 0)` is active in `old-env` — even when the caller explicitly declares `(declare (optimize (safety 3) (speed 3) (space 0)))` — the inlined body is compiled with `(safety . 0)` and `(speed . 3)`, which makes `(nx-reckless-p new-env)` evaluate to **`T`** (`safety = 0` and `speed >= safety`) and `(nx-trust-declarations new-env)` evaluate to **`T`**!

*(Note: Unless the inline function itself contains an explicit inner `(declare (optimize (safety 3)))`, its body inherits `new-env`'s `(safety . 0)` directly.)*

#### Impact

1. **Complete loss of memory safety at `(safety 3)` when `(space 0)` is active:**
   - Calling an inlined `(defun get-elem (v i) (svref v i))` on `#(:a :b)` with out-of-bounds index `5` under `(optimize (safety 3) (speed 3) (space 0))` omits `uuo-error-vector-bounds`:
     - On **ARM64 CCL 1.14**, it silently reads out-of-bounds heap memory without error.
     - On **x86-64 CCL 1.14**, reading and printing the returned out-of-bounds word (`#xF983FFFFFFF92D8D`) immediately faults with `SIGNAL 7` (`SIGBUS` / `CCL::INVALID-MEMORY-OPERATION`) and **dumps core**.
   - Calling an inlined `(defun add1 (x) (declare (type fixnum x)) (the fixnum (+ x 1)))` with `"not-a-fixnum"` under `(optimize (safety 3) (speed 3) (space 0))` skips fixnum tag verification and adds raw pointer bits (`8`), fabricating `#<BOGUS object>`!
2. **ACL2 Impact (`acl2.lisp:165-167, 212, 2610`):**
   - ACL2 proclaims `(space 0)` by default on CCL (`acl2.lisp:212`: `#-(or cmu sbcl) 0`).
   - ACL2's own build instructions (`acl2.lisp:165-167` and `2610`) specifically recommend building high-safety debug images on CCL with:
     ```lisp
     (defparameter cl-user::*acl2-optimize-form*
       '(OPTIMIZE (COMPILATION-SPEED 0) (DEBUG 0) (SPEED 0) (SPACE 0) (SAFETY 3)))
     ```
   - Because `(space 0)` is included, CCL silently compiles every ACL2 `defun-inline` (`FOO$INLINE`) and raw `(declaim (inline ...))` helper (`swap-stobjs-check`, `increment-file-clock-raw`, `bad-lisp-objectp`, etc.) with `(safety 0)` instead of `(safety 3)`. (In guard-verified `:logic` mode alone, ACL2's own verified guards prevent invalid inputs from reaching the body, so this does not prove `NIL` in pure `:logic` mode; however, in `:program` mode or raw system debugging where `(safety 3)` is relied upon to trap violations, safety checks inside inline functions are silently stripped.)

#### Suggested Fix

In `compiler/nx0.lisp:2453`:

```diff
       (setf (lexenv.mdecls new-env)
             `((speed . ,(speed-optimize-quantity old-env))
               (space . ,(space-optimize-quantity old-env))
-              (safety . ,(space-optimize-quantity old-env))
+              (safety . ,(safety-optimize-quantity old-env))
               (compilation-speed . ,(compilation-speed-optimize-quantity old-env))
               (debug . ,(debug-optimize-quantity old-env))))
```

---

### Finding 3 (`CCL-CG-3`): Unsound Floating-Point Rewrite `(/ (* c1 x) c2)` -> `(* (/ c1 c2) x)` in `acode-rewrite-div2` and `arm642-div2`

- **Locations:**
  - `compiler/acode-rewrite.lisp:369-386` (`acode-rewrite-div2`, shared across all architectures whenever `(speed >= 1)`, including `(safety 3) (speed 1)`)
  - `compiler/ARM64/arm642.lisp:7376-7386` (`arm642-div2`, plus analogous `x862-div2` / `ppc2-div2` / `arm2-div2`)
- **Reproducer:** `repros/ccl-div2-float-rewrite-unsound/`

#### Root Cause

In `compiler/acode-rewrite.lisp:369-386`:

```lisp
(define-acode-rewrite acode-rewrite-div2 %div (quotient dividend divisor)
  ...
  (let* ((v2 (acode-constant-p divisor)))
    (when (typep v2 '(and rational (not (eql 0))))
      (cond ((and (acode-p dividend) (eq (acode-operator dividend) (%nx1-operator mul2)))
             (collect ((other-factors))
               (let* ((operands (acode-operands dividend))
                      (const-factor nil))
                 (dolist (op operands (when const-factor
                                        (acode-rewrite-as dividend (%nx1-operator mul2)
                                                          (make-acode* (%nx1-operator fixnum) (/ const-factor v2))
                                                          (car (other-factors)))))
                   (let* ((val (and (null const-factor) (acode-constant-p op))))
                     (if (typep val 'rational)
                       (setq const-factor val)
                       (other-factors op))))))) ...))))
```

*(Note also a secondary latent bug on line 381: `(make-acode* (%nx1-operator fixnum) (/ const-factor v2))` tags `(/ const-factor v2)` with operator `fixnum` even when `(/ const-factor v2)` is a `ratio` or `bignum`, relying only on downstream code treating `fixnum`/`immediate` constants interchangeably when `fixnump` fails!)*

Crucially, `acode-rewrite-div2` checks only that `c1` (`const-factor`) and `c2` (`v2`) are `rational` — it **never checks that the remaining factor `x` is `rational`**, nor does it check `(safety 0)`. Because `*nx-do-acode-rewrites*` is enabled whenever `(> speed 0)` (including `(optimize (safety 3) (speed 1))`), `(/ (* c1 x) c2)` is rewritten to `(* (/ c1 c2) x)` for arbitrary floating-point `x`, violating IEEE-754 arithmetic in two distinct ways:

1. **Overflow / Exception Erasure (`(/ (* 3 x) 3)` -> `(* 1 x)`):**
   For `x = most-positive-double-float` (`1.7976931348623157d308`), `(* 3 x)` overflows:
   - On **ARM64 CCL 1.14** (FP overflow traps masked by default): `notinline` and `(speed 0) (safety 3)` return IEEE-754 `+Inf` (`1.0d++0`), whereas `(safety 3) (speed 1)` returns finite `1.7976931348623157d308`!
   - On **x86-64 CCL 1.14** (and SBCL 2.6.10, where FP overflow traps are enabled by default): `notinline` signals `FLOATING-POINT-OVERFLOW`, whereas `(safety 3) (speed 1)` **suppresses the `FLOATING-POINT-OVERFLOW` condition completely** and returns finite `1.7976931348623157d308`!
2. **IEEE-754 Signed-Zero Sign Flip (`(/ (* 0 x) -3)` -> `(* 0 x)`):**
   For `x = 0.0d0` (or `1.0d0`), `(* 0 0.0d0)` is `+0.0d0`, and `(/ +0.0d0 -3)` is **`-0.0d0`** (`(float-sign res) => -1.0d0`) in both `notinline` CCL and SBCL. Under `acode-rewrite-div2`, `(/ 0 -3)` folds in rational arithmetic to exact integer `0` (losing the negative sign of `-3`!), rewriting the expression to `(* 0 x)` which returns **`+0.0d0`** (`(float-sign res) => +1.0d0`) at `(safety 3) (speed 1)`!

#### Suggested Fix

Guard the associative `(/ (* c1 x) c2) -> (* (/ c1 c2) x)` rewrite in `acode-rewrite-div2` (and `arm642-div2` / `x862-div2`) so that it only fires when `(acode-form-type other trust-decls)` is a subtype of `'rational` (and use `(%nx1-operator immediate)` when `(/ const-factor v2)` is not a target `fixnum`).

---

### Finding 4 (`CCL-CG-4a` & `CCL-CG-4b`): P2 Backend Compiler Bugs in `%fixnum-ref-double-float` and `%get-bit` / `(setf %get-bit)`

- **Reproducer:** `repros/ccl-arm64-lowlevel-p2-bugs/`

#### Finding 4a: Reversed `(base seg)` Arguments in `*-fixnum-ref-double-float` When Compiled For Effect

In `compiler/ARM64/arm642.lisp:9635-9639` (as well as `compiler/X86/x862.lisp:11877-11881` and `compiler/ARM/arm2.lisp:9769-9773`, all ported from `compiler/PPC/ppc2.lisp:9113-9117` where `ppc2-form` took `form` before `seg`):

```lisp
(defarm642 arm642-fixnum-ref-double-float %fixnum-ref-double-float (seg vreg xfer base index)
  (if (null vreg)
    (progn
      (arm642-form base seg nil nil)    ; <-- BUG: signature is (arm642-form seg form vreg xfer)!
      (arm642-form index seg nil xfer))
    ...))
```

Compiling any expression where `(ccl::%fixnum-ref-double-float base index)` appears in a non-value (`for-effect`) context — e.g. `(compile nil '(lambda (v) (progn (ccl::%fixnum-ref-double-float v 0) :ok)))` — passes `seg` (a `dll-header`) as `form`, immediately aborting compilation with:
- ARM64: `CCL::COMPILER-BUG: Compiler bug or inconsistency: arm642-form ? NIL`
- x86-64: `CCL::COMPILER-BUG: Compiler bug or inconsistency: x862-form ? NIL`

**Suggested Fix:** Swap `(base seg ...)` to `(seg base ...)` and `(index seg ...)` to `(seg index ...)` in `arm642.lisp:9637-9638`, `x862.lisp:11880-11881`, and `arm2.lisp:9772-9773`.

#### Finding 4b: Missing Lower-Bound Check on Negative Constant Bit Offsets in `arm642-get-bit` / `arm642-set-bit` (Plus Unsigned `lsr` in Runtime Vinsns)

In `compiler/ARM64/arm642.lisp:8159-8164` (`arm642-get-bit`) and `9129-9135` (`arm642-set-bit`):

```lisp
(let* ((const-bit (acode-fixnum-form-p offset))
       (byte-index (if const-bit (ash const-bit -3)))
       (bit-index (if const-bit (logand const-bit 7))))
  (if (and byte-index (< byte-index 4096))   ; <-- BUG: missing (<= 0 byte-index)!
    (! mem-ref-c-bit-fixnum vreg reg byte-index bit-index)
    ...))
```

`ccl::%get-bit` and `(setf ccl::%get-bit)` support negative bit offsets (verified via `notinline` on ARM64 and inline on x86-64, where `:s32const` accepts negative byte displacements). On ARM64, however, `MEM-REF-C-BIT-FIXNUM`, `MEM-REF-C-BIT`, `MEM-SET-C-BIT-0`, and `MEM-SET-C-BIT-1` use ARM64 unsigned offset `ldrb`/`strb` (`:u16const`). When `offset = -8`, `byte-index = -1` satisfies `(< -1 4096)` and crashes `compile`:

```text
SIMPLE-ERROR: -1 : value doesn't match constraint :U16CONST in template for CCL::MEM-REF-C-BIT-FIXNUM .
```

**Related ARM64 Linux / MTE Portability Hazard in `compiler/ARM64/arm64-vinsns.lisp:6374, 6417, 6506, 6523, 6541`:**
In the variable-offset templates (`mem-ref-bit-fixnum`, `mem-ref-bit`, `mem-set-bit-0`, `mem-set-bit-1`, `mem-set-bit`), the unscaled fixnum bit offset (`tag_fixnum = 0`, shifted left by `$fixnumshift = 3`) is converted to a byte index via:

```lisp
(lsr byte-index bit-index (:$ (+ 3 arm64::fixnumshift))) ; unsigned lsr #6!
```

For a negative runtime bit offset (e.g. `-8`, represented as `-64 = #xFFFFFFFFFFFFFFC0`), unsigned `lsr #6` produces `#x03FFFFFFFFFFFFFF` (`+2^58 - 1`) instead of `-1` (`#xFFFFFFFFFFFFFFFF`)! Adding that to the 64-bit `macptr` address sets bits `63..58 = #b000011` (`0x0C00_0000_0000_0000` tag in the top byte). On **macOS ARM64**, `TCR_EL1.TBI0 = 1` (Top Byte Ignore) masks bits `63..56` during MMU translation so the load/store accidentally hits `addr - 1`; on **ARM64 Linux** with TBI disabled or ARMv8.5-A MTE tag checking enabled, any negative runtime bit offset will `SIGSEGV`! Changing `lsr` to `asr` fixes the upper bits cleanly.

**Suggested Fix:**
1. Change `(< byte-index 4096)` to `(<= 0 byte-index 4095)` in `arm642-get-bit` (`arm642.lisp:8161`) and `arm642-set-bit` (`arm642.lisp:9131`).
2. Change `lsr` to `asr` on `byte-index` in `mem-ref-bit-fixnum`, `mem-ref-bit`, `mem-set-bit-0`, `mem-set-bit-1`, and `mem-set-bit` (`arm64-vinsns.lisp:6374, 6417, 6506, 6523, 6541`).

---

## ACL2 Guard-Verified Soundness Assessment

We specifically audited `/Users/ember/dev/acl2-fix/ccl-worktree/` to check whether any of `CCL-CG-1` through `CCL-CG-4` can be exploited from guard-verified `:logic` mode in ACL2 (`saved_acl2` on CCL 1.14) to prove `(defthm nil-proved nil)` without trust tags:

1. **`CCL-CG-1` (2D `aset2` / 3D `aref3` register clobber):** **Cannot prove `NIL` in ACL2 `:logic` mode.**
   - ACL2's `defstobj` array fields (`basis-a.lisp:8345-8354`) strictly enforce 1-dimensional `(simple-array etype (*))` arrays (`simple-array-type` signals a hard error if `(not (= (length dimensions) 1))`).
   - ACL2's built-in 2D functional arrays (`aref2` / `aset2` in `axioms.lisp:13492, 13748`) declare their backing cache as `(array * (* *))` (wildcard element type `*`, which compiles to an out-of-line `.SParef2` / `.SPaset2` subprim call via `arm642-four-targeted-reg-forms` rather than `arm642-four-untargeted-reg-forms`), and pass plain lexical variables `i, j, val` (`btriv = T, ctriv = T`).
2. **`CCL-CG-2` (`inline` functions compiled at `(safety 0)` when `(space 0)` is active):** **Does not prove `NIL` in guard-verified `:logic` mode, but silently defeats `(safety 3)` in `:program` mode / debug builds.**
   - In guard-verified `:logic` mode, ACL2 verifies type and array-bounds guards theorem-provingly before raw Lisp execution, so eliding runtime bounds/type checks does not cause unsound evaluation on guard-verified calls.
   - However, ACL2 sets `(space 0)` by default on CCL (`acl2.lisp:212`) and explicitly recommends `(OPTIMIZE ... (SPACE 0) (SAFETY 3))` in `acl2.lisp:165-167` for safe builds; `CCL-CG-2` silently strips `(safety 3)` inside every `defun-inline` (`$INLINE`) and raw `(declaim (inline ...))` helper.
3. **`CCL-CG-3` (`(/ (* c1 x) c2)` float rewrite):** **Cannot prove `NIL` in ACL2 `:logic` mode.**
   - Standard ACL2 logic values (`acl2-numberp`) are exact rationals or complex rationals, where `(/ (* c1 x) c2) = (* (/ c1 c2) x)` holds identically; ACL2's `df` (double-float) operations use dedicated constrained/wrapper primitives (`df*`, `df/`, `to-df`) with explicit finite guards rather than untyped `cl:/` on rational-float products.

---

## Differential Fuzzing & Verified-Clean Subsystems

The differential harness in `/Users/ember/dev/compiler-audit/hunts/ccl-codegen/` (`fuzz.lisp`, `cross_sbcl.lisp`, `fuzz_extra.lisp`, `cross_sbcl_extra.lisp`) executed **76,687 multi-policy differential checks** across 5 CCL compilation modes (`NOTINLINE`, `(speed 0)(safety 3)`, `(speed 1)(safety 1)`, `(speed 3)(safety 3)(space 0)`, and `(speed 3)(safety 0)(space 0)`) and **16,974 cross-oracle checks** against SBCL 2.6.10, confirming **zero unexpected discrepancies** across all of the following subsystems:

- **Bitfield & Shift Seams (`Suite A`):** `ash` (left/right, constant & variable counts across `-2^62 .. +128`, fixnum/u64/s64/bignum seams `0, 1, 59, 60, 61, 63, 64, 65, 128`), `ldb`, `dpb`, `mask-field`, `deposit-field` (constant & variable `byte` specifiers, width `0`, width `60..128`, negative integers), `logbitp`, `logtest`, `logcount`, `integer-length`, `isqrt`, `gcd`, `lcm`, `expt`, and all 16 `boole` / `lognand` / `lognor` / `logandc1` / `logandc2` / `logorc1` / `logorc2` / `logeqv` operations.
- **Side Effects in Algebraic Identities (`Suite B`):** Verified that `acode-rewrite` and `nx1` **properly preserve side effects** (`incf`, `setq`, `(setf svref)`) in dead-value positions (`(* (incf s x) 0)`, `(logand (incf s x) 0)`, `(logior (incf s x) -1)`, `(boole boole-clr ...)`, `(boole boole-2 ...)`, `(ash 0 (incf s x))`, `(ldb (byte 0 5) (incf s x))`, `(dpb (incf s x) (byte 0 5) y)`, `(expt (incf s x) 0)`, `(expt 1 (incf s x))`) via `acode-wrap-in-progn` / `acode-side-effect-free-p`.
- **Multiple-Value Propagation Outside `optimizers.lisp` (`Suite C` & `Suite J`):** Verified `values`, `multiple-value-list`, `multiple-value-bind`, `Multiple-value-prog1`, `nth-value`, `if`/`progn`/`let` tail MV forwarding, `catch`/`throw` MV, `unwind-protect` MV, and binary `truncate`/`floor`/`ceiling`/`round` across `nx1` and `arm642`.
- **1D Specialized Vectors, Bit-Vectors, Strings, Complex Floats & Random ASTs (`Suites D, E, F, G, H, I`):** Verified 16 simple and displaced 1D specialized array element types (`t`, `bit`, `u8/s8`, `u16/s16`, `u32/s32`, `u64/s64`, `fixnum`, `single-float`, `double-float`, `(complex single-float)`, `(complex double-float)`, `character`), 135-bit `simple-bit-vector` logical operations (`bit-and`..`bit-orc2`), `schar`/`(setf schar)`/`replace`/`fill`/`subseq`, complex float arithmetic, float decomposition/rounding, and 300 random stateful/bitwise/arithmetic ASTs.
