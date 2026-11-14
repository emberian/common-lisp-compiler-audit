# ACL2 Industrial FV Clause Processors & Trust-Tagged Solver Bridges Audit

**Scope:** Community books `books/clause-processors/`, `books/centaur/gl/`, `books/centaur/fgl/`, `books/centaur/satlink/`, `books/centaur/ipasir/`, `books/projects/smtlink/`, `books/hacking/`, and `books/centaur/misc/` under `/Users/ember/dev/acl2-fix/head-worktree/books/`.  
**Runtimes Tested:** ACL2 8.7+ on SBCL 2.6.10 (`/Users/ember/dev/acl2-fix/head-worktree/saved_acl2`), ACL2 8.7+ on CCL 1.14 (`/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2`), Python 3 (`/opt/homebrew/bin/python3`), and Z3 5.4.1 (`import z3` / `/opt/homebrew/bin/z3`).  
**Reproducers:** [`/Users/ember/dev/compiler-audit/repros/fv-*/`](file:///Users/ember/dev/compiler-audit/repros/) (all 6 self-contained harnesses verified exit 0 on SBCL 2.6.10 and CCL 1.14).  
**Prototype Fuzzers:** [`/Users/ember/dev/compiler-audit/hunts/fv-engines/`](file:///Users/ember/dev/compiler-audit/hunts/fv-engines/).

---

## 1. Executive Summary

We audited ACL2's lightweight and industrial formal-verification clause processors (`clause-processors/`, `gl/`, `fgl/`) alongside the trust-tagged (`defttag` / `include-raw`) solver bridges and utilities (`projects/smtlink/`, `centaur/satlink/`, `centaur/ipasir/`, `centaur/misc/`, `hacking/`).

**Primary Takeaways:**
1. **Verified `:ttags nil` clause processors held up:** No `:ttags nil` unsoundness was found in the audited `books/clause-processors/` meta/clause processors (`autohide`, `use-by-hint`, `replace-equalities`, `induction`, `let-abstraction`, `witness-cp`, `just-expand`, `bv-add`, `null-fail-hints`, `meta-extract-user`) or the verified clause-processor / symbolic-evaluation cores of `centaur/gl` and `centaur/fgl`. Those processors either enforce `pseudo-termp` / correctness meta-theorems or safely fail closed on malformed hints.
2. **Six concrete soundness, bypass, or trust-boundary bugs were confirmed** across trust-tagged bridges and raw-Lisp extensions:
   - **FV-1 (`fv-fast-alist-pop-star-bypass`)**: `fast-alist-pop-raw.lsp` registers ACL2's `invariant-risk` property on `'fast-alist-pop` only, omitting `'fast-alist-pop*`. Calling `(fast-alist-pop* nil x)` from `:program` mode + `make-event` mutates backing fast-alist hash tables and proves `NIL`.
   - **FV-2 (`fv-sulfa-eriks-ht-mismatch`)**: `SULFA/books/bv-smt-solver/redundancy-removal.lisp` defines `:logic`-mode alist operations (`eriks-ht-reset`, `eriks-ht-lookup`, `eriks-ht-set`) and replaces them via `progn!` + `set-raw-mode t` with imperative Common Lisp hash-table mutations returning `'eriks-fake-alist` (ignoring `table`), allowing guard verification of `eriks-ht-set` and an immediate proof of `NIL`.
   - **FV-3 (`fv-smtlink-type-coercion`)**: SMTLink's `ACL2_to_Z3.py` translates active `*SMT-functions*` (`equal`, `<`, `binary-+`, `binary-*`, `unary-/`, `unary--`, `if`, `not`, `implies`) directly into Python/Z3 operators without separating ACL2 booleans from numbers (`False == 0`, `True == 1`, `False < True`, `0 < True`, `True + (-1) == 0`, `-True == -1`, `1/True == 1`, `False * False == False`).
   - **FV-4 (`fv-smtlink-symbol-collision-and-index`)**: SMTLink's `translate-symbol` folds case (`str::downcase-string`) and drops package names (`symbol-name` only), collapsing `|x|` vs `X`, `ACL2::X` vs `OTHER-PKG::X`, and `||` vs `""`. Independently, `translator.lisp:417` passes `a.symbol-index` instead of `symbol-index-rest` when numbering consecutive quoted symbols in `a.avoid-list`, mapping distinct quoted symbols `'foo` and `'bar` to the same `"gensym_0"` identifier.
   - **FV-5 (`fv-smtlink-python-injection-spoof`)**: `translate-uninterpreted-decl` (`translator.lisp:1049-1051`) interpolates raw `,name` inside single-quoted Python strings (`_SMT_.Function('...')`), and `SMT-interpret` (`trusted/run.lisp:48`) accepts any stdout whose first line equals `"proved"`. An uninterpreted function symbol containing `'` executes arbitrary Python and spoofs `"proved"` for `_SMT_.prove(False)`.
   - **FV-6 (`fv-satlink-parser-and-unsat-claim`)**: `satlink-handle-line` (`centaur/satlink/top.lisp:550-555`) uses prefix matching `(str::strprefixp "s UNSATISFIABLE" line)` rather than exact token equality, `satlink-run-impl` (`top.lisp:751`) rejects only exit code `127` (accepting segfault exit `139` or CLI-error exit `1`), and `satlink-run-fn-unsat-claim` (`top.lisp:885-907`) trusts `:unsat` for arbitrary `config.cmdline` when `(not (config->lrat-check config))`.

---

## 2. Summary of Findings

| ID | Component | Source Location | Class | Requires `:ttags`? | SBCL & CCL Verified | Reproducer |
|---|---|---|---|---|---|---|
| **FV-1** | `centaur/misc` | [`fast-alist-pop.lisp:105`](file:///Users/ember/dev/acl2-fix/head-worktree/books/centaur/misc/fast-alist-pop.lisp#L105), [`fast-alist-pop-raw.lsp:145-153`](file:///Users/ember/dev/acl2-fix/head-worktree/books/centaur/misc/fast-alist-pop-raw.lsp#L145-L153) | `invariant-risk` omission -> unsoundness (`NIL`) | Yes (`:fast-alist-pop`) | Yes (`NIL-PROVED`) | [`fv-fast-alist-pop-star-bypass`](file:///Users/ember/dev/compiler-audit/repros/fv-fast-alist-pop-star-bypass/run.sh) |
| **FV-2** | `clause-processors/SULFA` | [`redundancy-removal.lisp:17-51`](file:///Users/ember/dev/acl2-fix/head-worktree/books/clause-processors/SULFA/books/bv-smt-solver/redundancy-removal.lisp#L17-L51) | Raw-Lisp / logic mismatch -> unsoundness (`NIL`) | Yes (`acl2::SMT`) | Yes (`NIL-PROVED`) | [`fv-sulfa-eriks-ht-mismatch`](file:///Users/ember/dev/compiler-audit/repros/fv-sulfa-eriks-ht-mismatch/run.sh) |
| **FV-3** | `projects/smtlink` | [`ACL2_to_Z3.py:84-118`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/z3_interface/ACL2_to_Z3.py#L84-L118), [`basics.lisp:40-49`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/verified/basics.lisp#L40-L49), [`run.lisp:48`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/trusted/run.lisp#L48) | Unsound Z3/Python boolean-arithmetic coercion | Yes (`smtlink`) | Yes (Z3 5.4.1 + SBCL/CCL) | [`fv-smtlink-type-coercion`](file:///Users/ember/dev/compiler-audit/repros/fv-smtlink-type-coercion/run.sh) |
| **FV-4** | `projects/smtlink` | [`translate-type.lisp:37-40`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/trusted/z3-py/translate-type.lisp#L37-L40), [`names.lisp:136-167`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/trusted/z3-py/names.lisp#L136-L167), [`translator.lisp:408-427`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/trusted/z3-py/translator.lisp#L408-L427) | Symbol collision (case/pkg) & `symbol-index` shadowing | Yes (`smtlink`) | Yes (Z3 5.4.1 + SBCL/CCL) | [`fv-smtlink-symbol-collision-and-index`](file:///Users/ember/dev/compiler-audit/repros/fv-smtlink-symbol-collision-and-index/run.sh) |
| **FV-5** | `projects/smtlink` | [`translator.lisp:1049-1051`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/trusted/z3-py/translator.lisp#L1049-L1051), [`run.lisp:48`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/trusted/run.lisp#L48) | Python code injection + stdout `"proved"` spoof | Yes (`smtlink`) | Yes (Z3 5.4.1 + SBCL/CCL) | [`fv-smtlink-python-injection-spoof`](file:///Users/ember/dev/compiler-audit/repros/fv-smtlink-python-injection-spoof/run.sh) |
| **FV-6** | `centaur/satlink` | [`top.lisp:550-555,751,885-907`](file:///Users/ember/dev/acl2-fix/head-worktree/books/centaur/satlink/top.lisp#L550-L555) | Solver line prefix & exit-code acceptance | Yes (`satlink`) | Yes (SBCL/CCL) | [`fv-satlink-parser-and-unsat-claim`](file:///Users/ember/dev/compiler-audit/repros/fv-satlink-parser-and-unsat-claim/run.sh) |

---

## 3. Detailed Findings

### FV-1: `fast-alist-pop*` Omits `invariant-risk`, Allowing `NIL` via `:program` + `make-event`

- **Locations:**
  - [`books/centaur/misc/fast-alist-pop.lisp#L105`](file:///Users/ember/dev/acl2-fix/head-worktree/books/centaur/misc/fast-alist-pop.lisp#L105)
  - [`books/centaur/misc/fast-alist-pop-raw.lsp#L145-L153`](file:///Users/ember/dev/acl2-fix/head-worktree/books/centaur/misc/fast-alist-pop-raw.lsp#L145-L153)
- **Root Cause:**
  `fast-alist-pop*` (`fast-alist-pop.lisp:105`) is a `:logic`-mode function whose logical definition simply returns `(cdr alist)`, while its raw Lisp override in `fast-alist-pop-raw.lsp` mutates the backing hash table when the first argument `execp` is `nil`. At the bottom of `fast-alist-pop-raw.lsp:145-153`, `setf (getprop 'fast-alist-pop 'invariant-risk ...)` is installed to prevent ACL2 from calling `fast-alist-pop` safely in raw evaluation from `:program` mode / `make-event`, **but `'fast-alist-pop*` has no `invariant-risk` property**.
- **Impact:**
  Any `:program`-mode wrapper invoked via `make-event` can evaluate `(fast-alist-pop* nil *alist2*)` on a shared fast alist without ACL2 detecting an invariant-risk violation, silently deleting `'a` from the backing hash table of `*alist1*`. Executable evaluation (`hons-get` -> `NIL`) then contradicts the logical definition (`(hons-get 'a *alist1*) = '(a . 2)`), proving `NIL`.
- **Verification:**
  [`repros/fv-fast-alist-pop-star-bypass/run.sh`](file:///Users/ember/dev/compiler-audit/repros/fv-fast-alist-pop-star-bypass/run.sh) loads `centaur/misc/fast-alist-pop` directly and verifies:
  - `@CHECK fast-alist-pop-inv=FAST-ALIST-POP fast-alist-pop*-inv=NIL`
  - `NIL-PROVED` on both SBCL 2.6.10 and CCL 1.14.
- **Recommended Fix:**
  Register `(setf (getprop 'fast-alist-pop* 'invariant-risk t nil 'current-acl2-world *the-live-state*) 'fast-alist-pop*)` alongside `'fast-alist-pop` in `fast-alist-pop-raw.lsp`.

---

### FV-2: SULFA `eriks-ht-*` Raw-Lisp Override Violates Logical Specification (`NIL` Proved)

- **Location:** [`books/clause-processors/SULFA/books/bv-smt-solver/redundancy-removal.lisp#L17-L51`](file:///Users/ember/dev/acl2-fix/head-worktree/books/clause-processors/SULFA/books/bv-smt-solver/redundancy-removal.lisp#L17-L51)
- **Root Cause:**
  Inside an `encapsulate` gated by `(defttag acl2::SMT)`, `eriks-ht-reset`, `eriks-ht-lookup`, and `eriks-ht-set` are defined in `:logic` mode as pure association-list functions (`nil`, `(assoc-equal key table)`, `(cons (cons key val) table)`). Immediately below, a `(progn! (set-raw-mode t) ...)` block redefines them in raw Common Lisp to mutate a global `(defparameter eriks-hash-table (make-hash-table :test #'equal))` and return the symbol `'eriks-fake-alist`, ignoring `table`.
- **Impact:**
  Because ACL2's logical world keeps the original pure definition while raw Lisp executes the mutating definition, `(verify-guards eriks-ht-set)` succeeds trivially and executable evaluation yields `'eriks-fake-alist` while logical expansion yields `'((a . 1))`. With `(in-theory ...)` splitting `:executable-counterpart` vs `:definition`, `NIL` is proved directly.
- **Verification:**
  [`repros/fv-sulfa-eriks-ht-mismatch/run.sh`](file:///Users/ember/dev/compiler-audit/repros/fv-sulfa-eriks-ht-mismatch/run.sh) reproduces the exact `encapsulate`, runs `(verify-guards eriks-ht-set)`, and proves `NIL-PROVED` on both SBCL 2.6.10 and CCL 1.14.
- **Recommended Fix:**
  Replace the raw global hash table with a proper ACL2 stobj / `fast-alist` or restrict the functions via non-executable / `defattach` axioms that accurately model the return token rather than claiming `(cons (cons key val) table)`.

---

### FV-3: SMTLink `ACL2_to_Z3.py` Bool/Number Type Coercion Violates ACL2 Semantics

- **Locations:**
  - [`books/projects/smtlink/z3_interface/ACL2_to_Z3.py#L84-L118`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/z3_interface/ACL2_to_Z3.py#L84-L118)
  - [`books/projects/smtlink/verified/basics.lisp#L40-L49`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/verified/basics.lisp#L40-L49)
  - [`books/projects/smtlink/trusted/run.lisp#L48`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/trusted/run.lisp#L48)
- **Root Cause:**
  SMTLink's active `*SMT-functions*` map `equal`, `<`, `binary-+`, `binary-*`, `unary-/`, `unary--`, `if`, `not`, `implies` to Python `ACL22SMT` methods that evaluate on raw Python `bool`/`int`/`float`/Z3 expressions without checking ACL2's disjoint type domains (`booleanp` vs `acl2-numberp` / `rationalp`, where ACL2 non-numeric arguments coerce to `0` in arithmetic and booleans are never `equal` to numbers). In Python/Z3, `bool` is a subclass of `int` (`False == 0`, `True == 1`), so `ACL22SMT.equal(False, 0)`, `ACL22SMT.lt(False, True)`, `ACL22SMT.plus(True, -1) == 0`, etc., evaluate to Python `True`, which `_SMT_.prove(...)` turns into `"proved"`. (Additionally, `ACL22SMT.rationalp` comments out `RealSort()` behavior in a way where Z3 integers return `False` for `sort(x) == RealSort()`.)
- **Impact:**
  False ACL2 theorems over ground or mixed boolean/numeric subexpressions translate to Z3 proofs outputting `"proved"`, which `SMT-interpret` (`trusted/run.lisp:48`) accepts unconditionally.
- **Verification:**
  [`repros/fv-smtlink-type-coercion/run.sh`](file:///Users/ember/dev/compiler-audit/repros/fv-smtlink-type-coercion/run.sh) confirms all 8 ground expressions evaluate to `isThm=True` + `"proved"` via `ACL2_to_Z3.py` on Z3 5.4.1 (`equal(False, 0)`, `equal(True, 1)`, `False < True`, `0 < True`, `True + (-1) == 0`, `-True == -1`, `1/True == 1`, `False * False == False`) while ACL2 on SBCL and CCL proves `ACL2-TRUTH-ALL-FALSE` (`NIL` on all 8) and `smt-interpret('("proved")) = T`.  
  The prototype differential fuzzer [`smtlink_diff_fuzz.py`](file:///Users/ember/dev/compiler-audit/hunts/fv-engines/smtlink_diff_fuzz.py) independently uncovered **19 distinct unsoundness classes** (`ACL2=NIL`, `Z3=proved`) and **23 runtime exception classes** (`Z3Exception`, `TypeError`, `ZeroDivisionError`, `"giving up"`).
- **Recommended Fix:**
  Separate Z3 sorts or wrap ACL2 terms in a tagged algebraic datatype / explicit `acl2_numberp`/`fix` coercion wrapper in `ACL2_to_Z3.py` rather than relying on Python `bool`/`int` subtyping.

---

### FV-4: SMTLink Symbol Collision (`translate-symbol`) and Quoted-Symbol Index Shadowing

- **Locations:**
  - [`books/projects/smtlink/trusted/z3-py/translate-type.lisp#L37-L40`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/trusted/z3-py/translate-type.lisp#L37-L40)
  - [`books/projects/smtlink/trusted/z3-py/names.lisp#L136-L167`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/trusted/z3-py/names.lisp#L136-L167)
  - [`books/projects/smtlink/trusted/z3-py/translator.lisp#L408-L427`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/trusted/z3-py/translator.lisp#L408-L427)
- **Root Cause:**
  1. `translate-symbol` passes `(lisp-to-python-names sym)` through `str::downcase-string`, and `lisp-to-python-names` reads only `(symbol-name var)`. This **drops the package name** and **collapses uppercase/lowercase symbol names**, so distinct ACL2 variables/symbols `|x|` vs `X` and `ACL2::X` vs `OTHER-PKG::X` map to the identical Python identifier `"x"`, and empty-named `||` maps to `""`.
  2. Independently, when translating consecutive quoted symbols that collide with `a.avoid-list` (`translator.lisp:417`), the outer call passes `a.symbol-index` rather than the updated `symbol-index-rest` returned from the recursive call into `(generate-symbol-enumeration a.symbol-index ...)`. Two distinct avoided quoted symbols `'foo` and `'bar` both receive `"gensym_0"`.
- **Impact:**
  Distinct ACL2 variables or quoted constants alias onto the same Z3 variable / enumeration constant, allowing Z3 to prove `(implies (and (integerp |x|) (integerp x)) (equal |x| x))` or equate distinct quoted symbols.
- **Verification:**
  [`repros/fv-smtlink-symbol-collision-and-index/run.sh`](file:///Users/ember/dev/compiler-audit/repros/fv-smtlink-symbol-collision-and-index/run.sh) proves `CASE-AND-PKG-COLLISIONS` and `QUOTED-SYMBOL-INDEX-COLLISION` (`(car trans) = "gensym_0"` and `(cadr trans) = "gensym_0"` for `'(foo bar)`) on SBCL and CCL, and confirms Z3 5.4.1 proves `x == x` for collapsed identifiers.
- **Recommended Fix:**
  Encode package name and case distinction injectively in `lisp-to-python-names` (escaping lowercase letters and package prefixes), and pass `symbol-index-rest` at `translator.lisp:417`.

---

### FV-5: SMTLink Python Injection via Uninterpreted Function Name Spoofs `"proved"`

- **Locations:**
  - [`books/projects/smtlink/trusted/z3-py/translator.lisp#L1049-L1051`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/trusted/z3-py/translator.lisp#L1049-L1051)
  - [`books/projects/smtlink/trusted/run.lisp#L48`](file:///Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/trusted/run.lisp#L48)
- **Root Cause:**
  `translate-uninterpreted-decl` emits Python declarations as:
  `(,(translate-symbol name) "= _SMT_.Function(" #\' ,name #\' ...)`
  It sanitizes `name` for the LHS variable with `translate-symbol`, but interpolates **unescaped `,name` inside Python single quotes `'...'`** for the Z3 function name string. Meanwhile, `SMT-interpret` (`trusted/run.lisp:48`) returns success whenever `(equal (car lines) "proved")`, ignoring exit status or subsequent output.
- **Impact:**
  An ACL2 theorem containing an uninterpreted function symbol with single quotes and Python syntax—such as `|bad', _SMT_.IntSort(), _SMT_.BoolSort());print('proved');import sys;sys.exit(0)#|`—executes arbitrary Python during solver invocation, prints `"proved"` on line 1, exits cleanly before `_SMT_.prove(False)` executes, and tricks `SMT-interpret` into accepting `False`.
- **Verification:**
  [`repros/fv-smtlink-python-injection-spoof/run.sh`](file:///Users/ember/dev/compiler-audit/repros/fv-smtlink-python-injection-spoof/run.sh) generates `injected.py` from ACL2 using the exact declaration format, executes it via `/opt/homebrew/bin/python3` (`_SMT_.prove(False)` is skipped), captures `first_line="proved"`, and feeds `'("proved")` to `smt-interpret-lines`, yielding `@INTERP T` on both SBCL 2.6.10 and CCL 1.14.
- **Recommended Fix:**
  Use `(translate-symbol name)` (or hex-escape `'`, `\`, newlines) inside `_SMT_.Function(...)`, require a non-spoofable structured response / proof check, and reject any non-zero exit or unexpected stdout tokens.

---

### FV-6: SATlink `s UNSATISFIABLE` Prefix Matching and Exit-Code Blindness

- **Locations:** [`books/centaur/satlink/top.lisp#L550-L555`](file:///Users/ember/dev/acl2-fix/head-worktree/books/centaur/satlink/top.lisp#L550-L555), [`#L751`](file:///Users/ember/dev/acl2-fix/head-worktree/books/centaur/satlink/top.lisp#L751), [`#L885-L907`](file:///Users/ember/dev/acl2-fix/head-worktree/books/centaur/satlink/top.lisp#L885-L907)
- **Root Cause:**
  1. `satlink-handle-line` checks `(str::strprefixp "s UNSATISFIABLE" line)` instead of exact line equality or token boundaries. Lines like `"s UNSATISFIABLE_ERROR_OR_NOT"` or `"s UNSATISFIABLE? FALSE!"` are classified as `:unsat`.
  2. `satlink-run-impl` (`top.lisp:751`) only errors on `(equal exit-status 127)`. Any other non-zero exit status—including `139` (SIGSEGV) or `1` (CLI usage error)—is ignored if stdout contains `"s UNSATISFIABLE..."`, returning `:unsat`.
  3. `satlink-run-fn-unsat-claim` (`top.lisp:885-907`) is a `:defttag`-backed axiom asserting that when `(not (config->lrat-check config))` and `satlink-run-fn` returns `:unsat`, `formula` is unsatisfiable for **arbitrary** `config->cmdline` strings without verifying solver identity or exit code 0/20.
- **Impact:**
  When LRAT checking is disabled, any solver crash (`139`), wrapper error message (`1`), or corrupted `"s UNSATISFIABLE..."` status line causes `satlink-run-fn` to claim `:unsat`, making `satlink-run-fn-unsat-claim` unsound relative to the external solver process.
- **Verification:**
  [`repros/fv-satlink-parser-and-unsat-claim/run.sh`](file:///Users/ember/dev/compiler-audit/repros/fv-satlink-parser-and-unsat-claim/run.sh) verifies `PARSER-AND-EXITCODE-BUGS` and `@CHECK corrupted-prefix=:UNSAT segfault-139=:UNSAT` on both SBCL 2.6.10 and CCL 1.14.  
  The parser fuzzer [`satlink_parser_fuzz.py`](file:///Users/ember/dev/compiler-audit/hunts/fv-engines/satlink_parser_fuzz.py) found **6 adversarial bypasses** and **477/1000 randomized trials** yielding `:unsat` on non-zero exit codes or corrupted `"s UNSATISFIABLE..."` prefixes.
- **Recommended Fix:**
  Enforce exact DIMACS status line matching (`"s UNSATISFIABLE"` with optional whitespace only), reject any exit status not equal to `20` (for UNSAT) / `10` (for SAT) / `0`, and document `config->lrat-check` as mandatory for high-assurance soundness.

---

## 4. Audited Clean Components (`:ttags nil` and Core Verified Paths)

No soundness defects were found in the verified `:clause-processor` / `:meta` proofs or core formula checks of the following audited files:

- **`books/clause-processors/` (`:ttags nil`):**
  - `autohide.lisp`, `use-by-hint.lisp`, `replace-equalities.lisp`, `induction.lisp`, `let-abstraction.lisp`, `witness-cp.lisp`, `just-expand.lisp`, `bv-add.lisp`, `null-fail-hints.lisp`, `meta-extract-user.lisp`, and `SULFA/books/sat/sat.lisp`.
  - Confirmed via source review and [`cp_falsify.lisp`](file:///Users/ember/dev/compiler-audit/hunts/fv-engines/cp_falsify.lisp) that malformed hints (`fuzz-autohide-bad-hint`, `fuzz-remove-hyp-bad-hint`, `fuzz-identity-cp`) fail closed or reduce safely without dropping obligations.
- **`books/centaur/gl/` & `books/centaur/fgl/`:**
  - `gl/eval-f-i-cp.lisp`, `gl/run-gified-cp.lisp`, `gl/gl.lisp`, `gl/gl-generic-clause-proc.lisp`, `gl/def-gl-clause-proc.lisp`, `gl/bfr-satlink.lisp`, `gl/bfr-fraig-satlink.lisp`, `gl/solutions.lsp`.
  - `fgl/clauseproc.lisp`, `fgl/equivcheck.lisp`, `fgl/checks.lisp`, `fgl/primitives-stub.lisp`, `fgl/add-primitives.lisp`, `fgl/casesplit.lisp`, `fgl/ipasir-sat.lisp`.
  - Verified clause-processor wrappers enforce `pseudo-termp` / evaluator-backed correctness obligations; FGL `def-fgl-primitive` / `add-primitives` and `gl-generic-clause-proc` guard shape and evaluator correspondence.
- **`books/centaur/satlink/dimacs.lisp` & `top-raw.lsp`, `books/centaur/ipasir/`:**
  - `satlink/dimacs.lisp` DIMACS literal numbering and header encoding (`1`-based `lit->var + 1`, negated `-var`) and `ipasir/` (`ipasir-backend.lisp`, `ipasir-logic.lisp`, `ipasir-interface-raw.lsp`) C-FFI status code decoding (`10` / `20`) checked cleanly against their logical contracts.
- **`books/centaur/misc/` (excluding `fast-alist-pop*`) & `books/hacking/`:**
  - `sneaky-load.lisp` / `sneaky-raw.lsp`, `tshell.lisp` / `tshell-raw.lsp`, `hons-extra.lisp`, `spacewalk-raw.lsp`, `sharedlibs-raw.lsp`, `collect-like-terms.lisp`, `context-rw.lisp`, and `hacking/` (`defcode.lisp`, `redefun.lisp`, `bridge.lisp`, `raw.lisp`) expose explicit `defttag` / `progn!` capabilities as documented (with `tshell-unsound.lisp` already separated as explicitly unsound).

---

## 5. Prototype Mechanical Fuzzer Results

All three prototype scripts live in [`/Users/ember/dev/compiler-audit/hunts/fv-engines/`](file:///Users/ember/dev/compiler-audit/hunts/fv-engines/):

1. **[`smtlink_diff_fuzz.py`](file:///Users/ember/dev/compiler-audit/hunts/fv-engines/smtlink_diff_fuzz.py)**: Generates ground expressions over ACL2 booleans (`T`, `NIL`) and rationals (`-1`, `0`, `1/2`, `1`, `2`) using active `*SMT-functions*` (`equal`, `<`, `+`, `*`, `/`, `-`, `if`, `not`, `implies`), evaluates exact ACL2 ground semantics in Python, runs `ACL2_to_Z3.py` (`ACL22SMT().prove(...)`) against Z3 5.4.1, and classifies mismatches.
   - **Latest run output:** **19 unsoundness classes** (`ACL2=NIL`, `Z3=proved`) and **23 runtime exception classes** (`Z3Exception`, `TypeError`, `ZeroDivisionError`, `"giving up"`).
2. **[`satlink_parser_fuzz.py`](file:///Users/ember/dev/compiler-audit/hunts/fv-engines/satlink_parser_fuzz.py)**: Models `satlink-handle-line` and `satlink-run-impl` (`top.lisp:550-555, 751`) across adversarial and 1,000 randomized `(exit_status, stdout_lines)` streams.
   - **Latest run output:** **6 adversarial bypasses** and **477/1000 randomized trials** yielding `:unsat` on non-zero exit codes or corrupted `"s UNSATISFIABLE..."` prefixes.
3. **[`cp_falsify.lisp`](file:///Users/ember/dev/compiler-audit/hunts/fv-engines/cp_falsify.lisp)**: Exercises `:ttags nil` clause processors (`autohide`, `remove-hyp`, `null-fail-hints`) with malformed hints (all `Q.E.D.`) alongside automated SBCL verification of `NIL-VIA-FAST-ALIST-POP*` (`Q.E.D.`) and `NIL-VIA-SULFA-ERIKS-HT` (`Q.E.D.`).

---

## 6. Systematic Mechanical Fuzzing Blueprint

To scale coverage across all FV engines beyond manual review and prototype scripts, we propose a four-target automated fuzzing pipeline:

### 6.1 SMTLink End-to-End Term, Sort, & Translator Differential Fuzzer
- **Oracle:** Evaluate randomly generated closed/open ACL2 expressions with witness assignments $(x_1 \mapsto v_1, \dots, x_k \mapsto v_k)$ directly inside ACL2 (`eval-ground`) vs translating the ACL2 AST through ACL2's actual `verified/` + `trusted/z3-py/translator.lisp` pipeline and executing `/opt/homebrew/bin/python3` + Z3 5.4.1.
- **Generators & Mutations:**
  - *Mixed-type expressions:* Mix `booleanp`, `integerp`, `rationalp`, `symbolp`, and `stringp` literals inside `+`, `*`, `/`, `<`, `equal`, `if`, `implies`, `not`, and `let`/`lambda`.
  - *Symbol & package edge cases:* Generate symbols across multiple packages (`PKG1::x`, `PKG2::x`), case-colliding symbols (`|x|`, `X`, `|X|`), empty symbol `||`, Python keywords (`and`, `or`, `None`, `True`, `lambda`), quotes/newlines (`|a'b\nc|`), and consecutive quoted constants in `avoid-list`.
  - *Config & custom-fn fuzzing:* Mutate `smtlink-custom` (`*SMT-functions*`, `type-hyp`, uninterpreted return/arg sorts) and flag any case where `ACL2(witness) == NIL` while Z3 prints `"proved"` on line 1.

### 6.2 SATlink & IPASIR DIMACS / Output / LRAT Bridge Fuzzer
- **Oracle:** Generate satisfiable and unsatisfiable random $k$-SAT formulas (including empty clauses, zero variables, duplicate/tautological literals `(v, ¬v)`, and single-literal unit clauses). Check:
  1. CNF round-trip: ACL2 `dimacs-export` -> external solver (CaDiCaL/Kissat/Glucose/mock fault-injecting shim) -> `satlink-parse-output` / `lrat-check`.
  2. *Solver-shim fault injection:* Inject non-20/non-10/non-0 exit codes (`1`, `134`, `139`), truncated files, `s UNSATISFIABLE...` suffixes, interleaved `v `/`c ` lines, and corrupted LRAT proofs. Assert `satlink` NEVER returns `:unsat` on satisfiable formulas or non-clean solver exits.
  3. *IPASIR FFI stateful fuzzing:* Random sequences of `(ipasir-add-lit ...)` / `(ipasir-assume ...)` / `(ipasir-solve ...)` / `(ipasir-val ...)` checking `(ipasir-val s lit)` only reads valid `:sat` state and matches brute-force evaluation on small $n \le 12$ formulas.

### 6.3 GL & FGL Symbolic-vs-Concrete Differential Fuzzer
- **Oracle:** Pick random $n$-bit expressions over `logand`, `logior`, `logxor`, `lognot`, `ash`, `logbitp`, `integer-length`, `+`, `*`, `if`, `equal`, and FGL/GL G-objects (`g-integer`, `g-boolean`, `g-ite`, `g-apply`, `g-concrete`), instantiate random concrete $k$-bit assignments, and assert:
  - Symbolic `glcp` / `fgl-interp-cp` evaluation under the symbolic-to-concrete assignment `eval-g-base` / `fgl-eval` equals native ACL2 evaluation of the original term on the concrete inputs.
  - Explicitly fuzz `def-gl-clause-proc` / `def-fgl-primitive` edge inputs: negative bit-widths, zero-length shifts, out-of-range indices, `bfr-to-aig` / `aig-to-bfr` round-trips, and `:g-bindings` with overlapping or malformed variable intervals.
  - Inject random raw-mode / fast-alist / `hons` hash-table sharing across symbolic runs to catch stale memoization or missing `invariant-risk` guards (mirroring **FV-1**).

### 6.4 `:clause-processor` & `:meta` Hint / Non-`pseudo-termp` Falsification Harness
- **Oracle:** Drive every exported `:clause-processor` and `:meta` rule in `books/clause-processors/` and `books/centaur/misc/` with:
  1. *Non-trivial false conjectures* (e.g., `(equal x y)`, `nil`, `(not (consp x))`) combined with malformed `hint` objects (improper lists, shadowed `alist` keys, free variables, quoted `lambda`s, non-`pseudo-termp` s-expressions, and duplicate bindings). Any `Q.E.D.` on a falsifiable goal immediately isolates an unsound CP.
  2. *Guard / `raw-mode` / `progn!` static scanner:* Automatically flag any `books/` file pairing `defttag` + `(set-raw-mode t)` / `include-raw` with `:logic`-mode function stubs (like **FV-2**), verifying whether `:executable-counterpart` vs `:definition` diverges on minimal witness terms `(eriks-ht-set 'a 1 nil)` or lacks `invariant-risk` declarations (like **FV-1**).
