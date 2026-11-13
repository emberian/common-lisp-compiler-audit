# Literature survey and design recommendations for the consistency harness

Written 2026-11-13. Scope: what the published work on program generation,
compiler fuzzing and proof-assistant testing implies for `synth/synth.lisp`,
`routes/run-matrix.sh`, `coverage/*.lisp` and `tools/reduce.lisp`. No code was
changed. 25 Kagi queries were used; every cited source is marked **[opened]**
(I fetched and read the page or PDF) or **[excerpt]** (I saw only the search
result text). Things I recall but did not confirm are listed in the last section
and are not used as evidence anywhere above it.

## Where the bugs are: the evidence the ranking rests on

Five independent records point the same way.

1. **This harness.** F1 and F2 both come from context around a definition (a
   defaults-table setting that is live at certification and absent when `oneify`
   re-translates). C1 ran 360k Dietz forms per host with 0 diffs, and L1/L3 ran
   thousands of typed arithmetic queries with 0 diffs.
2. **ACL2's own release notes** (`doc.lisp` in the worktree; my keyword census,
   categories overlap, counts are approximate). Of 278 paragraphs that mention a
   soundness bug or a proof of nil: 72 mention books, certification, `local`,
   `encapsulate`, `make-event` or compiled files; 43 stobjs or arrays; 43 prover
   internals; 39 raw Lisp or the host compiler; 34 guards, `mbe` or `ec-call`;
   23 packages; 17 redefinition or undo; 12 memoization; 7 a numeric, character
   or string primitive.
3. **The two most recent host-related ACL2 soundness bugs**, both found in 2026
   by a language model and both shipped as regression books:
   `books/system/tests/dcl-guardian-nil.lisp` (ACL2 dropped every type-declaration
   proof obligation of a `LET` whose first declaration was `(type (or t ...) v)`,
   while SBCL still trusted the declarations) and
   `books/system/tests/integer-length-bad-optimization.lisp` with
   `length-bad-optimization.lsp` (SBCL derives a bounded integer type for
   `integer-length` and `length` of anything, folds a comparison to `T`, and the
   logic disagrees; fixed in note-8-7 by proclaiming those functions `notinline`).
   Neither is an arithmetic miscompilation. Both are a mismatch between what the
   logic allows and what the compiler is told or assumes.
4. **Lean and Rocq in 2026.** The proofs of `False` found by agent-driven hunts
   were in the guard checker and module system (Rocq), in definitional-equality
   caching, `is_prop`, nested-inductive registration, name-keyed accelerators for
   `Nat`/`String`, module-boundary stubs, and in the runtime (reference-count
   overflow, an old GMP) (Lean). See topic 7.
5. **SBCL's history.** Dietz's random tester has been run against SBCL for a long
   time (reports I saw are dated 2012, 2013, 2017 and 2019) and SBCL's `NEWS`
   credits random testing in five items. The grammar this harness shares
   with it is the most heavily fuzzed part of the compiler.

Conclusion used for ranking: the expected yield per unit of work is highest for
(a) context and persistence around definitions, (b) the interface where ACL2
tells the host compiler something (declarations, guards, derived types), and
(c) exhaustive coverage of small degenerate shapes. It is lowest for more random
integer arithmetic. Host-compiler table coverage still matters, but as the
denominator of the ledger's claims, not as the likeliest source of a proof of nil.

---

## Ranked recommendations

Cost is for one person who knows the harness. "Reaches" names the bug class the
harness cannot observe today.

### 1. Swarm-selected context envelope, and every function through every style

**Technique.** Swarm testing (Groce et al., ISSTA 2012) applied to the events
around the definitions, and "compilation space exploration" (Li et al., Artemis,
SOSP 2023): mutate the program with constructs that are neutral for its meaning
but change which compilation path each function takes, then cross-validate.

**Implementation.** In `emit` (synth.lisp:1038), add a feature set drawn per book
with independent omission, exactly as `kinds` is drawn at line 1046. Features are
text-level wrappers and prefix events, no IR change:
- defaults-table setters, each on or off and placed before, between or after the
  functions: the members of `*acl2-defaults-table-macros*`
  (`set-ignore-ok` and `set-irrelevant-formals-ok` are currently
  unconditional at line 1078, which is the opposite of swarm; also
  `set-state-ok`, `set-compile-fns`, `set-verify-guards-eagerness`,
  `set-bogus-mutual-recursion-ok`, `set-ruler-extenders`,
  `set-well-founded-relation`, `set-measure-function`, `(program)`/`(logic)`);
- wrappers around a twin's events: `local` helpers, nested `encapsulate`,
  `progn`, `make-event` whose expansion is the `defun`, `with-output`, a
  redundant second copy of the same `defun`, `verify-termination` after
  `:program` (exists as `:program` style), `defun` vs `defun-inline` vs
  `defun-notinline`, `flet` (listed as an open obligation in the ledger);
- book-level: a second generated book included by the first (plain and `local`),
  portcullis commands (certify with a non-empty world), `defmacro`s defined in
  the book and used inside `loop$` and `lambda$` bodies (today only `zm-id`,
  `zm-inc`, `zm-sel`, used outside them).

Also change `make-function` (line 861) so that a sample of functions is emitted
in all four `fn-style`s under different names instead of one random style each;
the styles must agree with each other (an in-book metamorphic check that needs
no extra query generation).

Write the enabled feature list to `manifest.txt` (line 1116 already records
kinds). Oracle: unchanged, the matrix in `run-matrix.sh`. Feedback signal: none
needed at first; later, correlate features with failures (recommendation 9).

**Reaches.** Every sibling of F1/F2: state that is in effect when a form is
first translated and absent or different when it is re-translated, re-compiled
or re-loaded. The scout note `scouts/acl2-rederive/FINDINGS.md` C1 already shows
that every defaults-table key set in a book is dropped at `include-book`; only
two keys have been driven through the matrix.

**Cost.** 2 to 4 days. Highest yield per day because it is the only class in
which this harness has found anything and the generator currently holds the
context constant.

### 2. Skeletal enumeration of binding and usage patterns, crossed with context and route

**Technique.** Skeletal program enumeration (Zhang, Sun, Su, PLDI 2017):
fix a small syntactic skeleton, enumerate all variable-usage patterns up to
alpha-equivalence. Canonical-form enumeration of small first-order programs
(Reich, Naylor, Runciman, IFL 2011), which generates programs over positional
names and prunes non-canonical representatives.

**Implementation.** A new small driver next to `synth.lisp` that reuses `infer`,
`finish`, `twin-events` and `emit`'s file writers. Skeletons are IR trees with
typed holes `(:hole :int)`. Seeds for skeletons: the two repro directories, the
152 `.lisp` regression books in `books/system/tests/` (each one is a past ACL2
bug reduced by its finder; SPE took its skeletons from GCC's test suite), and the
binder forms the generator knows: `let`, `let*`, `mv-let`, `lambda$`, `loop$`
(`for`/`when`/`sum`/`collect`/`always`, with and without `of-type`), `flet`,
stobj `let*` rebinding. Fill holes by the canonical rule: a hole may take any
variable already used, or the single next unused variable of its type (a
restricted-growth string per type; this is the alpha-equivalence quotient).
Enumerate, per binder, the usage classes the random generator never or rarely
produces:
- a bound variable with zero uses (F1 and F2 are exactly this pattern; the
  generator now suppresses it inside `loop$`/`lambda$` with `*avoid-f1*`);
- shadowing: `fresh` (line 436) gives every binding a new name, so no integer
  variable is ever shadowed, no `let*` rebinds a name, no `loop$` variable
  shadows a formal, no `lambda$` formal captures an outer name;
- the same variable in two roles (loop bound and body, selector and arm);
- `mv-let` with one of the values unused; `(declare (ignore ..))` vs
  `(ignorable ..)` vs neither.
Cross each program with the context features of recommendation 1 taken one and
two at a time, and run the matrix. Sizes stay small: a binder with three holes
over at most three variables has 5 usage patterns up to renaming.

Oracle: the matrix. Ledger effect: a claim of the form "exhausted for all
programs of shape S up to size k" instead of "sampled", which is the form a
later proof can cite.

**Reaches.** Degenerate usage patterns and their interaction with context; this
generalises the only two findings mechanically instead of by luck. SPE's reported
result is that most of its 217 GCC/Clang bugs were long-latent despite Csmith and
EMI, because random generators concentrate on "typical" usage patterns.

**Cost.** 3 to 5 days.

### 3. Derived-type oracle: SBCL's inferred types against the logic

**Technique.** Checking a compiler's static facts against concrete or exact
semantics (Taneja, Liu, Regehr, CGO 2020, for LLVM known-bits and integer
ranges), and fine-grained state comparison instead of output-only comparison
(Dumpling, NDSS 2025). Honest caveat: Taneja et al. found no new soundness bug
in LLVM this way. The reason to expect more here is that two different semantics
meet (ACL2's unbounded logic and Common Lisp's bounded object sizes), and that
note-8-7 records real proofs of nil of exactly this kind.

**Implementation.** Two parts.

(a) Static audit, no test inputs. Inside the ACL2/SBCL image (so that ACL2's own
`notinline` and `ftype` proclamations are in force), for every primitive in
`*primitive-formals-and-guards*` and every function with a raw definition (the
ledger's 643 raw-only regions), compile
`(lambda (args) (declare <types implied by the guard>) (f args))` and read
`(sb-kernel:%simple-fun-type ...)`. I checked this on the installed SBCL 2.6.10:
a bare `(lambda (x) (integer-length x))` reports `(unsigned-byte 38)` and
`(lambda (x) (length x))` reports `(unsigned-byte 45)`. Flag every primitive
whose derived result type is narrower than its logical range under its guard.
Each flagged entry is a candidate proof of nil of the `length-bad-optimization`
shape `(< (f x) BOUND)`, and none needs a huge object to exist. The harness
cannot reach these by execution: `ti` rejects anything wider than 220 bits
(line 60) and lists are capped at 12 elements. A new file beside
`coverage/sbcl-cov.lisp`; output is a table that becomes a ledger claim
("for each primitive, the host's derived type contains the logical range").
For CCL, `coverage/ccl-cov.lisp` notes that `*next-nx-operators*` carries a type
per acode operator; audit those the same way (I did not verify how much CCL
derives beyond that).

(b) Dynamic membership check. After `book.lisp` is loaded, in raw mode read
`%simple-fun-type` of each `-OPT` function and add one line per query to
`queries.lisp`: the REF value must satisfy `typep` of OPT's derived return type.
For intermediate values, the generator already holds a `(form . type)` pair for
every subterm it builds; emit a sample of subterms as probe functions and check
both the value and the containment "values observed at the interval corners lie
in SBCL's derived type". This is stricter than output equality: a wrong derived
type is a bug even when the sampled output happens to agree, because callers
and later code are compiled against it.

**Reaches.** Logic-versus-Lisp range mismatches, and wrong type derivation that
is masked at the output. `sbcl-cov.lisp` records that a transform fired, not
whether the facts it relied on were true.

**Cost.** (a) 1 to 2 days, (b) 2 to 3 days.

### 4. Known-outcome negative tests for guard-obligation generation

**Technique.** XDsmith (Irfan et al., ISSTA 2022): generate annotated programs
whose verification outcome is known by construction, and test the verifier's
soundness with the ones that must be rejected. The same idea is the oracle of
semantic fusion for SMT solvers (Winterer, Zhang, Su, PLDI 2020).

**Implementation.** The harness replaces ACL2's guard verification with
`skip-proofs` and its own `infer`, so ACL2's obligation generator
(`dcl-guardian`, the `the` and `type` handling in `translate.lisp`, `mbe`,
stobj accessor guards) is never exercised. Add a pass in `synth.lisp` after
`finish`: take a valid function, pick one annotated position and falsify it with
a witness in hand. `infer` gives the exact range of a `let`-bound or
`the`-wrapped subterm; the integer IR is executable in the host Lisp, so run the
body on the query inputs, find one that drives the subterm to a value `v`, and
re-declare the subterm with a type that excludes `v`. Emit this `-BAD` twin
without `skip-proofs` on its `verify-guards`. Two oracles:
1. `(verify-guards zfN-bad)` must fail (wrap in `must-fail`, with a prover step
   limit). A success is a soundness bug in obligation generation or the prover.
2. To separate "the prover gave up" from "the obligation is false": obtain the
   obligation with `guard-obligation` (`defuns.lisp:4776`) or `guard-theorem`
   (`history-management.lisp:14550`), define it as a function of the formals via
   `make-event`, and evaluate it on the witness. It must be `NIL`.
Vary the declaration language while doing this. `type-for` (line 247) emits only
`signed-byte`, `unsigned-byte` and `(integer lo hi)`. Add `(or ..)`, `(and ..)`,
`(member ..)`, `(mod n)`, `bit`, `(satisfies ..)`, `(integer * hi)`, `t`, several
`declare` forms on one binder, and declaration order; the dcl-guardian bug was
`(or t integer)` in first position. Do the same for `mbe`: plant an `:exec` that
differs from `:logic` on a known witness; the obligation must be false there.

**Reaches.** Unsound obligation generation, the class of
`dcl-guardian-nil.lisp`. Invisible today by construction.

**Cost.** 3 to 5 days (start with the non-stobj, non-`loop$` kinds, where every
obligation is executable).

### 5. Persistence routes with an adversarial or stale artifact

**Technique.** The incremental-compilation oracle: the result of reusing saved
artifacts must equal the result of building from scratch (stated as a fuzzing
oracle in Rust RFC 1298). The 2026 Lean and Rocq catalog (Shenanigans) records
that module-boundary and cached-artifact checking paths had their own defects,
including one in a checker run with a bytecode compiler that accepted what the
plain checker rejected.

**Implementation.** New routes in `run-matrix.sh`, each a few lines in the
`s2`/`s3` style:
- `include-book` with `:load-compiled-file nil`, and with the fasl deleted,
  compared with the fasl route (the script only checks that no fallback
  happened);
- certify on one host, include on the other using the foreign `.cert` and no
  compiled file; residues must match (the hosts are compared today only on
  in-session values);
- include in a session whose defaults table, current package and `ld` settings
  differ from the certification session;
- stale artifacts: edit the book after certification (whitespace only, then a
  changed constant), swap in the fasl of a different seed's book, set file times
  backwards; ACL2 must refuse or recompile, never load silently. This is the
  ledger's open "fasl tampering through the hcomp path" entry;
- `make-event` forms whose expansion depends on something that differs between
  certification and inclusion, with and without `:check-expansion`;
- save-exec with memo tables populated, then query; save-exec, then
  `include-book` in the restarted image.
Oracle: equality of residues with `session`, plus "refused" as an accepted
outcome for tampered inputs.

**Reaches.** Disagreement between a cached artifact and its source, and
environment capture at the book boundary. 72 of 278 soundness paragraphs in the
release notes involve this machinery.

**Cost.** 3 to 4 days.

### 6. Annotation, narrowing and outlining variants of one body (metamorphic testing that fits this language)

**Technique.** Equivalence modulo inputs (Le, Afshari, Su, PLDI 2014) and its
successors, plus metamorphic compiler testing as used by DafnyFuzz
(Donaldson et al., ICST 2024). In a pure, total, first-order language with no
undefined behaviour, far more rewrites are unconditionally valid than in C; the
only side conditions are guards, termination measures and stobj
single-threadedness.

**Implementation.** Keep the un-annotated IR in the `fn` struct (today `finish`
overwrites `fn-body` at line 846) and derive variants that must all equal the
single REF twin on the same queries:
- **annotation variants** (free): call the annotating `infer` K times with
  different `*ann*` densities and `type-for` draws on the same IR. The generator
  already randomises annotation but never compares two annotations of one body;
- **equivalence modulo guard**: re-declare the formals with the hull of the
  query inputs and re-run `infer`, so every inner `THE` tightens. Narrower
  declarations enable more transforms; values on the narrower domain must not
  change. This is the cleanest EMI analogue here: the guard plays the role of
  the input set;
- **dead-arm mutation** (EMI/Orion, Athena): evaluate the IR on the queries in
  the host Lisp, find `if`/`case` arms no query reaches, and replace them with
  fresh `gen-int` output passed through `fit-type` to the arm's old type, so
  `infer` still accepts the function;
- **always-valid rewrites**: `e` to `(let ((v e)) v)`; `let` inlining and
  common-subexpression introduction; outlining a subterm into a new helper
  `defun`, `defun-inline` or macro; `(if c a b)` to `(if (not c) b a)`;
  `(mod x 2^k)` to `(logand x (1- 2^k))` for all `x` (the generator already uses
  this inside `mbe`); adding `0`, multiplying by `1`, double negation, De Morgan
  on `logand`/`logior`; a literal to a `defconst`; `:loop` (tail) to `:rec`
  (non-tail) to `loop$ sum` for the same fold.
Variants need no REF twin of their own, so each costs half a function.

**Reaches.** Miscompilations that depend on declared types and on program shape
around a fixed computation. Expected yield is modest (this is C1 territory), but
annotation and narrowing variants cost a day and are the cheapest way to make
transforms keyed on declared types fire on the same values.

**Cost.** 1 to 2 days for annotation and narrowing variants; about a week for
the rewrite set and dead-arm mutation.

### 7. Query inputs chosen from the body, and less masking

**Technique.** Boundary inputs that straddle the precondition of a specific
transformation, which is what Alive-style precondition reading buys cheaply,
done here by search instead of SMT. Dumpling's observation that an
internal miscalculation must reach a sink before an output-only oracle sees it.

**Implementation.** `query-args` (line 1012) draws 8 inputs from the parameter
ranges alone. Add to `synth.lisp` a host-Lisp evaluator for the integer IR that
records the value of every subterm, then:
- measure the fraction of subterms and `if` arms executed by the 8 queries and
  add inputs until every arm that `infer` considers reachable is executed. A
  miscompiled subterm that never runs cannot be observed;
- collect boundary targets for the function: endpoints of every `THE` and
  `declare` type in the body, the `*seam-bits*` powers, comparison constants,
  and the endpoints in the argument-type restrictions of each transform on an
  operator in the body (`sb-c::transform-type`, already read by
  `transform-key`; on this SBCL `ash` has a transform restricted to
  `(constant-arg (or (integer -4096 -1) (integer 1 4096)))`). Hill-climb the
  inputs to put intermediate values at target - 1, target, target + 1. Most
  bodies are compositions of monotone or invertible steps, so distance-guided
  search suffices; an SMT encoding is only worth it for nonlinear chains;
- reduce masking: `fit-int` (line 455) wraps most call arguments and recursive
  accumulators in `logand`, `max`/`min` or `mod`, and those wrappers erase a
  wrong intermediate value before `zhash` sees it. Emit a second OPT entry point
  that returns the `let`-bound intermediates as an `mv` or list, and compare all
  of them.

**Reaches.** Seam bugs inside bodies, such as SBCL lp#974406 where an
intermediate sum crossed a width cut inside modular arithmetic. Also raises the
value of every other recommendation that executes generated code.

**Cost.** 2 to 3 days.

### 8. Operator-level swarm, then directed swarm from the coverage table

**Technique.** Swarm testing (Groce et al., ISSTA 2012) and directed swarm
testing (Alipour et al., ISSTA 2016): use statistics over past runs to find
which features trigger and which suppress a coverage target, and build
configurations for the target.

**Implementation.** The swarm at line 1046 covers nine function kinds and stobj
presence. `gen-int-op`'s 47-way `ecase` (line 524), `gen-bool-form`,
`gen-list-op`, the constant classes of `random-const`, `*seam-bits*` and the
annotation density all use one fixed distribution in every book. Give each
alternative a per-book on/off bit (a bit vector consulted before the `ecase`,
with redraw), record the vector in `manifest.txt`, and have
`coverage/sbcl-cov.lisp` and `ccl-cov.lisp` dump one fired set per book. Then for
each table entry compute, over books, the features whose presence raises or
lowers its hit rate, and generate configurations for the entries that are rare.
This is a feedback loop over the transform/VOP/vinsn tables that needs no
mutation machinery: the signal is "fraction of books with feature F in which
entry E fired".

**Reaches.** Entries suppressed by competition for space in a function (Groce's
second mechanism) and by clamps. Note the specific suppressor in this generator:
`fit-int` and `tame` re-normalise ranges constantly, the pattern YARPGen's
authors criticise in Csmith's safe-math wrappers because it hides the operand
ranges an optimizer would otherwise exploit.

**Cost.** 1 to 2 days for the swarm and manifest, 2 more for the statistics.

### 9. Generation policies read off the transform tables

**Technique.** YARPGen's generation policies (Livinskii, Babokin, Regehr, OOPSLA
2020 and PLDI 2023): skew generation toward shapes that make particular
optimizations fire, added in response to coverage gaps. Optimization-directed
fuzzing (Optimuzz, PLDI 2025) and matcher-table coverage as the feedback signal
(IRFuzzer, ICSE 2025). WhiteFox (OOPSLA 2024) for the entries whose trigger
conditions are in code and not in a type.

**Implementation.** `coverage/gap.lisp` lists the unhit transforms on
ACL2-expressible operators with their argument-type signatures. Add a generator
case `gen-for-transform` to `gen-int-op` that takes one such key and builds
`(op e1 .. en)` where each `ei` is an ordinary `gen-int` result pushed into the
transform's argument type with `fit-type`, and each `constant-arg` position gets
a literal from `const-in` over the restricted range. The harness already owns
both tools; what is missing is the table-driven caller. Add YARPGen's four
general policies as specials bound over random subtrees:
- operator contexts (additive, bitwise, bitwise-shift, multiplicative,
  additive-multiplicative) that restrict the `ecase` inside a region;
- a constant buffer per function that re-offers `c`, `-c`, `(lognot c)`, `c±1`
  and masks of contiguous ones;
- a subexpression buffer that re-inserts an earlier subterm verbatim;
- regions whose leaves are all constants or half constants.
Add consumer contexts, since SBCL's modular-arithmetic and word VOPs are chosen
by how a result is used: wrap generated arithmetic in `(logand MASK ..)`,
`(the (unsigned-byte 64) ..)`, comparisons with constants, and `ash` by negative
constants. For VOPs, use `sb-c::template-arg-types`/`template-result-types` to
choose declared parameter widths (tagged fixnum, signed word, unsigned word,
two-word); for CCL, the vinsn operand specs. Entries still unhit after N directed
attempts go to a list for reading the transform body (conditions such as
`give-up-ir1-transform`, policy tests and "result unused" are not in the type).

**Reaches.** The roughly 82 percent of SBCL transforms, 64 percent of VOPs and
72 percent of CCL vinsns never executed. The ledger lists this as an open
obligation.

**Cost.** 1 to 2 weeks. Ranked below the items above because the expected number
of soundness bugs per entry is low, not because it matters less to the ledger.

### 10. Choice-tape generator with a table-keyed corpus and IR mutation

**Technique.** Zest (Padhye et al., ISSTA 2019): make the generator a
deterministic function of a parameter sequence, mutate the sequence, keep
sequences that add coverage or validity. Fuzzilli's IR mutators (Groß et al.,
NDSS 2023): input, operation, splice and generative mutation with minimisation
before corpus insertion. Type-aware operator mutation (OpFuzz, Winterer, Zhang,
Su, OOPSLA 2020).

**Implementation.** `rnd` (line 25) is the single source of randomness. Make it
read from a vector and extend the vector from the seeded state when it runs out;
save the vector per function. A function enters the corpus when its fired set
(recommendation 8's per-book dump, made per-function by resetting `ccov` around
each `defun`) contains a table entry or a pair of co-firing entries not seen
before, weighted toward the rarest entry it hits. Mutations:
- tape: point changes, range splices between two tapes, truncation; these map to
  structural changes in the program, and `finish` is the validity filter;
- operator (OpFuzz): replace an operator by another with the same `xfer`
  signature (`+ - * logand logior logxor ..`, the comparators, `floor`/`truncate`,
  `mod`/`rem`), then re-run `infer` and re-`fit` at the root;
- splice (Fuzzilli): move an integer subtree from one corpus function into
  another through `fit-type`, which makes any integer subtree legal anywhere;
- input: replace a variable reference by another in-scope variable of a type
  that `sub-p` accepts.
Coverage inside the ACL2 image needs `sbcl-cov.lisp` loaded in raw mode before
the book; the pure-CL tier can be driven in a bare SBCL as C1 is.

**Reaches.** Combinations of transforms that one random draw rarely produces.

**Cost.** 1 to 2 weeks. Each test costs seconds to minutes of ACL2, so the loop
runs thousands of iterations a day, not millions; that is why the cheaper
feedback of recommendation 8 comes first.

### 11. Reducer: structure-aware, joint, domain passes, cache

**Technique.** C-Reduce (Regehr et al., PLDI 2012): a fixpoint over modular,
domain-specific transformations that keep the test valid. Perses (Sun et al.,
ICSE 2018) and hierarchical delta debugging for syntax-guided removal. Vulcan
(Xu et al., OOPSLA 2023): transformations that do not shrink the program but
unblock further reduction past a 1-minimal result.

**Implementation.** `tools/reduce.lisp` drops top-level forms by halving chunks
and replaces subterms by `0`, `NIL`, `T` or a child. Missing:
- joint reduction: REF/OPT twins, `queries.lisp`, `memo.lisp` and the route list
  are separate artifacts. Reduce at the level of the generator's `fn` structs
  and re-emit, so removing a function removes its twin, its queries and its memo
  lines, and so that the set of routes and the number of queries are themselves
  reduced;
- validity: a candidate whose REF twin aborts is rejected only after a full ACL2
  run. Run `infer` on candidates first and skip invalid ones;
- domain passes: shrink integer literals toward 0, ±1 and powers of two by
  bisection; widen or drop one declaration or `THE` at a time; replace a call by
  a constant of the callee's type; replace `defun-inline` by `defun`; drop one
  context event at a time (for F1-type bugs this is the informative step);
  inline a `let`;
- Vulcan-style steps when stuck: replace one identifier by another of the same
  type, replace a subtree by a sibling-typed subtree;
- a failure signature in the predicate (route and message class) so reduction
  does not slide to a different bug, and a hash cache of tested candidates,
  since each test is several ACL2 runs.

**Reaches.** No new class by itself. It decides how many findings can be triaged:
the first finding needed a hand-written `*avoid-f1*` to stop recurring.

**Cost.** 3 to 5 days.

### Why this order

Items 1, 2 and 5 extend the only axis on which the harness has found bugs and on
which ACL2's history is densest, and item 1 costs days. Items 3 and 4 open the
two interfaces through which the 2026 ACL2 bugs came, which the harness
structurally cannot see today (one is bypassed by `skip-proofs`, the other is
out of range of any executable input); 3(a) is nearly free. Items 6 and 7 are
cheap multipliers on everything that executes code. Items 8 to 10 attack
host-compiler table coverage in increasing order of machinery; they are ranked
by cost, with the honest expectation that integer transforms in two mature
compilers yield few soundness bugs per entry. Item 11 is throughput.

The bounded-exhaustive sweep of primitives over a small value universe (ledger
obligation 1) is already under way in `primitives/sweep.lisp`, so it is not
listed; it reaches the `take` and `compress1` class of raw-twin bugs and would
otherwise rank next to item 3.

---

## Per-topic notes

### 1. Equivalence modulo inputs and metamorphic compiler testing

- Vu Le, Mehrdad Afshari, Zhendong Su. *Compiler Validation via Equivalence
  Modulo Inputs.* PLDI 2014. https://web.cs.ucdavis.edu/~su/publications/emi.pdf
  **[opened]**. Profile a program on given inputs, then stochastically prune
  code those inputs never execute; every variant must behave like the original
  on those inputs. Reported: 147 confirmed unique bugs in GCC and LLVM in eleven
  months, most of them miscompilations, more than 100 fixed.
- Vu Le, Chengnian Sun, Zhendong Su. *Finding Deep Compiler Bugs via Guided
  Stochastic Program Mutation.* OOPSLA 2015 (Athena).
  https://web.cs.ucdavis.edu/~su/publications/oopsla15-compiler.pdf **[opened]**.
  Adds insertion as well as deletion in unexecuted regions and guides the search
  by MCMC with an objective that favours control-flow diversity. Reported: 72
  new GCC/LLVM bugs in 19 months, all confirmed, 68 fixed.
- Chengnian Sun, Vu Le, Zhendong Su. *Finding Compiler Bugs via Live Code
  Mutation.* OOPSLA 2016. https://dl.acm.org/doi/10.1145/2983990.2984038
  **[excerpt]**; venue from the EMI project page
  https://web.cs.ucdavis.edu/~su/emi-project/ **[opened]**, which gives the
  project total as 1,602 reported GCC/LLVM bugs, 1,007 fixed. I could not open
  the paper; no bug count is stated here.
- Cong Li, Yanyan Jiang, Chang Xu, Zhendong Su. *Validating JIT Compilers via
  Compilation Space Exploration.* SOSP 2023 (Artemis).
  https://connglli.github.io/pdfs/artemis_sosp23.pdf **[opened]**. One program
  has many possible compilation choices; mutate it with semantics-preserving
  structures that change which code is compiled and cross-validate the results.
  Reported: 85 bug reports for HotSpot, OpenJ9 and ART, 53 confirmed or fixed,
  all in JIT compilers.

For this harness: which mutations preserve meaning is answered in
recommendation 6. The short form is that purity removes almost every side
condition; the guard is the "input set", and re-annotation is the cheapest
variant generator.

### 2. Csmith, YARPGen, and avoiding undefined behaviour

- Xuejun Yang, Yang Chen, Eric Eide, John Regehr. *Finding and Understanding
  Bugs in C Compilers.* PLDI 2011 (Csmith).
  https://www.flux.utah.edu/paper/yang-pldi11 **[opened]**. Random C programs
  that avoid undefined and unspecified behaviour; more than 325 previously
  unknown bugs reported over three years.
- Vsevolod Livinskii, Dmitry Babokin, John Regehr. *Random Testing for C and
  C++ Compilers with YARPGen.* OOPSLA 2020.
  https://users.cs.utah.edu/~regehr/yarpgen-oopsla20.pdf **[opened]**. Avoids UB
  by static analysis of the generated code instead of dynamic wrappers, and
  introduces generation policies: operator contexts applied to random regions,
  constant policies (all-constant and half-constant leaves, small magnitudes,
  near-limit values, contiguous bit blocks, a buffer that reuses constants with
  their negations and complements), and a common-subexpression buffer. Reported:
  more than 220 bugs (83 GCC, 62 LLVM, 76 Intel C++). The paper credits one LLVM
  bug in bit-tracking dead code elimination to the combination of the
  shift-bitwise context with half-constant leaves.
- Vsevolod Livinskii, Dmitry Babokin, John Regehr. *Fuzzing Loop Optimizations
  in Compilers for C++ and Data-Parallel Languages.* PLDI 2023.
  https://livinskii.com/assets/files/yarpgen-pldi23.pdf **[opened]**. Loop
  generation policies (loop sequences and nests, array access patterns,
  stencils, reductions) added piecemeal in response to coverage gaps; the stated
  principle is "we cannot find bugs in optimizations that we cannot trigger".
  Reported: 122 bugs.

For this harness: guards are the analogue of UB, and `infer` plus the REF twin
is the "by analysis" approach already. The part that resembles Csmith's "by
construction" wrappers is `fit-int`, with the same cost YARPGen describes
(recommendation 8). The scalar policies map directly (recommendation 9); the
loop policies do not (see "What does not transfer").

### 3. Coverage-guided, grammar-aware and IR-aware fuzzing

- Samuel Groß, Simon Koch, Lukas Bernhard, Thorsten Holz, Martin Johns.
  *FUZZILLI: Fuzzing for JavaScript JIT Compiler Vulnerabilities.* NDSS 2023.
  https://www.ndss-symposium.org/wp-content/uploads/2023-290-paper.pdf
  **[opened]**. Mutates an SSA-like IR (FuzzIL) whose invariants keep programs
  syntactically valid; mutators are input, operation, splice/combine and
  generative; only valid samples that add coverage enter the corpus, after
  minimisation. The paper's CVE table (JavaScriptCore and SpiderMonkey) includes
  incorrect type inference and loop-invariant code motion that removed a guard or
  bounds check; I did not extract a total bug count.
- Rohan Padhye, Caroline Lemieux, Koushik Sen, Mike Papadakis, Yves Le Traon.
  *Semantic Fuzzing with Zest.* ISSTA 2019. https://arxiv.org/abs/1812.00078
  **[opened]**. Turns a QuickCheck-style generator into a deterministic function
  of a parameter sequence, so byte-level mutations of the sequence are
  structural mutations of the output; feedback is coverage plus validity.
  Reported: 1.03x to 2.81x the branch coverage of baselines in semantic-analysis
  stages, 10 new bugs.
- Yuyang Rong, Zhanghan Yu, Zhenkai Weng, Stephen Neuendorffer, Hao Chen.
  *IRFuzzer: Specialized Fuzzing for LLVM Backend Code Generation.* ICSE 2025.
  https://arxiv.org/abs/2402.05256 **[opened]**. Uses "matcher table coverage"
  of instruction selection as feedback in place of edge coverage, and feeds the
  uncovered table entries back to the mutator. Reported: 74 confirmed new LLVM
  bugs, 49 fixed. This is the closest published precedent for a table of
  transforms or VOPs as the signal.
- Jaeseong Kwon, Bongjun Jang, Juneyoung Lee, Kihong Heo.
  *Optimization-Directed Compiler Fuzzing for Continuous Translation
  Validation.* PLDI 2025. http://prosys.kaist.ac.kr/publications/pldi25.pdf
  **[opened]**. Directed grey-box fuzzing toward one target optimization, then
  translation validation of what it produced. Reported: 55 new LLVM
  miscompilation bugs.
- Chenyuan Yang et al. *WhiteFox: White-Box Compiler Fuzzing Empowered by Large
  Language Models.* OOPSLA 2024. https://arxiv.org/abs/2310.15991 **[opened]**.
  One model reads an optimization's source and writes the conditions a test must
  meet; another writes tests; tests that trigger the optimization are fed back
  as examples. Reported: 101 bugs in deep-learning compilers, 92 confirmed new.

How to do feedback when the signal is a table: keep a per-test fired set;
reward new entries and new co-firing pairs; weight by rarity; and, before any
mutation loop, use the table statistically (recommendation 8) and
constructively (recommendation 9), because the table tells you the argument
types that make an entry applicable, which an edge bitmap never does.

### 4. Swarm testing and test-case reduction

- Alex Groce, Chaoqiang Zhang, Eric Eide, Yang Chen, John Regehr. *Swarm
  Testing.* ISSTA 2012. https://www.flux.utah.edu/paper/groce-issta12
  **[opened]**. Each configuration omits a random subset of features; omission
  helps because some features suppress behaviours and all features compete for
  space in a test. Reported: 42 percent more distinct compiler crashes in a week
  than the tuned default configuration.
- M. A. Alipour et al. *Generating Focused Random Tests Using Directed Swarm
  Testing.* https://agroce.github.io/issta16.pdf **[excerpt]** (ISSTA 2016 by the
  file name; I did not confirm the full author list). Uses statistics over swarm
  runs to focus random tests on a chosen target.
- John Regehr, Yang Chen, Pascal Cuoq, Eric Eide, Chucky Ellison, Xuejun Yang.
  *Test-Case Reduction for C Compiler Bugs.* PLDI 2012 (C-Reduce).
  https://www.flux.utah.edu/paper/regehr-pldi12 **[opened]**. A fixpoint over
  modular domain-specific transformations that keep the test valid; outputs on
  average more than 25 times smaller than the other reducers compared.
- Zhenyang Xu, Yongqiang Tian, Mengxiao Zhang, Gaosen Zhao, Yu Jiang, Chengnian
  Sun. *Pushing the Limit of 1-Minimality of Language-Agnostic Program
  Reduction.* OOPSLA 2023 (Vulcan).
  https://cs.uwaterloo.ca/~cnsun/public/publication/oopsla23/oopsla23.pdf
  **[opened]**. After a syntax-guided reducer such as Perses reaches a 1-minimal
  result, apply transformations that change the program without shrinking it, to
  create new reduction opportunities.
- Chengnian Sun, Yuanbo Li, Qirun Zhang, Tianxiao Gu, Zhendong Su. *Perses:
  Syntax-Guided Program Reduction.* ICSE 2018. Listed on
  https://web.cs.ucdavis.edu/~su/emi-project/ **[opened]**; paper not read.

What the swarm lacks: it covers kinds only (recommendations 1 and 8). What the
reducer lacks: recommendation 11.

### 5. Skeletal enumeration and bounded-exhaustive testing

- Qirun Zhang, Chengnian Sun, Zhendong Su. *Skeletal Program Enumeration for
  Rigorous Compiler Testing.* PLDI 2017. https://arxiv.org/abs/1610.03148
  **[opened]**. Fix a skeleton, enumerate all variable-usage patterns, and
  compute the canonical set of programs that are not alpha-equivalent. Reported:
  217 confirmed GCC/Clang bug reports in under six months, 104 fixed, most
  long-latent; the canonicalisation removes six orders of magnitude of
  duplicates on GCC's test suite.
- Jason S. Reich, Matthew Naylor, Colin Runciman. *Lazy Generation of Canonical
  Test Programs.* IFL 2011.
  https://www.cs.tufts.edu/comp/150FP/archive/colin-runciman/canonical-test.pdf
  **[opened]**. Enumerates small programs in a first-order core language with
  positional names using Lazy SmallCheck, with validity conditions and
  canonical-representative conditions stated separately so that pruning is lazy.
  Used to test an optimisation and two language implementations. The language
  and method are the closest match in the literature to this harness's IR.
- Michał Pałka, Koen Claessen, Alejandro Russo, John Hughes. *Testing an
  Optimising Compiler by Generating Random Lambda Terms.* AST 2011. Seen in the
  reference list at
  https://link.springer.com/chapter/10.1007/978-3-642-34407-7_5 **[excerpt]**;
  paper not read.

Which bug classes enumeration reaches that random generation does not: usage
patterns that a generator with fresh names cannot produce (shadowing, capture),
patterns it produces rarely (zero uses, one variable in two roles), and every
pairing of those with a context feature. See recommendation 2.

### 6. Symbolic and semi-symbolic input selection, translation validation, tier differencing

- Nuno P. Lopes, Juneyoung Lee, Chung-Kil Hur, Zhengyang Liu, John Regehr.
  *Alive2: Bounded Translation Validation for LLVM.* PLDI 2021.
  https://pldi21.sigplan.org/details/pldi-2021-papers/5/Alive2-Bounded-Translation-Validation-for-LLVM
  **[opened]**. SMT check that the optimized IR refines the source IR, with
  bounded loop unrolling and no false alarms. Reported: 47 new bugs from running
  it over LLVM's unit tests, 28 fixed, and eight patches to the language
  reference.
- Jubi Taneja, Zhengyang Liu, John Regehr. *Testing Static Analyses for
  Precision and Soundness.* CGO 2020.
  https://users.cs.utah.edu/~regehr/cgo20.pdf **[opened]**. Computes sound and
  maximally precise dataflow facts with an SMT solver and compares them with the
  compiler's. Reported: no new soundness bugs in LLVM, re-detection of
  re-introduced old ones, many imprecisions.
- Liam Wachter, Julian Gremminger, Christian Wressnegger, Mathias Payer, Flavio
  Toffalini. *DUMPLING: Fine-grained Differential JavaScript Engine Fuzzing.*
  NDSS 2025. https://www.ndss-symposium.org/wp-content/uploads/2025-1411-paper.pdf
  **[opened]**. Compares full frame state of interpreted and optimized execution
  at many points, because output-only comparison misses miscalculations that do
  not reach a sink. Reported: eight new V8 bugs.
- Optimuzz (topic 3) pairs directed generation with translation validation.

What applies cheaply given readable transform restrictions: reading the argument
types to place inputs and constants (recommendations 7 and 9) and checking
derived facts (recommendation 3). Full translation validation does not (below).

### 7. Proof assistants, SMT solvers and verified toolchains

Soundness bugs found, by technique:

- **Known-outcome program generation.** Ahmed Irfan, Sorawee Porncharoenwase,
  Zvonimir Rakamarić, Neha Rungta, Emina Torlak. *Testing Dafny (Experience
  Paper).* ISSTA 2022. https://ahmed-irfan.github.io/papers/issta22.pdf
  **[opened]**. Random annotated programs with a known verification outcome test
  the verifier's soundness and precision; the same programs differentially test
  four compiler back ends. Reported: 31 confirmed bugs across verifier and
  compilers.
- **Differential and metamorphic testing of the execution path of a verified
  language.** Alastair F. Donaldson, Dilan Sheth, Jean-Baptiste Tristan, Alex
  Usher. *Randomised Testing of the Compiler for a Verification-Aware
  Programming Language.* ICST 2024.
  https://www.doc.ic.ac.uk/~afd/papers/2024/ICST.pdf **[opened]**. Reported: 24
  previously unknown Dafny compiler bugs beyond XDsmith's reach, 9 of them
  soundness issues. The paper's framing matches this project: a wrong-code bug in
  the compiler of a verified language evades both review and verification.
- **Mutation of existing inputs.** Dominik Winterer, Chengyu Zhang, Zhendong Su.
  *On the Unusual Effectiveness of Type-Aware Operator Mutations for Testing SMT
  Solvers.* OOPSLA 2020 (OpFuzz). https://arxiv.org/abs/2004.08799 **[opened]**.
  Swap an operator for another of the same type in a seed formula. Reported:
  1,092 bugs filed against Z3 and CVC4, 819 confirmed, 184 of those soundness
  bugs. And the same authors, *Validating SMT Solvers via Semantic Fusion*, PLDI
  2020 (YinYang),
  https://testsmt.github.io/papers/winterer-zhang-su-pldi20.pdf **[excerpt]**:
  fuse two formulas of known satisfiability into one of known satisfiability;
  45 confirmed bugs in four months.
- **Agent-driven audit with expert hints and a list of past bugs.** Tristan
  Stérin, *In search of falsehood*, 2026-03-05,
  https://tristan.st/blog/in_search_of_falsehood **[opened]**: seven proofs of
  `False` in Rocq's official kernel (mainly guard checker and module system),
  none in Lean's official kernel at that time, three in two unofficial Lean
  kernels. One Lean kernel bug was an `unsigned` to `size_t` truncation that a
  compiler warning flag would have reported. Leonardo de Moura, *Postmortem for
  the Kernel Soundness Bug Hunt*, 2026-08-24,
  https://leodemoura.github.io/blog/2026-8-24-postmortem-for-the-kernel-soundness-bug-hunt/
  **[opened]**: an internal model found Lean kernel soundness bugs in
  proposition recognition up to universe normalisation, declarations naming
  kernel-internal auxiliary types, order-dependent caching in definitional
  equality, and `is_prop`; and two runtime routes to `False`, a reference-count
  overflow and a known bug in the GMP version the Linux binaries were built
  with. Most bogus proofs were rejected by independent checkers. Planned
  responses include shipping checkers built on two different bignum libraries.
- **Catalogues.** Vladimir Reshetnikov, *Shenanigans*,
  https://github.com/VladimirReshetnikov/Shenanigans **[opened]** (README and
  CATALOG.md): every known route to `False` in Lean 4 and Rocq, split into
  paradoxes, sanctioned escape hatches, kernel defects and failed audits.
  Kernel-defect entries relevant here: name-keyed `Nat`/`String`/`reduceBool`
  accelerators, a module boundary that lost `partial`, a recursor whose exported
  view dropped a dependency, Rocq guard-checker and module-system defects, and a
  checker that accepted `False` only when run with its bytecode compiler.
  *Lean Kernel Arena*, https://arena.lean-lang.org/ **[opened]**: a shared suite
  of 128 valid and 84 invalid proofs run against all Lean checkers.
- **ACL2.** Release notes (`doc.lisp`), census in the first section. Concrete
  entries on the routes this harness tests: raw Lisp `take`; `compress1` and
  `compress2` raw code (three separate fixes); `mbe` under `:acl2-mv-as-values`;
  `mbe` inside `encapsulate`; expansion files with `defstobj`; strings
  recognised as stobjs in raw Lisp; stobj recognisers not returning Booleans;
  `never-memoize-fn` returning different values in logic and raw Lisp; `loop$`
  with `:guard` as body; `defabsstobj` using `mbe`; `df-string` and negative
  zero; the SBCL bounded-return-type optimisations; `(type (or t ..))`. Older
  notes online: https://www.cs.utexas.edu/~moore/acl2/v2-7/NOTE-2-7-BUG-FIXES.html
  and https://cs.utexas.edu/users/moore/acl2/v6-3/NOTE-4-3.html **[excerpt]**.
- **Background figures.** *Correct and Complete Type Checking and Certified
  Erasure for Coq, in Coq*, Journal of the ACM,
  https://dl.acm.org/doi/10.1145/3706056 **[excerpt]**: "on average, one critical
  bug has been found every year in Coq". https://cr.yp.to/proofs.html
  **[excerpt]**: HOL Light's changelog shows three soundness bugs, fixed in 1996,
  2003 and 2003.

What this says about technique: no published fuzzer has found a kernel
soundness bug in Lean or Rocq that I could locate; the 2026 finds came from
directed audits seeded with past bugs, and were then confirmed by differential
checking against independent kernels. Fuzzers have found soundness bugs where
there is a second executable semantics to compare with (SMT solvers, Dafny's
verifier and compilers). ACL2 has that second semantics (logic versus raw
Lisp), which is why a harness is the right tool here, and the audits tell it
where to point: boundaries, caches, accelerated primitives, and the runtime
underneath.

### 8. Persistence, images, separate and incremental compilation

I found no paper devoted to fuzzing compiled-file or image caches. What exists:

- Rust RFC 1298, *Incremental compilation*,
  https://github.com/rust-lang/rfcs/blob/master/text/1298-incremental-compilation.md
  **[excerpt]**: proposes fuzzing with innocuous edits, with the oracle that the
  incremental result equals compiling from scratch.
- Shenanigans (topic 7): Lean lean4#14609 (exported stubs of `partial`
  definitions not marked unsafe) and lean4#14875 (a recursor keeps a dependency
  that its module's exported view drops, so a downstream module can rebind the
  name); Rocq module-system kernel defects; rocq#22352, where the checker of
  compiled files gave a different verdict depending on its own evaluation
  strategy.
- ACL2 notes: the expansion-file and `defstobj` bug; incomplete prohibition of
  `local` portcullis commands (note-8-5); acl2-defaults-table set in a local
  context (note-3-0-1, **[excerpt]**); counterfeit `record-expansion` calls
  (note-8-4).
- This project: F1, F2 and `scouts/acl2-rederive/FINDINGS.md` C1.

The common shape is a fact that is checked or established in one environment and
reused in another that differs in a way the cache key does not record.
Recommendations 1 and 5 enumerate the environment differences ACL2 has.

### 9. Common Lisp

- Paul F. Dietz. *The GCL ANSI Common Lisp Test Suite.* International Lisp
  Conference 2005.
  https://sources.debian.org/data/main/c/cl-ansi-tests/20060621-1/doc/ilc2005.pdf
  **[excerpt]** (the PDF did not download; abstract seen in the search result):
  more than 20,000 tests plus random generators for specific parts of
  implementations, which "revealed many conformance bugs in all implementations
  on which it has been run". The tester's source header
  (https://gitlab.common-lisp.net/cmucl/ansi-test/-/blob/6203b6f0445e3dec6fc9be1357c1add078d87b30/random/random-int-form.lsp,
  **[excerpt]**; the site blocked fetching) says it lists bugs found in various
  implementations. A 2005 commit log
  (https://lists.gnu.org/archive/html/gcl-commits/2005-07/msg00001.html,
  **[excerpt]**) shows it being adapted for ABCL. I found no published bug count.
- SBCL bug reports from the tester: lp#974406,
  https://bugs.launchpad.net/sbcl/+bug/974406 **[opened]**: wrong `logand` of a
  sum under one optimisation policy; cause was unsigned modular arithmetic
  implemented with signed operations without cutting constants to width.
  lp#1838267, https://bugs.launchpad.net/sbcl/+bug/1838267 **[opened]**: memory
  fault with a dynamic-extent local function and `multiple-value-call`.
  lp#1199127 and lp#1739652 **[excerpt]**: a type error inside
  `integer-type-numeric-bounds` on a `loop` with `logorc2` and `ash`, and wrong
  code with `dynamic-extent` and `progv` from pathwise back-propagation.
- SBCL `NEWS` (local checkout, my keyword census, approximate): about 60 of
  3,726 items describe a miscompilation or wrong result; among those, back end
  or VOP 8, modular arithmetic/shift/word 6, compile-file/constants/coalescing
  6, type derivation 5. Random testing is credited in five items, including "a
  large number of issues found through extended random testing" and lists of
  eight and three Launchpad numbers in two 1.4.x releases.
- ACL2 note-8-7 (topic 7): the only SBCL optimisation bugs recorded as ACL2
  soundness bugs came from derived bounded return types.

Later academic work on fuzzing SBCL, CCL, ECL or ABCL: my two searches found
none. Known miscompilation classes in SBCL, from the above: modular arithmetic
width cuts, type derivation producing an empty or too-narrow type, dynamic
extent and non-local exit, and back-end VOPs. This harness's grammar reaches the
first two; ACL2 code cannot express the third.

---

## What does not transfer

- **Loop-optimizer policies (YARPGen v2) and EMI's large dead regions.** SBCL
  and CCL have no loop fusion, interchange, vectoriser or idiom recogniser, and
  `loop$` and recursion compile to calls and jumps. Stencil, reduction and
  loop-nest policies have no target. EMI's premise is a large real program with
  much code unexecuted under the given inputs; these functions are a few dozen
  nodes, so dead-code pruning has little room (the dead-arm variant in
  recommendation 6 is what remains).
- **UB-avoidance machinery.** Csmith's wrappers and YARPGen's UB analysis solve
  a problem this language does not have. The lesson that does carry over is
  negative: the clamps in `fit-int` play the role of Csmith's wrappers.
- **Edge coverage and crash oracles.** Fuzzilli's targets are memory-safety
  bugs observed as crashes, with warm-up loops to trigger a JIT. Here
  compilation is ahead of time, a crash is not the failure of interest, and the
  transform table is a better signal than edges because it carries
  applicability conditions.
- **Grammar-based and byte-level mutators** (the Nautilus/Superion/PolyGlot/
  LangFuzz/Grammarinator family, known to me only by name and by Fuzzilli's
  related-work discussion). They buy syntactic validity, which s-expressions
  give for free. Validity here is semantic and whole-function (ACL2 rejects the
  entire `defun`), and one test costs seconds to minutes, so a mutator without a
  validity guarantee wastes most of a budget of thousands of runs per day. The
  idea that survives is Zest's.
- **Translation validation in the Alive2 sense.** It needs a formal semantics
  for the compiler's IR and an SMT encoding. SBCL's IR1/IR2 and CCL's acode have
  neither, and unbounded integers fit bit-vector theories badly. CompCert-style
  validated passes need changes inside the compiler. Building either is a
  research project, not a harness change.
- **Tier differencing as a new idea.** REF under `:all` against raw OPT already
  is interpreter-versus-compiled differencing. What transfers from Dumpling is
  only the observation about sinks (recommendation 7).
- **Export-and-recheck with independent kernels.** ACL2 produces no proof
  objects and has no second checker. The nearest analogue is a second host
  Lisp, which the harness has; a third host would add a third bignum
  implementation, in the spirit of Lean's plan to ship GMP and non-GMP checkers.
- **Semantic fusion's construction.** It depends on satisfiability having a
  known answer under formula combination. The transferable part is "outcome
  known by construction" (recommendation 4).

---

## Could not verify

Stated above only as marked; listed here so nothing is mistaken for checked.

- The name "Hermes" for the OOPSLA 2016 live-code-mutation tool, its mechanism
  beyond the one-line excerpt, and its bug count. Not opened.
- Perses and Palka et al.: titles, authors and venues seen in listings; papers
  not read. Directed swarm testing: first author and title seen; full author
  list and venue inferred from the file name.
- Semantic fusion (YinYang), the JACM Coq paper (author list not seen), the
  cr.yp.to remark on HOL Light, Rust RFC 1298, Dietz's ILC 2005 paper and the
  header of `random-int-form.lsp`, lp#1199127, lp#1739652, and the older ACL2
  notes online: search-result text only.
- Whether CCL exposes derived result types in a form usable for recommendation
  3; I read only the comment in `coverage/ccl-cov.lisp`.
- The two censuses (ACL2 `doc.lisp`, SBCL `NEWS`) are keyword counts over
  paragraphs with overlapping categories. They show proportions, not exact
  numbers.
- Seen in search results and not read: *A Survey of Modern Compiler Fuzzing*
  (arXiv 2306.06884); *GapForge: Directed Compiler Fuzzing via Coverage-Gap
  Analysis* (arXiv 2607.15762); *Targeted Testing of Compiler Optimizations via
  Grammar-Level Composition Styles* (arXiv 2512.04344); FuzzJIT (title and
  USENIX Security 2023 seen in a citation); Candle, a verified HOL Light
  (Springer excerpt); Rocq issue #22759.

### Unverified, from memory

Named in the task or relevant, but I did not confirm any of these online during
this task; treat authors, venues and years as recollection.

- Korat (Boyapati, Khurshid, Marinov, ISSTA 2002) and TestEra: bounded-exhaustive
  generation of structurally complex inputs from a predicate or Alloy
  specification.
- SmallCheck and Lazy SmallCheck (Runciman, Naylor, Lindblad, Haskell Symposium
  2008). Reich et al. cite "Runciman et al., 2008" for it, which is the only
  confirmation I have.
- Hierarchical delta debugging (Misherghi and Su, ICSE 2006). Named in Vulcan's
  abstract as "HDD" only. Zeller and Hildebrandt's delta debugging paper
  (IEEE TSE 2002) appears in a reference list I saw.
- STORM (Mansur, Christakis, Wüstholz, Zhang, FSE 2020) and Murxla (Niemetz,
  Preiner, Barrett, CAV 2022) for SMT solvers.
- LangFuzz (Holler, Herzig, Zeller, USENIX Security 2012), Nautilus (NDSS 2019),
  Superion (ICSE 2019), PolyGlot (IEEE S&P 2021), Grammarinator (2018).
- classfuzz, *Coverage-Directed Differential Testing of JVM Implementations*
  (PLDI 2016): the title and authors are on the EMI project page I opened; its
  mechanism (coverage-uniqueness as the acceptance criterion for mutated class
  files) is from memory.
- CompCert's validated passes (translation validation of register allocation and
  other untrusted passes inside a verified compiler).
- Any Lean or Coq kernel differential fuzzer as a published paper. I found
  checkers and a test arena, not a fuzzing paper.
