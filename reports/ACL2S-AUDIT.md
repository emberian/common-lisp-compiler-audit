# ACL2s (`books/acl2s/`) Security, Soundness & Contract Audit

Systematic source audit and live differential fuzzing of **ACL2s (`books/acl2s/`)** (`defdata`, `definec`/`defunc`, `cgen`, `ccg`, raw Lisp hooks, and ASPF interface utilities) against ACL2 `8.7+` (`1d2b39a424eabeab269f189b37c29148d49fc516`) on **SBCL 2.6.10** (`darwin-arm64`) and **Clozure CL 1.14** (`darwin-arm64`).

All four primary findings are confirmed live on **both SBCL 2.6.10 and CCL 1.14** via self-contained executable reproducers in [`repros/`](../repros/). Because `head-worktree/books/` was kept strictly read-only (no `make` or in-tree `.cert`/`.fasl` writes), every reproducer and the prototype mechanical fuzzer materialize an isolated temporary shadow `ACL2_SYSTEM_BOOKS` workspace (`mktemp -d`) cleaned up on exit.

---

## Summary of Findings

| ID | Subsystem | Class | Impact | Status / Repro |
|---|---|---|---|---|
| **ACL2S-1** | `defdata` (`defdata-attach`, `register-type`) | Trust-Tag / Guard-Check Bypass -> Raw Memory Fault | `defdata-attach` and `register-type` silently open `(defttag :defdata-attach)` and execute `(defattach ... :skip-checks t)` without verifying enumerator guards, allowing a guard-verified `:logic` function (`:verify-guards t`) to trigger an unhandled raw Lisp memory fault (`0xffffffffffffffff` / `#x1D`) | **Live (SBCL + CCL)** [`acl2s-defdata-attach-skip-checks-crash`](../repros/acl2s-defdata-attach-skip-checks-crash/run.sh) |
| **ACL2S-2** | `definec` (`definec-core`) | Parameter / Contract Integrity & Unsound `:exec` Guard Verification | `(remove-duplicates d-args)` silently accepts duplicate parameter names, strips earlier positional occurrences (swapping parameter order and dropping values), and conjoins contradictory guards so unsound `:exec` bodies (e.g., `(car x)` under `natp`) pass ACL2 guard verification (`:common-lisp-compliant`) | **Live (SBCL + CCL)** [`acl2s-definec-duplicate-formals-swap`](../repros/acl2s-definec-duplicate-formals-swap/run.sh) |
| **ACL2S-3** | `ccg` (`redefun defuns-fn`) | Unhandled `loop$` Recursion Hard Error / DoS | `(redefun defuns-fn ...)` calls `ccg-put-induction-info` on `:loop$-recursion t` functions, crashing admission with `HARD ACL2 ERROR in CHOKE-ON-LOOP$-RECURSION` even when a valid explicit `:measure` is supplied | **Live (SBCL + CCL)** [`acl2s-ccg-loop-recursion-crash`](../repros/acl2s-ccg-loop-recursion-crash/run.sh) |
| **ACL2S-4** | `defunc` (`test?-phase` + `cgen/with-timeout-raw`) | Uncaught `storage-condition` / Raw Lisp Stack-Overflow Abort | `test?-phase` admits unproved recursive definitions via `(skip-proofs ,defun)` and evaluates `test-body-contracts`/`test?` inside `with-timeout-aux-raw`, whose `(handler-case ... (error (c) ...))` fails to catch `storage-condition` stack exhaustion, killing ACL2 from raw Lisp | **Live (SBCL + CCL)** [`acl2s-defunc-nonterm-stack-overflow`](../repros/acl2s-defunc-nonterm-stack-overflow/run.sh) |

Additionally, static inspection identified **5 minor/latent source defects** (not observed to crash or prove `NIL` live) and confirmed **1 suspected defect (`number-enums-sampling.lisp`) is dead `#|`-commented code**.

---

## Detailed Findings

### ACL2S-1: `defdata-attach` & `register-type` Silently Open `(defttag :defdata-attach)` + `:skip-checks t`, Crashing Guard-Verified Functions

- **Locations**:
  - [`books/acl2s/defdata/defdata-attach.lisp`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/defdata/defdata-attach.lisp#L180-L209) (`defdata-attach/enum`, `defdata-attach/enum/acc`)
  - [`books/acl2s/defdata/register-type.lisp`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/defdata/register-type.lisp#L275-L365) (`register-type-fn`)
- **Root Cause**:
  Both `defdata-attach/enum` (`defdata-attach.lisp:188-193`), `defdata-attach/enum/acc` (`defdata-attach.lisp:203-208`), and `register-type-fn` (`register-type.lisp:359-362`) explicitly note an unresolved `;;TODO: type soundness obligation` and immediately emit an internal `defttag` + unchecked `defattach`:
  ```lisp
  ;; books/acl2s/defdata/defdata-attach.lisp:188-193
         ;;TODO: type soundness obligation

      `((DEFTTAG :defdata-attach)
        (DEFATTACH (,(get1 :enumerator kwd-alist) ,enum) :skip-checks t)
        (DEFTTAG nil))))
  ```
  ```lisp
  ;; books/acl2s/defdata/register-type.lisp:359-362
          (DEFTTAG :defdata-attach)
          (DEFATTACH (,enum-name ,enum) :skip-checks t)
          (DEFATTACH (,enum/acc-name ,(or enum/acc enum/acc-default)) :skip-checks t)
          (DEFTTAG nil)
  ```
  Neither function checks `(guard-verified-p enum wrld)` nor proves the attachment guard-compatibility obligation required by ACL2's `defattach` contract. Any user without a `defttag` or `:skip-checks` privilege can attach an un-guard-verified function whose body violates its declared `:guard` (e.g. `(declare (xargs :guard (natp n) :verify-guards nil)) (car n)`) to `nth-nat` (or a newly registered type's enumerator). Because `nth-nat`'s stub carries guard `(natp x)`, a subsequent `:logic`-mode caller `verified-nat-caller` passes ACL2 guard verification (`:verify-guards t`), runs unguarded raw Lisp machine code on `fixnum` `3`, and faults raw memory.
- **Verified Reproduction ([`repros/acl2s-defdata-attach-skip-checks-crash/run.sh`](../repros/acl2s-defdata-attach-skip-checks-crash/run.sh))**:
  - **SBCL 2.6.10**:
    ```text
    ************ ABORTING from raw Lisp ***********
    ********** (see :DOC raw-lisp-error) **********
    Error:  Unhandled memory fault at #xFFFFFFFFFFFFFFFF.
    ***********************************************
    ```
  - **CCL 1.14**:
    ```text
    ************ ABORTING from raw Lisp ***********
    ********** (see :DOC raw-lisp-error) **********
    Error:  Fault during read of memory address #x1D
    While executing: EVIL-NAT-ENUM
    ***********************************************
    ```
- **Recommendation**:
  Remove `:skip-checks t` (and the ambient `(DEFTTAG :defdata-attach)` around user-supplied attachments), require `(guard-verified-p enum wrld)` / `(guard-verified-p enum2 wrld)`, and pass explicit `:hints` (or validate witness theorems) so ACL2 kernel `defattach` proves guard & type-constraint obligations directly.

---

### ACL2S-2: `definec` Silently Drops/Reorders Duplicate Formals via `remove-duplicates` & Fuses Contradictory Guards

- **Location**: [`books/acl2s/definec.lisp`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/definec.lisp#L161-L172) (`definec-core`)
- **Root Cause**:
  `definec-core` extracts typed parameter names (`d-args`) and types (`d-arg-types`) as parallel lists, deduplicates `d-args` with CL `remove-duplicates` (which keeps the **last** occurrence and discards earlier ones, changing arity and reversing relative argument order), yet builds the input contract using the **un-deduplicated** `d-args` and `d-arg-preds`:
  ```lisp
  ;; books/acl2s/definec.lisp:161-172
        (d-args (evens f-argsp))
        (def-args (remove-duplicates d-args))
        (d-arg-types (odds f-argsp))
        (d-arg-types (map-intern-types d-arg-types pkg))
        (d-arg-preds (map-preds d-arg-types tbl atbl))
        (pred (pred-of-type f-type tbl atbl))
        (ic (make-input-contract d-args d-arg-preds))
        (oc (make-contract name def-args pred))
        (defunc `(defunc-core ,name ,d? ,def-args
                   :input-contract ,ic
                   :output-contract ,oc
                   ,@(cddr args)))
  ```
  Two distinct failures result without any diagnostic error:
  1. **Silent parameter drop & argument-order inversion**: `(definec sub-dup (x :int y :int x :pos) :int (- x y))` becomes `(DEFUN SUB-DUP (Y X) ... (- X Y))`. Calling `(sub-dup 10 1)` binds `y=10, x=1` and returns **`-9`** instead of `9` (or rejecting duplicate formal `x`).
  2. **Contradictory guard vacuum passing unsound `:exec` code**: `(definec bad-mbe (x :nat y :nat x :string) :nat (mbe :logic (+ x y) :exec (car x)))` generates input contract `(AND (NATP X) (NATP Y) (STRINGP X))` on `(Y X)`. Because the guard is unsatisfiable, ACL2 verifies `(CAR X)` (`:COMMON-LISP-COMPLIANT`) under `natp`/`stringp` contradiction with `Function Contract proven -- [*]` and `Body Contracts proven -- [*]`.
- **Verified Reproduction ([`repros/acl2s-definec-duplicate-formals-swap/run.sh`](../repros/acl2s-definec-duplicate-formals-swap/run.sh))**:
  - **SBCL 2.6.10 & CCL 1.14**:
    ```text
    ACL2S !> (:FORMALS (Y X))
    ACL2S !> (:EVAL-SUB-DUP -9)
    ACL2S !> (:BAD-MBE-CLASS :COMMON-LISP-COMPLIANT)
    ```
- **Recommendation**:
  Reject duplicate formal parameter names with an explicit `er hard 'definec` check immediately after extracting `d-args` (i.e., `((not (no-duplicatesp-eq d-args)) ...)`), matching standard ACL2 `defun` parameter uniqueness semantics.

---

### ACL2S-3: `ccg` Crashes `defun` Admission with `HARD ACL2 ERROR in CHOKE-ON-LOOP$-RECURSION` on Valid `:loop$-recursion t` Functions

- **Location**: [`books/acl2s/ccg/ccg.lisp`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/ccg/ccg.lisp#L7607-L7608) (`redefun defuns-fn` -> `ccg-defuns-fn` -> `ccg-put-induction-info`)
- **Root Cause**:
  When `acl2s/ccg/ccg` is loaded and `:ccg` termination mode is active (`(set-termination-method :ccg)`), `ccg.lisp:7607` globally redefines ACL2's `defuns-fn` to `ccg-defuns-fn`. When submitting a valid ACL2 `loop$`-recursive `:logic` function—even one carrying both `:loop$-recursion t` and an explicit terminating `:measure (nfix n)`—CCG passes the expanded `sum$` lambda term to ACL2's internal `ccg-put-induction-info`, which has no `loop$` support and aborts admission with `HARD ACL2 ERROR in ACL2::CHOKE-ON-LOOP$-RECURSION`.
- **Verified Reproduction ([`repros/acl2s-ccg-loop-recursion-crash/run.sh`](../repros/acl2s-ccg-loop-recursion-crash/run.sh))**:
  Submitting:
  ```lisp
  (set-termination-method :ccg)
  (defun ccg-loop-rec (n)
    (declare (xargs :mode :logic :loop$-recursion t :measure (nfix n)))
    (if (zp n) 0 (loop$ for i in (list (1- n)) sum (ccg-loop-rec i))))
  ```
  Produces on **both SBCL 2.6.10 and CCL 1.14**:
  ```text
  HARD ACL2 ERROR in CHOKE-ON-LOOP$-RECURSION:  It appears that the ACL2
  system function CCG-PUT-INDUCTION-INFO has been called inappropriately
  on a function body that engages in loop$ recursion.  In particular,
  (SUM$ '(LAMBDA (LOOP$-IVAR)
           (DECLARE (IGNORABLE LOOP$-IVAR))
  ```
- **Recommendation**:
  In `ccg-defuns-fn`, detect `:loop$-recursion` xargs (or `loop$` recursion flags in `def-lst` / xargs) and delegate directly to ACL2's original `:measure` termination path (skipping `ccg-put-induction-info`) whenever `loop$` recursion is present.

---

### ACL2S-4: `defunc`/`definec` `test?-phase` Admits Unverified Non-Terminating Functions via `skip-proofs` and Aborts Raw Lisp on Stack Overflow

- **Locations**:
  - [`books/acl2s/defunc.lisp`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/defunc.lisp#L1353-L1383) (`test?-phase`)
  - [`books/acl2s/cgen/with-timeout-raw.lsp`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/cgen/with-timeout-raw.lsp#L195-L208) (`with-timeout-aux-raw`)
- **Root Cause**:
  Before termination is proved, `defunc.lisp:1356` temporarily admits the raw definition into the world with `(skip-proofs ,defun)` and then runs `test-body-contracts` and `test?` wrapped in `(with-time-limit ,testing-timeout ...)`. When the definition is non-tail-recursively non-terminating (e.g., `(definec nt-crash (x :nat) :nat (1+ (nt-crash x)))`), the first counterexample evaluation exhausts the raw Lisp control stack in milliseconds—well before `cgen`'s timer fires. Moreover, `with-timeout-aux-raw` (`with-timeout-raw.lsp:199-204`) only handles `(error (c) ',timeout-id)`:
  ```lisp
  (let ((vals (handler-case
                  (catch1 ',timeout-id
                          (with-timeout-raw ,duration ,timeout-id ,body))
                (error (c) ',timeout-id))))
    ...)
  ```
  In ANSI Common Lisp (and both SBCL and CCL), stack overflow is signaled as a `storage-condition` (a `serious-condition`, **not** a subtype of `cl:error`), so `handler-case` does not intercept it and ACL2 immediately enters `ABORTING from raw Lisp`.
- **Verified Reproduction ([`repros/acl2s-defunc-nonterm-stack-overflow/run.sh`](../repros/acl2s-defunc-nonterm-stack-overflow/run.sh))**:
  Submitting `(definec nt-crash (x :nat) :nat (1+ (nt-crash x)))`:
  - **SBCL 2.6.10**:
    ```text
    ************ ABORTING from raw Lisp ***********
    ********** (see :DOC raw-lisp-error) **********
    Error:  Control stack exhausted (no more space for function call frames).
    ```
  - **CCL 1.14**:
    ```text
    ************ ABORTING from raw Lisp ***********
    ********** (see :DOC raw-lisp-error) **********
    Error:  Stack overflow on control stack.
    While executing: ACL2_*1*_ACL2S::NT-CRASH
    ```
- **Recommendation**:
  1. Handle `serious-condition` (or explicitly `storage-condition`, alongside unwinding stack safely via `handler-bind` / depth limit) in `with-timeout-aux-raw`, or instrument/bound recursion depth during `test?-phase` pre-termination testing.
  2. Preferably, prove or quick-check termination *before* executing unproved recursive bodies in raw Lisp, or run `test?-phase` for unproved recursive definitions with an explicit recursion-depth step counter in raw Lisp / safe wrapper.

---

## Secondary Static Audit Findings (Not Observed Crashing Live)

The following code defects were identified during read-only inspection of `books/acl2s/`:

1. **Copy-paste `keybody` check for `?valpred`** — [`books/acl2s/defdata/map.lisp`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/defdata/map.lisp#L160-L162) and [`L199-L201`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/defdata/map.lisp#L199-L201):
   ```lisp
   (?valpred (and (proper-symbolp keybody)
                  (assoc-eq keybody M)
                  (predicate-name valbody A M)))
   ```
   Checks `(proper-symbolp keybody)` and `(assoc-eq keybody M)` instead of `valbody`. When `keybody` is an inline/compound expression while `valbody` is a registered type symbol, `?valpred` stays `nil` (`:val-is-typename` omitted); conversely, if `keybody` is registered and `valbody` is an unregistered/compound type expression, `predicate-name` is called on `valbody` unexpectedly.
2. **Inverted `member-eq` variable-avoidance guard** — [`books/acl2s/defdata/defdata-core.lisp`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/defdata/defdata-core.lisp#L167-L169) and [`L208-L210`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/defdata/defdata-core.lisp#L208-L210):
   ```lisp
   (xvar (if (member-eq d avoid-lst)
             d
           (acl2::generate-variable d avoid-lst nil nil wrld)))
   ```
   When `d` *is* in `avoid-lst` (`(forbidden-names)` plus user type names `N`), the `if` keeps `d` verbatim instead of calling `generate-variable`! Tested live with `(defdata d (record (a . nat) (b . pos)))` in the fuzzer: `defdata` still succeeded because record accessors/constructor paths avoided capture, so impact appears latent.
3. **Discarded `ttree` check in CCG** — [`books/acl2s/ccg/ccg.lisp`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/ccg/ccg.lisp#L7566):
   `(chk-assumption-free-ttree nil;(cdr pair)` passes `nil` instead of `(cdr pair)`.
4. **Package typo in ASPF quiet-mode off-hook** — [`books/acl2s/aspf/interface/acl2s-utils/additions.lsp`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/aspf/interface/acl2s-utils/additions.lsp#L21):
   Uses `` `((acl2::table acl2s::defunc-defaults-table ...)) `` (`acl2::table` vs `acl2s::table` on line 18).
5. **Wrong arity in `enum/acc` error message** — [`books/acl2s/defdata/defdata-attach.lisp`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/defdata/defdata-attach.lisp#L202):
   Error format string prints `"arity 1"` after checking `(allows-arity enum2 2 wrld)`.
6. **Ruled-out lead — `number-enums-sampling.lisp`** — [`books/acl2s/defdata/number-enums-sampling.lisp`](file:///Users/ember/dev/acl2-fix/head-worktree/books/acl2s/defdata/number-enums-sampling.lisp#L282-L447):
   Contains `(natp (car ))` (line 353) and three `(skip-proofs ...)` `defthm`s (lines 310-326), verified to lie wholly inside a `#| ... |#` block comment (`lines 282-447`) and therefore inactive at load/certification time.

---

## Audited Clean / Hardened Boundaries

- **`cgen` `with-timeout-raw` for normal `error` conditions**: `with-timeout-aux-raw` safely catches `cl:error` conditions (such as SBCL's `"can't represent result of left shift"` in `expt`) and converts them into timeout results instead of aborting theorem proving.
- **`property` / `defthmskipall` & `(thm nil)`**: Random and adversarial `property` fuzzing did not produce any false-theorem acceptance (`MUST_FAIL` properties were cleanly rejected; post-batch `(thm nil)` canary never passed).
- **`ccg` `:hints` soundness**: Adversarial `:hints (("Goal" :by nil))` under `:ccg` termination mode was cleanly rejected (`CCG-BAD-BY`).
- **Suspected `impliez` redefinition collision**: `(property (x :nat) (natp (impliez t x)))` proved cleanly because `impliez` is an existing `std/basic/defs.lisp` macro; attempting `(defun impliez ...)` is rejected by ACL2 unless redefined.

---

## Prototype Mechanical Fuzzer (`hunts/acl2s/fuzz_acl2s.py`)

A self-contained dual-runtime differential & canary fuzzer was built at [`hunts/acl2s/fuzz_acl2s.py`](../hunts/acl2s/fuzz_acl2s.py). For each seed it generates randomized + adversarial forms across:
- `defdata`: `record`, `oneof`, `listof`, `alistof`, `map`, `range`, `enum`, mutual recursion (`d`, duplicate fields, nested aliases).
- `definec`: duplicate formal permutations, contradictory formal types, valid/false output contracts, and non-terminating calls.
- `property`/`cgen`: valid/contradictory hypotheses and `MUST_FAIL` false-property canaries.
- `ccg`: `:ccg` recursive function families and `:loop$-recursion`.

Oracles check:
1. Raw Lisp aborts (`ABORTING from raw Lisp`, memory faults, stack overflows).
2. CCG `CHOKE-ON-LOOP$-RECURSION` crashes.
3. Declared vs actual `(acl2::formals fn (w state))` mismatches on `definec`.
4. `MUST_FAIL` false-property proofs (`PROPERTY CHECKING SUCCESSFUL`) or `MUST_FAIL` non-terminating `ccg` admissions.
5. End-of-batch logical soundness canary `(thm nil)`.

Running `python3 /Users/ember/dev/compiler-audit/hunts/acl2s/fuzz_acl2s.py --seed 42 --cases 40 --runtime both` (188 cases per runtime) cleanly flags `ACL2S-2` (`DEFINEC_FORMALS_MISMATCH` on 7 duplicate-formal cases), `ACL2S-3` (`CRASH_CCG_LOOP`), and `ACL2S-4` (`RAW_LISP_ABORT` stack overflow) on **both SBCL 2.6.10 and CCL 1.14**, with zero `(thm nil)` soundness leaks.

---

## Systematic Mechanical Fuzzing Blueprint for ACL2s

To turn one-off auditing into continuous, high-yield vulnerability discovery across `books/acl2s/`, we recommend a 4-pipeline automated fuzzing architecture running inside isolated ephemeral `ACL2_SYSTEM_BOOKS` sandboxes (`mktemp -d` + `timeout --kill-after`):

### 1. Trust-Tag & `defattach` Contract Integrity Fuzzer (`defdata`)
- **Generator**: Synthesize `register-type`, `defdata-attach`, `register-data-constructor`, and `defdata` (`record`/`map`/`oneof`/`range`/custom combinators) events using:
  - Unverified (`:verify-guards nil`), `:program`-mode, and `mbe` enumerators (`enum`, `enum/acc`), recognizers, and destructors with intentionally narrow or raw-memory-unsafe bodies (`car`, `cdr`, `svref`, `aref` guarded by `natp`/`stringp`).
  - Destructor predicates/constructors with mismatched `:tau-system`, `:compound-recognizer`, `:elim`, and `:forward-chaining` signatures.
- **Oracle**: Generate a tiny `:logic` `:verify-guards t` caller invoking `nth-<type>` or destructor axioms, run it in raw Lisp under both SBCL and CCL, and assert zero raw Lisp aborts + `(thm nil)` refusal. (Would have caught **ACL2S-1** on iteration 1.)

### 2. Grammar-Based `definec` / `defunc` / `property` Frontend-vs-Kernel Differential Fuzzer
- **Generator**: Mutate ACL2s function/property ASTs along syntactic corner cases often omitted by hand-written tests:
  - Duplicate parameter names (`(x :int y :int x :pos)`), `ignored`/unused parameters, package-qualified symbols (`ACL2::X` vs `ACL2S::X`), reserved names (`D`, `X`, `RES`, `STATE`, `WORLD`), stobjs, multi-value returns (`mv`), and `mbe` `:logic`/`:exec` divergence.
  - Unsatisfiable type intersections (`nat` $\cap$ `string`, empty `range`, contradictory `:ic`).
- **Oracle**:
  - Structural equivalence check between declared signature (`d-args`, parameter count, position, non-vacuous guard) and resulting ACL2 kernel metadata (`formals`, `guard`, `stobjs-in`, `stobjs-out`, `symbol-class`).
  - Differential evaluation between `:logic` interpretation and guard-verified raw Lisp execution (`ACL2S-2` detector).
  - Unsoundness canary `(thm nil)` after every `defunc`/`property` batch.

### 3. `:ccg` vs `:measure` Differential Termination & `redefun` Interaction Fuzzer
- **Generator**: Generate pairs of identical `defun` / `mutual-recursion` / `defpun` / `loop$` definitions (varying xargs: `:loop$-recursion t`, explicit `:measure`, `:well-founded-relation`, `stobj` args, `mv` returns, `let*`/`mv-let`, higher-order `apply$`).
- **Oracle**: Admit each function in two fresh ACL2 worlds—one with `:measure` (baseline) and one with `:ccg` (`acl2s/ccg/ccg`). Flag:
  1. Any `:ccg` admission of a `MUST_FAIL` non-terminating witness (soundness leak).
  2. Any `:ccg` hard crash on a valid `:measure`-admitted function (`ACL2S-3` detector).
  3. World/event hook desync when combining `defstobj` (`ccg.lisp:7612` `redefun+rewrite defstobj-fn`), `local`, `:u`, or failed `encapsulate` rollbacks.

### 4. Resource-Isolated `cgen` / `test?` Evaluation & Condition-Handling Stress Fuzzer
- **Generator**: Feed `test?`, `cgen`, and `defunc` (`test?-phase`) with:
  - Non-terminating tail and non-tail recursions (with `:time-limit` / `testing-timeout` enabled).
  - Pathological arithmetic (`expt`, `ash`, `make-list` on `10^8`), fast-alist violations, `defattach` overrides, and deeply nested recursive `defdata` enumerators.
- **Oracle**: Run inside strict OS-level `timeout` + `ulimit` and fail immediately on any `ABORTING from raw Lisp`, unhandled `storage-condition` (`ACL2S-4` detector), `CORRUPTION WARNING`, or uncaught Lisp debugger break (`break$` / REPL prompt leak).
