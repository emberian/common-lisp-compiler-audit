# FINDINGS — things ACL2 recomputes after certification (acl2-rederive scout)

Ground truth: ACL2 8.7+ dev, commit `1d2b39a424`; `acl2-sbcl` = SBCL 2.6.10, `acl2-ccl` = CCL 1.14 darwin arm64. All work is in this directory. Commands below use `../lisp-run.sh HOST SCRIPT` from this directory; full transcripts are `SCRIPT.HOST.out`.

**Result: no wrong VALUE and no soundness bug found.** More than a dozen independent re-derivation hypotheses were executed on fresh images, with the substantive value comparisons run on both hosts. Two error/crash divergences from the prior worker were independently reproduced and retained.

## Confirmed

### C1. `loop$`: a certified book installs a function that errors when called (known bug, re-run on both hosts)

Files: `t1-book.lisp`, `t1-cert.in`, `t1-inc.in`.

Exact commands:

```
../lisp-run.sh acl2-sbcl t1-cert.in
../lisp-run.sh acl2-sbcl t1-inc.in
../lisp-run.sh acl2-ccl t1-cert.in
../lisp-run.sh acl2-ccl t1-inc.in
```

The book has `(set-ignore-ok t)` and a `loop$` body with an unused `let` variable. Certification and `include-book` succeed on both hosts. `(f 1)` then produces an **ERROR where the value `6` was expected**:

```
ACL2 Error in ACL2-INTERFACE:  Implementation error: translate11-loop$
in oneify encountered an untranslatable LOOP$, (LOOP$ FOR K FROM 0 TO 3 ...).
We thought that this could only happen under a call of non-exec, in
which case we should never be executing this code!  Please contact
the ACL2 implementors.
...
ABORTING from raw Lisp
```

Control: `repro-loop-inc-nocomp.in` uses `(include-book "t1-book" :load-compiled-file nil)` and returns `6` on **both hosts**. Thus the error is specific to the compiled/re-derived definition path, not unavoidable source-event replay. `t2-book.lisp`, whose loop body has no unused variable, returns `10` after ordinary include on both hosts (`inc-t2.in.*.out`).

### C2. `lambda$`: the same context mismatch aborts certification itself

Files: `t5-book.lisp`, `cert3.in`; also `repro-lambda-nocompile-cert.in`.

Exact commands:

```
../lisp-run.sh acl2-sbcl cert3.in
../lisp-run.sh acl2-ccl cert3.in
../lisp-run.sh acl2-sbcl repro-lambda-nocompile-cert.in
```

The book contains `(set-ignore-ok t)` and `(collect$ (lambda$ (y) (let ((unused y)) y)) ...)`. The function is admitted, then certification reaches a raw-Lisp implementation error on **both hosts**:

```
ACL2 Error in ACL2-INTERFACE:  Implementation error: Translate11-lambda-
object in oneify encountered an untranslatable LAMBDA$,
(LAMBDA$ (Y) (LET ((UNUSED Y)) Y)), even though it was supposedly translated
successfully earlier.  Please contact the ACL2 implementors.
...
ABORTING from raw Lisp
```

Unlike C1's delayed call-time error, the `lambda$` branch calls `interface-er` immediately. Passing `0 nil` to `certify-book` to disable its compile flag still fails the same way on SBCL, so the failure is not confined to the host's final `compile-file` call. This is a **certification failure/raw-Lisp error**, not a wrong value.

## Refuted / intended behavior

### R1. Non-exported `acl2-defaults-table` is intentional, not a standalone bug

The prior report's “silently dropped” wording and its generalization beyond the tested key were corrected. `doc.lisp:4954-4962` explicitly says `include-book`, `certify-book`, and `encapsulate` restore the prior table and changes inside books do not persist. `other-events.lisp:4002-4006` says the same. The whole table is restored by mechanism, so this applies to all keys, not only `:ignore-ok`.

`probe-table.in` was re-run on **both hosts**: `:ignore-ok` is absent after include and a later unrelated definition with an unused variable fails. This is intended restoration, but it is the context mismatch behind C1/C2. Direct runtime/key probes also covered `:defun-mode` (R16) and `:let*-abstractionp` (R18).

### R2. A different certifying-session macro does not silently change an included function

`mac1-book.lisp`, certified by `cert-mac1.in` with `my-mac = (+ x 1)`, was included by `inc-mac1-bad.in` after defining `my-mac = (+ x 100)`. Re-run on SBCL: the portcullis replays the original `defmacro`; the includer's conflicting definition causes a redefinition error and include fails without installing `f`.

The prior worker's `thm` forms were syntactically invalid because `thm` does not accept `:rule-classes`; they were not used as evidence.

### R3. Certified `make-event` expansions are reused when `ld-skip-proofsp` differs

Files: `repro-make-event-skip-book.lisp`, `repro-make-event-skip-{cert,inc,ld}.in`.

The book's expansion returns constant `CERTIFY` when `ld-skip-proofsp` is nil and `INCLUDE` otherwise. On **both hosts**, certification and ordinary include print `(CERTIFY CERTIFY)`; SBCL source `ld` also prints `(CERTIFY CERTIFY)`. The include does not re-evaluate the context-sensitive expansion (`repro-make-event-skip-*.out`).

### R4. Certified `make-event` expansion is also stable in a richer includer world

Files: `repro-make-event-world-book.lisp`, `repro-make-event-world-{cert,inc-rich,inc-rich-nocomp,ld-rich}.in`.

The book expands to `RICH` if `*include-marker*` already has a `const` property and to `BASE` otherwise. Certification in the base world yields `(BASE BASE)`. After predefining the marker, both compiled include and `:load-compiled-file nil` still yield `(BASE BASE)` on **both hosts**. As a positive control that the expression really is world-sensitive, SBCL `ld` in the rich world yields `(RICH RICH)`. Certificate substitution, not recomputation, wins.

### R5. An exported `defconst` depending on a local helper is rejected as a local incompatibility

Files: `repro-local-defconst-book.lisp`, `repro-local-defconst-cert.in`.

On SBCL, pass 1 evaluates the local helper and defines the constant, then pass 2 rejects the same `defconst` because `LOCAL-CHOICE` is no longer defined. Certification fails with “The error reported above is the manifestation of a local incompatibility.” There is no certified artifact from which a wrong value could arise.

### R6. Unequal `mbe` branches do not give a certified `defconst` mismatch

Two attempts were executed:

- `repro-defconst-mbe-book.lisp`: `defconst` over an unverified function with `:logic 'LOGICAL` and `:exec 'EXECUTIVE` fails on SBCL during safe-mode evaluation. The reported `RETURN-LAST` guard requires the two branches to be equal.
- `repro-defconst-mbe-vg-book.lisp`: attempting `verify-guards` on that unequal-`mbe` function also fails its guard conjecture on SBCL.

By contrast, `repro-oneify-constructs-book.lisp` contains an `mbe` whose branches are equal and works on both hosts (R10). Thus the tempting `defconst`/`mbe` wrong-value route is blocked before certification; an intentional logical/executed difference from unverified unequal `mbe` code would not be a certified-book finding.

### R7. Successful nonquoted `defconst` agrees in all three loading modes

Files: `repro-defconst-plain-book.lisp`, `repro-defconst-plain-{cert,inc,inc-nocomp,ld}.in`.

The book defines `DC-TWO`, then `(defconst *dc-two-value* (dc-two))`. On **both hosts**, certification, compiled include, include with `:load-compiled-file nil`, and source `ld` print:

```
(2 2 '2)
```

The third item is the logical `const` property. No raw/logical value split occurred.

### R8. Attachments are deliberately ignored in `defconst` evaluation

Files: `repro-defconst-attachment-book.lisp`, `repro-defconst-attachment-cert.in`.

On **both hosts**, the constrained function and attachment are admitted, but the subsequent `(defconst *dc-attach-value* (dc-attach-f 5))` fails:

```
ACL2 cannot ev the call of non-executable function DC-ATTACH-F ...
Note that because of logical considerations, attachments (including
DC-ATTACH-G) must not be called in this context.  See :DOC ignored-attachment.
```

So the compiled `defconst` re-evaluation path cannot be used to smuggle an evaluation-theory-only attachment value into a certified logical constant.

### R9. Ordinary `defattach` replay gives the same executed value

Files: `repro-defattach-book.lisp`, `repro-defattach-{cert,inc,inc-nocomp}.in`.

On **both hosts**, certification, compiled include, and no-compiled-file include all evaluate `(attach-h 3)` to `(ATTACHED 3)`. This is the documented evaluation-theory behavior, not a proof-theory result.

### R10. `oneify` controls for `flet`, `macrolet`, `ec-call`, and equal `mbe` agree

Files: `repro-oneify-constructs-book.lisp`, `repro-oneify-constructs-{cert,inc,inc-nocomp,ld}.in`.

On **both hosts**, certification, compiled include, and no-compiled-file include evaluate `(oneify-control-values 5)` to:

```
((3 . 3) (4 . 4) 5 6)
```

SBCL source `ld` gives the same result. No wrong-value divergence was found in these recursive transformations.

### R11. `ec-call` capturing an `flet`-bound function is rejected

Files: `repro-flet-ec-call-book.lisp`, `repro-flet-ec-call-cert.in`.

On **both hosts**, certification rejects the definition with:

```
The argument (FLET-EC-F 3) is illegal for EC-CALL, because FLET-EC-F is
bound by a superior FLET form.  See :DOC ec-call.
```

This matches `books/system/tests/ec-call-under-flet.lisp`; the previously dangerous raw/logical split is prevented during translation.

### R12. `with-local-stobj` and nested `stobj-let` agree

Local-stobj files: `repro-local-stobj-book.lisp`, `repro-local-stobj-{cert,inc,inc-nocomp}.in`. On **both hosts**, the result is `9` in all three modes.

Nested-stobj files: `repro-stobj-let-book.lisp`, `repro-stobj-let-{cert,inc,inc-nocomp}.in`. On **both hosts**, the result is:

```
((7 DONE) <nest-mom>)
```

The printed `<nest-mom>` is the live stobj; the computed ordinary value is `(7 DONE)`. Earlier transcript versions with translation errors were caller mistakes (a global stobj was not returned from its lexical binding), not findings.

### R13. Built-in warrants/badges used by `apply$` do not change values

Files: `repro-apply-builtin-book.lisp`, `repro-apply-builtin-{cert,inc,inc-nocomp}.in`.

The book applies built-in `car` and maps a `lambda$`. On **both hosts**, all three modes return:

```
(4 (5 6))
```

A separate new-`defwarrant` experiment could not get past its explicit prerequisite; see Not checked.

### R14. Reader constants are consistent; book-local `#.` is rejected before events

Portcullis-constant files: `repro-reader-const-book.lisp`, `repro-reader-const-{cert,inc,ld}.in`. The source contains `'#.*reader-const*`, with the constant defined in the certification session. On **both hosts**, certification and include return `(1 2)`; SBCL source `ld` also returns `(1 2)`.

Book-local-constant files: `repro-sharp-dot-internal-book.lisp`, `repro-sharp-dot-internal-cert.in`. On SBCL, certification fails in Step 1 because the whole book is read before its `defconst` is evaluated. This is exactly `doc.lisp:141949-141952`, Remark (2). `read-object` also binds `*read-base*` to 10 and uses `*acl2-readtable*` (`axioms.lisp:20529-20535`), ruling out includer read-base/readtable state as a legitimate value-changing channel.

### R15. Includer `:program` default does not reclassify a book's plain definition

Files: `repro-default-mode-book.lisp`, `repro-default-mode-{cert,inc-program}.in`.

After `(program)` in the includer, include still leaves `default-mode-f` as `:IDEAL` (logic mode, guards unverified) and returns:

```
(:IDEAL (3 . 3))
```

on **both hosts**. This matches the forced `:defun-mode :logic` at `other-events.lisp:5763-5780`; the includer's default is restored afterward.

### R16. Both forms of program-to-logic reclassification preserve values

Within-book `verify-termination`: `repro-reclassify-book.lisp`, `repro-reclassify-{cert,inc}.in`. On **both hosts**, `reclass-f` ends as `:IDEAL`, with values `(3 . 3)` and `(4 . 4)`.

Redundant include over an existing identical `:program` definition: `repro-redundant-reclass-book.lisp`, `repro-redundant-reclass-{cert,inc,inc-nocomp}.in`. On **both hosts**, compiled and no-compiled-file include produce:

```
(:IDEAL (3 . 3) (4 . 4))
```

The prior worker's `prog1-book.lisp` was not a valid experiment: its current body fails admission (“Translate failed to determine the output signature”), and its old transcript described a different body. The valid books above replace that probe.

### R17. `let*` abstraction setting does not change value or leak through include

Files: `repro-let-star-book.lisp`, `repro-let-star-{cert,inc,inc-nocomp}.in`.

On **both hosts**, all three modes return `7`. The post-include defaults table on both hosts has no `:let*-abstractionp` entry, consistent with whole-table restoration (R1).

### R18. A macro cannot directly inspect the live ACL2 state through a macro formal

Files: `repro-world-macro-book.lisp`, `repro-world-macro-cert.in`.

On SBCL, the attempted macro whose `STATE` formal is passed to `W` is rejected. ACL2 explains that the formal is bound to syntax, not the ACL2 state. This is documented at `doc.lisp:75398-75412`, which prescribes `make-event` for state-sensitive expansion. R3/R4 test that prescribed route; no certified wrong-value book resulted from the direct macro route.

### R19. The original `program`-mode report was a setup failure, not an include divergence

`cert-prog1.in` was re-run on SBCL before the valid replacements in R16. It fails during admission, so `inc-prog1.in` has no certified book to include. It is retained only as a correction to the prior worker's record, not as evidence about reclassification.

## Source landmarks used to select the probes

- `interface-raw.lisp:1350-1450`: `oneify` re-translates `lambda$` and `loop$` using its `w` argument.
- `interface-raw.lisp:1493-1638`: `return-last`, `ec-call`, and `mbe`; `interface-raw.lisp:1675-1767`: `flet`, `macrolet`, `with-local-stobj`, `stobj-let`, and macro re-expansion.
- `interface-raw.lisp:6567-6793`: include-time definition installation may reuse compiled definitions or call `oneify-cltl-code` again; `interface-raw.lisp:6417-6537` covers reclassifying values.
- `other-events.lisp:121-261`: `defconst-val` uses saved hcomp values when available and otherwise evaluates with `safe-mode` bound to `t`.
- `acl2.lisp:1018-1116`: raw `defconst` may evaluate its term during compiled/expansion-file loading; a discriminator handles an existing compatible constant.
- `other-events.lisp:13990-14065` and `15164-15325`: include substitutes certified `make-event` expansions and expansion files contain them.
- `other-events.lisp:14021-14023`: include binds guard checking to `t`; `other-events.lisp:5763-5780` forces logic default during include.
- `translate.lisp:21849-21920`: `ec-call` accepts function/inline names, rejects superior `flet` bindings, and mentions macro aliases only in diagnostics. `untrans-table` is used by untranslation/printing, not by `oneify` to assign a new logical meaning.

## Not checked (most promising first)

1. **User-introduced `defwarrant`/`defbadge` events.** `repro-warrant-cert.in` stops at ACL2's explicit request to include `projects/apply/top` first; that book is absent from the supplied checkout. Built-in warrant behavior was tested successfully in R13 instead. This is the highest-value remaining world-dependent evaluation path if the book becomes available.
2. **Abstract stobjs and attachable/generic stobj primitives.** Concrete local and nested stobjs passed, but `defabsstobj` and the `ext-gens`/`ext-gen-barriers` recompilation cases were not exercised.
3. **`make-event :check-expansion` and nested/expansion-alist edge cases.** Ordinary certified expansion replay passed in base and rich worlds; explicit `:check-expansion` mismatch handling and deeply nested `progn`/`encapsulate` expansion positions were not separately stress-tested.
4. **Richer-world `encapsulate` pass-2 constraint computation.** Basic constrained functions/attachments and redundant reclassification passed, but a larger encapsulate with several constrained signatures and redundant events was not constructed.
5. **Macro-alias and `untrans-table` table stress.** Source reading found no value-assignment path in `oneify` (untranslation is printing; general macro aliases are not accepted by `ec-call`), but table mutations in an includer were not executed as a standalone book comparison.
6. **Every remaining `acl2-defaults-table` key at runtime.** Restoration is uniform by source and three translation-relevant keys were exercised, but proof-only settings such as well-founded relation, measure function, backchain limits, and ruler extenders were not each given a separate book.
7. **Nondefault reader features and raw readtable changes.** `*features*` is explicitly required by `acl2.lisp:2333-2345` to remain fixed across phases; raw readtable changes are outside the no-trust-tag certified-book model. No claim is made about those unsupported contexts.
