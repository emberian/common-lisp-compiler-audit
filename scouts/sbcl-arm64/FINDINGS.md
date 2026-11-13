# FINDINGS — SBCL arm64 inline arithmetic scout

Host: SBCL 2.6.10, ARM64 Darwin, fresh images via
`/Users/ember/dev/compiler-audit/scouts/lisp-run.sh sbcl <relative-script>`.
Source tree `/Users/ember/dev/sbcl` HEAD=076335724 (2026-11-12), newer than
installed 2.6.10. Final differential runs use `(speed 3) (safety 0)` and only
arguments satisfying their declarations, except where a harness artifact is
explicitly being explained.

## Confirmed

(none)

No SBCL value divergence survived correction and reproduction, so there was no
candidate to port to `acl2-sbcl`.

## Refuted / attempted

### Previous worker: reruns and corrections

1. **move-if/word equal constants (af7cdfe71, post-release).** Re-ran
   `probe-a-move-if.lisp`, `probe-a2-disasm.lisp`, and
   `probe-a3-shapes.lisp`: no value divergence. Equal-constant `if` forms were
   folded before the VOP; the unequal-constant control emitted `CSEL`. This does
   not prove the vulnerable VOP state unreachable.
2. **overflow+t/-t on declared s128 operands (29d0bbc7f, post-release).**
   Re-ran `probe-b-overflow-s128.lisp`: full calls were selected and values
   agreed. Large-x calls in that script also violate its `(the fixnum ...)`
   result assertion; they are not candidate findings. No transform was reached
   even on valid fixnum-valued inputs.
3. **ash-into-word-mod for s128 (076335724, post-release).** Re-ran
   `probe-c-ash-mod.lisp`: no mismatch. `probe-j-post-release.lisp` then covered
   direct s128 inputs and s128-producing sums/products, variable counts
   -130..130, and u64/fixnum masks: `probe J done, fails=0`.
4. **ash-left-c/fixnum=>s128 around amount 65 and wrap past s128.** Re-ran
   probes D, E, F, and F2. Constant shifts and high-word/sign consumers agreed
   with generic `ash`; out-of-s128 result ranges used full calls where needed.
5. **Old probe G's 92 reported failures are harness artifacts.** Re-running
   `probe-g-battery.lisp` reproduces `fails=92`. Most entries compare distinct
   condition objects using `equalp`; the others are enormous left shifts where
   generic `ash` reports `can't represent result of left shift` while a modular
   mask returns the mathematically correct low bits. Its final fixnum subcase
   also uses the invalid type specifier `(fixnum)`.
6. **Old probe I originally tested neither I1 nor I2 correctly.** I1 supplied
   one list to a two-argument function; I2 supplied a type specifier as x. After
   correcting those, two further artifacts appeared: both functions mutated the
   same array sequentially, and one signed-64 comparison received u64 maximum.
   The final `probe-i-mixed.lisp` uses independent initial arrays, filters inputs
   by declaration, and leaves only the target operation notinline. Final output:
   `I1 done, fails=0`, `I2 done, fails=0`, `I3 done, fails=0`.
7. **`smoke.lisp` is not a reproducer.** It applies values outside declared
   types and constructs a one-argument reference for two-argument `ash`.
8. **Shared `quiet-compile` originally returned a captured output string rather
   than the compiled function.** This affected old H/I and the first versions of
   new K–R. `harness.lisp` and all new helpers now save and return the actual
   function. H and every K–R probe were rerun after the fix; only the final runs
   are used as evidence below.

### New executed hypotheses

9. **Post-release recursive-result inference (e7fd560f7).** Probe J ran the
   three exact upstream regression shapes. Their tested input `T` returns `:OK`;
   `NIL` returns `:BAD` as the source logic dictates.
10. **select-tagging stale costs and constant initial values (017564a7a,
    45bd6e948).** Probe J checked the exact logxor/u32-array shape and the
    conditional-initial-value logand shape with fresh arrays. Values and array
    contents agreed.
11. **integer-length comparison transforms.** Final
    `probe-k-bit-transforms.lisp` tested `= < > <= >=` against constants
    0,1,2,3,62,63,64,65,126..129 for fixnum/s64/u64/s128/integer. No mismatch.
12. **logcount and abs rewrites.** Probe K tested logcount/lognot/shift/
    multiply contexts, logcount versus integer-length, and abs compared by
    `= eql < >` to negative and positive constants. No mismatch.
13. **nested logbitp/logtest transforms.** Probe K tested lognot, shifts,
    logand/logior around bit indices 0,1,2,61..65,126..128 and signed/unsigned
    masks. No mismatch.
14. **variable-count ash near 63/64/127/128.** Probe K tested direct ash and
    u64/fixnum modular masks for fixnum/s64/u64/s128 at counts -130..130. Final
    summary for all K families: `cases=972 fails=0`.
15. **direct s128 arithmetic and mixed comparisons.** Final
    `probe-l-s128.lisp` tested +,-,*,logand,logior,logxor,logeqv,min,max,<,<=,=,
    >,>= on s128 pairs and mixed s128/s64/u64 operands, including mathematical
    results beyond signed 128. No mismatch.
16. **s128 unary and multiple-consumer representation changes.** Probe L tested
    negate/abs/lognot/integer-length/logcount/parity and boxed, shifted, masked,
    compared, and counted views of one s64-produced s128 result. Final summary:
    `cases=112 fails=0`.
17. **division destination contexts.** Final
    `probe-m-division-contexts.lisp` ran 2,550 cases: remainder/mod divisibility
    and sign predicates, nested abs+truncate/floor/ceiling with signed constant
    divisors, same-variable division, and valid checked-fixnum results.
    `fails=0`. The original direct division/bit probe H was also rerun with the
    corrected shared helper: H1/H2/H3 all `fails=0`.
18. **range<, range<=, and integer range type checks.** Final
    `probe-o-ranges.lisp` ran 4,343 cases with constant and variable bounds at
    fixnum/s64/u64/s128 edges. `fails=0`.
19. **negative count in overflow-ash-unsigned.** The source passes a negative
    constant to `lsr`, unlike its signed neighbor. Final
    `probe-n-overflow-ash.lisp` used truthful fixnum result declarations
    (notably u64 with count -2) and found no mismatch; disassembly is
    `LSR NL0, NL0, #2`. The suspicious VOP arm was not selected by these forms.
20. **large constant +,-,*, including u64 minus negative constants.** Final
    `probe-p-constant-arith.lisp` ran 1,224 forms over word/s128 boundaries and
    both argument orders. `fails=0`.
21. **expt transforms.** Final `probe-q-expt.lisp` executed variable and
    constant bases/powers, signed exponents, power-of-two bases, decimal bases,
    and reciprocal-producing forms: 7,899 calls. The 16 printed differences are
    only `division-by-zero` for zero to a negative power, with inline `/ 1 0`
    versus generic `EXPT 0 n` in the message. There is no value mismatch. Six
    transient apparent values in an earlier transcript came from passing two
    arguments to one-argument test functions; that call bug was fixed and the
    final transcript no longer contains them.
22. **constraint propagation and lvar annotations (34bab7d61).** Final
    `probe-r-constraints.lisp` ran annotated if tests, positive/negative and
    equality branches, typep narrowing, and the exact list/check-type source
    regression: 181 cases, `fails=0`.
23. **select-tagging through local recursive variables (cbc4c85d4).** Probe R
    evaluated the exact parser-like local-function graph. Results included
    `"123x45" => 168`, `"999999999999999999" => 999999999999999999`, and
    `"1x2x3" => 6`, all expected.
24. **ARM64 logical-immediate encoding.** Final
    `probe-s-logical-constants.lisp` tested logand/logior/logxor/logeqv in both
    argument orders over sign-bit, high/low-word, alternating-bit, and
    single-bit-clear constants: 2,520 forms, `fails=0`.
25. **bignum modular shifts beyond s128.** Final
    `probe-t-wide-bignum.lisp` tested values through 256 bits, variable and
    constant counts -320..320, word/fixnum masks, logbitp above bit 128,
    integer-length, and logcount: 134 form families, `fails=0`.

## Not checked (most promising first)

- Register-allocation pressure specifically forcing each `location=` alias in
  s128 shifts and multiplication. Value batteries do not prove those particular
  assignments; a future probe should inspect disassembly while varying live
  temporaries and multiple-use graphs.
- More elaborate select-tagging graphs involving assigned variables, calls, and
  `check-bound` together. Existing upstream additions are mostly IR-cost tests;
  a semantic wrong-value trigger remains uncertain.
- Constraint/lvar-annotation interaction from 34bab7d61 under deeper local-call
  and recursive graphs than the source regression and probe R.
- Rational/ratio-constant association transforms and ACL2-relevant character
  code transforms.
- Modular forms whose generic reference deliberately avoids huge intermediate
  allocation; current huge-shift differences are resource/error behavior, not
  wrong mathematical values.
