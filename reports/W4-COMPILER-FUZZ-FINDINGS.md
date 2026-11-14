# Wave-4 Lane 3: Host Compiler Mechanical Fuzzers & Z3 Equivalence Sweep (`W4-HC`)

**Targets Tested:**
- `sbcl-arm64`: SBCL 2.6.10 (`/opt/homebrew/bin/sbcl`) & SBCL `HEAD` (`076335724`)
- `sbcl-x86-64`: SBCL 2.6.10 (`/home/hbox/ca-sbcl-root/dl-2.6.10/sbcl-2.6.10-x86-64-linux/run-sbcl.sh`)
- `ccl-arm64`: Clozure CL 1.14 (`/Users/ember/dev/ccl/darm64cl`)
- `ccl-x86-64`: Clozure CL 1.14 (`/home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64`)
- ACL2 8.7+ (`:ttags nil`): `/Users/ember/dev/acl2-fix/head-worktree/saved_acl2` (SBCL) & `/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2` (CCL)

**Zero-UB & De-duplication Guarantee:** Every finding below is 100% well-defined ANSI Common Lisp (no `(safety 0)` type-declaration lies, no literal constant mutation) and is de-duplicated against all 26 prior `HC-W3-*`, `SB-*`, `CCL-*`, `Z3-*`, and sibling `w4-kc-*` findings.

---

## 1. Executive Summary

| ID | Target(s) | Status | Severity | Summary | Reproducer |
|---|---|---|---|---|---|
| `W4-HC-1` | SBCL 2.6.10 (`arm64`, `x86-64`) | Fixed post-2.6.10 (`4ef5439b8`) | **High** (`(safety 3)` wrong-code) | `eq` false-branch records `(not (eql x const))` for non-`eq-comparable` bignums, miscompiling `(eql x b)` & `(= x b)` to `NIL` | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-eq-non-eq-comparable/run.sh) |
| `W4-HC-2` | SBCL 2.6.10 (`arm64`, `x86-64`) | Fixed post-2.6.10 (`34bab7d61`) | **High** (`(safety 3)` wrong-code) | `type-from-constraints` collapses non-`NIL` `ref` in `if` test to `(member t)` despite `check-type`, raising bogus `SIMPLE-TYPE-ERROR` | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-when-check-type-collapse/run.sh) |
| `W4-HC-3` | SBCL 2.6.10 & `HEAD` (`arm64`, `x86-64`) | **UNPATCHED 0-DAY** | **Medium-High** (`(safety 3)` ICE) | `%dpb derive-type` omits `+left-shift-derive-type-cutoff+` on `related-byte-spec`, crashing `COMPILE` on `(ash 1 fixnum)` | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-dpb-derive-type-0day/run.sh) |
| `W4-HC-4` | SBCL 2.6.10 & `HEAD` (`arm64`, `x86-64`) | **UNPATCHED 0-DAY** | **Medium-High** (`(safety 3)` ICE) | `<`/`>`/`eql` rational transform on `(< (ash x c) (* y k))` lacks `(mod 4096)` cutoff, crashing `COMPILE` on `(ash 0 (expt 2 60))` | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-cmp-ash-unbounded-0day/run.sh) |
| `W4-HC-5` | SBCL 2.6.10 (`arm64`, `x86-64`) | Fixed post-2.6.10 (`9d5bac25d`) | **Medium** (`(safety 3)` ICE) | `convert-more-call` marks local call `:error` on non-symbol keyword despite `:allow-other-keys t`, crashing `COMPILE` | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-allow-other-keys-ice/run.sh) |
| `W4-HC-6` | SBCL 2.6.10 & `HEAD` (`arm64`) + ACL2 `:ttags nil` | **UNPATCHED 0-DAY** | **Critical** (`(safety 3)` ICE + ACL2 abort) | `define-partial-reffer`/`setter` omit `size` in `load-store-offset`, crashing `EMIT-LOAD-STORE` on 8-bit vector constant indices `4095, 4103, ..., 32759` | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-arm64-partial-ldr-str-0day/run.sh) |
| `W4-HC-7` | CCL 1.14 (`arm64`) | Unpatched in 1.14 | **Critical** (silent memory corruption) | 2D/3D `arm642-aset2`/`aset3` skips `idx-reg` init when `constidx > 32792`, causing `arm642-vset1` to write bit `1` via stale `arg_y` | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-ccl-arm64-aset2-uninit-reg-corrupt/run.sh) |
| `W4-HC-9` | CCL 1.14 (`arm64`, `x86-64`) | Unpatched in 1.14 | **Critical** (`(safety 3)` VM header exposure/corruption) | `%displace-array` overwrites `$arh_disp_bit` with stale `flags`, causing open-coded `aref` to read/write raw `vectorH`/`arrayH` header words | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-ccl-adjust-array-displaced-header-corrupt/run.sh) |
| `W4-HC-10` | CCL 1.14 (`x86-64` only) | Unpatched in 1.14 | **High** (silent bit corruption) | `%boole-orc2` SSE2 loop uses `movq` instead of `movaps`, dropping bits `128..191`, `256..319`, ... on `bit-orc2` length `>= 129` | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-ccl-x86-bit-orc2-movq/run.sh) |
| `W4-HC-11` | CCL 1.14 (`arm64`, `x86-64`) | Unpatched in 1.14 | **High** (broken ANSI hash-table contract) | `%%equalphash` hashes `ratio` via `(xor (hash num) (hash den))` vs `float` via `%dfloat-hash`, breaking `equalp` lookup for `1/2` vs `0.5d0` | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-ccl-equalp-hash-ratio-float/run.sh) |
| `W4-HC-12` | CCL 1.14 (`arm64`, `x86-64`) | Unpatched in 1.14 | **High** (`(safety 3)` type unsoundness) | `concatenate` & `coerce` compiler macros & runtime drop length/range bounds and return values claiming to inhabit empty type `NIL` | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-ccl-coerce-concat-empty-type-unsound/run.sh) |
| `W4-HC-13` | SBCL 2.6.10 & `HEAD` (`arm64`, `x86-64`) | **UNPATCHED 0-DAY** | **Medium-High** (`(safety 3)` ICE) | `(locally (declare (notinline gcd)) (gcd))` reaches `derive-gcd` with `args = NIL`, crashing `COMPILE` in `(abs nil)` | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-notinline-gcd-ice-0day/run.sh) |
| `W4-HC-14` | SBCL 2.6.10 (`arm64`, `x86-64`) | Unpatched in 2.6.10 | **Medium** (`(safety 3)` wrong condition) | `deftransform coerce` rewrites `(coerce seq '(vector t N))` to `(make-array ...)`, signaling `SIMPLE-ERROR` instead of `TYPE-ERROR` | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-coerce-vector-length-simple-error/run.sh) |
| `W4-HC-15` | CCL 1.14 (`arm64`, `x86-64`) | Unpatched in 1.14 | **Medium** (stdlib semantic bugs) | 0D adjustable `adjust-array :initial-contents` silently ignored (`arrays-fry.lisp:318-321`) & `(signum -0.0)` returns `+0.0` (`numbers.lisp:616`) | [run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-ccl-0d-adjust-array-and-signum-negzero/run.sh) |

*(Note on `W4-HC-8`: an earlier candidate `(coerce (the (or null (and (satisfies oddp) (satisfies plusp))) x) 'integer)` did not reproduce a crash on local SBCL 2.6.10 and is omitted from the reproducer set.)*

---

## 2. Fuzzer Harness Suite (`/Users/ember/dev/compiler-audit/hunts/w4-compiler-fuzz/`)

1. **`z3_ir_sweep.py` (Stage 1 — Z3 SMT IR1 & Constraint Sweep)**:
   - Scans 10 SBCL 2.6.10 compiler files (36,296 LOC; 181 `derive-type` definitions, 626 `csubtypep`/`:not` sites, 21 `constraint-back` definitions) and executes **16 Z3 SMT checks** (`5` novel `SAT` bugs live-verified on SBCL 2.6.10, `1` known `SAT` `Z3-2` de-duped, `10` `UNSAT` proofs) in ~9s.
2. **`fuzz_context_positions.py` (Stage 2 — Continuation Context Differential Fuzzer)**:
   - Tests 9 operator families × 4 continuation contexts (value, predicate, for-effect, evaluation-order trace) × 4 policies (`(speed 1)(safety 3)`, `(speed 3)(safety 3)`, `(speed 1)(safety 1)`, `(notinline)`).
   - `--seed 20261113 --count 650` across all 4 targets: **41,600 compiled lambdas / 166,400 context sub-evaluations** (`rc=0`).
3. **`fuzz_regpressure_immediates.py` (Stage 3 — Register Pressure, Spills, & Immediate Boundaries)**:
   - Tests 7 families (`gpr_pressure_trees`, `fpr_pressure_trees`, `complex_spill_trees`, `mv_dx_closure_pressure`, `array_imm_boundaries_1d`, `array_multidim_2d_3d`, `bitfield_shift_boundaries`) × 4 policies.
   - `--seed 20261114 --count 560 --include-safety0` across all 4 targets: **8,960 compiled functions** (`rc=0`), organically catching `W4-HC-6` (`R0277`) and CCL ARM64 bit-vector bugs (`R0018`, `R0074`, `R0228`, `R0368`).
4. **`fuzz_stdlib_boundaries.py` (Stage 4 — ANSI CL Stdlib & Transform Boundary Differential Fuzzer)**:
   - Tests 6 domains (set/list, sequence/array, bit-vectors, chars/strings, hash-tables/`sxhash`, numeric primitives) × 3 modes (`S3`, `S1`, `NI`).
   - **1,282 cases/target × 3 modes = 15,246 evaluations** across all 4 targets (`rc=0`), uncovering `W4-HC-9` through `W4-HC-15`.

---

## 3. Detailed Findings & Root Causes

### `W4-HC-1` — SBCL 2.6.10 `eq` Non-`eq-comparable` Constraint Complementation (`(safety 3)` Wrong-Code)
- **Source**: `src/compiler/constraint.lisp:891`, `:1073-1092` (fixed post-2.6.10 in `4ef5439b8`).
- **Root Cause**: The `eq` false branch records `(not (eql x const))` even for non-`eq-comparable` bignum constants. Subsequent `(eql x b)` and `(= x b)` against an equal freshly allocated bignum (`(+ (expt 2 70) 1)`) miscompile to `NIL` at `(safety 3)`.
- **Reproducer**: [repros/w4-hc-sbcl-eq-non-eq-comparable/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-eq-non-eq-comparable/run.sh) (exits `0`).

### `W4-HC-2` — SBCL 2.6.10 `type-from-constraints` `check-type` Collapse (`(safety 3)` Wrong-Code)
- **Source**: `src/compiler/constraint.lisp:1166-1172` (fixed post-2.6.10 in `34bab7d61`).
- **Root Cause**: `type-from-constraints` collapses a non-`NIL` `ref` in an `if` test to `(member t)` despite `lvar-annotations` (`(check-type y cons)`), raising a bogus runtime `SIMPLE-TYPE-ERROR: Value of Y in Y is T, not a CONS` on `(list 42)`.
- **Reproducer**: [repros/w4-hc-sbcl-when-check-type-collapse/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-when-check-type-collapse/run.sh) (exits `0`).

### `W4-HC-3` — SBCL 2.6.10 & `HEAD` `%dpb derive-type` Unbounded Shift Crash (**UNPATCHED 0-DAY**)
- **Source**: `src/compiler/srctran.lisp:3980-3988` (verified unpatched on `HEAD` `076335724`).
- **Root Cause**: `%dpb derive-type` omits `+left-shift-derive-type-cutoff+` (`256`, present in `%ldb` `:3894` & `%mask-field` `:3918`) on `related-byte-spec` `(byte count (- a count))`, evaluating `(ash 1 4611686018427387903)` when `a : fixnum` and crashing `COMPILE` at `(safety 3)`.
- **Reproducer**: [repros/w4-hc-sbcl-dpb-derive-type-0day/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-dpb-derive-type-0day/run.sh) (exits `0`).

### `W4-HC-4` — SBCL 2.6.10 & `HEAD` `<`/`>`/`eql` Rational `ash` Transform Unbounded Shift Crash (**UNPATCHED 0-DAY**)
- **Source**: `src/compiler/srctran.lisp:8089-8092, 8182-8185` (verified unpatched on `HEAD` `076335724`).
- **Root Cause**: Rational comparison transforms on `(< (ash x c) (* y k))` check only `(plusp c)` without a `(mod 4096)` cutoff, crashing `COMPILE` on valid `(ash 0 (expt 2 60)) = 0`.
- **Reproducer**: [repros/w4-hc-sbcl-cmp-ash-unbounded-0day/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-cmp-ash-unbounded-0day/run.sh) (exits `0`).

### `W4-HC-5` — SBCL 2.6.10 `convert-more-call` `:allow-other-keys t` ICE (`(safety 3)`)
- **Source**: `src/compiler/locall.lisp:865-868` (fixed post-2.6.10 in `9d5bac25d`).
- **Root Cause**: `convert-more-call` marks a local call `:error` on a non-symbol keyword even when `:allow-other-keys t` suppresses keyword checking (CLHS §3.4.1.4.1), crashing `COMPILE` with `NIL is not of type SB-C::NODE`.
- **Reproducer**: [repros/w4-hc-sbcl-allow-other-keys-ice/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-allow-other-keys-ice/run.sh) (exits `0`).

### `W4-HC-6` — SBCL 2.6.10 & `HEAD` ARM64 Partial `ldr`/`str` Missing `size` Argument (**UNPATCHED 0-DAY**, + ACL2 `:ttags nil` Abort)
- **Source**: `src/compiler/arm64/macros.lisp:45-50, 508-511, 562-565` (and `src/compiler/arm64/float.lisp:161, 881, 952, 958, 1009`; verified unpatched on `HEAD` `076335724`).
- **Root Cause**: `define-partial-reffer`/`setter` call `(load-store-offset ...)` without passing `size` (`8`/`16`/`32`), so `load-store-offset` defaults to `size = 64`. For 8-bit vectors / `simple-base-string` at constant indices `4095, 4103, ..., 32759` (`3,584` indices where `(index + 1) mod 8 == 0`), `ldr-str-offset-encodable` accepts `byte_offset >= 4096`, crashing `SB-ARM64-ASM::EMIT-LOAD-STORE` at `(safety 3)` and aborting `:ttags nil` ACL2 `saved_acl2` on inline `(unsigned-byte 8)` stobjs.
- **Reproducer**: [repros/w4-hc-sbcl-arm64-partial-ldr-str-0day/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-arm64-partial-ldr-str-0day/run.sh) (exits `0`).

### `W4-HC-7` — CCL 1.14 ARM64 2D/3D `arm642-aset2`/`aset3` Uninitialized-Register Arbitrary Memory Corruption
- **Source**: `/Users/ember/dev/ccl/compiler/ARM64/arm642.lisp:2040-2052, 2165-2176, 2641`.
- **Root Cause**: For 2D/3D `bit` arrays with linearized `constidx > 32792` (e.g. `(setf (aref a 328 0) 1)` on `(simple-array bit (400 100))`), `(unless constidx ...)` skips initializing `idx-reg` (`arg_y`), and `arm642-vset1:2641` writes bit `1` using stale caller `arg_y` (`x = 100`) instead of `32800`.
- **Cross-References**: 1D `arm642-vref1:1883` + `:ttags nil` ACL2 `NIL` proof and x86-64 `x862-vref1:2093..2172` are packaged by sibling lane `w4-kimi-core-compilers` in `repros/w4-kc-ccl-arm64-bitvec-const-idx/` and `repros/w4-kc-ccl-x86-vref1-double-offset/` (not duplicated here).
- **Reproducer**: [repros/w4-hc-ccl-arm64-aset2-uninit-reg-corrupt/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-ccl-arm64-aset2-uninit-reg-corrupt/run.sh) (exits `0`).

### `W4-HC-9` — CCL 1.14 `adjust-array :displaced-to` Wipes `$arh_disp_bit` (`(safety 3)` Raw VM Header Exposure & Corruption)
- **Source**: `/Users/ember/dev/ccl/lib/arrays-fry.lisp:376-385` (`%displace-array`) + `/Users/ember/dev/ccl/compiler/ARM64/arm64-vinsns.lisp:7014-7025` & `/Users/ember/dev/ccl/compiler/X86/X8664/x8664-vinsns.lisp:911-919` (`deref-vector-header`).
- **Root Cause**: `%displace-array` caches `flags` at line 376, sets `$arh_disp_bit` in `flags-cell` at line 381 when `data` is a header array, then overwrites `flags-cell` at lines 382–385 using `(bitset $arh_exp_disp_bit flags)` on the stale local `flags`, wiping `$arh_disp_bit`. Open-coded `deref-vector-header` at `(safety 3)` stops after one hop at the target `vectorH`/`arrayH` header object itself, returning `(4 4 #(:A :B :C :D))` instead of `(:A :B :C)` and allowing `(setf aref)` to corrupt VM header words.
- **Reproducer**: [repros/w4-hc-ccl-adjust-array-displaced-header-corrupt/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-ccl-adjust-array-displaced-header-corrupt/run.sh) (exits `0`).

### `W4-HC-10` — CCL 1.14 x86-64 `bit-orc2` SSE2 `movq` Typo Drops Upper 64 Bits
- **Source**: `/Users/ember/dev/ccl/level-0/X86/x86-array.lisp:502-519` (`%boole-orc2`, line `511`).
- **Root Cause**: Line 511 emits `(movq (% xmm0) ...)` instead of `(movaps (% xmm0) ...)`, storing only the low 64 bits of each 128-bit SSE2 chunk on `simple-bit-vector` lengths `>= 129` and leaving bits `128..191`, `256..319`, ... zeroed or stale.
- **Reproducer**: [repros/w4-hc-ccl-x86-bit-orc2-movq/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-ccl-x86-bit-orc2-movq/run.sh) (exits `0` via `hbox`).

### `W4-HC-11` — CCL 1.14 `equalp` Hash Tables Fail `ratio` vs `float` Lookup
- **Source**: `/Users/ember/dev/ccl/level-0/l0-hash.lisp:1769-1780` (`%%equalphash`).
- **Root Cause**: `ratio`s hash via `(%ilogxor (%%equalphash (numerator key)) (%%equalphash (denominator key)))` whereas floats hash via `%dfloat-hash`, violating CLHS 18.1.2 for `1/2` vs `0.5d0` (lookup misses and `(setf gethash)` inserts duplicate keys).
- **Reproducer**: [repros/w4-hc-ccl-equalp-hash-ratio-float/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-ccl-equalp-hash-ratio-float/run.sh) (exits `0`).

### `W4-HC-12` — CCL 1.14 `concatenate` & `coerce` Compiler Macros / Runtime Drop Bounds & Violate Empty Type `NIL`
- **Source**: `/Users/ember/dev/ccl/compiler/optimizers.lisp:2412-2441, 2649-2653`; `/Users/ember/dev/ccl/lib/sequences.lisp:106, 851-908`.
- **Root Cause**: `concatenate` compiler macro rewrites `(concatenate '(string 2) ...)` dropping length constraints (`S3` returns `"abcdef"`, `notinline` signals `TYPE-ERROR`); `coerce` compiler macro & runtime dispatch via `(csubtypep (specifier-type result-type) X)` which is vacuously `T` for `NIL` (`(coerce 5 nil)` returns `5.0` compiled at `(safety 3)`, and `(coerce #\a nil)` returns `#\a` at runtime).
- **Reproducer**: [repros/w4-hc-ccl-coerce-concat-empty-type-unsound/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-ccl-coerce-concat-empty-type-unsound/run.sh) (exits `0`).

### `W4-HC-13` — SBCL 2.6.10 & `HEAD` `(notinline gcd)` 0-Arg `derive-gcd` Compiler ICE (**UNPATCHED 0-DAY**)
- **Source**: `src/compiler/srctran.lisp:8306-8354` (verified unpatched on `HEAD`).
- **Root Cause**: Suppressing the `gcd` source transform with `(declare (notinline gcd))` sends 0-arg `(gcd)` to `derive-gcd` with `args = NIL`, evaluating `(max (abs min) (abs max))` on `min = NIL` and crashing `COMPILE` with `TYPE-ERROR: The value NIL is not of type NUMBER`.
- **Reproducer**: [repros/w4-hc-sbcl-notinline-gcd-ice-0day/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-notinline-gcd-ice-0day/run.sh) (exits `0`).

### `W4-HC-14` — SBCL 2.6.10 `(safety 3)` `deftransform coerce` Signals `SIMPLE-ERROR` Instead of `TYPE-ERROR`
- **Source**: `src/compiler/typetran.lisp:2076-2077`.
- **Root Cause**: `deftransform coerce` rewrites `(coerce x '(vector t 2))` to `(make-array 2 :initial-contents x)`, whose runtime length mismatch signals `SIMPLE-ERROR` instead of CLHS-mandated `TYPE-ERROR`, bypassing `(handler-case ... (type-error ...))` at `(safety 3)`.
- **Reproducer**: [repros/w4-hc-sbcl-coerce-vector-length-simple-error/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-sbcl-coerce-vector-length-simple-error/run.sh) (exits `0`).

### `W4-HC-15` — CCL 1.14 0D Adjustable `adjust-array :initial-contents` & `(signum -0.0)` Bugs
- **Source**: `/Users/ember/dev/ccl/lib/arrays-fry.lisp:318-321` & `/Users/ember/dev/ccl/lib/numbers.lisp:616`.
- **Root Cause**: `(adjust-array a nil :initial-contents 'new)` on an adjustable 0D array overwrites the new value with `(aref array)` at line 320 because `(not initial-contents-p)` is missing; `(signum -0.0f0)` / `(signum -0.0d0)` returns `+0.0` via `(float 0.0 x)` instead of preserving `-0.0`.
- **Reproducer**: [repros/w4-hc-ccl-0d-adjust-array-and-signum-negzero/run.sh](file:///Users/ember/dev/compiler-audit/repros/w4-hc-ccl-0d-adjust-array-and-signum-negzero/run.sh) (exits `0`).
