# Wave-3 Report: Unraked Host Compiler Subsystems (SBCL 2.6.10 & Clozure CL 1.14)

**Agent:** `w3-host-compilers` (with helpers `sbcl-seq-constraint` and `ccl-x86-acode-audit`)  
**Scope:** Unraked SBCL 2.6.10 (`constraint.lisp`, `constraint-back.lisp`, `loop.lisp`, `seqtran.lisp`, `array-tran.lisp`, `srctran.lisp`, `modarith.lisp`, `arm64/arith.lisp`) and Clozure CL 1.14 (`X86/x862.lisp`, `X86/X8664/x8664-vinsns.lisp`, `ARM64/arm642.lisp`, `nx1.lisp`, `acode-rewrite.lisp`, `level-0/`), plus guard-verified ACL2 (`head-worktree/saved_acl2`, `ccl-worktree/saved_acl2`) soundness escalation and Z3 (`5.4.1`) equivalence checking.

---

## 1. Executive Summary

We discovered and independently verified **9 confirmed compiler bugs** (all with zero-UB standalone reproducers under `repros/host-w3-*/run.sh` that pass/reproduce cleanly with exit code `0`), including **2 pure guard-verified `:logic`-mode ACL2 soundness exploits (`defthm nil-proved nil` with `:ttags nil`, `:skip-proofs-seen nil`, `:redef-seen nil`)**:

| ID | Target / Arch | Subsystem (`file:line`) | Impact | ACL2 `nil-proved`? | Reproducer |
|---|---|---|---|---|---|
| **HC-W3-1** | SBCL 2.6.10 (`ARM64`) | `srctran.lisp:4084,4118` + `arm64/arith.lisp:1158-1189` | Wrong integer result & negative result escaping `(logand #xffffffffffffffff (ash ... (- x)))` at `(safety 3)` | **YES (`nil-proved` Q.E.D.)** | [`host-w3-sbcl-ash-inverted-arm64/run.sh`](../repros/host-w3-sbcl-ash-inverted-arm64/run.sh) |
| **HC-W3-2** | SBCL 2.6.10 (`ARM64`, `X86-64`) | `constraint-back.lisp:505-516` (`char-code` `eq`) | Unsound range negation on `not-eq` branch when `y` is non-singleton integer interval | **YES (`nil-proved` Q.E.D.)** | [`host-w3-sbcl-char-code-constraint/run.sh`](../repros/host-w3-sbcl-char-code-constraint/run.sh) |
| **HC-W3-3** | SBCL 2.6.10 (`ARM64`, `X86-64`) | `srctran.lisp:6664-6676` + `target-char.lisp:441-444` | 12 constant-char transform mismatches + 16 non-symmetric `char-equal`/`string-equal` pairs on Unicode titlecase triples | No (ACL2 8-bit chars) | [`host-w3-sbcl-char-equal-titlecase/run.sh`](../repros/host-w3-sbcl-char-equal-titlecase/run.sh) |
| **HC-W3-4** | SBCL 2.6.10 (`ARM64`, `X86-64`) | `seqtran.lisp:4350-4364` | `(set-exclusive-or x x)` & `(nset-exclusive-or x x)` return `x` instead of `NIL` with zero decls | N/A | [`host-w3-sbcl-set-exclusive-or/run.sh`](../repros/host-w3-sbcl-set-exclusive-or/run.sh) |
| **HC-W3-5** | SBCL 2.6.10 (`ARM64`, `X86-64`) | `seqtran.lisp:4470-4475` | `(reduce #'logior s ...)` `derive-type` omits `0` and `initial-value-type` on `#()` | N/A | [`host-w3-sbcl-reduce-logior-type/run.sh`](../repros/host-w3-sbcl-reduce-logior-type/run.sh) |
| **HC-W3-6** | CCL 1.14 (`X86-64`) | `compiler/X86/x862.lisp:9591-9592, 9606-9607` | `(- (+ a b) (- c d))` and `(+ (+ a b) (- c d))` on `(complex single-float)` clobber `r2` (`#C(4.0 6.0)`) | No | [`host-w3-ccl-complex-sub-add-x8664/run.sh`](../repros/host-w3-ccl-complex-sub-add-x8664/run.sh) |
| **HC-W3-7** | CCL 1.14 (`ARM64`, `X86-64`) | `x862.lisp:8785-8811,9540-9628` + `arm642.lisp:7273-7297,7915-8003` | `COMPILE` crashes with `bad regspec: NIL` on for-effect float negate at `(safety 3)` and complex binary ops | No | [`host-w3-ccl-for-effect-bad-regspec/run.sh`](../repros/host-w3-ccl-for-effect-bad-regspec/run.sh) |
| **HC-W3-8** | CCL 1.14 (`X86-64`) | `compiler/X86/x862.lisp:3018-3024` | Misplaced paren in `x862-vset1` silently drops `(setf (aref v #x10000000) val)` stores at `(safety 3)` | No | [`host-w3-ccl-vset1-dropped-store/run.sh`](../repros/host-w3-ccl-vset1-dropped-store/run.sh) |
| **HC-W3-9** | CCL 1.14 (`X86-64`, ext. `Z3-3`) | `x862.lisp:4887-4934` + `x8664-vinsns.lisp:1718-1726` | `COMISD`/`COMISS` + unsigned flag tests treat `NaN` as `=`, `<`, `<=`, and not `/=` when `:invalid nil` | No | [`host-w3-ccl-x86-nan-cmp/run.sh`](../repros/host-w3-ccl-x86-nan-cmp/run.sh) |

---

## 2. De-Duplication Against Prior Waves

Checked against `README.md`, `SBCL.md`, `CCL.md`, `CCL-OPTIMIZERS.md`, `reports/SBCL-2.6.10-FINDINGS.md`, `reports/CCL-CODEGEN-FINDINGS.md`, and `reports/Z3-COMPILER-EQUIVALENCE.md`:
- **No overlap** with `SB1`, `SB2/F18`, `SB-2610-1..4` (SIMD/bignum/`%more-arg`), `Z3-1` (`equality-constraints.lisp`), `Z3-2` (`srctran.lisp` same-arg float `derive-type`), `CCL-1..3`, `CCL-OPT-1..2`, or `CCL-CG-1..4b` (`ARM64` `arm642.lisp`).
- **Note on NaN comparisons:** We explicitly excluded `constraint.lisp:1232-1256` (`type-after-comparison` NaN negation) as a standalone headline bug because its observable trigger overlaps `Z3-1` (`1g`). **HC-W3-9** (`x862.lisp:4887-4934`) is the `X86-64` counterpart to ARM64 `Z3-3`, adding `=` and `/=` failures on top of `<`/`<=` due to `COMISD`/`COMISS` setting `ZF=PF=CF=1`.

---

## 3. Confirmed Findings

### HC-W3-1: SBCL 2.6.10 ARM64 `ash-inverted` Negated Shift-Amount Miscompilation (`NIL-PROVED` in ACL2)
- **Locations:** `src/compiler/srctran.lisp:4015-4030, 4084-4093, 4111-4125`, `src/compiler/arm64/arith.lisp:1158-1189`.
- **Root Cause (2 compounding bugs):**
  1. `srctran.lisp:4084` (`word` base) and `4118` (`sb-vm:signed-word` base) inside `(when-vop-existsp (:translate ash-inverted) ...)` guard the `(ash integer (- x))` transform with `(combination-typed-p use %negate (:not (integer * 0)))`. Per `combination-typed-p` (`4026-4029`), `(:not (integer * 0))` expands to `(not (csubtypep (lvar-type arg) (specifier-type '(integer * 0))))` — which tests "not guaranteed `<= 0`" rather than "guaranteed `>= 0`". Any type that includes positive and negative integers (such as `(type integer x)`) passes, splices `%negate`, and wraps the unvalidated `x` in `(truly-the (mod 64) x)` before calling `ash-inverted`. On ARM64, `ASR`/`LSR` masks the shift count to `x mod 64`, so for `(logand #xffffffffffffffff (ash 1 (- x)))` at `x = -1`, SBCL computes `1 >> 63 = 0` instead of `1 << 1 = 2`.
  2. Even when `x` fits in `sb-vm:signed-word` (`4111-4117`) and reaches `ash-inverted/signed/unsigned` (`arm64/arith.lisp:1167-1189`), lines `1181-1188` set `temp` to all-ones (`-1`) via `CSINV` when `|x| >= 64`, then fall through `TBZ x, 63, done` for negative `x` and execute `(inst lsl result number temp)`. Because ARM64 `LSL` uses only the low 6 bits (`63`), `(logand #xffffffffffffffff (ash 1 (- x)))` with `(type (signed-byte 64) x)` at `x = -64` shifts `1` left by `63` (and types it as `signed-word`, yielding `-9223372036854775808`) instead of `0`.
- **Z3 Verification (`hunts/host-compilers-w3/verify_w3_z3.py`):** Both bugs returned `sat` witnesses; the fixed guard (`x >= 0` or `CSEL zr` when `|x| >= 64`) proved `unsat`.
- **ACL2 Exploit (`repros/host-w3-sbcl-ash-inverted-arm64/acl2-nil-proved.lisp`):** Pure guard-verified `:logic`-mode function `(defun bad-ash (x) (declare (xargs :guard (integerp x))) (logand #xffffffffffffffff (ash 1 (- (the integer x)))))` proves `(defthm nil-proved nil)` Q.E.D. on `head-worktree/saved_acl2` (`ttags-seen = NIL`, `skip-proofs-seen = NIL`, `redef-seen = NIL`).

### HC-W3-2: SBCL 2.6.10 `char-code` `constraint-propagate-back` Unsound Range Negation (`NIL-PROVED` in ACL2)
- **Locations:** `src/compiler/constraint-back.lisp:505-516` (`eq` arm of `(defoptimizer (char-code constraint-propagate-back) ...)`).
- **Root Cause:** When `(eql (char-code c) y)` compares `(char-code c)` against a non-singleton integer interval `[low, high]` (e.g. `(integer 10 20)`), SBCL builds `(character-set ((low . high)))` and adds `(conset-add-constraint-to-eql gen 'typep var type t alternative)` (`not-p = t`), asserting on the `not-eq` branch that `c` is NOT in `[low, high]`. That is sound only when `low = high`.
- **Observed Behavior (ARM64 & X86-64):** At `(speed 3)(safety 3)` and default optimize (`=`), `(bad-cc (code-char 10) 15)` returns `:OUT-OF-RANGE` / `(NIL NIL)` instead of `:IN-RANGE-NOT-EQ` / `(T T)`.
- **Z3 & ACL2:** `verify_w3_z3.py` gives `sat` witness `[c = 10, y = 11]` and `unsat` when `low = high`. Pure guard-verified ACL2 (`repros/host-w3-sbcl-char-code-constraint/acl2-nil-proved.lisp`) proves `(defthm nil-proved nil)` Q.E.D. on `head-worktree/saved_acl2`.

### HC-W3-3: SBCL 2.6.10 `char-equal` / `string-equal` Unicode Titlecase Asymmetry & Transform Mismatch
- **Locations:** `src/compiler/srctran.lisp:6664-6676` (`transform-constant-char-equal`), `src/code/target-char.lisp:441-444` (`two-arg-char-equal-inline`).
- **Root Cause:**
  1. `transform-constant-char-equal` assumes every `both-case-p` character has a single opposite-case partner via `(if (upper-case-p char) (char-downcase char) (char-upcase char))`, omitting the third character of the 4 Unicode digraph titlecase triples (`452/453/454` `Ǆ/ǅ/ǆ`, `455/456/457` `Ǉ/ǈ/ǉ`, `458/459/460` `Ǌ/ǋ/ǌ`, `497/498/499` `Ǳ/ǲ/ǳ`). Full sweep over `[0, char-code-limit)` gives **12** compiler-vs-runtime mismatches.
  2. `two-arg-char-equal-inline` compares `(char-code c2)` only against `c1`'s lower and upper table slots, omitting titlecase. Full pairwise sweep gives **16** asymmetric pairs (`(char-equal #\U01C5 #\U01C4) => T`, `(char-equal #\U01C4 #\U01C5) => NIL`; same asymmetry in `string-equal`). Verified identically on ARM64 and X86-64.

### HC-W3-4: SBCL 2.6.10 `set-exclusive-or` / `nset-exclusive-or` Returns `list1` Instead of `NIL`
- **Location:** `src/compiler/seqtran.lisp:4350-4364`.
- **Root Cause:** Copy-pasted from `union`/`nunion`: when `(same-leaf-ref-p list1 list2)` holds (no `:key`, no `:test-not`, default/`eq`/`eql`/`equal`/`equalp` `:test`), the transform returns `'list1` instead of `nil` (`X XOR X = {}`). Triggers with zero type declarations at default `(speed 1)(safety 1)` and `(speed 3)(safety 3)` on both ARM64 and X86-64 (`(set-exclusive-or x x)` on `(1 2 3)` returns `(1 2 3)` instead of `NIL`).

### HC-W3-5: SBCL 2.6.10 `(reduce #'logior ...)` `derive-type` Ignores Empty Sequence Identity & `:initial-value`
- **Location:** `src/compiler/seqtran.lisp:4470-4475`.
- **Root Cause:** For `function = #'logior`, when `initial-value` is omitted, `derive-type` returns `element-type` without unioning `0` (`(logior)` on `#()`); when `initial-value` is supplied, it returns `(%two-arg-derive-type element-type initial-value-type ...)` without unioning `initial-value-type`. On `#()`, `(typep r '(integer 1 10))` and `(plusp r)` mis-fold to `T` at default optimize and `(speed 3)(safety 3)` on ARM64 and X86-64.

### HC-W3-6: CCL 1.14 X86-64 `(complex single-float)` `+` and `-` Target Register Clobber
- **Locations:** `compiler/X86/x862.lisp:9591-9592` (`x862-%complex-single-float+-2`), `9606-9607` (`x862-%complex-single-float--2`), `compiler/X86/X8664/x8664-vinsns.lisp:1938`.
- **Root Cause:** Unlike `x862-%complex-double-float--2` (`9562`) which passes `(with-fp-target (r1 target) (r2 :complex-double-float) ...)`, both `x862-%complex-single-float+-2` and `x862-%complex-single-float--2` pass only `(with-fp-target (r1) ...)`, omitting `target`. When `target` aliases `r2`, moving `r1` / computing into `target` clobbers `r2` on x86-64. On `lx86cl64` at default optimize, `(- (+ a b) (- c d))` returns `#C(4.0 6.0)` instead of `#C(6.0 8.0)`, and `(+ (+ a b) (- c d))` returns `#C(4.0 6.0)` instead of `#C(2.0 4.0)`.

### HC-W3-7: CCL 1.14 ARM64 & X86-64 For-Effect Float Negation & Complex Binary Ops Crash `COMPILE` (`bad regspec: NIL`)
- **Locations:** `compiler/X86/x862.lisp:8785-8811, 9540-9628`, `compiler/ARM64/arm642.lisp:7273-7297, 7915-8003`, `compiler/acode-rewrite.lisp:388-402`.
- **Root Cause:** `x862/arm642-%double/single-float-negate` and all 6 `x862/arm642-%complex-{double,single}-float{+-2,--2,*-2}` methods unconditionally invoke `(ensuring-node-target (... vreg) ...)` even when compiled for effect (`vreg = NIL`). Triggers at `(optimize (speed 1)(safety 3))` on inferred floats (`(progn (let ((y ...)) (- y)) :ok)`) and at default optimize on complex `+`/`-`/`*` on both `darm64cl` and `lx86cl64`.

### HC-W3-8: CCL 1.14 X86-64 `x862-vset1` Misplaced Paren Drops Constant-Index 64-Bit Stores `>= #x10000000`
- **Location:** `compiler/X86/x862.lisp:3018-3024`.
- **Root Cause:** Line `3019` closes `(if index-known-fixnum ...)` before the `(! misc-set-{double-float,s64,u64} ...)` dispatch, placing the memory store in the false branch of `(if index-known-fixnum ...)`. Any constant-index `(setf (aref v #x10000000) val)` on `(simple-array double-float (*))`, `(unsigned-byte 64)`, or `(signed-byte 64)` at `(safety 3)` emits the offset calculation and silently drops the store (`pass=NIL` on all 3 types on `lx86cl64`).

### HC-W3-9: CCL 1.14 X86-64 `COMISD`/`COMISS` Unordered `NaN` Comparisons (Extending `Z3-3`)
- **Locations:** `compiler/X86/x862.lisp:4887-4934`, `compiler/X86/X8664/x8664-vinsns.lisp:1718-1726`.
- **Root Cause:** With `(ccl:set-fpu-mode :invalid nil)`, `COMISD`/`COMISS` sets `ZF=PF=CF=1` on `NaN`. Unsigned condition codes (`x862-cr-bit-for-unsigned-comparison`) without a parity check make `(= nan 1.0)`, `(< nan 1.0)`, `(<= nan 1.0)` return `T` and `(/= nan 1.0)` return `NIL` (`(T NIL T T NIL NIL)` vs expected `(NIL T NIL NIL NIL NIL)` on `lx86cl64`).

---

## 4. Fuzzing & Formal Verification Coverage

- **Z3 Formal Verification ([`hunts/host-compilers-w3/verify_w3_z3.py`](../hunts/host-compilers-w3/verify_w3_z3.py)):**
  - `SAT` counterexamples found and confirmed for `HC-W3-1` (`(type integer x)` and `(signed-byte 64)` VOP), `HC-W3-2` (`char-code eq`), `HC-W3-4` (`set-exclusive-or`), `HC-W3-5` (`reduce #'logior`).
  - `UNSAT` (verified clean/sound) for: fixed `ash-inverted`, singleton `char-code eq`, `truncate` `rem /= 0` quotient bound tightening (`constraint-back.lisp:371-405`), `%dpb` bitvector transform (`srctran.lisp:3891-3911`, `size+posn <= 64`), `%mask-field` bitvector transform (`srctran.lisp:3860-3862`).
- **SBCL IR/Modarith Differential Fuzzer ([`hunts/host-compilers-w3/fuzz_sbcl_ir.lisp`](../hunts/host-compilers-w3/fuzz_sbcl_ir.lisp)):** `2,000` random programs / `46,000` evaluations comparing `(speed 3)(safety 3)` vs `(speed 3)(safety 0)` vs `(notinline)` -> isolated `HC-W3-1` (`310` raw diffs: `ash-inverted` + dead-code float overflow elision).
- **SBCL Sequence & Constraint Fuzzer (`hunts/host-compilers-w3/sbcl-seq-constraint/`):** `4,000` cases (`2,000` seq/string/bit-vector + `2,000` constraint/loop/float) across SBCL `(safety 3)`, `(safety 0)`, `(notinline)`, and CCL 1.14 -> isolated `HC-W3-2`, `HC-W3-4`, `HC-W3-5`. Audited clean: `loop.lisp` widening, `array-tran.lisp`, `bit-and`..`bit-nor` word loops, `length` constraint-back.
- **CCL Cross-Arch Differential Fuzzer (`hunts/host-compilers-w3/ccl-x86-acode/`):** `4,140` cases across `fuzz.py` (`900`), `fuzz2.py` (`1,440`), `fuzz3.py` (`1,800`), plus `585`-case for-effect sweep comparing `lx86cl64` vs `darm64cl` vs `sbcl` -> isolated `HC-W3-6`, `HC-W3-7` (plus `HC-W3-8`/`HC-W3-9` from targeted backend audit and `nx0.lisp:789` typo in v1.14 release binary already fixed in CCL git master).

---

## 5. Systematic Mechanical Fuzzing Blueprint

To eliminate entire classes of host-compiler bugs before they can invalidate ACL2 or CL proofs, deploy a 4-stage continuous pipeline:

1. **SMT-Guided IR Transform & VOP Verifier (Z3 + Dissolver):**
   - Extract SBCL `deftransform`/`derive-type`/`constraint-propagate-back` predicates and backend VOP instruction semantics (e.g. ARM64/x86-64 shift-amount masking `count & 63`, `UCOMISD`/`COMISD` `PF` flag, modular bit-width cuts `cut-to-width`) into `BitVec`/`Real`/`Int` SMT queries (`verify_w3_z3.py` template).
   - Prioritize every predicate using `(:not ...)`, `truly-the`, `combination-typed-p`, or `when-vop-existsp`: any `SAT` model automatically emits a concrete `(lambda (x ...) ...)` CL test case + ACL2 `(defthm nil-proved ...)` probe.
2. **Differential Context-Position Fuzzer (Value vs. Predicate vs. Effect):**
   - Generate expression ASTs wrapped in **all three continuation contexts**: value return, boolean/branch predicate (`(if (op ...) ...)`), and **for-effect** (`(progn (op ...) :ok)`), across declared, inferred (`if`/`random`/`the`), and unannotated types at `(safety 3)`, `(safety 1)`, and `(speed 3)(safety 0)`.
   - Catches `vreg = NIL` backend crashes (`HC-W3-7`) and dead-code/type-derivation divergences (`HC-W3-5`).
3. **Register-Pressure & Target-Aliasing Cross-Arch Oracle:**
   - Generate deep binary/ternary expression trees (`(- (+ a b) (- c d))`, `(f a (g b c))`) with 2–8 live temporaries per register class (`GPR`, `FPR`, `complex-single`, `complex-double`) and run `(lx86cl64 vs darm64cl vs sbcl-arm64 vs sbcl-x86-64)` under normalized output comparison (`fuzz3.py` template).
   - Explicitly vary constant literal magnitudes at backend encoding boundaries (`#x0fffffff`, `#x10000000`, `2^18`, `2^31`, `2^59`, `2^63`) to hit misplaced-paren/immediate-overflow bugs like `HC-W3-8`.
4. **CL Standard Library Boundary & Case-Equivalence Oracle:**
   - Systematically fuzz sequence/set/string/character primitives (`set-exclusive-or`, `reduce`, `char-equal`, `string-equal`, `equalp`, `substitute`, `mismatch`, `subseq`) with edge inputs: empty sequences `#()`, shared leaf references `(op x x)`, non-zero `:start`/`:end`/`:from-end`, custom `:key` returning tight subranges, and full `[0, char-code-limit)` Unicode equivalence-class partitioning checking symmetry, transitivity, and compiled-vs-`(notinline)` agreement.
