# Wave-2 Lane C: Z3 / SMT Symbolic Equivalence & Interval-Transfer Verification ("Alive2-Lite") for SBCL 2.6.10 & CCL 1.14

**Author:** `@z3-compiler-eq` (Wave-2 Lane C)  
**Solver:** Z3 `5.4.1` (`QF_BV`, `QF_FP`, `QF_FPBV`, `QF_LIA`, `QF_NIA`)  
**Targets Verified:**
- **SBCL 2.6.10** (`0fd47cc68daff8329bef1cdc40f35e616cf026e6`): `arm64-darwin` (`/opt/homebrew/bin/sbcl`) and `x86-64-linux` (`hbox:/home/hbox/ca-sbcl-root/dl-2.6.10/...`)
- **CCL 1.14** (`23c9edcff62ed9480970cb88704253ab90718083`): `arm64-darwin` (`/Users/ember/dev/ccl/darm64cl`)
- **ACL2 Version 8.7+** (`1d2b39a424`): pure guard-verified `saved_acl2` hosted on SBCL 2.6.10

---

## 1. Executive Summary

Random differential fuzzing across $2^{64}$ integers or $2^{128}$ IEEE-754 floating-point pairs misses measure-zero corner cases: equality-lattice coarsening across mixed representations (`1` vs `1.0d0`, `-0.0d0` vs `+0.0d0`, `#\a` vs `#\A`, distinct equal bignums), singleton `[lo, hi]` interval derivations on `0.0d0 / 0.0d0 = NaN` or rounding-mode signed zeros, and AArch64 `FCMP` unordered `NZCV = 0011` condition-code collisions on quiet `NaN`.

We built two standalone Python Z3 symbolic equivalence & interval-transfer verification suites totaling **67 formal SMT checks** (`44` for SBCL 2.6.10, `23` for CCL 1.14):

- `/Users/ember/dev/compiler-audit/hunts/z3-compiler-eq/verify_sbcl_z3.py` → `sbcl_z3_results.json` (**44 checks**: **10 `SAT` bugs**, **34 `UNSAT` formal proofs**)
- `/Users/ember/dev/compiler-audit/hunts/z3-compiler-eq/verify_ccl_z3.py` → `ccl_z3_results.json` (**23 checks**: **5 `SAT` bugs**, **18 `UNSAT` formal proofs**)

Every single `SAT` counterexample emitted by Z3 was turned into a **zero-UB live compiled Common Lisp reproducer** at safe `(optimize (speed 1) (safety 3))`, uncovering **3 new compiler soundness bug families** (none overlapping prior `SBCL.md`, `CCL.md`, `CCL-OPTIMIZERS.md`, or `LEDGER.md` entries) and **1 pure guard-verified proof of `(defthm nil-proved nil)` in ACL2 8.7+ on SBCL 2.6.10**:

| ID | Target & Scope | Compiler Pass / `file:line` | Default FPU & `(safety 3)`? | Impact Summary | Standalone Reproducer |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **Z3-1** | **SBCL 2.6.10** (`arm64` + `x86-64`) | `inherit-equality-p` + float `equality-constraint` (`src/compiler/equality-constraints.lisp:26-31, 153-163, 535-537, 575-577`) | **YES** (6 of 7 cases; zero declarations!) | Chains `(eql y z)` + `(= x y)` / `(char-equal x y)` into `(eql x z)` / `(char= x z)` / `(eq x z)`; folds `(eql qNaN qNaN)` to `NIL` after `(not (= qNaN qNaN))` and `(= qNaN qNaN)` to `T` after `(eql qNaN qNaN)` | `repros/z3-sbcl-equality-constraints-unsound/run.sh` |
| **Z3-1-ACL2** | **ACL2 8.7+ on SBCL 2.6.10** | Guard-verified `1*` function calling `cl:char-equal` (`axioms.lisp:18530` + SBCL `equality-constraints.lisp:153-163`) | **YES** (`:ttag nil`, `:skip-proofs-seen nil`) | **Proves `(defthm nil-proved nil)`** (`Q.E.D.` in 0.00s) in pure guard-verified ACL2 with zero trust tags or raw escapes | `repros/z3-acl2-sbcl-char-equal-nil/run.sh` |
| **Z3-2** | **SBCL 2.6.10** (`arm64` + `x86-64`) | `same-arg` float `derive-type` (`src/compiler/srctran.lisp:2026-2055, 2171-2185, 2560-2585, 2666-2715` + `float-tran.lisp:1864-1960`) | **Compile-time `WARNING`: YES**; Runtime: masked / `RTN` | Emits bogus full `WARNING` (`compile-file` failure) on `(truncate/floor/ceiling x x)` for `double-float`; folds `(/ 0.0d0 0.0d0)` / `(ftruncate 0.0d0 0.0d0)` `NaN` to `1.0d0`; folds `(- x x)` under `:negative-infinity` to `+0.0d0` instead of `-0.0d0` | `repros/z3-sbcl-same-arg-div-derive-type/run.sh` |
| **Z3-3** | **CCL 1.14** (`arm64`) | AArch64 `FCMP` condition-code lowering (`compiler/ARM64/arm642.lisp:477-485, 7845-7858, 9878-9885, 9915-9920` + `l0-numbers.lisp:359-368, 1160-1172`) | **YES** (all 17 cases under default FPU!) | Reuses signed-integer `cond-lt` / `cond-le` on `FCMP` (`NZCV=0011` on `NaN`): `(< qNaN 1.0d0) => T`, `(<= 0.0d0 qNaN 1.0d0) => T`, `(> qNaN 0) => T`, `min`/`max` differential miscompilation, and **silent `(truncate 1d+-0) => 0` / `(ceiling 1d+-0) => 1`** instead of signaling `FLOATING-POINT-INVALID-OPERATION` | `repros/z3-ccl-arm64-fp-nan-unordered/run.sh` |

Equally important, **52 Z3 checks returned `UNSAT`**, providing machine-checked soundness proofs across $2^{64}$ bitvectors, Presburger 64-bit magic-multiplier arithmetic, and mixed-sign interval transfer functions — notably proving that SBCL 2.6.10's modernized O(1) `bitops-derive-type.lisp` bounds (historically notorious in SBCL, e.g., `lp#1199127`), `ash-derive-type-aux`, 64-bit Granlund–Montgomery signed/unsigned constant division (including intermediate `truly-the` overflow-freedom), and CCL 1.14's `nx0` interval arithmetic, `%iash`, `%fixnum-signum`, `%fixnum-intlen`, and `UBFM`/`BFM` bitfield lowering are **formally sound**.

---

## 2. Confirmed Bug Families & Z3 Counterexamples

### Bug Family 1 (`Z3-1` & `Z3-1-ACL2`): SBCL 2.6.10 Equivalence-Lattice Coarsening & Quiet-`NaN` Constraint Inversions (`src/compiler/equality-constraints.lisp`)

#### 2.1 Root Cause A: `inherit-equality-p` Returns `from` Instead of the Equivalence-Lattice Meet

In `src/compiler/equality-constraints.lisp:153-163` (introduced in commit `ac267f217` *"Better propagation of equality constraints on LVARs"* and extended in `d22e9121c`):

```lisp
(defun inherit-equality-p (new from not-p &optional (min-amount 0) max-amount (from-amount 0))
  (unless min-amount
    (setf min-amount 0))
  (unless from-amount
    (setf from-amount 0))
  (case new
    ((char= char-equal . #.+eq-ops+)   ; +eq-ops+ = (eq eql =)
     (unless not-p
       (values from from-amount)))     ; <--- BUG: returns FROM instead of meet(NEW, FROM)!
```

When constraint propagation already holds a positive equality constraint `(FROM y z)` (`not-p = nil`) for a **finer** equivalence relation `FROM` $\in \{\texttt{eq}, \texttt{eql}, \texttt{char=}\}$ and subsequently enters the `then` branch of `(NEW x y)` for a **coarser** equivalence relation `NEW` $\in \{\texttt{=}, \texttt{char-equal}\}$, `add-eq-constraint` calls `(inherit-equality-p new from nil ...)`, receives `FROM`, and records `(FROM x z)`!

In Common Lisp, $\{\texttt{eq} \subsetneq \texttt{eql} \subsetneq \texttt{=}\}$ (on non-`NaN` numbers) and $\{\texttt{eq}/\texttt{eql}/\texttt{char=} \subsetneq \texttt{char-equal}\}$ (on characters) form a strict hierarchy. If $x \sim_{\text{coarse}} y$ and $y \sim_{\text{fine}} z$, transitivity guarantees only $x \sim_{\text{coarse}} z$, **never** $x \sim_{\text{fine}} z$.

Z3 (`verify_sbcl_z3.py`, checks 1–4) synthesized four minimal counterexamples in `< 75 ms` total, all miscompiling at `(optimize (speed 1) (safety 3))` with **zero type declarations**:

1. **Cross-type numeric contagion (`eq_constraints_inherit_int_vs_float`, `SAT` in 74.5 ms):**
   - Input: `x = 1`, `y = 1.0d0`, `z = 1.0d0`.
   - `(eql y z)` is `T` and `(= x y)` is `T`, so SBCL derives `(eql x z)` and folds `(eql 1 1.0d0)` to **`T`** (expected: **`NIL`**).
2. **IEEE-754 signed zeros (`eq_constraints_inherit_signed_zero`, `SAT` in 8.8 ms):**
   - Input: `x = -0.0d0` (`0x8000000000000000`), `y = +0.0d0` (`0x0`), `z = +0.0d0` (`0x0`).
   - `(eql +0.0d0 +0.0d0)` is `T` and `(= -0.0d0 +0.0d0)` is `T`, so SBCL folds `(eql -0.0d0 +0.0d0)` to **`T`** (expected: **`NIL`**).
3. **Case-insensitive vs case-sensitive characters (`eq_constraints_inherit_char_equal_acl2`, `SAT` in 2.7 ms):**
   - Input: `x = #\a`, `y = #\A`, `z = #\A`.
   - `(eql #\A #\A)` is `T` and `(char-equal #\a #\A)` is `T`, so SBCL derives `(eql #\a #\A)` and folds **both** `(eql #\a #\A)` and `(char= #\a #\A)` to **`T`** (expected: **`NIL`**).
4. **Distinct heap-allocated bignums (`eq_constraints_inherit_bignum_eq`, `SAT` in 1.6 ms):**
   - Input: two freshly consed bignums `b1 = 2^100 + 1` and `b2 = 2^100 + 1` (`(not (eq b1 b2))`, `(= b1 b2)`).
   - Testing `(eq b2 b2)` followed by `(= b1 b2)` derives `(eq b1 b2)` and folds it to **`T`** (expected: **`NIL`**).

#### 2.2 Weaponization in Pure Guard-Verified ACL2 8.7+ (`(defthm nil-proved nil)`)

In ACL2's kernel (`axioms.lisp:18530`), `char-equal` is defined inside `#+acl2-loop-only`, meaning that once an ACL2 function's guards `(and (characterp x) (characterp y) (characterp z))` are verified, its compiled `1*` executable counterpart calls Common Lisp `cl:char-equal` directly on raw characters. Defining and compiling:

```lisp
(defun char-eq-coarsen (x y z)
  (declare (xargs :guard (and (characterp x) (characterp y) (characterp z))))
  (if (eql y z)
      (if (char-equal x y)
          (eql x z)
          nil)
      nil))
(comp 'char-eq-coarsen)
```

causes `(char-eq-coarsen #\a #\A #\A)` to evaluate to **`T`** via the SBCL-miscompiled `1*` executable counterpart, while instantiating `(:definition char-eq-coarsen)` reduces `(char-eq-coarsen #\a #\A #\A)` to **`NIL`** in the logic. ACL2 immediately accepts `(defthm nil-proved nil :rule-classes nil)` in **0.00 seconds (15 prover steps)** with `ttag = NIL`, `skip-proofs-seen = NIL`, and `redef-seen = NIL` (`/Users/ember/dev/compiler-audit/repros/z3-acl2-sbcl-char-equal-nil/run.sh`).

#### 2.3 Root Cause B: IEEE-754 Quiet-`NaN` Inversions Under Default FPU Mode (`equality-constraints.lisp:26-31, 535-537, 575-577`)

In the same file, Z3 (`QF_FP` `Float64`, checks 5–7) found three IEEE-754 `NaN` soundness bugs:

1. **Line 535–537 (`eql` optimizer):** When `(= x y)` is false (`not-p = t`), SBCL folds `(eql x y)` to **`NIL`**. For `x = y = qNaN` (`0x7ff8000000000001`), IEEE-754 `(= qNaN qNaN)` is `NIL`, while CL `(eql qNaN qNaN)` is **`T`**!
2. **Line 575–577 (`=` optimizer):** When `(eql x y)` is true (`not-p = nil`), SBCL folds `(= x y)` to **`T`**. For `x = y = qNaN`, `(eql qNaN qNaN)` is `T`, while `(= qNaN qNaN)` is **`NIL`**!
3. **Line 26–31 (`not-operator`):** Maps `<` to `>=` and `<=` to `>` unconditionally, folding `(>= qNaN 1.0d0)` to **`T`** in the `else` branch of `(< qNaN 1.0d0)`.

**Crucial Default-FPU Observation (Verified on Both `arm64-darwin` and `x86-64-linux`):** Cases (1) and (2) trigger under SBCL 2.6.10's **out-of-the-box default FPU mode** on **both** architectures:
- On `arm64-darwin`, hardware FPCR exception trap-enable bits are RAZ/WI (`(:TRAPS NIL ...)`), so `FCMP` never traps on quiet `NaN`.
- On `x86-64-linux` (`hbox`), even though SBCL enables `:TRAPS (:OVERFLOW :INVALID :DIVIDE-BY-ZERO)` by default, SBCL compiles float `=` to **`UCOMISD`** (unordered compare), which by Intel/AMD architecture specification signals `#IA` *only* on signaling `SNaN` and **never traps on quiet `QNaN`**! Thus `(= qnan qnan)` cleanly returns `NIL` without trapping, and SBCL's equality-constraint pass miscompiles `(eql qnan qnan)` to `NIL` and `(= qnan qnan)` to `T` under default settings on both platforms.

#### 2.4 Z3-Verified Fix for `equality-constraints.lisp`

1. In `inherit-equality-p` (`equality-constraints.lisp:158-160`), compute the partial-order **lattice meet** of `new` and `from` instead of returning `from` (and block chaining `=` when operands may be `NaN` or mixed signed-zero/rational types unless coarsened to `=` on non-`NaN` reals):
   - $\text{meet}(\texttt{eq}, \texttt{eq}) = \texttt{eq}$;
   - $\text{meet}(\texttt{eql}, \texttt{eq}/\texttt{eql}/\texttt{char=}) = \texttt{eql}$;
   - $\text{meet}(\texttt{char=}, \texttt{eq}/\texttt{eql}/\texttt{char=}) = \texttt{char=}$;
   - $\text{meet}(\texttt{char-equal}, \text{any char/eq op}) = \texttt{char-equal}$;
   - $\text{meet}(\texttt{=}, \texttt{eq}/\texttt{eql}/\texttt{=}) = \texttt{=}$ (only when `from` and `new` share a non-`NaN` numeric domain; otherwise `nil`).
   - Z3 check `eq_constraints_fixed_lattice_meet_sound` (`verify_sbcl_z3.py`) proved this lattice meet **`UNSAT` (sound)** in `2.67 ms`.
2. Guard `(= . nil) -> (eql => nil)` (`:535`), `(eql . t) -> (= => t)` (`:575`), and `not-operator` `<`/`<=` inversions (`:26-31`) on neither LVAR intersecting `float` (or float `NaN` being excluded).

---

### Bug Family 2 (`Z3-2`): SBCL 2.6.10 `same-arg` Float `derive-type` Soundness & Full `WARNING` Bugs (`src/compiler/srctran.lisp` & `float-tran.lisp`)

#### 3.1 Root Cause

When both arguments of a binary arithmetic/rounding call reference the same `leaf` (`(same-leaf-ref-p x y)` $\implies$ `same-arg = t`), `src/compiler/srctran.lisp` takes fast-path interval shortcuts that violate IEEE-754 semantics in three places:

1. **Compile-time bogus full `WARNING` (`compile-file` `failure-p = T`) on `(truncate x x)`, `(floor x x)`, `(ceiling x x)` for `double-float` (`srctran.lisp:2560-2585` + `float-tran.lisp:1864-1960`):**
   - Compiling `(lambda (x) (declare (optimize (speed 1) (safety 3)) (type double-float x)) (truncate x x))` causes `truncate-derive-type-quot-aux` (`srctran.lisp:2564`) to derive quotient type `(INTEGER 1 1)`.
   - Simultaneously, `float-tran.lisp` expands two-arg float `truncate`/`floor`/`ceiling` into a fixnum-range branch plus an out-of-fixnum-range fallback `(sb-bignum:unary-truncate-double-float-to-bignum-div div x f)` whose declared return type is `(VALUES BIGNUM DOUBLE-FLOAT &OPTIONAL)`.
   - Because SBCL intersects the outer `(VALUES (INTEGER 1 1) T &OPTIONAL)` assertion into both branches before dead-branch elimination can prove `div = (/ x x)` fits in a fixnum (which isn't even true when `x = 0.0d0` or `±Inf` → `NaN`!), IR1 sees `BIGNUM` $\cap$ `(INTEGER 1 1)` $= \emptyset$ and emits a **full `WARNING`** (`Caught WARNING: Derived type of (SB-BIGNUM:UNARY-TRUNCATE-DOUBLE-FLOAT-TO-BIGNUM-DIV ...) is (VALUES BIGNUM ...), conflicting with its asserted type (VALUES (INTEGER 1 1) ...)`), breaking `asdf:compile-system` / `(compile-file ...)` at default safety without ever calling the function!
2. **Runtime `0.0d0 / 0.0d0 = NaN` folded to `1.0d0` (`srctran.lisp:2171-2185, 2560-2585, 2666-2715`):**
   - In `/-derive-type-aux`, `truncate-derive-type-quot-aux`, `fceiling`, and `ffloor`, when `same-arg = t` and `x` is any bounded float interval such as `(double-float -1.0d0 1.0d0)`, SBCL derives singleton `(double-float 1.0d0 1.0d0)` (and remainder `(double-float 0.0d0 0.0d0)`), forgetting that `0.0d0` $\in [-1.0d0, 1.0d0]$ and **`(/ 0.0d0 0.0d0)` is `NaN`**!
   - Z3 (`srctran_div_same_arg_bounded_float`, `SAT` in 3.26s; `srctran_ftruncate_ffloor_fceiling_same_arg`, `SAT` in 5.03s) produced witness `x = +0.0d0` (`0x0`). Under masked traps on both `arm64-darwin` and `x86-64-linux`, compiled `(/ x x)`, `(ftruncate x x)`, `(ffloor x x)`, and `(fceiling x x)` constant-fold `NaN` into **`1.0d0`** (and remainder **`0.0d0`**)!
3. **Runtime `(- x x)` signed-zero misfolding under `:rounding-mode :negative-infinity` (`srctran.lisp:2026-2055`):**
   - In `--derive-type-aux`, when `same-arg = t` and `(bounded-numeric-type-p x)`, SBCL constructs `(make-interval :low 0 :high 0)` and converts it to `(double-float 0.0d0 0.0d0)` with **`:normalize-zeros nil`** (`+0.0d0` only, excluding `-0.0d0`!).
   - By IEEE-754-2019 §6.3, under `roundTowardNegative` (`:rounding-mode :negative-infinity`), $x - x = \mathbf{-0.0}$ for every finite floating-point number $x$! Z3 (`srctran_sub_same_arg_rtn_signed_zero`, `SAT` in 13.4 ms) found finite witnesses where SBCL constant-folds `(- x x)` to `+0.0d0` (`(float-sign (- x x)) => +1.0d0`, `(eql (- x x) -0.0d0) => NIL`), contradicting `(- x y)` at `x = y = 1.0d0` (`-1.0d0`, `T`). (Z3 also proved in `9.4 ms` that under `RNE`, finite `x - x` is always `+0.0`.)

#### 3.2 Recommended Fix for `srctran.lisp`

- Guard all `same-arg` division/truncation singleton `1` / `1.0` shortcuts (`/-derive-type-aux`, `truncate-derive-type-quot-aux`, `truncate-derive-type-rem-aux`, `floor-quotient-bound-aux`, `ceiling-quotient-bound-aux`, `floor-rem-bound-aux`, `ceiling-rem-bound-aux`) on **both** `(bounded-numeric-type-p x)` (excluding `±Inf` and `NaN` for unbounded `double-float`) **and** `(not (interval-contains-p 0 x-interval))` (excluding `0 / 0`!).
- In `--derive-type-aux` (`srctran.lisp:2041-2055`), pass `:normalize-zeros t` (yielding `(double-float -0.0d0 0.0d0)`) when deriving float types for `(- x x)`, since dynamic FPU rounding mode may be `:negative-infinity`.

---

### Bug Family 3 (`Z3-3`): CCL 1.14 ARM64 IEEE-754 Unordered `NaN` Condition-Code Miscompilation (`compiler/ARM64/arm642.lisp` & `level-0/l0-numbers.lisp`)

#### 4.1 Root Cause: Signed-Integer Condition Codes Applied to AArch64 `FCMP`

Per the ARMv8-A Architecture Reference Manual (Section C1.2.3, *Floating-point comparisons*), `FCMP Dn, Dm` sets the condition flags `NZCV` as follows:

| IEEE-754 Relation | `N` | `Z` | `C` | `V` | `NZCV` |
| :--- | :-: | :-: | :-: | :-: | :-: |
| $x = y$ (Ordered Equal) | `0` | `1` | `1` | `0` | `0110` |
| $x < y$ (Ordered Less Than) | `1` | `0` | `0` | `0` | `1000` |
| $x > y$ (Ordered Greater Than) | `0` | `0` | `1` | `0` | `0010` |
| **Unordered ($x$ or $y$ is `NaN`)** | **`0`** | **`0`** | **`1`** | **`1`** | **`0011`** |

Notice that while `arm642-%natural<>` (`compiler/ARM64/arm642.lisp:7840-7843`) explicitly translates condition codes to unsigned AArch64 codes via `arm64-cr-bit-to-arm64-unsigned-cr-bit`, all three floating-point comparison generators — `arm642-double-float-compare` (`arm642.lisp:7845-7850`), `arm642-single-float-compare` (`arm642.lisp:7852-7857`), and `arm642-short-float-compare` (`arm642.lisp:9915-9920`) — pass the **signed-integer** condition codes from `condition-to-arm64-cr-bit` (`:477-485`) / `condition-to-arm64-cond-bit` (`:9878-9885`) directly to `FCMP`:

- `:LT` $\to$ `(values arm64::cond-lt t)` (`0b1011`, predicate `N != V`). On unordered `NaN` (`NZCV = 0011`, `N = 0, V = 1`), `N != V` is **TRUE**!
- `:LE` $\to$ `(values arm64::cond-gt nil)` $\to$ `arm64::cond-le` (`0b1101`, predicate `Z == 1 || N != V`). On unordered `NaN` (`NZCV = 0011`), `Z == 1 || N != V` is **ALSO TRUE**!
- Meanwhile, `:GT` (`cond-gt`, `Z == 0 && N == V`) and `:GE` (`cond-ge`, `N == V`) evaluate to `FALSE` on `0011` (`0 == 1` is false).

Because Apple Silicon / AArch64 hardware implements FPCR exception trap-enable bits as RAZ/WI (`(ccl:get-fpu-mode)` has `:overflow nil :invalid nil :divide-by-zero nil` by default), **every quiet `NaN` (`1d+-0`, `1s+-0`) triggers these miscompilations under CCL 1.14's default FPU mode at `(optimize (speed 1) (safety 3))`!**

#### 4.2 Cascade of 17 Confirmed Miscompilations & Runtime Corruptions (`repros/z3-ccl-arm64-fp-nan-unordered/run.sh`)

Z3 (`verify_ccl_z3.py`, checks 1–9) identified the primary `FCMP` failures in `2.4–10.8 ms` and traced four severe downstream cascades, all 17 of which are confirmed live on `/Users/ember/dev/ccl/darm64cl`:

1. **Direct `<`, `<=`, and `not` inversions (7 cases):**
   - `(< 1d+-0 1.0d0) => T`, `(< 1.0d0 1d+-0) => T`, `(< 1d+-0 1d+-0) => T`, single-float `(< 1s+-0 1.0s0) => T`.
   - `(<= 1d+-0 1.0d0) => T`, `(<= 1.0d0 1d+-0) => T`.
   - Branch inversion `(if (not (< 1d+-0 1.0d0)) :not-lt :lt) => :LT` (because `cbranch-false` flips bit 0 of `cond-lt` to `cond-ge`, which is `FALSE` on `0011`, so it does not branch!).
2. **Broken relational anti-symmetry & mixed fixnum/float comparison (3 cases):**
   - `(< 1d+-0 1.0d0) => T` while `(> 1.0d0 1d+-0) => NIL`; `(<= 1d+-0 1.0d0) => T` while `(>= 1.0d0 1d+-0) => NIL`.
   - Mixed `(> 1d+-0 0) => T` (while `(> 1d+-0 0.0d0) => NIL`)! In `fixnum-dfloat-compare` (`level-0/l0-numbers.lisp:359-368`), `(cond ((< 0.0d0 dfloat) -1) ((= 0.0d0 dfloat) 0) (t 1))` evaluates `(< 0.0d0 1d+-0)` to **`T`**, returning `-1` (`0 < NaN`, i.e., `NaN > 0`)!
3. **Range-guard bypass (1 case):**
   - `(if (<= 0.0d0 1d+-0 1.0d0) :in-unit-interval :rejected)` returns **`:IN-UNIT-INTERVAL`**, allowing `NaN` straight past `[0, 1]` bounds checks!
4. **Differential miscompilation between generic and open-coded `MIN` / `MAX` (2 cases):**
   - `(notinline min)` on `(1d+-0, 1.0d0)` returns **`1.0d0`** (generic `min` tests `(< y x)` $\to$ `(< 1.0d0 1d+-0) => T` $\to$ `y = 1.0d0`), whereas `(declare (double-float x y)) (min x y)` open-codes `(if (< x y) x y)` (`compiler/optimizers.lisp:1812`) $\to$ `(< 1d+-0 1.0d0) => T` $\to$ **`1d+-0` (`NaN`)**! Symmetric flip occurs for `max` (`1d+-0` vs `1.0d0`).
5. **Silent `NaN` $\to$ Integer Corruption in `TRUNCATE`, `FLOOR`, `CEILING`, and `ROUND` (4 cases):**
   - In `%unary-truncate` (`level-0/l0-numbers.lisp:1160-1172`):
     ```lisp
     (if (and (< (the double-float number) +4.611686018427388d18)
              (< -4.611686018427388d18 (the double-float number)))
       (%truncate-double-float->fixnum number)   ; <--- FAST PATH: raw `FCVTZS imm0, d0`!
       (%truncate-double-float number))          ; <--- SLOW PATH: checks exponent 2047 & signals error!
     ```
   - Because **both** `<` comparisons evaluate to **`T`** on `1d+-0`, `%unary-truncate` routes `NaN` into the unguarded fast path `%truncate-double-float->fixnum` (`level-0/ARM64/arm64-numbers.lisp:43-47`), executing AArch64 `FCVTZS imm0, d0`, which hardware-converts `NaN` to **`0`** without signaling!
   - Worse still, `(ceiling 1d+-0)` then tests `(< 0.0d0 rem)` on `rem = 1d+-0` (`=> T`) and increments the quotient, so under default FPU mode:
     - `(truncate 1d+-0)` $\implies$ **`0, 1D+-0`**
     - `(floor 1d+-0)` $\implies$ **`0, 1D+-0`**
     - **`(ceiling 1d+-0)` $\implies$ `1, 1D+-0`**
     - `(round 1d+-0)` $\implies$ **`0, 1D+-0`**
     instead of signaling `FLOATING-POINT-INVALID-OPERATION`!

#### 4.3 Z3-Verified Zero-Overhead AArch64 Condition-Code Fix

A subtle constraint in CCL's ARM64 backend (`arm64-vinsns.lisp`: `compare-double-float-cbranch` and `cond->boolean`) is that `true-p = nil` negates a condition by **inverting bit 0** (`cr-bit ^ 1`), which in AArch64 hardware computes the **exact logical negation** of the 4-bit condition test across all 16 `NZCV` states. Therefore, an IEEE-754 comparison `op` can use `(cr-bit, true-p)` without extra instructions if and only if the effective AArch64 condition `eff = cr-bit if true-p else (cr-bit ^ 1)` is `FALSE` on `0011` (`NaN`), so its hardware inverse `eff ^ 1` is automatically `TRUE` on `0011` (`Not(op)` in `cbranch-false`!).

Z3 (`verify_ccl_z3.py`, checks 10–15) exhaustively verified across all $2^{128}$ `Float64 × Float64` pairs (`UNSAT` in `0.36–17.75 ms` per operator, covering both `cond->boolean` value materialization and `cbranch-true`/`cbranch-false` branching) that the following 6-entry floating-point condition map has **zero instruction overhead** and **100% IEEE-754 compliance**:

| ACODE Cond | Current CCL `(cr-bit, true-p)` | Bug on `NaN` (`0011`)? | **Z3-Proved FP `(cr-bit, true-p)`** | Effective AArch64 Cond | `NZCV` Predicate | Value on `NaN` (`0011`) |
| :---: | :--- | :---: | :--- | :---: | :--- | :---: |
| `:EQ` | `(cond-eq, t)` | Sound | `(arm64::cond-eq, t)` | `EQ` (`0000`) | `Z == 1` | `FALSE` (inv `NE`: `TRUE`) |
| `:NE` | `(cond-eq, nil)` | Sound | `(arm64::cond-eq, nil)` | `NE` (`0001`) | `Z == 0` | `TRUE` (inv `EQ`: `FALSE`) |
| `:GT` | `(cond-gt, t)` | Sound | `(arm64::cond-gt, t)` | `GT` (`1100`) | `Z == 0 && N == V` | `FALSE` (inv `LE`: `TRUE`) |
| `:GE` | `(cond-lt, nil)` | Sound | `(arm64::cond-ge, t)` (or `(cond-lt, nil)`) | `GE` (`1010`) | `N == V` | `FALSE` (inv `LT`: `TRUE`) |
| **`:LT`** | `(cond-lt, t)` | **BUG (`TRUE`)** | **`(arm64::cond-mi, t)`** | **`MI` (`0100`)** | **`N == 1`** | **`FALSE` (inv `PL`: `TRUE`)** |
| **`:LE`** | `(cond-gt, nil)` | **BUG (`TRUE`)** | **`(arm64::cond-hi, nil)`** (or `(cond-ls, t)`) | **`LS` (`1001`)** | **`!(C == 1 && Z == 0)`** | **`FALSE` (inv `HI`: `TRUE`)** |

Replacing `acode-condition-to-arm64-cr-bit` / `acode-condition-to-arm64-cond-bit` in `arm642-double-float-compare`, `arm642-single-float-compare`, and `arm642-short-float-compare` with this `condition-to-arm64-fp-cr-bit` helper simultaneously resolves **all 17 failures** — including routing `NaN` in `%unary-truncate` to `%truncate-double-float` so `(truncate/floor/ceiling/round 1d+-0)` properly signals `FLOATING-POINT-INVALID-OPERATION`!

---

## 3. Formal Soundness Ledger (`UNSAT` Positive Verification Results)

To provide positive formal assurance for `LEDGER.md`, below is the complete catalog of **52 `UNSAT` formal verification checks** proved by Z3 across SBCL 2.6.10 (`34 UNSAT`) and CCL 1.14 (`18 UNSAT`).

### 3.1 SBCL 2.6.10 Verified Sound Passes & Transfer Functions (`34 UNSAT`)

| Check Name | Compiler Source (`file:line`) | Z3 Theory / Domain | Result | Time (ms) | What Z3 Proved |
| :--- | :--- | :--- | :---: | ---: | :--- |
| `bitops_unsigned_logand_bounds_o1_bv8` | `bitops-derive-type.lisp:118-139, 207-228` | `QF_BV` (all `[x1,x2] × [y1,y2]` unsigned intervals) | `UNSAT` | 14.0 | Exact O(1) `integer-length`/`zeroes`/`ones` lower & upper bounds for unsigned `logand` |
| `bitops_unsigned_logior_bounds_o1_bv8` | `bitops-derive-type.lisp:118-139, 240-261` | `QF_BV` (all unsigned intervals) | `UNSAT` | 24.5 | Exact O(1) `ones`/`zeroes` lower & upper bounds for unsigned `logior` |
| `bitops_unsigned_logxor_bounds_o1_bv8` | `bitops-derive-type.lisp:118-139, 314-332` | `QF_BV` (all unsigned intervals) | `UNSAT` | 22.1 | Exact O(1) `zeroes`/`ones` lower & upper bounds for unsigned `logxor` |
| `bitops_signed_logand_bounds_bv8` | `bitops-derive-type.lisp:141-238` | `QF_BV` (all neg/pos/mixed-sign intervals) | `UNSAT` | 124.1 | Mixed-sign interval splitting & two's-complement `lognot` duality for signed `logand` |
| `bitops_signed_logior_bounds_add_one_bv8` | `bitops-derive-type.lisp:240-312` | `QF_BV` (all neg/pos/mixed-sign intervals) | `UNSAT` | 87.0 | Mixed-sign `logior` interval derivation including `add-one` saturation helper |
| `bitops_signed_logxor_bounds_bv8` | `bitops-derive-type.lisp:314-364` | `QF_BV` (all neg/pos/mixed-sign intervals) | `UNSAT` | 83.7 | Mixed-sign `logxor` 4-quadrant split (`[-,-]`, `[+,+]`, `[-,+]`) |
| `bitops_cmatch_gray_code_logxor_ash_right` | `bitops-derive-type.lisp:395-410` | `QF_BV` (`x` interval + shift `k`) | `UNSAT` | 18.5 | Combination-match Gray-code bound `(logxor x (ash x -k))` $\le 2^{\text{len}(x_{\text{hi}})} - 1$ |
| `bitops_signed_lognot_bounds_bv64` | `srctran.lisp:3305-3320` | `QF_BV` (64-bit signed `[lo, hi]`) | `UNSAT` | 1.8 | Exact signed `lognot` interval transfer `[-hi - 1, -lo - 1]` over $2^{64}$ |
| `bitops_cmatch_logxor_x_sub_1_bv64` | `bitops-derive-type.lisp:372-375` | `QF_BV` (64-bit signed) | `UNSAT` | 3.4 | `(logxor x (1- x))` $\ge 1$ for $x \ne \text{MIN\_INT}$, $= -1$ for $x = 0$ |
| `bitops_cmatch_logxor_x_add_1_bv64` | `bitops-derive-type.lisp:377-380` | `QF_BV` (64-bit signed) | `UNSAT` | 5.6 | `(logxor x (1+ x))` $\ge 1$ for $x \ne \text{MAX\_INT}$ |
| `bitops_cmatch_logxor_x_neg_x_bv64` | `bitops-derive-type.lisp:382-393` | `QF_BV` (64-bit signed) | `UNSAT` | 6.3 | `(logxor x (- x))` is `0` iff $x=0$, else $\le -2$ (even negative) |
| `bitops_cmatch_logior_x_neg_x_bv64` | `bitops-derive-type.lisp:419-434` | `QF_BV` (64-bit signed) | `UNSAT` | 3.6 | `(logior x (- x))` is `0` iff $x=0$, else $\le -1$ (negative) |
| `bitops_cmatch_logand_x_neg_x_bv64` | `bitops-derive-type.lisp:443-462` | `QF_BV` (64-bit signed) | `UNSAT` | 4.1 | Lowest-set-bit `(logand x (- x))` $\in [0, |x|]$ (unsigned power-of-2 or 0) |
| `srctran_ash_derive_type_aux_mixed_sign` | `srctran.lisp:2243-2305` | `QF_BV` (mixed-sign `x` × mixed-sign `shift`) | `UNSAT` | 477.8 | 4-corner `ash` interval transfer across negative, zero, and positive shifts & operands |
| `srctran_floor_via_truncate_bounds_bv12` | `srctran.lisp:4909-4949` | `QF_BV` (all mixed-sign `n`, `d != 0` intervals) | `UNSAT` | 52.3 | `floor` $\to$ `truncate` rewrite + `rem` & `quot` interval bounds straddling 0 |
| `srctran_ceiling_via_truncate_bounds_bv12` | `srctran.lisp:4951-4975` | `QF_BV` (all mixed-sign `n`, `d != 0` intervals) | `UNSAT` | 51.9 | `ceiling` $\to$ `truncate` rewrite + `rem` & `quot` interval bounds (incl. `±1` divisor check) |
| `srctran_floor_pow2_pos_8_bv64` | `srctran.lisp:5038-5052` | `QF_BV` (64-bit signed $\to$ 66-bit exact) | `UNSAT` | 1.5 | `(floor x 2^k)` $\equiv$ `(values (ash x -k) (logand x (1- 2^k)))` |
| `srctran_floor_pow2_neg_8_bv64` | `srctran.lisp:5038-5052` | `QF_BV` (64-bit signed $\to$ 66-bit exact) | `UNSAT` | 30.6 | `(floor x -2^k)` $\equiv$ `(values (ash (- x) -k) (- (logand (- x) (1- 2^k))))` (incl. `MIN_INT`!) |
| `srctran_ceiling_pow2_word_no_overflow_bv64` | `srctran.lisp:5065-5074` | `QF_BV` (64-bit unsigned `word`) | `UNSAT` | 18.7 | Overflow-free unsigned `(ceiling u 2^k)` $\equiv$ `(if (= u 0) 0 (+ 1 (ash (1- u) -k)))` at `u = 2^64-1` |
| `srctran_granlund_montgomery_udiv_{3,7,10,14}_word64` (4 checks) | `srctran.lisp:5110-5152` | `QF_LIA` (all $2^{64}$ unsigned 64-bit words) | `UNSAT` | 6.4–17.1 | Exact 64-bit Granlund–Montgomery unsigned constant division (incl. `m >= 2^64` add-shift & even-divisor pre-masking + `truly-the word` overflow-freedom) |
| `srctran_granlund_montgomery_sdiv_{3,7,-7,-10}_word64` (4 checks) | `srctran.lisp:5157-5195` | `QF_LIA` (all $2^{64}$ signed 64-bit words) | `UNSAT` | 1.9–5.2 | Exact 64-bit Granlund–Montgomery signed `truncate` by positive & negative constants + `(truly-the sb-vm:signed-word (+ x ...))` overflow-freedom |
| `srctran_ldb_dpb_deposit_field_identities_bv64` | `srctran.lisp:3450-3620` | `QF_BV` (64-bit) | `UNSAT` | 0.2 | `ldb`-of-`dpb`, self-`dpb`, and `deposit-field` $\equiv$ `dpb`-of-`ldb` bitvector identities |
| `modarith_unsigned_width_cut_identities_bv64` | `modarith.lisp:1-620` | `QF_BV` (64-bit $\to$ 32-bit modular cut) | `UNSAT` | 3.0 | Modular width-cutting (`+`, `-`, `*`, `logand`, `logior`, `logxor`, `lognot`, left `ash`) |
| `srctran_interval_untruncate_truncate_bv10` | `srctran.lisp:1486-1510` | `QF_BV` (all mixed-sign quotient & divisor intervals) | `UNSAT` | 905.9 | Exact backward soundness of `interval-untruncate` for `cl:truncate` across zero-straddling divisors |
| `srctran_signed_word_checked_{floor,ceiling}_sound` (2 checks) | `srctran.lisp:4977-4995` | `QF_BV` (scaled fixnum/signed-word boundaries) | `UNSAT` | 186.5–239.8 | Proves `signed-word-checked-transform` using `interval-untruncate` for `floor` & `ceiling` is sound because `fixnum` and `signed-word` are symmetric `[-2^B, 2^B-1]` intervals containing divisor `y`* |
| `eq_constraints_fixed_lattice_meet_sound` | `equality-constraints.lisp:158` (fix) | `QF_FP` (`Float64`) | `UNSAT` | 2.7 | Proves proposed lattice-meet fix is transitive across all non-`NaN` IEEE-754 floats |
| `srctran_sub_same_arg_rne_sound` | `srctran.lisp:2041` (under `RNE`) | `QF_FP` (`Float64`) | `UNSAT` | 9.4 | Proves finite `(- x x)` under `roundNearestTiesToEven` is always `+0.0d0` |

*\*Audit Note on `interval-untruncate` (`srctran.lisp:1486-1510`): While `interval-untruncate` is NOT a general backward inverse for `floor` or `ceiling` near zero (e.g., `(floor -1 2) = -1` while `(interval-untruncate [-1,-1] [2,2]) = [-3,-2]`, excluding `x = -1`), SBCL's sole caller at `srctran.lisp:4987-4994` only checks whether `[low, high]` fits in `fixnum` or `sb-vm:signed-word`, which Z3 proved `UNSAT` (sound). However, `interval-untruncate` must **not** be wired into `constraint-propagate-back` for `floor` or `ceiling` without widening near zero.*

### 3.2 CCL 1.14 Verified Sound Passes, Runtime LAP Routines & Proposed Fix (`18 UNSAT`)

| Check Name | Compiler / Runtime Source (`file:line`) | Z3 Theory / Domain | Result | Time (ms) | What Z3 Proved |
| :--- | :--- | :--- | :---: | ---: | :--- |
| `ccl_arm64_fcmp_actual_{eq,ne,gt,ge}` (4 checks) | `compiler/ARM64/arm642.lisp:477-485, 7845-7858` | `QF_FP` (`Float64 × Float64`, all $2^{128}$ pairs incl. `NaN`, `±0`, `±Inf`, subnormals) | `UNSAT` | 0.4–14.7 | Existing ARM64 `:EQ`, `:NE`, `:GT`, `:GE` `FCMP` condition codes match IEEE-754 |
| `ccl_arm64_fcmp_proposed_fix_{eq,ne,gt,ge,lt,le}_sound` (6 checks) | `compiler/ARM64/arm642.lisp` (proposed `condition-to-arm64-fp-cr-bit`) | `QF_FP` (`Float64 × Float64`, all $2^{128}$ pairs, value + `cbranch-false`) | `UNSAT` | 0.4–17.8 | Proposed 0-overhead FP condition map (`:LT -> cond-mi`, `:LE -> (cond-hi, nil)`) is 100% IEEE-754 exact in both value and branch-inversion contexts |
| `ccl_arm64_lap_%iash_under_caller_contract_bv64` | `level-0/ARM64/arm64-numbers.lisp:23-33` + `l0-numbers.lisp:1791-1806` | `QF_BV` (64-bit tagged fixnum `x << 3` × shift) | `UNSAT` | 17.0 | ARM64 `%iash` (`LSL` / `ASR` + `BIC #7`) is exact across all callers obeying `%ash-left` (`len + count <= 60`) and `%ash-right` (`count > -64`) |
| `ccl_acode_rewrite_ash_const_right_clamp_63` | `compiler/acode-rewrite.lisp:465-495` | `QF_BV` (64-bit signed fixnum × arbitrary negative shift) | `UNSAT` | 0.7 | Clamping right shifts `< -63` on 61-bit/64-bit signed fixnums to `-63` is bit-exact (`0` or `-1`) |
| `ccl_arm64_lap_%fixnum_signum_bv64` | `level-0/ARM64/arm64-numbers.lisp:7-12` | `QF_BV` (all $2^{61}$ 64-bit tagged fixnums) | `UNSAT` | 1.2 | Branchless `CMP Xz, #0; CSET Xz, GT; CSINV Xz, Xz, XZR, GE; LSL #3` equals `cl:signum` |
| `ccl_arm64_lap_%fixnum_intlen_cls_eor_trick` | `level-0/ARM64/arm64-numbers.lisp:36-41` | `QF_BV` (all $2^{61}$ 64-bit tagged fixnums) | `UNSAT` | 1.6 | Branchless `CLS X0, Xz; EOR X0, X0, #63` (`63 - CLS(x << 3)`) equals `cl:integer-length` for all pos/neg/zero fixnums! |
| `ccl_nx0_bounded_integer_add_sub_mul` | `compiler/nx0.lisp:422-490` | `QF_NIA` (unbounded mathematical `Int` intervals) | `UNSAT` | 409.9 | Soundness of `nx0` interval `+`, `-`, and 4-product `*` across arbitrary mixed-sign integer bounds |
| `ccl_nx0_bounded_integer_logand_bv16` | `compiler/nx0.lisp:510-555` | `QF_BV` (16-bit signed intervals) | `UNSAT` | 18.4 | Soundness of `nx0` `(logand [0, u1] [s0, s1])` $\subseteq [0, u_1]$ and positive-pair `[0, min(u1, u2)]` |
| `ccl_arm642_ubfm_bfm_and_align_up_bv64` | `compiler/ARM64/arm642.lisp:9266-9269` + `arm64-vinsns.lisp` | `QF_BV` (64-bit bitfield decoding) | `UNSAT` | 18.2 | Exactness of AArch64 `UBFM` (`ldb`), `BFM` (`dpb`), and `arm642-align-up` |
| `ccl_optimizers_ldb_dpb_mask_deposit_bv64` | `compiler/optimizers.lisp:2040-2135` | `QF_BV` (64-bit) | `UNSAT` | 0.1 | Exactness of `optimizers.lisp` `ldb`, `dpb`, `mask-field`, and `deposit-field` expansions |

---

## 4. Artifact Inventory & Reproduction Commands

All verification suites, machine-readable JSON proofs/counterexamples, and standalone executable reproducers reside strictly within our owned paths and run cleanly under `timeout`:

1. **Z3 Symbolic Verification Suites & JSON Outputs:**
   ```sh
   /opt/homebrew/bin/timeout --kill-after=10s 60s python3 /Users/ember/dev/compiler-audit/hunts/z3-compiler-eq/verify_sbcl_z3.py
   /opt/homebrew/bin/timeout --kill-after=10s 60s python3 /Users/ember/dev/compiler-audit/hunts/z3-compiler-eq/verify_ccl_z3.py
   ```
   - JSON outputs: `/Users/ember/dev/compiler-audit/hunts/z3-compiler-eq/sbcl_z3_results.json` and `ccl_z3_results.json`.

2. **Standalone Live Compiler & ACL2 Reproducers (`exit 0` = bug reproduced):**
   ```sh
   # Z3-1: SBCL 2.6.10 equality-constraints soundness bugs (7 cases; supports `hbox` for x86-64 Linux)
   /Users/ember/dev/compiler-audit/repros/z3-sbcl-equality-constraints-unsound/run.sh
   /Users/ember/dev/compiler-audit/repros/z3-sbcl-equality-constraints-unsound/run.sh hbox

   # Z3-1-ACL2: Pure guard-verified ACL2 (defthm nil-proved nil) on SBCL 2.6.10 (:ttag nil)
   /Users/ember/dev/compiler-audit/repros/z3-acl2-sbcl-char-equal-nil/run.sh

   # Z3-2: SBCL 2.6.10 same-arg float derive-type WARNING + NaN/RTN misfolding (8 cases; supports `hbox`)
   /Users/ember/dev/compiler-audit/repros/z3-sbcl-same-arg-div-derive-type/run.sh
   /Users/ember/dev/compiler-audit/repros/z3-sbcl-same-arg-div-derive-type/run.sh hbox

   # Z3-3: CCL 1.14 ARM64 default-FPU NaN miscompilations + (truncate/ceiling 1d+-0) -> 0/1 (17 cases)
   /Users/ember/dev/compiler-audit/repros/z3-ccl-arm64-fp-nan-unordered/run.sh
   ```
