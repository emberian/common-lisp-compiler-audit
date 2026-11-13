# Derived-type oracle: host-compiler result types against ACL2's logic

RESEARCH.md recommendation 3. ACL2 compiles at `safety 0, speed 3`, so whatever result type
the host compiler infers for a call is trusted by the code around it. This directory records
those inferred types for ACL2's built-ins and checks each against the function's logical
value on guard-satisfying inputs. Hosts: SBCL 2.6.10 and CCL 1.14, darwin arm64, ACL2 at
1d2b39a424. Run on 2026-11-13.

## Result

| | SBCL | CCL |
|---|---|---|
| operators with typed rows | 265 | 264 |
| rows (operator x declared signature) | 35,624 | 35,608 |
| A-top: derived type is `T` | 5,123 | 19,197 |
| A-narrow: narrower than `T`, contains the range | 30,345 | 16,395 |
| B: narrower, excludes only unconstructible values | 156 (13 operators) | 16 (1 operator) |
| **C: narrower, excludes a constructible value** | **0** | **0** |
| guard-satisfying boundary tuples | 679,304 | 675,515 |
| membership / value checks | 7,073,399 | 6,974,697 |
| planted control reported | yes | yes |

Zero rows in class C on either host for the host compilers' inferred types. Three defects were
found on the way; none is an inferred-type row, each has a two-value test under `repros/`:

| repro | what | SBCL | CCL |
|---|---|---|---|
| `repros/stale-df-ftype/` | step 4 (ACL2's own ftype proclamation). `proclaim-dfs` proclaims `(function (double-float) double-float)` for a df function; after `:u` and a non-df `defun` of the same name the proclamation is still in force on CCL, and a guard-verified caller is compiled against it | 2361183241434822606850 / 2361183241434822606850 | **1.0E-323** / 2361183241434822606850 |
| `repros/count-eql-vs-equal/` | ACL2: `count` is a logic macro for `count-fn` (elements compared with `equal`) but is `#+acl2-loop-only`, so raw Lisp uses `cl:count` (`eql`). `(count (list 1) (list (list 1)))` | **0** / 1 | **0** / 1 |
| `repros/ccl-ash-near-fixnum-limit/` | CCL runtime: `(ash 1 k)` for fixnum `k` within a few bits of 2^60 returns a malformed object instead of signalling (`%ash-left`, `level-0/l0-numbers.lisp`: `(+ length shift)` wraps in fixnum arithmetic). `(integer-length (ash 1 (1- (expt 2 60))))`, logically 2^60 | error "can't represent result of left shift" (correct) | **-1152921504606846976** / -1152921504606846976 |

Ledger: claim T1, findings F13, F14, F15 in that order. Values are "guard-verified / not guard-verified". In the third both routes reach the same raw
`ash`, so they agree with each other and disagree with the logic; plain CCL gives the same
value (`plain-ccl.lisp`). The same defect kills the CCL process (Mach exception) on
`(unsigned-byte-p 1152921504606846975 0)`, logically `T`. `repros/*/observed-HOST.txt` hold
the output of `run.sh HOST` in a fresh session.

`repros/ccl-ash-near-fixnum-limit/prior-agent/` is the previous worker's version of that repro,
which goes further than a two-value test (a book ending in a theorem `nil`). It was not re-run
here and is not needed for the report.

## Method

Everything runs in raw Lisp inside the saved ACL2 image, so ACL2's global `optimize`
proclamation and its `inline`/`notinline`/`ftype` proclamations are in force.

**Known case first.** `scratch/k1.lisp`: `(lambda (x) (integer-length x))` reports
`(unsigned-byte 38)` and `(lambda (x) (length x))` reports `(unsigned-byte 45)`, as RESEARCH.md
says; `(len x)` reports `(unsigned-byte 62)`. A planted false declaration,
`(the (unsigned-byte 8) (binary-+ a 1))`, is carried through stage 2 as the operator
`DT-CONTROL-FALSE-NARROWING` and is reported as `RESULT-NOT-IN-DERIVED` on both hosts.

**Stage 1, enumeration (`stage1.lisp`, `stage1-ccl.lisp`).** Every symbol with a `formals`
property in the boot-strap world, 6,542 functions, and every symbol with a `macro-body`, 1,896
macros (68 of which are host functions in raw Lisp). For each: what the host knows about it
(inline, ftype, compiler transforms) and the derived type of a call with undeclared arguments.
`results/HOST-enumeration.tsv`; classified for SBCL in `results/sbcl-unconstrained-table.tsv`:
6,388 `T`, 144 narrower and containing the range, 9 class B, 1 special form (`if`), 6 logic
functions that are raw macros (derived type recorded, not classified further). On CCL 6,457
are `T` and 78 narrower (`results/ccl-unconstrained-counts.json`).

**Stage 2, typed signatures (`stage2.lisp`, `run-stage2.sh`).** Targets are the functions a
call site can learn anything about: all of `*primitive-formals-and-guards*` (32, less `if`),
every world function in the `COMMON-LISP` package, proclaimed inline, given an ftype, or known
to the compiler (SBCL `fun-info`; CCL nx1 handler or compiler macro): 186 on SBCL. Added to
these are 92 call forms of the logic macros whose raw counterpart is a host function (`+`,
`logand`, `append`, `count`, `position`, `member`, `c[ad]+r`, ... at arities 1 to 3). For each
operator and each tuple of declared argument types drawn from `t bit (unsigned-byte 8)
(signed-byte 61) fixnum (unsigned-byte 64) (signed-byte 64) (integer 0 *) integer rational
(complex rational) character standard-char string symbol cons` (`t double-float` for df
operators) it compiles

    (lambda (a b) (declare (type T1 a) (type T2 b)) (values (OP a b) a b))

and reads `sb-kernel:%simple-fun-type` (the result type and the argument types after the
call). Signatures are only compiled when some boundary tuple satisfies them and the guard.
Boundary tuples come from a universe of 38 integers at the 8, 31, 32, 60, 62, 63, 64-bit seams
and 10^40, plus rationals, complex rationals, characters, strings, symbols, lists and two ACL2
arrays (`dt-universe`). For each tuple that satisfies the declared types and OP's guard:

- `RESULT-NOT-IN-DERIVED`: the value is not `typep` the derived result type (class C);
- `ARG-NOT-IN-DERIVED`: an argument is not of its derived post-call type (class C);
- `VALUE-MISMATCH`: the compiled typed lambda returns something else.

The reference value is ACL2's evaluator `ev-w` with guard checking on, which also decides
whether the tuple satisfies the guard, so no guard-violating tuple reaches raw code. For
guard-verified built-ins the evaluator itself runs the host's out-of-line code; logical
definition against raw code is ledger claim P1, not this one.

**Classification (`classify.py`, `classify-stage1.py`).** A-top: derived type `T`. C: a
`*-NOT-IN-DERIVED` row. B: one of the rules below. A-narrow: everything else.

How class A-narrow was decided: every boundary tuple is a member (the counts above), and the
distinct (operator, type) pairs were read by hand. Types without numbers (`BOOLEAN`, `LIST`,
`CONS`, `NULL`, `INTEGER`, ...) are listed per operator by the one-liner in "Re-run". Types with
numeric bounds where every declared argument is bounded follow from the argument bounds and
are checked at the interval corners. Types with a bound of six or more digits and an unbounded
argument that no B rule claimed are written to `results/HOST-review-large-bounds.tsv`
(45 shapes on SBCL, 1 on CCL); each is implied by the bounded argument (for example
`(rem (integer 0 *) fixnum)` is `(unsigned-byte 62)`) or is a superset
(`char-code`: `(mod 1114112)`).

Class B rules, all from limits the host hard-codes:

| operators (SBCL) | derived | bound and reason | rows |
|---|---|---|---|
| `integer-length`, `logcount` | `(unsigned-byte 38)` | a bignum has at most 2^32-1 64-bit words (`sb-bignum:maximum-bignum-length`; `bignum.lisp` signals past it) | 8 |
| `length` of a cons | `(integer 1 274877906943)` | `max-dynamic-space-size` is 2^42 bytes, a cons is 16 | 1 |
| `length`, `count`, `string<` `<=` `>` `>=`, `symbol<` | `(unsigned-byte 45)` | `array-dimension-limit` is 2^45 (2^42 bytes of bits) | 70 |
| `position`, `search` | `(mod 35184372088831)` | an index is below a length | 75 |
| `len` | `(unsigned-byte 62)` | ACL2's `(declaim (ftype (function (t) fixnum) len))`; the raw loop signals at `most-positive-fixnum`; 2^62 conses need 2^66 bytes | 2 |

On CCL the only B rows are `len` -> `fixnum` (16 rows, same declaration; 2^60 conses).
The ACL2 images here run with a 32 GB heap, far below every bound.

**Step 4, ACL2's own ftype declarations.** `grep -n ftype *.lisp` in the ACL2 sources, read by
hand. In force on these hosts: `len` (fixnum; class B above, boundary tuples in stage 2);
`apply$`, `tamep-functionp`, `large-consp`, `ser-decode-from-stream`,
`output-type-for-declare-form-rec(-list)` (all `(values t)`, nothing to compare); local
`(declare (ftype ... (values t)))` forms (same); and `proclaim-dfs` (`interface-raw.lisp`),
which proclaims double-float signatures for every user function with a `:df` input or output.
For the last: a df function at boundary inputs agrees on both hosts
(`scratch/df-boundary.lsp`: 2^-100, -1, 2^200 agree; 2^1000 signals overflow on both routes),
and the proclamation outliving the function is `repros/stale-df-ftype/`. On SBCL the new
`defun` replaces the proclaimed type, which is why SBCL is unaffected. `make-defun-declare-form`
ftypes are GCL-only (`*do-proclaims*`).

**Step 5, CCL.** CCL does expose inferred types, more coarsely than SBCL.
`compiler/nx0.lisp`: `acode-form-type` gives a type for any acode node from
`*acode-operator-types*` (a static type per operator, `results/ccl-acode-operator-types.tsv`:
267 operators, 81 of them `:infer`), 18 `def-simple-type-infer` inferrers, declared variable
types and `typed-form` nodes; `compiler/acode-rewrite.lisp` refines it. `common.lisp` wraps
`ccl::rewrite-acode-form`, keeps the lambda's acode after rewriting, and reads
`acode-form-type` of its body. What cannot be read: there is no per-function derived type
stored on a compiled function, no post-call argument types, and nothing later than acode
(the vinsn back end selects on these types but records none).

## Re-run

    ./run-sbcl.sh stage1.lisp 900          # results/sbcl-enumeration.tsv
    ./run-ccl.sh stage1-ccl.lisp 900       # results/ccl-enumeration.tsv, ccl-acode-operator-types.tsv
    ./run-stage2.sh sbcl                   # about 12 minutes; results/sbcl-{summary,signatures,violations}.tsv
    ./run-stage2.sh ccl                    # under an hour, three restarts expected (below)
    python3 classify.py sbcl; python3 classify.py ccl; python3 classify-stage1.py
    repros/NAME/run.sh sbcl; repros/NAME/run.sh ccl
    # structural types per operator:
    awk -F'\t' '$4=="A-narrow" && $3 !~ /[0-9]/ {print $3"\t"$1}' results/sbcl-table.tsv | sort -u

Every Lisp runs under `nice` and `timeout`; `run-stage2.sh` writes `results/HOST-driver.pid`
and `results/HOST-stage2.pid`. If the Lisp dies, the driver records the operator in
`results/HOST-crashed.txt` and resumes; an operator that crashed once is re-run without
integers of more than 33 bits. On CCL that happens for `unsigned-byte-p`, `signed-byte-p` and
`ash` (the `ash` defect above; `results/ccl-crash-N.log`).

Files in `results/`: `HOST-table.tsv` is the classified table (operator, declared types,
derived result, class, bound, reason, tuples checked); `HOST-counts.json` the counts;
`HOST-signatures.tsv` the raw rows including SBCL post-call argument types or the CCL acode
operator; `HOST-violations.tsv` the control rows and the two `count` rows.

## Not covered

- Logical definition against raw code at these boundary inputs: the reference is the
  evaluator with guard checking on (see Method). `count` was caught only because its raw
  counterpart is a different function.
- 11 targets excluded: 4 take `state`, 7 for side effects or allocation, `make-list` among
  them (`results/HOST-counts.json`, `excluded`). No target has more than 4 arguments.
- `pkg-witness`, `pkg-imports`, `bad-atom<=`: no universe tuple satisfies the guard.
- The 6 logic functions that are raw macros (`zp-big-n`, `decrement-big-n`, `to-df`,
  `wormhole-eval`, `mv-list`, `return-last`): stage 1 only. The 1,828 logic macros that are
  not host functions in raw Lisp: not measured.
- The return types SBCL recorded for ACL2's own definitions (`sbcl-enumeration.tsv`, column
  `declared-or-recorded-ftype`; 248 have numeric bounds) are listed, not compared. SBCL does
  not use them at call sites here (`*derive-function-types*` is NIL; stage 1 shows such calls
  derive `T`).
- Keyword arguments other than `:test 'eq`; `subseq`, `search` and `position` with
  `:start`/`:end`. Arity 3 uses a 51-object universe and arity 4 a 15-object one.
- CCL on `ash`, `unsigned-byte-p`, `signed-byte-p` with integers above 33 bits; `check-sum-obj`
  is a target on SBCL only.
- 112 (SBCL) and 219 (CCL) reference evaluations hit the 0.3 s cap and were dropped; 592 and
  149 slow tuples (very large results) had the membership check but not the compiled call.
- Class A-narrow rests on boundary sampling and reading, not on a proof of containment.
- Compiled files and `include-book`: only `compile` in a live session was measured.
- The stale proclamation was tried only for the df case and only through `:u`.
