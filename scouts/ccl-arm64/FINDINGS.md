# CCL arm64 scout findings

## Confirmed

**No valid divergence found.** In particular, no wrong value, unexpected error, or crash was reproduced with truthful declarations on the allowed integer/list/character/multiple-value operations. The inherited `ash` report is invalid, as detailed below. No ACL2 soundness bug is claimed; no ACL2 run was needed because no valid raw-CCL divergence survived validation.

Clean fresh-image runs on `ccl` (CCL 1.14 darwinarm64), from this directory:

```sh
/Users/ember/dev/compiler-audit/scouts/lisp-run.sh ccl w1-broad.lisp
/Users/ember/dev/compiler-audit/scouts/lisp-run.sh ccl w3-corrected-core.lisp
/Users/ember/dev/compiler-audit/scouts/lisp-run.sh ccl w4-control-mv.lisp
/Users/ember/dev/compiler-audit/scouts/lisp-run.sh ccl w5-bytes-types.lisp
/Users/ember/dev/compiler-audit/scouts/lisp-run.sh ccl w6-residual.lisp
```

Exact final summaries:

```text
wave1 done: 326 tests, 0 diffs
wave3 done: 2311 tests, 0 diffs
wave4 done: 4553 tests, 0 diffs
wave5 done: 36991 tests, 0 diffs
wave6 done: 2032 tests, 0 diffs
```

That is 46,213 recorded checks, including direct encoder checks and allocation stress as well as optimized/reference comparisons.

## Refuted

### Invalid inherited report

1. **Constant-left-shift / `%ilsl` overflow claim: refuted as a finding.** I re-ran `repro-ash-const-overflow.lisp` and `probe-ash-trigger.lisp` on fresh `ccl` images. The reported differences remain, but every differing input violates its declaration. For example, `(signed-byte 45)` is `-2^44 .. 2^44-1`, whereas the probe passes `2^45-1`; the safety-3 control prints:

   ```text
   Error of type TYPE-ERROR: The value 35184372088831 is not of the expected type (SIGNED-BYTE 45).
   ```

   The same mistake affects the inherited `(signed-byte 60)`, `(signed-byte 59)`, and `(signed-byte 2)` cases. `(the fixnum (ash x 16))` additionally lies about the result type. These are guard/type violations under safety 0, not compiler findings. The source gate in `compiler/acode-rewrite.lisp:852-859` requests signed width `61-shift`, which is exactly the correct bound; the inherited explanation treated `(signed-byte n)` as if its positive endpoint were `2^n-1`.

2. **The inherited `w2-cmp-arith.lisp` run is incomplete and its apparent shift difference is invalid.** It aborts while compiling `mul-i-star` because the type contains unevaluated bounds `(- (expt 2 25))` and `(1- (expt 2 26))`. Its earlier `ash-const-left-bounded` difference is item 1. Corrected independent coverage is in waves 3, 4, and 6 below.

3. **Surrogate `code-char`/`char-code` composition differences are unsafe test calls, not findings.** An early wave-5 version composed `(char-code (code-char n))` for surrogate codes. CCL correctly returns `nil` for those codes; passing that `nil` to `char-code` at safety 0 is then invalid. Another early case directly passed the resulting `nil` to an argument declared `character`. Standalone `code-char`, including surrogate inputs, had already agreed with the reference in wave 1. After removing the invalid calls, wave 5 has zero differences.

4. **Uninitialized high digit in inline `u64->integer`: refuted by the allocator contract and stress test.** The vinsn allocates three digits for u64 values at least `2^63` and stores only the low 64 bits, but `lisp-kernel/arm64-spentry.s:105-108` explicitly documents that allocation returns zero-filled memory, making the third digit zero. Wave 5 also produced the same high-u64 result correctly 10,000 times: `RESULT high-u64-allocation-stress cases=10000 diffs=0`.

### Executed hypothesis families

The following all compared `(optimize (speed 3) (safety 0))` code against calls through `symbol-function` or an independent value-transfer computation, except H22, which intentionally uses safety 3 to reach checked `require-*` templates, and H29/H30, which are direct encoder/allocation checks. All final differences are zero.

1. **H1 — constant left shift / `%ilsl-c`:** `w3-corrected-core.lisp`; shifts 1, 2, 3, 7, 15, 16, 31, 32, 59, 60 with exact signed widths and filtered endpoints.
2. **H2 — constant arithmetic right shift / `%iasr-c`:** wave 3; negative counts through -100, including -60..-65 and both fixnum endpoints.
3. **H3 — constant numerator, variable left shift / `%ilsl`:** wave 3; positive and negative numerators at the largest permitted shift.
4. **H4 — bounded variable `fixnum-ash`:** wave 3; bidirectional and nonnegative-only counts, at all range endpoints.
5. **H5 — `natural-shift-left`:** wave 3; shifts 1, 2, 31, 32, 60..63 with result types truthfully contained in u64.
6. **H6 — `natural-shift-right` and large-right-count zeroing:** wave 3; counts -1 through -100 around 32/60/63/64.
7. **H7 — `%natural+` and high-u64 boxing:** wave 3; two u63 operands, with sums through `2^64-2`.
8. **H8 — guarded `%natural-`:** wave 3; all operand orders around fixnum, sign-bit, and u64 boundaries, with the `the u64` assertion made true by a runtime guard.
9. **H9 — fixnum add/subtract/negate overflow repair:** wave 3; extrema and neighbours, including `most-negative-fixnum` negation.
10. **H10 — one- and two-lane `add-immediate`:** wave 3; positive and negative constants around 12-bit lanes and the signed-24 shifted-constant limit.
11. **H11 — immediate and register fixnum multiplication:** wave 3; signed-16 constants and signed-30 variable pairs with products proven to fit fixnums.
12. **H12 — tagged logical immediates:** wave 3; `logand`, `logior`, and `logxor` with negative masks, alternating-bit patterns, and fixnum endpoints.
13. **H13 — exact-width u64/s64 and narrower identities:** wave 3; `(signed/unsigned-byte 8/16/32/64)` at their true endpoints.
14. **H14 — signed fixnum comparison immediate/register paths:** `w4-control-mv.lisp`; all six predicates, both operand orders, constants around the boxed-immediate boundary, and variable pairs.
15. **H15 — unsigned u64 comparisons:** wave 4; all six predicates across `2^60` and `2^63`.
16. **H16 — binary division relatives of the known unary bug:** wave 4; binary `floor`, `ceiling`, `truncate`, `round`, `mod`, and `rem`, including signs and `most-negative-fixnum / -1`. The already-known one-argument division bug was not re-reported.
17. **H17 — `multiple-value-bind` with missing/excess values:** wave 4; nil filling, truncation, and computed values.
18. **H18 — constant and variable `nth-value`:** wave 4; indices through 60 and out-of-range nil results.
19. **H19 — `logbitp`, `logcount`, and `integer-length`:** wave 4; bit indices 0, 1, 2, 59..65, 100, 255 and signed/u64 bignum values.
20. **H20 — tail self-calls with stack arguments:** wave 4; generated rotating self-calls with 4, 5, 7, 9, 13, 17, 21, and 25 total arguments, checked against a nonrecursive reference.
21. **H21 — tail self-calls returning many values:** wave 4; 2, 3, 4, 6, 8, 12, 16, 20, and 24 returned values after recursion.
22. **H22 — checked `require-s8/s16/s32/s64` and `require-u8/u16/u32/u64`:** `w5-bytes-types.lisp`; valid and invalid values around every exact-width boundary, using safety 3 so checks are required.
23. **H23 — `%natural-logand/logior/logxor`:** wave 5; high-u64 patterns and mixed natural/nonnegative-fixnum operands.
24. **H24 — `ldb` and `mask-field`:** wave 5; sizes 0, 1, 2, 7, 8, 16, 31, 32, 59..65 and positions 0, 1, 31, 32, 59..64, on both general integers and the fixnum-specific compiler-macro path.
25. **H25 — `dpb` and `deposit-field`:** wave 5; sizes through 65 and positions through 64, with negative and high-u64 values.
26. **H26 — derived arithmetic/predicate rewrites:** wave 5; `abs`, `signum`, `evenp`, `oddp`, `zerop`, `plusp`, `minusp`, `min`, `max`, and `logtest` at fixnum boundaries.
27. **H27 — valid character conversions:** wave 5; `code-char`/`char-code` round trips and arithmetic at UTF-16 and Unicode boundaries, excluding surrogate codes for which `code-char` returns nil.
28. **H28 — list inline operations:** wave 5; valid `cons`, `car`, `cdr`, `consp`, and `endp` cases.
29. **H29 — AArch64 logical-immediate encoding:** wave 5; exhaustive contiguous-run lengths and rotations at pattern widths 2, 4, 8, 16, 32, and 64. Exact output: `RESULT logical-immediate-roundtrip cases=5334 encoded=5334 missing=0 tagged-compatible=2433 diffs=0`. This replaced an initial random tagged-integer probe that selected zero encodable masks and was therefore vacuous.
30. **H30 — high-u64 allocation reuse:** wave 5; 10,000 inline natural additions producing `2^64-2`, zero differences.
31. **H31 — `1+`, `1-`, and nested additions:** `w6-residual.lisp`; fixnum endpoints and intermediate/final overflow.
32. **H32 — multiply-by-power-of-two to shift rewrite:** wave 6; valid exact-width endpoints for exponents 1, 2, 3, 7, 15, 16, 31, 32, 59, and 60 (only constants below `2^24` are eligible for the frontend rewrite; the larger cases are controls).
33. **H33 — u64 comparisons against constants:** wave 6; all predicates and both operand orders with fixnum and bignum constants through `2^64-1`.
34. **H34 — composite logical rewrites:** wave 6; `logandc1`, `logandc2`, `logorc1`, `logorc2`, `lognand`, `lognor`, and `logeqv` on fixnum boundaries.
35. **H35 — very large `nth-value` indices:** wave 6; 60, 61, 1000, `2^32`, and `most-positive-fixnum`, all returning the correct nil without index-arithmetic wrap.
36. **H36 — wide `multiple-value-bind`:** wave 6; 20 bindings with 1, 19, 20, 21, and 24 supplied values.
37. **H37 — `multiple-value-prog1`:** wave 6; preservation of four values across later arithmetic forms.

## Not checked

- **Instrumented proof of template selection for each final probe.** Declarations and rewrites were chosen from the source paths, but the clean differential runs themselves do not prove that every intended vinsn was emitted. A coverage-instrumented rerun is the best next step if this distinction matters.
- **Internal-only operators outside the allowed ACL2 surface.** `%word-to-int`, `u64-popcount`, and direct `%ilsr`/`%ilsl` calls were not separately unit-tested. Standard operations that lower to the relevant public paths were tested instead; an internal-only defect would not satisfy this scout's requested function shape.
- **Arrays, floats, FFI, structs, and other unreached arm64 handlers** outside the integer/list/character/multiple-value scope.
- **ACL2 proof-level consequences.** No valid host divergence was found, so no ACL2 reproducer or soundness experiment was performed.
