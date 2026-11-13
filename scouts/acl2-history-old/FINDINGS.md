# ACL2 historical soundness scout

Source: `/Users/ember/dev/acl2-fix/head-worktree`, commit `1d2b39a424eabeab269f189b37c29148d49fc516` (the requested snapshot). Material read in full: `../data/acl2-soundness-old.txt`.

Unless stated otherwise, every experiment below was run from a fresh image with

```
/Users/ember/dev/compiler-audit/scouts/lisp-run.sh acl2-sbcl <script>
```

and the full transcript is in `<script>.acl2-sbcl.out`. No trust tags, `skip-proofs`, `defaxiom`, redefinition, or raw-Lisp redefinition were used. “Refuted” means the particular exploit route was executed and blocked, or logical and execution results agreed; it does not claim a proof of correctness.

## Confirmed

No confirmed soundness failure so far. In particular, no script has proved a false theorem or returned inconsistent values for a closed term. All apparent successes below are valid positive controls; all false goals named `bad`, `ouch`, `contradiction`, or `nil-proved` failed unless explicitly reported otherwise.

## Refuted

### Local events, redundancy, and termination

1. **NOTE-3-0-1: local `program` permits a nonterminating exported definition.** `repro-local-program.lisp` rejects `(LOCAL (PROGRAM))`: “not an embedded event form in the context of LOCAL because it implicitly sets the acl2-defaults-table in a local context.” The enclosing encapsulate and final `thm nil` fail. Current check: `chk-embedded-event-form`, `other-events.lisp:3995-4018`.
2. **The same local-defaults route hidden on either side of `make-event`.** `repro-make-event-local-program.lisp` `(make-event '(local (program)))` and `repro-local-make-event-program.lisp` `(local (make-event '(program)))` produce the same locality error during `make-event` processing. Neither exports `foo`; both `thm nil` attempts fail.
3. **NOTE-3-0-2: redundant definition drops a sound measure.** `repro-measure-redundancy.lisp` rejects the non-local definition: “the proposed and existing definitions for FOO differ on their measures … proposed … NIL … existing … (ACL2-COUNT Y).” The bad induction and contradiction are unavailable. Check: `non-identical-defp-chk-measures`, `defuns.lisp:6844-6902`.
4. **Modern sibling: `defun-nx` measure redundancy.** `repro-nx-measure-redundancy.lisp` rejects the second `defun-nx` for differing measures `(ACL2-COUNT X)` versus `(ACL2-COUNT Y)`. The bogus `:termination-theorem` cannot be used. The non-executable branch now reaches the same comparison (`defuns.lisp:7318`, `7436-7452`).
5. **Encapsulate-wide redundancy under a changed default measure function.** `repro-encap-measure-default.lisp` rejects the repeated definition: “the default measure function has changed (see :DOC set-measure-function).” `bad` and `nil-proved` fail. The encapsulate checks compare this default at `other-events.lisp:7839-7842` and `7917-7924`.
6. **Encapsulate-wide redundancy under a changed default well-founded relation.** `repro-encap-wfr-default.lisp` rejects the repeated definition: “the default well-founded relation has changed … from O< to NEVER<.” The bogus termination theorem and `nil-proved` fail. Check: `non-identical-defp-chk-well-founded-relation`, `defuns.lisp:6904-6930`.
7. **NOTE-2-8 guard-status redundancy promoted through `:non-executable`.** `repro-nonexec-guard-promotion.lisp` rejects the second definition: “demands guard verification, but there is already a corresponding existing definition without its guard verified. Use verify-guards instead.” The false guard theorem and `nil-proved` fail. The explicit non-executable promotion check is at `defuns.lisp:7456-7458`.

### Guard verification and raw/logical execution

8. **NOTE-2-7: normalization hides an unverified `bar` call.** `repro-zp-guards.lisp` proves the valid `(foo -3) = 0`, but `verify-guards foo` fails: “The body for FOO calls the function BAR, the guards of which have not yet been verified.” The false `(foo -3) = 1` and `bug nil` fail.
9. **The same normalized-guard route through `prog2$`/`return-last`.** `repro-prog2-guards.lisp` puts the `bar` call in the erased first argument of `prog2$`; `verify-guards` still reports the unverified `bar`, and the contradictory theorem fails.
10. **The same route through `defun-inline`.** `repro-inline-zp-guards.lisp` reaches the generated `FOO$INLINE`; guard verification reports the unverified `bar`. The macro alias does not bypass the unnormalized-body check.
11. **NOTE-2-9-3 safe `defconst`, using a modern `program`/`mbe` mismatch.** `repro-defconst-program-mbe.lisp` rejects `(defconst *a* (foo))` when `(foo)` is `(mbe :logic t :exec nil)` in program mode. Safe evaluation reports the violated `RETURN-LAST` guard `(EQUAL LAST-ARG EAGER-ARG)`. `verify-termination foo` subsequently gives logical `(foo) = t`, but no poisoned constant exists. Check: safe-mode binding in `defconst-val`, `other-events.lisp:183-260`.

### Subversive recursion and constraints

12. **NOTE-3-5 original bogus type prescription.** `repro-subversive-tp.lisp` emits the expected “G is ``subversive'' … no induction schemes or type-prescription rules” warning. `atom-g` fails (“No induction schemes are suggested”), so the functional-instance contradiction fails. Check: `putprop-type-prescription-lst` returns immediately for `subversive-p`, `defuns.lisp:3714-3719`.
13. **Subversive recursion transported through `mbe`.** `repro-subversive-mbe.lisp` has identical recursive logic and exec branches. It gets the same subversive warning, no exported type prescription, and `atom-g` fails; no contradiction.
14. **Subversive recursion in `defun-nx`.** `repro-subversive-nx.lisp` also gets the subversive warning and no type prescription. `atom-g` and the functional-instance contradiction fail.
15. **Direct `loop$`-recursive subversive route.** `repro-subversive-loop.lisp` transports the recursive value through `car (loop$ … collect …)`, preserving the shape of the original exploit. Admission fails before export because `G calls the function F which does not have a badge`; `F` is the constrained signature function. `defbadge` requires a *defined*, not constrained, function (`doc.lisp:26017-26020`), so this direct route cannot reach the old type-prescription invariant. A follow-up using a local badge remains below under Not checked.

### Historical proof-engine controls

16. **NOTE-3-5 nested `flet` discards an outer binding.** `repro-nested-flet.lisp` evaluates `(foo1 3 4)` to `(B (A (3 4)))`. The historically bogus `(B (C (3 4)))` theorem fails, and `contradiction` fails.
17. **NOTE-2-7 stale functional-instantiation cache after reverting to induction.** `repro-functional-cache.lisp` reproduces the complete report from `prove.lisp:518-592`. `f1-lst=f1` is proved by induction, but the later invalid `0=f1` fails; `0=1` cannot be proved. The current reversion clears the tag tree (`prove.lisp:399-418`).
18. **NOTE-2-9-4 local evaluator supports an exported `:meta` rule.** `repro-local-meta.lisp` rejects `meta-foo-rule`: non-local `:META` rules are illegal in a non-empty-signature encapsulate (here introducing `EVX`). `qed` and `contradiction` fail. `chk-acceptable-rules` also retains `:META` and `:CLAUSE-PROCESSOR` checks during include/second passes (`defthm.lisp:10130-10205`).
19. **NOTE-3-6.1 ruler-extenders misses a `let` substitution.** `repro-ruler-let.lisp` generates the correct impossible measure obligation containing `(< (ACL2-COUNT X) (ACL2-COUNT X))`; definition admission fails, and `foo-bad` cannot use it.
20. **NOTE-2-7 BDD reflexive rule treated as commutativity.** `repro-bdd-reflexive.lisp` first rejects the naive `(equal (f x x) (f x x))` rewrite as self-rewriting; `repro-bdd-reflexive-2.lisp` then reaches BDD with Boolean hypotheses and the valid reflexive theorem stored as `:rule-classes nil`. The false commutativity goal is not proved, and contradiction fails. `commutative-p1` now additionally requires distinct variables (`bdd.lisp:575-580`).
21. **NOTE-2-8 double-negation tautology.** `repro-double-negation.lisp` rejects the historical `equal` formula, which is in fact invalid for generalized Boolean `q` (counterexample `p=t,q=5`), and rejects its negation too. The valid `iff` control proves. This is a rejected false-theorem control, not a claim that the historical `equal` formula was true.
22. **NOTE-3-5 inequality context follows a variable into a lambda rebinding.** `repro-lambda-inequality.lisp` rejects the false assertion that `((lambda (x) (< x 0)) (- x))` is true under `x<0`; the valid assertion that it is false proves. Thus the outer `x<0` was not reused after rebinding.

### Arrays and packages

23. **Exact NOTE-3-5 `compress1` proof-of-`nil` shapes.** `repro-compress1-original-proof.lisp` proves all three correct logical formulas with `(compress1)` execution disabled. Every corresponding `ouch-n` proof of `nil` fails. `repro-compress1-old.lisp` independently prints the expected compressed values and proves the corresponding constant equalities.
24. **Honsed and memoized `compress1` on CCL.** `repro-compress-hons-memoize.lisp` was run with `acl2-ccl` (CCL 1.14 darwinarm64). Honsed input compresses to the expected header-only alist. Plain `memoize` is rejected because `compress1` has raw code, but the documented `(memoize 'compress1 :recursive nil)` succeeds. Repeated historical cases still print the expected values, and `memoized-compress-good` proves; no wrong value or false theorem. Transcript: `repro-compress-hons-memoize.lisp.acl2-ccl.out`.
25. **Illegal package names and `pkg-witness`’s empty-name route.** `repro-package-controls.lisp` rejects `defpkg` on `""`, `"LISP"`, and `"ACL2_*1*_MYPKG"` with their dedicated checks. Direct `(pkg-witness "")` is rejected because `pkg-imports` requires a known package, before an execution/logical mismatch can be exploited. `repro-pkg-witness-axiom.lisp` confirms the same `defpkg ""` rejection; its attempted direct proof of the default-package equality did not succeed, so that equality is not being claimed as a positive control. Source shows the corrected axiom defaults to `"ACL2"` only when the input is not a nonempty string (`axioms.lisp:5540-5550`).

### Partial modern-lambda control

26. **Ground `apply$`/`lambda$` rebinding.** `repro-apply-lambda-ground.lisp` prints `APPLY-LAMBDA-GROUND NIL` for `(apply$ (lambda$ (y) (< y 0)) (list (- -1)))`; the false equality to `t` is not proved. The valid equality to `nil` also does not prove automatically, and the variable-general `apply$` control in `repro-apply-lambda-inequality.lisp` is inconclusive (both directions fail automatically). Thus only the top-level ground value is refuted evidence here, not a general prover soundness result.

### Additional modern siblings and exact regression controls

27. **Functional-instantiation cache through the newer `:or` hint.** `repro-functional-cache-or.lisp` gives one disjunct the historical functional-instance `:use` and another `:induct t`. ACL2 chooses the induction-only branch; the later invalid `0=f1` still fails, so no unproved constraint leaked through branch selection.
28. **`memoize-partial` recursive `ec-call`, including an `mbe :exec` hiding place.** `repro-memoize-partial-ec.lisp` is the direct capture exploit; `repro-memoize-partial-mbe-ec.lisp` uses a plain recursive call in `:logic` and `ec-call` in `:exec`. Both definitions are valid and guard-verified, but `memoize-partial` rejects its table event: “has has EC-CALL applied to a call of F-LIMIT. This is illegal.” No partial function is installed and `bad` fails. The checker traverses both branches of the unnormalized translated body (`other-events.lisp:36285-36315`).
29. **NOTE-3-2.1 multiple-value/`mbe` mismatch on both hosts.** `repro-mbe-mv.lisp` was run with both `acl2-sbcl` and `acl2-ccl`; each rejects the definition because the expected and actual numbers of return values differ. `repro-mbe-mv-context.lisp` additionally tries an outer `mv-let` on SBCL and is rejected at the same `RETURN-LAST 'MBE1-RAW` signature check. Neither host reaches contradictory theorems. The signature requirement is implemented at `translate.lisp:26821-26850`.
30. **NOTE-2-8 stobj reclassification, explicit and implicit.** `repro-stobj-reclassify.lisp` rejects the new definition solely because its `:stobjs` declaration differs. `repro-stobj-implicit-reclassify.lisp` omits `:stobjs`; this is accepted as a stobj-less logic definition, not as a changed stobj signature. The pre-existing program-mode caller and a safe `defconst` both evaluate `(my-callee-is-stobjless 3)` to `3`, so there is no wrong value or error. The explicit comparison is at `defuns.lisp:7033-7071`.
31. **Exact NOTE-3-5 measured-subset `verify-termination` exploit.** `repro-verify-termination-subset.lisp` follows `doc.lisp:163329-163373`. The `make-event` expansion is recorded as the correct redundant definition with measure `(ACL2-COUNT Y)`. The historical `bad-lemma` now fails: “No induction schemes are suggested by the induction hint.” Contradiction fails.

## Not checked

Most promising remaining work, in order:

1. **Functional-instantiation cache through `:backtrack` and computed/override hints.** The original reversion and the newer `:or` branch-selection paths are covered above, but other hint-control flow has not been executed. Source inspection shows `:backtrack` restores the pre-processor pspv at `prove.lisp:6325-6343`; that is not a substitute for a run.
2. **Local badge across encapsulate passes for the `loop$` subversive variant.** `repro-subversive-loop-local-badge.lisp` stopped at `CONFIRM-APPLY-BOOKS`: the requested source tree lacks `books/projects/apply/top`. This is not a semantic refutation of that extra route. The direct no-local-badge route is structurally blocked as described above.
3. **Other `memoize-partial` raw-body and cache routes.** Recursive `ec-call`, including the `mbe` variant, is now covered. Still untested: unusual non-`ec-call` `return-last` keys, nested `flet` shadowing, macro-alias/memoize interactions, and attachments invalidating cached values.
4. **General `apply$`/`lambda$` inequality reasoning with suitable warrants/hints.** Ground execution is correct, but the general valid theorem did not prove automatically; no soundness conclusion is drawn from that incompleteness.
5. **Clause-processor sibling of the local-evaluator `:meta` bug, and proof-builder expansion of constrained functions.** The source shares the second-pass rule check, but neither route has been exercised interactively.
6. **Original meta-hypothesis free-variable bug, linear-arithmetic forced-assumption bugs, and equivalence-hittable alternative definitions.** These require precise reconstruction beyond the short release-note descriptions.
7. **Book certification/expansion-file variants.** Current `make-event` and `verify-termination` tests were interactive sessions, not `certify-book` followed by fresh-image `include-book`.
8. **Newer stobj representations.** The original concrete-stobj signature check is covered, but `stobj-let`, abstract/nested/congruent stobjs, stobj tables, and `with-global-stobj` remain untested.
9. **Additional `compress2` order/length cases and modern array-invariant checks.** Only the historical `compress1` cases, honsing, and ordinary memoization were run.
